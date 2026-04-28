import path from 'path';
import fs from 'fs';
import express from 'express';
import cors from 'cors';
import helmet from 'helmet';
import morgan from 'morgan';
import dotenv from 'dotenv';
import http from 'http';
import { WebSocketServer, WebSocket } from 'ws';

// =============================================================
// ENVIRONMENT
// =============================================================
dotenv.config();

// =============================================================
// SERVICE ACCOUNT BOOTSTRAP
// Copy service.json → service-account.json on first run
// =============================================================
const saPath = path.resolve(process.cwd(), 'service-account.json');
const fallbackSa = path.resolve(process.cwd(), '..', 'service.json');

if (!fs.existsSync(saPath) && fs.existsSync(fallbackSa)) {
  fs.copyFileSync(fallbackSa, saPath);
  console.log('📄 [Bootstrap] Copied service.json → service-account.json');
}

// =============================================================
// IMPORT CONFIGS (after env is loaded)
// =============================================================
import { initDb }       from './config/db';
import { initFirebase }  from './config/firebase';
import { getMessaging }  from './config/firebase';
import { query }         from './config/db';
import authRouter        from './routes/auth';
import incidentsRouter   from './routes/incidents';
import sosRouter         from './routes/sos';
import dashboardRouter   from './routes/dashboard';
import analyticsRouter   from './routes/analytics';

// =============================================================
// EXPRESS APP
// =============================================================
const app = express();
const PORT = parseInt(process.env.PORT || '8080');

// --- Security & Parsing Middleware ---
app.use(helmet());
app.use(cors({
  origin: '*', // Flutter apps — lock down to your domain in production
  methods: ['GET', 'POST', 'PUT', 'DELETE', 'PATCH'],
  allowedHeaders: ['Authorization', 'Content-Type', 'X-Api-Key'],
}));
app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ extended: true }));
app.use(morgan('[:date[clf]] :method :url :status :response-time ms'));

// =============================================================
// ROUTES
// =============================================================
app.use('/auth',       authRouter);
app.use('/incidents',  incidentsRouter);
app.use('/sos',        sosRouter);
app.use('/dashboard',  dashboardRouter);
app.use('/analytics',  analyticsRouter);

// --- Health Check ---
app.get('/', (_req, res) => {
  res.json({
    service:   '🤖 Arion AI — LiveCrisis API',
    version:   '3.0.0',
    status:    'operational',
    timestamp: new Date().toISOString(),
    endpoints: {
      auth:      '/auth',
      incidents: '/incidents',
      sos:       '/sos',
      dashboard: '/dashboard',
      analytics: '/analytics',
      websocket: 'ws://<host>/ws',
    },
    features: [
      '🧠 Gemini AI triage + SITREP generation',
      '🔗 Smart incident clustering (500m dedup)',
      '👥 Crowd corroboration voting',
      '🚨 Auto-escalation engine (every 2 min)',
      '🗺️  Heatmap analytics API',
      '📊 Trend charts + responder performance',
    ],
  });
});

// --- 404 Handler ---
app.use((_req, res) => {
  res.status(404).json({ success: false, error: 'Endpoint not found' });
});

// --- Global Error Handler ---
app.use((err: Error, _req: express.Request, res: express.Response, _next: express.NextFunction) => {
  console.error('🔴 [Server] Unhandled error:', err.message);
  res.status(500).json({ success: false, error: 'Internal server error' });
});

// =============================================================
// HTTP SERVER + WEBSOCKET SERVER
// WebSocket rooms: 'emergency' (responders) | 'user:<uid>' (personal)
// =============================================================
const server = http.createServer(app);
const wss    = new WebSocketServer({ server, path: '/ws' });

// Track connected clients with their room
interface WSClient {
  ws:   WebSocket;
  room: string;
  uid?: string;
}

const wsClients: Set<WSClient> = new Set();

