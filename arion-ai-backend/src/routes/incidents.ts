import { Router, Response, Request } from 'express';
import { body, query as queryParam, validationResult } from 'express-validator';
import { verifyToken, requireRole, optionalAuth, requireApiKey, AuthRequest } from '../middleware/auth';
import { query } from '../config/db';
import { triageIncident, generateSitrep } from '../config/ai';
import { getFirestore, getMessaging } from '../config/firebase';
import { broadcastToClients } from '../index';

const router = Router();

// =============================================================
// HELPER — Map raw DB incident row → Flutter CrisisAlert shape
// Flutter model fields: id, title, description, severity,
//   time, distance, latitude, longitude, status, mappedSeverity
// mappedSeverity: 'critical' | 'warning' | 'safe' (matches Flutter AlertSeverity enum)
// =============================================================
function mapIncidentToAlert(row: Record<string, unknown>, userLat?: number, userLng?: number) {
  // Compute relative time string
  const createdAt = row.created_at ? new Date(row.created_at as string) : null;
  let time = 'Unknown time';
  if (createdAt) {
    const diffMs  = Date.now() - createdAt.getTime();
    const diffMin = Math.floor(diffMs / 60000);
    if (diffMin < 1)       time = 'Just now';
    else if (diffMin < 60) time = `${diffMin} min${diffMin > 1 ? 's' : ''} ago`;
    else {
      const diffHr = Math.floor(diffMin / 60);
      if (diffHr < 24)     time = `${diffHr} hour${diffHr > 1 ? 's' : ''} ago`;
      else {
        const diffDay = Math.floor(diffHr / 24);
        time = `${diffDay} day${diffDay > 1 ? 's' : ''} ago`;
      }
    }
  }

  // Compute distance string
  const distanceM = row.distance_m as number | undefined;
  let distance = 'Unknown distance';
  if (distanceM !== undefined && distanceM !== null) {
    const km = distanceM / 1000;
    distance = km < 1
      ? `${Math.round(distanceM)} m away`
      : `${km.toFixed(1)} km away`;
  }

  // Map severity to Flutter enum values
  const dbSeverity = (row.severity as string || '').toUpperCase();
  const dbStatus   = (row.status   as string || '').toUpperCase();
  let mappedSeverity: 'critical' | 'warning' | 'safe';
  if (dbStatus === 'RESOLVED' || dbStatus === 'CANCELLED') {
    mappedSeverity = 'safe';
  } else if (dbSeverity === 'CRITICAL') {
    mappedSeverity = 'critical';
  } else {
    // HIGH, MODERATE, LOW, IN_PROGRESS all map to warning
    mappedSeverity = 'warning';
  }

  return {
    // Original DB fields (kept for full data access)
    ...row,
    // Flutter CrisisAlert model fields
    id:             String(row.id),
    title:          row.incident_type   || 'Unknown Incident',
    description:    row.ai_summary      || (row.message as string) || 'No details available.',
    severity:       mappedSeverity,       // Flutter AlertSeverity enum value
    mappedSeverity,                       // explicit alias
    time,
    distance,
    latitude:       row.lat,
    longitude:      row.lng,
    status:         row.status || 'ACTIVE',
  };
}

