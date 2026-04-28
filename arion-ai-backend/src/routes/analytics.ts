import { Router, Response } from 'express';
import { optionalAuth, AuthRequest } from '../middleware/auth';
import { query } from '../config/db';

const router = Router();

// =============================================================
// GET /analytics/heatmap
// Returns incident density grid for Flutter map overlay.
// Divides the requested area into a grid and counts incidents
// per cell. No auth required — useful for public dashboards.
// Query: ?lat=&lng=&radius=20&hours=24&resolution=10
// =============================================================
router.get('/heatmap', optionalAuth, async (req: AuthRequest, res: Response): Promise<void> => {
  const {
    lat,
    lng,
    radius     = '20',    // km radius from center
    hours      = '24',    // look-back window in hours
    resolution = '10',    // grid cells across the diameter
  } = req.query as Record<string, string>;

  if (!lat || !lng) {
    res.status(400).json({ success: false, error: 'lat and lng are required' });
    return;
  }

  try {
    const centerLat    = parseFloat(lat);
    const centerLng    = parseFloat(lng);
    const radiusKm     = parseFloat(radius);
    const hoursBack    = parseInt(hours);
    const radiusMeters = radiusKm * 1000;

    // Fetch all incidents in the radius within the time window
    const result = await query(
      `SELECT
         lat, lng, severity, status, incident_type,
         corroboration_count,
         earth_distance(ll_to_earth($1, $2), ll_to_earth(lat, lng)) AS distance_m
       FROM incidents
       WHERE lat IS NOT NULL
         AND lng IS NOT NULL
         AND created_at >= NOW() - ($3 * INTERVAL '1 hour')
         AND earth_distance(ll_to_earth($1, $2), ll_to_earth(lat, lng)) <= $4
       ORDER BY distance_m ASC
       LIMIT 500`,
      [centerLat, centerLng, hoursBack, radiusMeters]
    );

    // Build heatmap points with weight (corroboration + severity)
    const points = result.rows.map((row: Record<string, unknown>) => {
      const severity = (row.severity as string || '').toUpperCase();
      const severityWeight =
        severity === 'CRITICAL' ? 4 :
        severity === 'HIGH'     ? 3 :
        severity === 'MODERATE' ? 2 : 1;

      const corrobCount = (row.corroboration_count as number) || 1;
      const weight = severityWeight * Math.min(corrobCount, 5); // cap at 5x boost

      return {
        lat:              row.lat,
        lng:              row.lng,
        weight,
        severity:         severity.toLowerCase(),
        incidentType:     row.incident_type,
        corroborationCount: corrobCount,
      };
    });

    res.json({
      success:     true,
      centerLat,
      centerLng,
      radiusKm,
      hoursBack,
      totalPoints: points.length,
      points,
    });
  } catch (err) {
    console.error('🔴 [Analytics/heatmap]', (err as Error).message);
    res.status(500).json({ success: false, error: 'Failed to generate heatmap' });
  }
});

// =============================================================
// GET /analytics/trends
// Incident type and severity trends over configurable windows.
// Useful for the rescue dashboard summary / charts.
// Query: ?hours=168 (default 7 days)
// =============================================================
router.get('/trends', optionalAuth, async (req: AuthRequest, res: Response): Promise<void> => {
  const { hours = '168' } = req.query as Record<string, string>;
  const hoursBack = parseInt(hours);

  try {
    const [byTypeResult, bySeverityResult, byHourResult, responseTimeResult] = await Promise.all([
      // Incidents by type in time window
      query(
        `SELECT incident_type, COUNT(*) AS count,
                AVG(corroboration_count) AS avg_corroboration
         FROM incidents
         WHERE created_at >= NOW() - ($1 * INTERVAL '1 hour')
         GROUP BY incident_type
         ORDER BY count DESC`,
        [hoursBack]
      ),

      // Incidents by severity in time window
      query(
        `SELECT severity, COUNT(*) AS count
         FROM incidents
         WHERE created_at >= NOW() - ($1 * INTERVAL '1 hour')
         GROUP BY severity
         ORDER BY
           CASE severity
             WHEN 'CRITICAL' THEN 4 WHEN 'HIGH' THEN 3
             WHEN 'MODERATE' THEN 2 ELSE 1
           END DESC`,
        [hoursBack]
      ),

      // Hourly incident count (last 24h) for sparkline chart
      query(
        `SELECT
           date_trunc('hour', created_at) AS hour,
           COUNT(*) AS count,
           COUNT(CASE WHEN severity IN ('HIGH','CRITICAL') THEN 1 END) AS high_priority_count
         FROM incidents
         WHERE created_at >= NOW() - INTERVAL '24 hours'
         GROUP BY hour
         ORDER BY hour ASC`,
        []
      ),

      // Average response time (ACTIVE → IN_PROGRESS) in minutes
      query(
        `SELECT
           AVG(EXTRACT(EPOCH FROM (
             (SELECT MIN(iu.created_at) FROM incident_updates iu
              WHERE iu.incident_id = i.id AND iu.update_type = 'ASSIGNED')
             - i.created_at
           )) / 60) AS avg_response_minutes
         FROM incidents i
         WHERE i.status IN ('IN_PROGRESS', 'RESOLVED')
           AND i.created_at >= NOW() - ($1 * INTERVAL '1 hour')`,
        [hoursBack]
      ),
    ]);

    res.json({
      success:             true,
      windowHours:         hoursBack,
      incidentsByType:     byTypeResult.rows,
      incidentsBySeverity: bySeverityResult.rows,
      hourlyVolume:        byHourResult.rows,
      avgResponseMinutes:  parseFloat(responseTimeResult.rows[0]?.avg_response_minutes) || null,
    });
  } catch (err) {
    console.error('🔴 [Analytics/trends]', (err as Error).message);
    res.status(500).json({ success: false, error: 'Failed to fetch trends' });
  }
});

// =============================================================
// GET /analytics/response-performance
// Per-responder response statistics — for command review.
// Requires emergency role.
// =============================================================
router.get('/response-performance', async (req: AuthRequest, res: Response): Promise<void> => {
  try {
    const result = await query(
      `SELECT
         u.name,
         u.firebase_uid,
         COUNT(i.id) AS incidents_handled,
         COUNT(CASE WHEN i.status = 'RESOLVED' THEN 1 END) AS resolved_count,
         AVG(EXTRACT(EPOCH FROM (i.resolved_at - i.created_at)) / 60)
           FILTER (WHERE i.resolved_at IS NOT NULL) AS avg_resolution_minutes
       FROM users u
       LEFT JOIN incidents i ON i.assigned_to = u.firebase_uid
       WHERE u.role = 'emergency'
       GROUP BY u.firebase_uid, u.name
       ORDER BY incidents_handled DESC`,
      []
    );

    res.json({ success: true, responders: result.rows });
  } catch (err) {
    console.error('🔴 [Analytics/performance]', (err as Error).message);
    res.status(500).json({ success: false, error: 'Failed to fetch performance data' });
  }
});

export default router;