wss.on('connection', (ws, req) => {
  const url   = new URL(req.url || '/', `http://${req.headers.host}`);
  const room  = url.searchParams.get('room') || 'emergency';
  const uid   = url.searchParams.get('uid') || undefined;

  const client: WSClient = { ws, room, uid };
  wsClients.add(client);
  console.log(`🔌 [WS] Client connected — room: ${room}, uid: ${uid || 'anonymous'}`);

  ws.send(JSON.stringify({ type: 'CONNECTED', room, message: 'Connected to Arion AI real-time feed' }));

  ws.on('close', () => {
    wsClients.delete(client);
    console.log(`🔌 [WS] Client disconnected — room: ${room}`);
  });

  ws.on('error', (err) => {
    console.warn('🟡 [WS] Client error:', err.message);
    wsClients.delete(client);
  });

  // Ping to keep connection alive
  const pingInterval = setInterval(() => {
    if (ws.readyState === WebSocket.OPEN) {
      ws.ping();
    } else {
      clearInterval(pingInterval);
    }
  }, 30000);
});

// =============================================================
// BROADCAST HELPER
// Used by routes to push updates to connected WebSocket clients
// room: 'emergency' sends to all emergency room clients
// room: 'user:<uid>' sends to a specific user
// =============================================================
export function broadcastToClients(room: string, payload: object): void {
  const message = JSON.stringify(payload);
  for (const client of wsClients) {
    if (
      client.ws.readyState === WebSocket.OPEN &&
      (client.room === room || client.room === 'all')
    ) {
      try {
        client.ws.send(message);
      } catch (e) { /* ignore send errors */ }
    }
  }
}

// =============================================================
// STARTUP
// =============================================================
async function bootstrap(): Promise<void> {
  console.log('\n╔══════════════════════════════════════════╗');
  console.log('║   🤖  ARION AI — LIVECRISIS BACKEND      ║');
  console.log('║   Powered by Google Cloud + Gemini AI    ║');
  console.log('╚══════════════════════════════════════════╝\n');

  // --- 1. Initialize Firebase Admin ---
  try {
    initFirebase();
  } catch (err) {
    console.error('🔴 [Firebase] FATAL:', (err as Error).message);
    process.exit(1);
  }

  // --- 2. Initialize PostgreSQL (Cloud SQL) ---
  try {
    await initDb();
    console.log('✅ [Cloud SQL] Connected and schema verified');
  } catch (err) {
    console.error('🔴 [Cloud SQL] Connection failed:', (err as Error).message);
    console.error('   → Add your IP to Cloud SQL Authorized Networks');
    console.error('   → GCP Console → SQL → Your Instance → Connections → Networking');
    // Continue startup — DB errors shouldn't prevent health checks from working
  }

  // --- 3. Start HTTP + WebSocket Server ---
  server.listen(PORT, () => {
    console.log(`\n🚀 [Server] Arion AI API running on http://localhost:${PORT}`);
    console.log(`🔌 [WS]     WebSocket feed at ws://localhost:${PORT}/ws`);
    console.log(`\n📋 API Endpoints:`);
    console.log(`   POST   /auth/register         — Register/sync user profile`);
    console.log(`   GET    /auth/profile           — Get user profile`);
    console.log(`   PUT    /auth/profile           — Update FCM token, location`);
    console.log(`   POST   /incidents/report       — Report incident (AI triage) [auth]`);
    console.log(`   POST   /incidents/quick-report — Report incident anonymous [X-Api-Key]`);
    console.log(`   GET    /incidents              — List incidents`);
    console.log(`   GET    /incidents/nearby       — Map view nearby incidents (Flutter model)`);
    console.log(`   GET    /incidents/:id          — Incident detail + timeline`);
    console.log(`   PUT    /incidents/:id/resolve  — Mark resolved [emergency]`);
    console.log(`   PUT    /incidents/:id/assign   — Assign to self [emergency]`);
    console.log(`   PUT    /incidents/:id/safe     — Mark self safe [normal]`);
    console.log(`   POST   /sos                   — SOS panic button [normal]`);
    console.log(`   POST   /sos/quick             — SOS anonymous [X-Api-Key]`);
    console.log(`   GET    /sos                   — Active SOS alerts [emergency]`);
    console.log(`   PUT    /sos/:id/respond        — Respond to SOS [emergency]`);
    console.log(`   DELETE /sos/:id               — Cancel SOS [normal]`);
    console.log(`   GET    /dashboard/stats        — Dashboard stats + availableUnits [emergency]`);
    console.log(`   GET    /dashboard/incidents    — Priority sorted list [emergency]`);
    console.log(`   GET    /dashboard/sos          — SOS map view [emergency]`);
    console.log('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');
  });
}