// =============================================================
// POST /incidents/report
// Submit a new incident report — core endpoint
// Normal users only.
// Pipeline: User message → Gemini AI triage → PostgreSQL → Firestore → FCM push
// =============================================================
router.post(
  '/report',
  verifyToken,
  requireRole('normal'),
  [
    body('message').isString().trim().isLength({ min: 5, max: 1000 })
      .withMessage('Message must be between 5 and 1000 characters'),
    body('lat').isFloat({ min: -90, max: 90 }).withMessage('Valid latitude required'),
    body('lng').isFloat({ min: -180, max: 180 }).withMessage('Valid longitude required'),
    body('address').optional().isString().trim(),
  ],
  async (req: AuthRequest, res: Response): Promise<void> => {
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
      res.status(400).json({ success: false, errors: errors.array() });
      return;
    }

    const { message, lat, lng, address } = req.body as {
      message: string;
      lat: number;
      lng: number;
      address?: string;
    };

    try {
      console.log(`🔍 [Incidents] Triaging report from ${req.user!.uid}...`);

      // --- STEP 1: AI TRIAGE ---
      const triage = await triageIncident(message, lat, lng);
      console.log(`🤖 [AI] Result: ${triage.incidentType} | ${triage.severity} | ${triage.confidence}% confidence`);

      // --- STEP 2: PERSIST TO CLOUD SQL ---
      const dbResult = await query(
        `INSERT INTO incidents
           (reporter_uid, message, incident_type, severity, confidence, ai_summary, lat, lng, address)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
         RETURNING *`,
        [
          req.user!.uid,
          message,
          triage.incidentType,
          triage.severity,
          triage.confidence,
          triage.summary,
          lat,
          lng,
          address || null,
        ]
      );

      const incident = dbResult.rows[0];
      console.log(`💾 [DB] Incident saved: ${incident.id}`);

      // --- STEP 3: PUBLISH TO FIRESTORE (Real-time) ---
      const firestorePayload = {
        id:              incident.id,
        reporterUid:     incident.reporter_uid,
        message:         incident.message,
        incidentType:    incident.incident_type,
        severity:        incident.severity,
        confidence:      incident.confidence,
        aiSummary:       incident.ai_summary,
        lat:             incident.lat,
        lng:             incident.lng,
        address:         incident.address,
        status:          incident.status,
        recommendedActions: triage.recommendedActions,
        createdAt:       incident.created_at,
      };

      try {
        const db = getFirestore();
        await db.collection('incidents').doc(incident.id).set(firestorePayload);
        console.log(`🔥 [Firestore] Incident published: ${incident.id}`);
      } catch (firestoreErr) {
        console.warn('🟡 [Firestore] Publish failed (non-fatal):', (firestoreErr as Error).message);
      }

      // --- STEP 4: FCM PUSH to Emergency Responders ---
      if (['HIGH', 'CRITICAL'].includes(triage.severity)) {
        sendPushToResponders(triage, incident.id, lat, lng, address);
      }

      // --- STEP 5: WebSocket Broadcast ---
      broadcastToClients('emergency', {
        type: 'NEW_INCIDENT',
        incident: firestorePayload,
      });

      res.status(201).json({
        success: true,
        message: 'Incident reported successfully',
        incident: {
          ...firestorePayload,
          recommendedActions: triage.recommendedActions,
        },
      });
    } catch (err) {
      console.error('🔴 [Incidents/report]', (err as Error).message);
      res.status(500).json({ success: false, error: 'Failed to process incident report' });
    }
  }
);

