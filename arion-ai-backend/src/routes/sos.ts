import { Router, Response, Request } from 'express';
import { body, validationResult } from 'express-validator';
import { verifyToken, requireRole, requireApiKey, AuthRequest } from '../middleware/auth';
import { query } from '../config/db';
import { getFirestore, getMessaging } from '../config/firebase';
import { broadcastToClients } from '../index';

const router = Router();

// =============================================================
// POST /sos/quick   ← MUST be BEFORE /:id routes!
// Anonymous SOS panic button — for Flutter before Firebase Auth.
// Protected by X-Api-Key header (ARION_API_KEY in .env).
// Body: { lat, lng, message?, deviceId?, name?, phone?, accuracy?, altitude? }
// =============================================================
router.post(
  '/quick',
  requireApiKey,
  [
    body('lat').isFloat({ min: -90,  max: 90  }).withMessage('Valid latitude required'),
    body('lng').isFloat({ min: -180, max: 180 }).withMessage('Valid longitude required'),
    body('message').optional().isString().trim().isLength({ max: 500 }),
    body('deviceId').optional().isString().trim(),
    body('name').optional().isString().trim().isLength({ max: 100 }),
    body('phone').optional().isString().trim().isLength({ max: 20 }),
    body('accuracy').optional().isFloat(),
    body('altitude').optional().isFloat(),
  ],
  async (req: Request, res: Response): Promise<void> => {
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
      res.status(400).json({ success: false, errors: errors.array() });
      return;
    }

    const {
      lat,
      lng,
      message   = 'EMERGENCY SOS — User needs immediate help!',
      deviceId,
      name,
      phone,
      accuracy,
      altitude,
    } = req.body as {
      lat: number;
      lng: number;
      message?: string;
      deviceId?: string;
      name?: string;
      phone?: string;
      accuracy?: number;
      altitude?: number;
    };

    const userUid = deviceId ? `anonymous:${deviceId}` : `anonymous:${Date.now()}`;

    try {
      // --- STEP 1: Save to PostgreSQL (with graceful fallback) ---
      let sosAlert: Record<string, unknown>;
      try {
        const result = await query(
          `INSERT INTO sos_alerts (user_uid, lat, lng, message, name, phone, accuracy, altitude, anonymous)
           VALUES ($1, $2, $3, $4, $5, $6, $7, $8, TRUE)
           RETURNING *`,
          [userUid, lat, lng, message, name || null, phone || null, accuracy || null, altitude || null]
        );
        sosAlert = result.rows[0];
        console.log(`🆘 [SOS/quick] Alert created: ${sosAlert.id} from ${userUid}`);
      } catch (dbErr) {
        console.error('🔴 [SOS/quick] DB insert failed (non-fatal):', (dbErr as Error).message);
        // Synthetic ID so the app still gets a response
        sosAlert = {
          id: `tmp-${Date.now()}`,
          user_uid: userUid,
          lat,
          lng,
          status: 'ACTIVE',
          created_at: new Date().toISOString(),
        };
      }

      // --- STEP 2: Build full SOS payload ---
      const sosPayload = {
        id:        sosAlert.id,
        userUid,
        name:      name    || 'Anonymous',
        phone:     phone   || null,
        lat:       sosAlert.lat    ?? lat,
        lng:       sosAlert.lng    ?? lng,
        accuracy:  accuracy ?? null,
        altitude:  altitude ?? null,
        status:    sosAlert.status ?? 'ACTIVE',
        message,
        anonymous: true,
        createdAt: sosAlert.created_at ?? new Date().toISOString(),
      };

      // --- STEP 3: Publish to Firestore ---
      try {
        await getFirestore()
          .collection('sos_alerts')
          .doc(String(sosAlert.id))
          .set(sosPayload);
      } catch (e) {
        console.warn('🟡 [SOS/quick] Firestore write failed (non-fatal):', (e as Error).message);
      }

      // --- STEP 4: FCM push to ALL emergency responders ---
      sendSOSToAllResponders(String(sosAlert.id), userUid, lat, lng, message, name);

      // --- STEP 5: WebSocket broadcast ---
      broadcastToClients('emergency', {
        type: 'SOS_ALERT',
        sos:  sosPayload,
      });

      res.status(201).json({
        success:  true,
        message:  'SOS alert sent to all emergency responders',
        sosAlert: sosPayload,
      });
    } catch (err) {
      console.error('🔴 [SOS/quick]', (err as Error).message);
      res.status(500).json({ success: false, error: 'Failed to send SOS. Please call 112 immediately.' });
    }
  }
);