bootstrap().catch((err) => {
  console.error('🔴 [FATAL] Server failed to start:', err);
  process.exit(1);
});

// =============================================================
// AUTO-ESCALATION ENGINE
// Runs every 2 minutes. Finds CRITICAL incidents that have been
// ACTIVE for more than 3 minutes with no responder assigned,
// and re-pushes FCM to all emergency responders.
// Escalation count is tracked to avoid infinite re-alerting
// (stops after 3 escalations).
// =============================================================
async function runEscalationEngine(): Promise<void> {
  try {
    // Find unassigned CRITICAL incidents older than 3 minutes, not yet over-escalated
    const result = await query(
      `SELECT id, incident_type, severity, ai_summary, lat, lng, address,
              escalation_count, corroboration_count
       FROM incidents
       WHERE severity = 'CRITICAL'
         AND status = 'ACTIVE'
         AND assigned_to IS NULL
         AND created_at <= NOW() - INTERVAL '3 minutes'
         AND (escalation_count IS NULL OR escalation_count < 3)
         AND (last_escalated_at IS NULL OR last_escalated_at <= NOW() - INTERVAL '2 minutes')
       LIMIT 10`,
      []
    );

    if (result.rows.length === 0) return;

    for (const incident of result.rows) {
      // Increment escalation count and timestamp
      await query(
        `UPDATE incidents
         SET escalation_count  = COALESCE(escalation_count, 0) + 1,
             last_escalated_at = NOW()
         WHERE id = $1`,
        [incident.id]
      );

      const escalationNum = (incident.escalation_count || 0) + 1;
      console.log(`🚨 [Escalation] Re-alerting for incident ${incident.id} (escalation #${escalationNum})`);

      // Add timeline entry
      await query(
        `INSERT INTO incident_updates (incident_id, author_uid, message, update_type)
         VALUES ($1, 'system', $2, 'STATUS_CHANGE')`,
        [
          incident.id,
          `⚠️ AUTO-ESCALATION #${escalationNum}: CRITICAL incident unattended for >3 minutes. Re-alerting all responders.`,
        ]
      );

      // Re-push FCM to all emergency responders
      try {
        const tokenResult = await query(
          `SELECT fcm_token FROM users WHERE role = 'emergency' AND fcm_token IS NOT NULL`,
          []
        );
        const tokens = tokenResult.rows
          .map((r: { fcm_token: string }) => r.fcm_token)
          .filter(Boolean);

        if (tokens.length > 0) {
          await getMessaging().sendEachForMulticast({
            tokens,
            notification: {
              title: `🚨 ESCALATION #${escalationNum} — ${incident.incident_type} UNATTENDED`,
              body:  incident.ai_summary || `CRITICAL ${incident.incident_type} requires immediate response!`,
            },
            data: {
              incidentId:   incident.id,
              incidentType: incident.incident_type,
              severity:     'CRITICAL',
              escalation:   String(escalationNum),
              lat:          String(incident.lat),
              lng:          String(incident.lng),
              click_action: 'FLUTTER_NOTIFICATION_CLICK',
            },
            android: { priority: 'high' },
          });
          console.log(`📱 [Escalation] FCM re-sent to ${tokens.length} responders for incident ${incident.id}`);
        }
      } catch (fcmErr) {
        console.warn('🟡 [Escalation] FCM failed (non-fatal):', (fcmErr as Error).message);
      }

      // WebSocket alert
      broadcastToClients('emergency', {
        type:         'INCIDENT_ESCALATED',
        incidentId:   incident.id,
        escalationNum,
        incidentType: incident.incident_type,
        message:      `CRITICAL incident unattended — escalation #${escalationNum}`,
      });
    }
  } catch (err) {
    console.warn('🟡 [Escalation Engine] Error (non-fatal):', (err as Error).message);
  }
}

// Start the escalation engine AFTER the server is up (delay 10s for DB to be ready)
setTimeout(() => {
  console.log('⚡ [Escalation Engine] Started — checking every 2 minutes');
  setInterval(runEscalationEngine, 2 * 60 * 1000);
}, 10000);

export default app;