// =============================================================
// GET /incidents
// - Emergency: all incidents, sorted by priority
// - Normal: nearby incidents within radius (default 5km)
// Query: ?lat=&lng=&radius=5&status=ACTIVE&page=1&limit=20
// =============================================================
router.get('/', optionalAuth, async (req: AuthRequest, res: Response): Promise<void> => {
  try {
    const {
      lat, lng,
      radius = '5',
      status = 'ACTIVE',
      page = '1',
      limit = '20',
      type,
      severity,
    } = req.query as Record<string, string>;

    const pageNum  = Math.max(1, parseInt(page));
    const limitNum = Math.min(50, parseInt(limit));
    const offset   = (pageNum - 1) * limitNum;

    const isEmergency = req.user?.role === 'emergency';

    let queryText: string;
    let params: unknown[];

    if (isEmergency) {
      // Emergency responders: ALL incidents with optional filters
      const conditions: string[] = [];
      params = [];

      if (status && status !== 'ALL') {
        params.push(status);
        conditions.push(`status = $${params.length}`);
      }
      if (type) {
        params.push(type);
        conditions.push(`incident_type = $${params.length}`);
      }
      if (severity) {
        params.push(severity);
        conditions.push(`severity = $${params.length}`);
      }

      const where = conditions.length > 0 ? `WHERE ${conditions.join(' AND ')}` : '';

      // Priority sort: CRITICAL > HIGH > MODERATE > LOW, then newest
      params.push(limitNum, offset);
      queryText = `
        SELECT *,
          CASE COALESCE(severity, 'MODERATE')
            WHEN 'CRITICAL' THEN 4
            WHEN 'HIGH' THEN 3
            WHEN 'MODERATE' THEN 2
            WHEN 'LOW' THEN 1
            ELSE 0
          END AS severity_rank
        FROM incidents
        ${where}
        ORDER BY severity_rank DESC, COALESCE(created_at, NOW()) DESC
        LIMIT $${params.length - 1} OFFSET $${params.length}
      `;
    } else {
      // Normal users: nearby incidents (within radius km)
      if (!lat || !lng) {
        res.status(400).json({
          success: false,
          error: 'lat and lng are required for nearby incident lookup',
        });
        return;
      }

      const radiusMeters = parseFloat(radius) * 1000;
      params = [parseFloat(lat), parseFloat(lng), radiusMeters, status, limitNum, offset];
      queryText = `
        SELECT *,
          earth_distance(
            ll_to_earth($1, $2),
            ll_to_earth(lat, lng)
          ) AS distance_m
        FROM incidents
        WHERE COALESCE(status, 'ACTIVE') = $4
          AND lat IS NOT NULL AND lng IS NOT NULL
          AND earth_distance(ll_to_earth($1, $2), ll_to_earth(lat, lng)) <= $3
        ORDER BY distance_m ASC, COALESCE(created_at, NOW()) DESC
        LIMIT $5 OFFSET $6
      `;
    }

    const result = await query(queryText, params);

    // Get total count for pagination
    const countResult = await query(
      `SELECT COUNT(*) FROM incidents WHERE COALESCE(status, 'ACTIVE') = $1`,
      [status]
    );

    const userLat = lat ? parseFloat(lat) : undefined;
    const userLng = lng ? parseFloat(lng) : undefined;
    const mapped  = result.rows.map((row) => mapIncidentToAlert(row, userLat, userLng));

    res.json({
      success: true,
      incidents: mapped,
      pagination: {
        page: pageNum,
        limit: limitNum,
        total: parseInt(countResult.rows[0].count),
        pages: Math.ceil(parseInt(countResult.rows[0].count) / limitNum),
      },
    });
  } catch (err) {
    console.error('🔴 [Incidents/list]', (err as Error).message);
    res.status(500).json({ success: false, error: 'Failed to fetch incidents' });
  }
});

