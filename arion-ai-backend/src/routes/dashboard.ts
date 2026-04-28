import { Router, Response } from 'express';
import { verifyToken, requireRole, AuthRequest } from '../middleware/auth';
import { query } from '../config/db';

const router = Router();

// All dashboard routes require emergency responder role
router.use(verifyToken, requireRole('emergency'));

// =============================================================
// GET /dashboard/stats
// Overview stats for the emergency responder dashboard
// =============================================================
router.get('/stats', async (req: AuthRequest, res: Response): Promise<void> => {
  try {
    const [
      activeResult,
      criticalResult,
      resolvedTodayResult,
      sosResult,
      byTypeResult,
      bySeverityResult,
      recentResult,
      availableUnitsResult,
    ] = await Promise.all([
      // Active incidents count
      query(`SELECT COUNT(*) FROM incidents WHERE status IN ('ACTIVE', 'IN_PROGRESS')`, []),

      // Critical incidents count
      query(`SELECT COUNT(*) FROM incidents WHERE severity = 'CRITICAL' AND status = 'ACTIVE'`, []),

      // Resolved today
      query(
        `SELECT COUNT(*) FROM incidents WHERE status = 'RESOLVED' AND resolved_at >= NOW() - INTERVAL '24 hours'`,
        []
      ),

      // Active SOS alerts
      query(`SELECT COUNT(*) FROM sos_alerts WHERE status = 'ACTIVE'`, []),

      // Incidents by type (top 5)
      query(
        `SELECT incident_type, COUNT(*) as count FROM incidents
         WHERE created_at >= NOW() - INTERVAL '7 days'
         GROUP BY incident_type ORDER BY count DESC LIMIT 5`,
        []
      ),

      // Incidents by severity
      query(
        `SELECT severity, COUNT(*) as count FROM incidents
         WHERE status IN ('ACTIVE', 'IN_PROGRESS')
         GROUP BY severity`,
        []
      ),

      // Recent activity (last 10 updates)
      query(
        `SELECT iu.message, iu.update_type, iu.created_at,
                i.incident_type, i.severity,
                u.name as author_name
         FROM incident_updates iu
         JOIN incidents i ON i.id = iu.incident_id
         LEFT JOIN users u ON u.firebase_uid = iu.author_uid
         ORDER BY iu.created_at DESC LIMIT 10`,
        []
      ),

      // Available emergency responders (total registered)
      query(`SELECT COUNT(*) FROM users WHERE role = 'emergency'`, []),
    ]);

    res.json({
      success: true,
      stats: {
        activeIncidents:     parseInt(activeResult.rows[0].count),
        criticalIncidents:   parseInt(criticalResult.rows[0].count),
        resolvedToday:       parseInt(resolvedTodayResult.rows[0].count),
        activeSosAlerts:     parseInt(sosResult.rows[0].count),
        availableUnits:      parseInt(availableUnitsResult.rows[0].count),
        incidentsByType:     byTypeResult.rows,
        incidentsBySeverity: bySeverityResult.rows,
        recentActivity:      recentResult.rows,
      },
    });
  } catch (err) {
    console.error('🔴 [Dashboard/stats]', (err as Error).message);
    res.status(500).json({ success: false, error: 'Failed to fetch dashboard stats' });
  }
});

// =============================================================
// GET /dashboard/incidents
// Priority-sorted incident list with advanced filtering
// Query: ?severity=&type=&status=&assignedToMe=true&lat=&lng=
// =============================================================
router.get('/incidents', async (req: AuthRequest, res: Response): Promise<void> => {
  try {
    const {
      severity,
      type,
      status,
      assignedToMe,
      lat,
      lng,
      page = '1',
      limit = '20',
    } = req.query as Record<string, string>;

    const conditions: string[] = [];
    const params: unknown[] = [];

    if (status && status !== 'ALL') {
      params.push(status);
      conditions.push(`i.status = $${params.length}`);
    }
    if (severity) {
      params.push(severity);
      conditions.push(`i.severity = $${params.length}`);
    }
    if (type) {
      params.push(type);
      conditions.push(`i.incident_type = $${params.length}`);
    }
    if (assignedToMe === 'true') {
      params.push(req.user!.uid);
      conditions.push(`i.assigned_to = $${params.length}`);
    }

    const where = conditions.length > 0 ? `WHERE ${conditions.join(' AND ')}` : '';
    const pageNum  = Math.max(1, parseInt(page));
    const limitNum = Math.min(50, parseInt(limit));
    const offset   = (pageNum - 1) * limitNum;

    let distanceSelect = '';
    let distanceOrder  = '';
    if (lat && lng) {
      params.push(parseFloat(lat), parseFloat(lng));
      const latIdx = params.length - 1;
      const lngIdx = params.length;
      distanceSelect = `, earth_distance(ll_to_earth($${latIdx}, $${lngIdx}), ll_to_earth(i.lat, i.lng)) AS distance_m`;
      distanceOrder  = ', distance_m ASC';
    }

    params.push(limitNum, offset);

    const queryText = `
      SELECT
        i.*,
        u.name as reporter_name${distanceSelect},
        CASE i.severity
          WHEN 'CRITICAL' THEN 4
          WHEN 'HIGH' THEN 3
          WHEN 'MODERATE' THEN 2
          WHEN 'LOW' THEN 1
          ELSE 0
        END AS severity_rank
      FROM incidents i
      LEFT JOIN users u ON u.firebase_uid = i.reporter_uid
      ${where}
      ORDER BY severity_rank DESC, i.created_at DESC${distanceOrder}
      LIMIT $${params.length - 1} OFFSET $${params.length}
    `;

    const result = await query(queryText, params);

    const countResult = await query(
      `SELECT COUNT(*) FROM incidents i ${where}`,
      params.slice(0, params.length - 2)
    );

    res.json({
      success: true,
      incidents: result.rows,
      pagination: {
        page: pageNum,
        limit: limitNum,
        total: parseInt(countResult.rows[0].count),
        pages: Math.ceil(parseInt(countResult.rows[0].count) / limitNum),
      },
    });
  } catch (err) {
    console.error('🔴 [Dashboard/incidents]', (err as Error).message);
    res.status(500).json({ success: false, error: 'Failed to fetch incidents' });
  }
});

// =============================================================
// GET /dashboard/sos
// All active SOS alerts for responder map
// =============================================================
router.get('/sos', async (req: AuthRequest, res: Response): Promise<void> => {
  try {
    const result = await query(
      `SELECT sa.*, u.name, u.email, u.last_lat, u.last_lng
       FROM sos_alerts sa
       LEFT JOIN users u ON u.firebase_uid = sa.user_uid
       WHERE sa.status = 'ACTIVE'
       ORDER BY sa.created_at DESC`,
      []
    );

    res.json({ success: true, sosAlerts: result.rows });
  } catch (err) {
    console.error('🔴 [Dashboard/sos]', (err as Error).message);
    res.status(500).json({ success: false, error: 'Failed to fetch SOS alerts' });
  }
});

export default router;