// =============================================================
// POST /sos/quick/update  — Live location tracking for active SOS
// Body: { sosId, lat, lng, deviceId?, accuracy? }
// =============================================================
router.post(
  '/quick/update',
  requireApiKey,
  [
    body('sosId').isString().trim().notEmpty(),
    body('lat').isFloat({ min: -90,  max: 90  }),
    body('lng').isFloat({ min: -180, max: 180 }),
    body('deviceId').optional().isString().trim(),
    body('accuracy').optional().isFloat(),
  ],
  async (req: Request, res: Response): Promise<void> => {
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
      res.status(400).json({ success: false, errors: errors.array() });
      return;
    }

    const { sosId, lat, lng, accuracy } = req.body as {
      sosId: string;
      lat: number;
      lng: number;
      accuracy?: number;
    };

    try {
      // Update Firestore for real-time responder map
      try {
        await getFirestore().collection('sos_alerts').doc(sosId).update({
          lat,
          lng,
          accuracy:  accuracy ?? null,
          updatedAt: new Date().toISOString(),
        });
      } catch (_) { /* non-fatal */ }

      // Update SQL for non-temp IDs
      if (!sosId.startsWith('tmp-')) {
        try {
          await query(
            `UPDATE sos_alerts SET lat = $2, lng = $3 WHERE id = $1 AND status = 'ACTIVE'`,
            [sosId, lat, lng]
          );
        } catch (_) { /* non-fatal */ }
      }

      broadcastToClients('emergency', {
        type:      'SOS_LOCATION_UPDATE',
        sosId,
        lat,
        lng,
        accuracy:  accuracy ?? null,
        updatedAt: new Date().toISOString(),
      });

      res.json({ success: true });
    } catch (err) {
      console.error('🔴 [SOS/quick/update]', (err as Error).message);
      res.status(500).json({ success: false, error: 'Failed to update SOS location' });
    }
  }
);

// =============================================================
// POST /sos/quick/cancel  — User signals they are safe
// Body: { sosId, deviceId? }
// =============================================================
router.post(
  '/quick/cancel',
  requireApiKey,
  [
    body('sosId').isString().trim().notEmpty(),
    body('deviceId').optional().isString().trim(),
  ],
  async (req: Request, res: Response): Promise<void> => {
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
      res.status(400).json({ success: false, errors: errors.array() });
      return;
    }

    const { sosId } = req.body as { sosId: string };

    try {
      if (!sosId.startsWith('tmp-')) {
        await query(
          `UPDATE sos_alerts SET status = 'CANCELLED' WHERE id = $1 AND status = 'ACTIVE'`,
          [sosId]
        );
      }

      try {
        await getFirestore().collection('sos_alerts').doc(sosId).update({
          status:      'CANCELLED',
          cancelledAt: new Date().toISOString(),
        });
      } catch (_) { /* non-fatal */ }

      broadcastToClients('emergency', { type: 'SOS_CANCELLED', sosId });

      res.json({ success: true, message: 'SOS cancelled — glad you are safe.' });
    } catch (err) {
      console.error('🔴 [SOS/quick/cancel]', (err as Error).message);
      res.status(500).json({ success: false, error: 'Failed to cancel SOS' });
    }
  }
);

// =============================================================
// POST /sos  — Authenticated SOS (Firebase auth users)
// =============================================================
router.post(
  '/',
  verifyToken,
  requireRole('normal'),
  [
    body('lat').isFloat({ min: -90, max: 90 }).withMessage('Valid latitude required'),
    body('lng').isFloat({ min: -180, max: 180 }).withMessage('Valid longitude required'),
    body('message').optional().isString().trim().isLength({ max: 500 }),
  ],
  async (req: AuthRequest, res: Response): Promise<void> => {
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
      res.status(400).json({ success: false, errors: errors.array() });
      return;
    }

    const { lat, lng, message = 'EMERGENCY SOS — User needs immediate help!' } = req.body as {
      lat: number;
      lng: number;
      message?: string;
    };

    try {
      const result = await query(
        `INSERT INTO sos_alerts (user_uid, lat, lng, message)
         VALUES ($1, $2, $3, $4)
         RETURNING *`,
        [req.user!.uid, lat, lng, message]
      );

      const sosAlert = result.rows[0];
      console.log(`🆘 [SOS] Alert created: ${sosAlert.id} from ${req.user!.uid}`);

      const sosPayload = {
        id:        sosAlert.id,
        userUid:   sosAlert.user_uid,
        lat:       sosAlert.lat,
        lng:       sosAlert.lng,
        status:    sosAlert.status,
        message,
        createdAt: sosAlert.created_at,
      };

      try {
        await getFirestore().collection('sos_alerts').doc(sosAlert.id).set(sosPayload);
      } catch (e) { /* non-fatal */ }

      sendSOSToAllResponders(sosAlert.id, req.user!.uid, lat, lng, message);
      broadcastToClients('emergency', { type: 'SOS_ALERT', sos: sosPayload });

      res.status(201).json({
        success: true,
        message: 'SOS alert sent to all emergency responders',
        sosAlert: sosPayload,
      });
    } catch (err) {
      console.error('🔴 [SOS/create]', (err as Error).message);
      res.status(500).json({ success: false, error: 'Failed to send SOS' });
    }
  }
);