// =============================================================
// POST /incidents/quick-report
// Anonymous incident report — for Flutter before Firebase Auth.
// Protected by X-Api-Key header (ARION_API_KEY in .env).
// Pipeline: AI triage → PostgreSQL → Firestore → WebSocket
// Body: { message, lat, lng, address?, deviceId? }
// =============================================================
router.post(
  '/quick-report',
  requireApiKey,
  [
    body('message').isString().trim().isLength({ min: 5, max: 1000 })
      .withMessage('Message must be between 5 and 1000 characters'),
    body('lat').isFloat({ min: -90,  max: 90  }).withMessage('Valid latitude required'),
    body('lng').isFloat({ min: -180, max: 180 }).withMessage('Valid longitude required'),
    body('address').optional().isString().trim(),
    body('deviceId').optional().isString().trim(),
  ],
  async (req: Request, res: Response): Promise<void> => {
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
      res.status(400).json({ success: false, errors: errors.array() });
      return;
    }

    const { message, lat, lng, address, deviceId } = req.body as {
      message:   string;
      lat:       number;
      lng:       number;
      address?:  string;
      deviceId?: string;
    };

    try {
      console.log(`🔍 [Incidents/quick-report] Triaging anonymous report (device: ${deviceId || 'unknown'})...`);

      // --- STEP 1: AI TRIAGE ---
      const triage = await triageIncident(message, lat, lng);
      console.log(`🤖 [AI] Result: ${triage.incidentType} | ${triage.severity} | ${triage.confidence}% confidence`);

      // --- STEP 1.5: SMART CLUSTERING ---
      // Check if an active incident of the same type exists within 500m in the last 30 mins.
      // If yes, corroborate instead of creating a duplicate.
      const clusterResult = await query(
        `SELECT id, corroboration_count, confidence
         FROM incidents
         WHERE incident_type = $1
           AND status NOT IN ('RESOLVED', 'FALSE_ALARM')
           AND created_at >= NOW() - INTERVAL '30 minutes'
           AND lat IS NOT NULL AND lng IS NOT NULL
           AND earth_distance(ll_to_earth($2, $3), ll_to_earth(lat, lng)) <= 500
         ORDER BY created_at DESC
         LIMIT 1`,
        [triage.incidentType, lat, lng]
      );

      if (clusterResult.rows.length > 0) {
        // ✅ Existing nearby incident found — corroborate it
        const existing = clusterResult.rows[0];
        const updated = await query(
          `UPDATE incidents
           SET
             corroboration_count = COALESCE(corroboration_count, 1) + 1,
             confidence          = LEAST(99, COALESCE(confidence, 50) + 3),
             updated_at          = NOW()
           WHERE id = $1
           RETURNING *`,
          [existing.id]
        );
        const updatedRow = updated.rows[0];
        console.log(`🔗 [Clustering] Merged into existing incident ${existing.id} (${updatedRow.corroboration_count} reports)`);

        await query(
          `INSERT INTO incident_updates (incident_id, author_uid, message, update_type)
           VALUES ($1, $2, $3, 'UPDATE')`,
          [
            existing.id,
            deviceId ? `anonymous:${deviceId}` : 'anonymous',
            `Additional corroborating report received. Total confirmations: ${updatedRow.corroboration_count}`,
          ]
        );

        // Broadcast the corroboration event
        broadcastToClients('emergency', {
          type: 'INCIDENT_CORROBORATED',
          incidentId:         existing.id,
          corroborationCount: updatedRow.corroboration_count,
          confidence:         updatedRow.confidence,
        });

        const mapped = mapIncidentToAlert({ ...updatedRow, distance_m: 0 }, lat, lng);
        res.status(200).json({
          success:   true,
          clustered: true,
          message:   `This incident has already been reported. Your report has been added as confirmation #${updatedRow.corroboration_count}.`,
          incident: {
            ...mapped,
            recommendedActions: triage.recommendedActions,
          },
        });
        return;
      }

      // --- STEP 2: NEW INCIDENT — PERSIST TO CLOUD SQL ---
      const reporterUid = deviceId ? `anonymous:${deviceId}` : 'anonymous';
      const dbResult = await query(
        `INSERT INTO incidents
           (reporter_uid, message, incident_type, severity, confidence, ai_summary, lat, lng, address, corroboration_count)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, 1)
         RETURNING *`,
        [
          reporterUid,
          message,
          triage.incidentType,
          triage.severity,
          triage.confidence,
          triage.summary,
          lat,
          lng,
          address || null,
        ]
      );

      const incident = dbResult.rows[0];
      console.log(`💾 [DB] Anonymous incident saved: ${incident.id}`);

      // --- STEP 3: PUBLISH TO FIRESTORE ---
      const firestorePayload = {
        id:                 incident.id,
        reporterUid:        incident.reporter_uid,
        message:            incident.message,
        incidentType:       incident.incident_type,
        severity:           incident.severity,
        confidence:         incident.confidence,
        aiSummary:          incident.ai_summary,
        lat:                incident.lat,
        lng:                incident.lng,
        address:            incident.address,
        status:             incident.status,
        corroborationCount: 1,
        recommendedActions: triage.recommendedActions,
        createdAt:          incident.created_at,
        anonymous:          true,
      };

      try {
        const db = getFirestore();
        await db.collection('incidents').doc(incident.id).set(firestorePayload);
        console.log(`🔥 [Firestore] Anonymous incident published: ${incident.id}`);
      } catch (firestoreErr) {
        console.warn('🟡 [Firestore] Publish failed (non-fatal):', (firestoreErr as Error).message);
      }

      // --- STEP 4: FCM PUSH (high/critical only) ---
      if (['HIGH', 'CRITICAL'].includes(triage.severity)) {
        sendPushToResponders(triage, incident.id, lat, lng, address);
      }

      // --- STEP 5: WebSocket Broadcast ---
      broadcastToClients('emergency', {
        type: 'NEW_INCIDENT',
        incident: firestorePayload,
      });

      const mapped = mapIncidentToAlert({ ...incident, distance_m: 0 }, lat, lng);

      res.status(201).json({
        success:   true,
        clustered: false,
        message:   'Incident reported successfully',
        incident: {
          ...mapped,
          recommendedActions: triage.recommendedActions,
        },
      });
    } catch (err) {
      console.error('🔴 [Incidents/quick-report]', (err as Error).message);
      res.status(500).json({ success: false, error: 'Failed to process incident report' });
    }
  }
);

