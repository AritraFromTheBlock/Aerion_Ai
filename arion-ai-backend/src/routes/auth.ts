import { Router, Response } from 'express';
import { body, validationResult } from 'express-validator';
import { verifyToken, AuthRequest } from '../middleware/auth';
import { query } from '../config/db';

const router = Router();

// =============================================================
// POST /auth/register
// Called after Firebase sign-in to create/update profile in DB
// Flutter: Call this right after firebase_auth.signIn()
// Body: { name, role?, fcmToken? }
// =============================================================
router.post(
  '/register',
  verifyToken,
  [
    body('name').optional().isString().trim().isLength({ min: 1, max: 255 }),
    body('role').optional().isIn(['normal', 'emergency']),
    body('fcmToken').optional().isString(),
  ],
  async (req: AuthRequest, res: Response): Promise<void> => {
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
      res.status(400).json({ success: false, errors: errors.array() });
      return;
    }

    try {
      const { name, role = 'normal', fcmToken } = req.body as {
        name?: string;
        role?: string;
        fcmToken?: string;
      };

      const result = await query(
        `INSERT INTO users (firebase_uid, name, email, role, fcm_token)
         VALUES ($1, $2, $3, $4, $5)
         ON CONFLICT (firebase_uid) DO UPDATE SET
           name      = COALESCE(EXCLUDED.name, users.name),
           email     = COALESCE(EXCLUDED.email, users.email),
           role      = EXCLUDED.role,
           fcm_token = COALESCE(EXCLUDED.fcm_token, users.fcm_token),
           updated_at = NOW()
         RETURNING *`,
        [
          req.user!.uid,
          name || req.user?.name || 'Anonymous',
          req.user?.email || null,
          role,
          fcmToken || null,
        ]
      );

      res.status(201).json({
        success: true,
        message: 'User registered/updated successfully',
        user: sanitizeUser(result.rows[0]),
      });
    } catch (err) {
      console.error('🔴 [Auth/register]', (err as Error).message);
      res.status(500).json({ success: false, error: 'Server error during registration' });
    }
  }
);

// =============================================================
// GET /auth/profile
// Get current user's profile
// =============================================================
router.get('/profile', verifyToken, async (req: AuthRequest, res: Response): Promise<void> => {
  try {
    const result = await query(
      'SELECT * FROM users WHERE firebase_uid = $1',
      [req.user!.uid]
    );

    if (result.rows.length === 0) {
      res.status(404).json({ success: false, error: 'Profile not found. Call /auth/register first.' });
      return;
    }

    res.json({ success: true, user: sanitizeUser(result.rows[0]) });
  } catch (err) {
    console.error('🔴 [Auth/profile]', (err as Error).message);
    res.status(500).json({ success: false, error: 'Server error' });
  }
});

// =============================================================
// PUT /auth/profile
// Update profile (name, FCM token, location)
// Flutter: Call this on app start to refresh FCM token
// =============================================================
router.put(
  '/profile',
  verifyToken,
  [
    body('name').optional().isString().trim().isLength({ min: 1, max: 255 }),
    body('fcmToken').optional().isString(),
    body('lat').optional().isFloat({ min: -90, max: 90 }),
    body('lng').optional().isFloat({ min: -180, max: 180 }),
  ],
  async (req: AuthRequest, res: Response): Promise<void> => {
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
      res.status(400).json({ success: false, errors: errors.array() });
      return;
    }

    try {
      const { name, fcmToken, lat, lng } = req.body as {
        name?: string;
        fcmToken?: string;
        lat?: number;
        lng?: number;
      };

      const result = await query(
        `UPDATE users SET
          name      = COALESCE($2, name),
          fcm_token = COALESCE($3, fcm_token),
          last_lat  = COALESCE($4, last_lat),
          last_lng  = COALESCE($5, last_lng)
         WHERE firebase_uid = $1
         RETURNING *`,
        [req.user!.uid, name || null, fcmToken || null, lat || null, lng || null]
      );

      res.json({ success: true, user: sanitizeUser(result.rows[0]) });
    } catch (err) {
      console.error('🔴 [Auth/profile PUT]', (err as Error).message);
      res.status(500).json({ success: false, error: 'Server error' });
    }
  }
);

// Helper to remove sensitive fields
function sanitizeUser(user: Record<string, unknown>) {
  const { fcm_token: _fcm, ...safe } = user;
  return safe;
}

export default router;
