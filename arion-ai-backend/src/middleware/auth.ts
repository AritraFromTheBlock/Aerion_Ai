import { Request, Response, NextFunction } from 'express';
import { admin } from '../config/firebase';
import { query } from '../config/db';

// =============================================================
// EXTENDED REQUEST TYPE
// Adds decoded Firebase user data to Express request
// =============================================================
export interface AuthRequest extends Request {
  user?: {
    uid: string;
    email?: string;
    name?: string;
    role: 'normal' | 'emergency';
    dbId?: string;
  };
}

// =============================================================
// VERIFY TOKEN MIDDLEWARE
// Validates Firebase ID Token from Authorization header
// Flutter sends: Authorization: Bearer <Firebase ID Token>
// =============================================================
export async function verifyToken(
  req: AuthRequest,
  res: Response,
  next: NextFunction
): Promise<void> {
  const authHeader = req.headers.authorization;

  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    res.status(401).json({
      success: false,
      error: 'Missing or invalid Authorization header. Expected: Bearer <token>',
    });
    return;
  }

  const idToken = authHeader.split('Bearer ')[1];

  try {
    const decodedToken = await admin.auth().verifyIdToken(idToken);

    // Look up user role from our PostgreSQL database
    const userResult = await query(
      'SELECT id, role FROM users WHERE firebase_uid = $1',
      [decodedToken.uid]
    );

    const dbUser = userResult.rows[0];
    const role = (dbUser?.role as 'normal' | 'emergency') || 'normal';

    req.user = {
      uid:    decodedToken.uid,
      email:  decodedToken.email,
      name:   decodedToken.name,
      role,
      dbId:   dbUser?.id,
    };

    // Auto-create user record if first time
    if (!dbUser) {
      await query(
        `INSERT INTO users (firebase_uid, name, email, role)
         VALUES ($1, $2, $3, 'normal')
         ON CONFLICT (firebase_uid) DO NOTHING`,
        [decodedToken.uid, decodedToken.name || 'Anonymous', decodedToken.email || null]
      );
    }

    next();
  } catch (err) {
    console.error('🔴 [Auth] Token verification failed:', (err as Error).message);
    res.status(401).json({
      success: false,
      error: 'Invalid or expired token. Please sign in again.',
    });
  }
}

// =============================================================
// ROLE GUARD MIDDLEWARE
// Use after verifyToken to restrict routes by role
// Usage: router.get('/dashboard', verifyToken, requireRole('emergency'), handler)
// =============================================================
export function requireRole(role: 'normal' | 'emergency') {
  return (req: AuthRequest, res: Response, next: NextFunction): void => {
    if (!req.user) {
      res.status(401).json({ success: false, error: 'Not authenticated' });
      return;
    }
    if (req.user.role !== role) {
      res.status(403).json({
        success: false,
        error: `Access denied. This endpoint requires the '${role}' role.`,
        yourRole: req.user.role,
      });
      return;
    }
    next();
  };
}

// =============================================================
// OPTIONAL AUTH — doesn't fail if no token provided
// Useful for public endpoints that show more data to authed users
// =============================================================
export async function optionalAuth(
  req: AuthRequest,
  res: Response,
  next: NextFunction
): Promise<void> {
  const authHeader = req.headers.authorization;
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    next();
    return;
  }
  return verifyToken(req, res, next);
}

// =============================================================
// REQUIRE API KEY — lightweight guard for anonymous endpoints
// Flutter sends: X-Api-Key: <value from .env ARION_API_KEY>
// Used by /incidents/quick-report and /sos/quick until Firebase
// Auth is integrated into the Flutter app.
// =============================================================
export function requireApiKey(
  req: Request,
  res: Response,
  next: NextFunction
): void {
  const expectedKey = process.env.ARION_API_KEY;
  if (!expectedKey) {
    // If not configured, deny all requests to this endpoint
    res.status(503).json({ success: false, error: 'Anonymous endpoint not configured on server.' });
    return;
  }
  const providedKey = req.headers['x-api-key'];
  if (!providedKey || providedKey !== expectedKey) {
    res.status(401).json({ success: false, error: 'Missing or invalid X-Api-Key header.' });
    return;
  }
  next();
}