// =============================================================
// GET /incidents/nearby
// Dedicated map endpoint — returns incidents within radius.
// Public endpoint (no auth required for basic view).
// Response is normalized to match Flutter CrisisAlert model.
// =============================================================
router.get('/nearby', async (req: AuthRequest, res: Response): Promise<void> => {
  const { lat, lng, radius = '10', status } = req.query as Record<string, string>;

  if (!lat || !lng) {
    res.status(400).json({ success: false, error: 'lat and lng are required' });
    return;
  }

  try {
    const userLat     = parseFloat(lat);
    const userLng     = parseFloat(lng);
    const radiusMeters = parseFloat(radius) * 1000;

    // Build parameterized status filter
    const params: unknown[] = [userLat, userLng, radiusMeters];
    let statusFilter: string;
    if (status && status !== 'ALL') {
      params.push(status);
      statusFilter = `AND COALESCE(status, 'ACTIVE') = $${params.length}`;
    } else {
      statusFilter = `AND COALESCE(status, 'ACTIVE') != 'RESOLVED'`;
    }

    const result = await query(
      `SELECT
        id,
        reporter_uid,
        incident_type,
        severity,
        status,
        confidence,
        ai_summary,
        message,
        lat,
        lng,
        address,
        created_at,
        earth_distance(ll_to_earth($1, $2), ll_to_earth(lat, lng)) AS distance_m
       FROM incidents
       WHERE lat IS NOT NULL
         AND lng IS NOT NULL
         AND earth_distance(ll_to_earth($1, $2), ll_to_earth(lat, lng)) <= $3
         ${statusFilter}
       ORDER BY distance_m ASC
       LIMIT 50`,
      params
    );

    const mapped = result.rows.map((row) => mapIncidentToAlert(row, userLat, userLng));

    res.json({
      success: true,
      count: mapped.length,
      incidents: mapped,
      centerLat: userLat,
      centerLng: userLng,
      radiusKm: parseFloat(radius),
    });
  } catch (err) {
    console.error('🔴 [Incidents/nearby]', (err as Error).message);
    res.status(500).json({ success: false, error: 'Failed to fetch nearby incidents' });
  }
});

// =============================================================
// GET /incidents/:id
// Incident detail with updates timeline
// =============================================================
router.get('/:id', optionalAuth, async (req: AuthRequest, res: Response): Promise<void> => {
  try {
    const incidentResult = await query(
      'SELECT * FROM incidents WHERE id = $1',
      [req.params.id]
    );

    if (incidentResult.rows.length === 0) {
      res.status(404).json({ success: false, error: 'Incident not found' });
      return;
    }

    // Fetch updates timeline
    const updatesResult = await query(
      `SELECT iu.*, u.name as author_name, u.role as author_role
       FROM incident_updates iu
       LEFT JOIN users u ON u.firebase_uid = iu.author_uid
       WHERE iu.incident_id = $1
       ORDER BY iu.created_at ASC`,
      [req.params.id]
    );

    res.json({
      success: true,
      incident: incidentResult.rows[0],
      updates: updatesResult.rows,
    });
  } catch (err) {
    console.error('🔴 [Incidents/detail]', (err as Error).message);
    res.status(500).json({ success: false, error: 'Failed to fetch incident' });
  }
});