// =============================================================
// GET /sos — Active SOS list (Emergency responders only)
// =============================================================
router.get('/', verifyToken, requireRole('emergency'), async (req: AuthRequest, res: Response): Promise<void> => {
  try {
    const result = await query(
      `SELECT sa.*, u.name as user_name, u.email as user_email
       FROM sos_alerts sa
       LEFT JOIN users u ON u.firebase_uid = sa.user_uid
       WHERE sa.status = 'ACTIVE'
       ORDER BY sa.created_at DESC
       LIMIT 50`,
      []
    );

    res.json({ success: true, sosAlerts: result.rows });
  } catch (err) {
    console.error('🔴 [SOS/list]', (err as Error).message);
    res.status(500).json({ success: false, error: 'Failed to fetch SOS alerts' });
  }
});

// =============================================================
// PUT /sos/:id/respond — Responder acknowledges SOS
// =============================================================
router.put('/:id/respond', verifyToken, requireRole('emergency'), async (req: AuthRequest, res: Response): Promise<void> => {
  try {
    const result = await query(
      `UPDATE sos_alerts SET status = 'RESOLVED', responded_by = $2
       WHERE id = $1 AND status = 'ACTIVE'
       RETURNING *`,
      [req.params.id, req.user!.uid]
    );

    if (result.rows.length === 0) {
      res.status(404).json({ success: false, error: 'SOS alert not found or already resolved' });
      return;
    }

    try {
      await getFirestore().collection('sos_alerts').doc(req.params.id).update({
        status:      'RESOLVED',
        respondedBy: req.user!.uid,
        resolvedAt:  new Date().toISOString(),
      });
    } catch (e) { /* non-fatal */ }

    broadcastToClients('emergency', {
      type:        'SOS_RESPONDED',
      sosId:       req.params.id,
      respondedBy: req.user!.uid,
    });

    res.json({ success: true, sosAlert: result.rows[0] });
  } catch (err) {
    console.error('🔴 [SOS/respond]', (err as Error).message);
    res.status(500).json({ success: false, error: 'Failed to update SOS' });
  }
});

// =============================================================
// DELETE /sos/:id — Authenticated user cancels own SOS
// =============================================================
router.delete('/:id', verifyToken, async (req: AuthRequest, res: Response): Promise<void> => {
  try {
    const result = await query(
      `UPDATE sos_alerts SET status = 'CANCELLED'
       WHERE id = $1 AND user_uid = $2 AND status = 'ACTIVE'
       RETURNING *`,
      [req.params.id, req.user!.uid]
    );

    if (result.rows.length === 0) {
      res.status(404).json({ success: false, error: 'SOS alert not found or already resolved' });
      return;
    }

    try {
      await getFirestore().collection('sos_alerts').doc(req.params.id).update({ status: 'CANCELLED' });
    } catch (e) { /* non-fatal */ }

    broadcastToClients('emergency', { type: 'SOS_CANCELLED', sosId: req.params.id });
    res.json({ success: true, message: 'SOS alert cancelled' });
  } catch (err) {
    console.error('🔴 [SOS/cancel]', (err as Error).message);
    res.status(500).json({ success: false, error: 'Failed to cancel SOS' });
  }
});

// =============================================================
// FCM PUSH — SOS to all emergency responders
// =============================================================
async function sendSOSToAllResponders(
  sosId: string,
  userId: string,
  lat: number,
  lng: number,
  message: string,
  name?: string
): Promise<void> {
  try {
    const tokenResult = await query(
      `SELECT fcm_token FROM users WHERE role = 'emergency' AND fcm_token IS NOT NULL`,
      []
    );

    const tokens = tokenResult.rows.map((r: { fcm_token: string }) => r.fcm_token).filter(Boolean);
    if (tokens.length === 0) {
      console.warn('🟡 [FCM/SOS] No emergency responder tokens registered');
      return;
    }

    await getMessaging().sendEachForMulticast({
      tokens,
      notification: {
        title: `🆘 SOS ALERT${name ? ` — ${name}` : ''} — IMMEDIATE RESPONSE REQUIRED`,
        body:  message,
      },
      data: {
        type:         'SOS',
        sosId,
        userId,
        name:         name || 'Anonymous',
        lat:          String(lat),
        lng:          String(lng),
        click_action: 'FLUTTER_NOTIFICATION_CLICK',
      },
      android: {
        priority: 'high',
        notification: { sound: 'default', channelId: 'sos_alerts' },
      },
      apns: {
        payload: { aps: { contentAvailable: true, sound: 'default' } },
      },
    });

    console.log(`📱 [FCM] SOS pushed to ${tokens.length} responders`);
  } catch (err) {
    console.warn('🟡 [FCM/SOS] Push failed (non-fatal):', (err as Error).message);
  }
}

export default router;