// =============================================================
// POST /incidents/:id/retriage
// Re-run AI triage for incidents where the original triage failed.
// Public endpoint (API key) — used by Flutter when it detects the
// fallback "Automated triage unavailable" text.
// =============================================================
router.post(
  '/:id/retriage',
  requireApiKey,
  async (req: Request, res: Response): Promise<void> => {
    try {
      const incidentResult = await query(
        'SELECT id, message, lat, lng, ai_summary FROM incidents WHERE id = $1',
        [req.params.id]
      );

      if (incidentResult.rows.length === 0) {
        res.status(404).json({ success: false, error: 'Incident not found' });
        return;
      }

      const incident = incidentResult.rows[0];
      const currentSummary = (incident.ai_summary as string) || '';

      // Only retriage if the current summary is the fallback text or empty
      const isFallback = !currentSummary
        || currentSummary.includes('Automated triage unavailable')
        || currentSummary.includes('Manual review required')
        || currentSummary === 'Incident reported — details pending.'
        || currentSummary === 'No details available.';

      if (!isFallback) {
        // Already has valid AI analysis — return it as-is
        res.json({
          success: true,
          retriaged: false,
          message: 'Incident already has valid AI analysis.',
          aiSummary: currentSummary,
        });
        return;
      }

      // Re-run AI triage
      console.log(`🔄 [Retriage] Re-triaging incident ${incident.id}...`);
      const triage = await triageIncident(
        incident.message as string,
        incident.lat as number,
        incident.lng as number
      );

      // Check if retriage also failed (returned the fallback again)
      if (triage.summary === 'Automated triage unavailable. Manual review required.') {
        res.json({
          success: true,
          retriaged: false,
          message: 'AI triage still unavailable. Please try again later.',
          aiSummary: currentSummary,
        });
        return;
      }

      // Update DB with new AI results
      await query(
        `UPDATE incidents SET
           ai_summary    = $2,
           incident_type = $3,
           severity      = $4,
           confidence    = $5,
           updated_at    = NOW()
         WHERE id = $1`,
        [incident.id, triage.summary, triage.incidentType, triage.severity, triage.confidence]
      );

      console.log(`✅ [Retriage] Incident ${incident.id} updated: ${triage.incidentType} | ${triage.severity}`);

      // Update Firestore too
      try {
        const db = getFirestore();
        await db.collection('incidents').doc(String(incident.id)).update({
          aiSummary:    triage.summary,
          incidentType: triage.incidentType,
          severity:     triage.severity,
          confidence:   triage.confidence,
        });
      } catch (e) { /* non-fatal */ }

      res.json({
        success:            true,
        retriaged:          true,
        message:            'AI triage completed successfully.',
        aiSummary:          triage.summary,
        incidentType:       triage.incidentType,
        severity:           triage.severity,
        confidence:         triage.confidence,
        recommendedActions: triage.recommendedActions,
      });
    } catch (err) {
      console.error('🔴 [Incidents/retriage]', (err as Error).message);
      res.status(500).json({ success: false, error: 'Failed to retriage incident' });
    }
  }
);

// =============================================================
// GET /incidents/:id/sitrep
// AI-generated military-grade Situation Report (SITREP)
// Emergency responders only. Synthesises all incident data
// including corroboration count, updates timeline, and location.
// =============================================================
router.get(
  '/:id/sitrep',
  verifyToken,
  requireRole('emergency'),
  async (req: AuthRequest, res: Response): Promise<void> => {
    try {
      const incidentResult = await query(
        `SELECT * FROM incidents WHERE id = $1`,
        [req.params.id]
      );

      if (incidentResult.rows.length === 0) {
        res.status(404).json({ success: false, error: 'Incident not found' });
        return;
      }

      const incident = incidentResult.rows[0];

      // Fetch updates timeline
      const updatesResult = await query(
        `SELECT iu.message, iu.update_type, iu.created_at,
                u.name as author_name
         FROM incident_updates iu
         LEFT JOIN users u ON u.firebase_uid = iu.author_uid
         WHERE iu.incident_id = $1
         ORDER BY iu.created_at ASC`,
        [req.params.id]
      );

      const sitrep = await generateSitrep({
        incidentType:       incident.incident_type,
        severity:           incident.severity,
        aiSummary:          incident.ai_summary || '',
        message:            incident.message,
        lat:                incident.lat,
        lng:                incident.lng,
        address:            incident.address,
        corroborationCount: incident.corroboration_count || 1,
        status:             incident.status,
        createdAt:          incident.created_at,
        updates:            updatesResult.rows.map((u: Record<string, unknown>) => ({
          message:    u.message as string,
          updateType: u.update_type as string,
          createdAt:  u.created_at as string,
          authorName: u.author_name as string | undefined,
        })),
      });

      console.log(`🦖 [SITREP] Generated for incident ${req.params.id}`);

      res.json({
        success:  true,
        incidentId: req.params.id,
        sitrep,
        incidentSnapshot: {
          type:               incident.incident_type,
          severity:           incident.severity,
          status:             incident.status,
          corroborationCount: incident.corroboration_count || 1,
          address:            incident.address,
          createdAt:          incident.created_at,
        },
      });
    } catch (err) {
      console.error('🔴 [Incidents/sitrep]', (err as Error).message);
      res.status(500).json({ success: false, error: 'Failed to generate SITREP' });
    }
  }
);

// =============================================================
// POST /incidents/:id/corroborate
// Crowd-sourced incident verification.
// Anyone (even anonymous with API key) can confirm an incident.
// Increments corroboration_count and boosts AI confidence.
// Body: { deviceId? }
// =============================================================
router.post(
  '/:id/corroborate',
  requireApiKey,
  async (req: Request, res: Response): Promise<void> => {
    try {
      const result = await query(
        `UPDATE incidents
         SET
           corroboration_count = COALESCE(corroboration_count, 1) + 1,
           confidence          = LEAST(99, COALESCE(confidence, 50) + 3),
           updated_at          = NOW()
         WHERE id = $1
           AND status NOT IN ('RESOLVED', 'FALSE_ALARM')
         RETURNING id, incident_type, severity, corroboration_count, confidence, status`,
        [req.params.id]
      );

      if (result.rows.length === 0) {
        res.status(404).json({
          success: false,
          error: 'Incident not found or already resolved',
        });
        return;
      }

      const updated = result.rows[0];
      console.log(`👤 [Corroborate] Incident ${updated.id} now confirmed by ${updated.corroboration_count} report(s)`);

      // Log as a timeline update
      await query(
        `INSERT INTO incident_updates (incident_id, author_uid, message, update_type)
         VALUES ($1, $2, $3, 'UPDATE')`,
        [
          req.params.id,
          (req.body as { deviceId?: string }).deviceId ? `anonymous:${(req.body as { deviceId?: string }).deviceId}` : 'anonymous',
          `Incident corroborated by an additional witness. Total confirmations: ${updated.corroboration_count}`,
        ]
      );

      // Update Firestore
      try {
        await getFirestore().collection('incidents').doc(req.params.id).update({
          corroborationCount: updated.corroboration_count,
          confidence:         updated.confidence,
        });
      } catch (e) { /* non-fatal */ }

      // WebSocket broadcast — so dashboard updates live
      broadcastToClients('emergency', {
        type: 'INCIDENT_CORROBORATED',
        incidentId:         req.params.id,
        corroborationCount: updated.corroboration_count,
        confidence:         updated.confidence,
      });

      res.json({
        success:            true,
        message:            'Thank you for confirming this incident.',
        incidentId:         updated.id,
        corroborationCount: updated.corroboration_count,
        confidence:         updated.confidence,
      });
    } catch (err) {
      console.error('🔴 [Incidents/corroborate]', (err as Error).message);
      res.status(500).json({ success: false, error: 'Failed to corroborate incident' });
    }
  }
);

// =============================================================
// PUT /incidents/:id/resolve
// Mark incident as resolved — Emergency responders only
// =============================================================
router.put(
  '/:id/resolve',
  verifyToken,
  requireRole('emergency'),
  [body('notes').optional().isString().trim()],
  async (req: AuthRequest, res: Response): Promise<void> => {
    try {
      const result = await query(
        `UPDATE incidents SET
           status = 'RESOLVED',
           resolved_at = NOW(),
           resolved_by = $2
         WHERE id = $1 AND status != 'RESOLVED'
         RETURNING *`,
        [req.params.id, req.user!.uid]
      );

      if (result.rows.length === 0) {
        res.status(404).json({ success: false, error: 'Incident not found or already resolved' });
        return;
      }

      // Add timeline update
      const notes = (req.body as { notes?: string }).notes || 'Incident resolved';
      await query(
        `INSERT INTO incident_updates (incident_id, author_uid, message, update_type)
         VALUES ($1, $2, $3, 'RESOLVED')`,
        [req.params.id, req.user!.uid, notes]
      );

      // Update Firestore
      try {
        await getFirestore().collection('incidents').doc(req.params.id).update({
          status: 'RESOLVED',
          resolvedAt: new Date().toISOString(),
          resolvedBy: req.user!.uid,
        });
      } catch (e) { /* non-fatal */ }

      // Broadcast to WebSocket clients
      broadcastToClients('emergency', {
        type: 'INCIDENT_RESOLVED',
        incidentId: req.params.id,
        resolvedBy: req.user!.uid,
      });

      res.json({ success: true, incident: result.rows[0] });
    } catch (err) {
      console.error('🔴 [Incidents/resolve]', (err as Error).message);
      res.status(500).json({ success: false, error: 'Failed to resolve incident' });
    }
  }
);

// =============================================================
// PUT /incidents/:id/safe
// Normal user marks themselves as safe at an incident
// =============================================================
router.put('/:id/safe', verifyToken, async (req: AuthRequest, res: Response): Promise<void> => {
  try {
    await query(
      `INSERT INTO incident_updates (incident_id, author_uid, message, update_type)
       VALUES ($1, $2, 'User marked themselves as safe', 'SAFE_MARK')`,
      [req.params.id, req.user!.uid]
    );

    broadcastToClients('emergency', {
      type: 'USER_SAFE',
      incidentId: req.params.id,
      userId: req.user!.uid,
    });

    res.json({ success: true, message: 'Marked as safe' });
  } catch (err) {
    console.error('🔴 [Incidents/safe]', (err as Error).message);
    res.status(500).json({ success: false, error: 'Failed to mark safe' });
  }
});

// =============================================================
// PUT /incidents/:id/assign
// Emergency responder assigns themselves to an incident
// =============================================================
router.put(
  '/:id/assign',
  verifyToken,
  requireRole('emergency'),
  async (req: AuthRequest, res: Response): Promise<void> => {
    try {
      const result = await query(
        `UPDATE incidents SET status = 'IN_PROGRESS', assigned_to = $2
         WHERE id = $1 RETURNING *`,
        [req.params.id, req.user!.uid]
      );

      await query(
        `INSERT INTO incident_updates (incident_id, author_uid, message, update_type)
         VALUES ($1, $2, 'Emergency responder assigned and en route', 'ASSIGNED')`,
        [req.params.id, req.user!.uid]
      );

      broadcastToClients('emergency', {
        type: 'INCIDENT_ASSIGNED',
        incidentId: req.params.id,
        assignedTo: req.user!.uid,
      });

      res.json({ success: true, incident: result.rows[0] });
    } catch (err) {
      console.error('🔴 [Incidents/assign]', (err as Error).message);
      res.status(500).json({ success: false, error: 'Failed to assign incident' });
    }
  }
);

// =============================================================
// FCM PUSH — Send to all emergency responders (async, non-blocking)
// =============================================================
async function sendPushToResponders(
  triage: { incidentType: string; severity: string; summary: string },
  incidentId: string,
  lat: number,
  lng: number,
  address?: string
): Promise<void> {
  try {
    // Get all emergency responder FCM tokens
    const tokenResult = await query(
      `SELECT fcm_token FROM users WHERE role = 'emergency' AND fcm_token IS NOT NULL`,
      []
    );

    const tokens = tokenResult.rows.map((r: { fcm_token: string }) => r.fcm_token).filter(Boolean);
    if (tokens.length === 0) return;

    const messaging = getMessaging();
    await messaging.sendEachForMulticast({
      tokens,
      notification: {
        title: `🚨 ${triage.severity} — ${triage.incidentType}`,
        body:  triage.summary || `New ${triage.incidentType} reported`,
      },
      data: {
        incidentId,
        incidentType: triage.incidentType,
        severity:     triage.severity,
        lat:          String(lat),
        lng:          String(lng),
        address:      address || '',
        click_action: 'FLUTTER_NOTIFICATION_CLICK',
      },
      android: { priority: 'high' },
      apns:    { payload: { aps: { contentAvailable: true } } },
    });

    console.log(`📱 [FCM] Pushed to ${tokens.length} emergency responders`);
  } catch (err) {
    console.warn('🟡 [FCM] Push failed (non-fatal):', (err as Error).message);
  }
}

export default router;
