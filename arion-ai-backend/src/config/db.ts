import { Pool, PoolClient } from 'pg';
import dotenv from 'dotenv';

dotenv.config();

// =============================================================
// DATABASE POOL — Production-grade pg.Pool
// =============================================================
const pool = new Pool({
  host:     process.env.DB_HOST     || '136.113.64.114',
  port:     parseInt(process.env.DB_PORT || '5432'),
  user:     process.env.DB_USER     || 'postgres',
  password: process.env.DB_PASSWORD || '',
  database: process.env.DB_NAME     || 'postgres',
  ssl: { rejectUnauthorized: false }, // Required for Cloud SQL public IP
  max: 20,
  idleTimeoutMillis: 30000,
  connectionTimeoutMillis: 5000,
});

pool.on('error', (err) => {
  console.error('🔴 [DB] Unexpected pool error:', err.message);
});

// =============================================================
// HELPERS
// =============================================================
async function tableExists(client: PoolClient, tableName: string): Promise<boolean> {
  const res = await client.query(
    `SELECT EXISTS (
       SELECT FROM information_schema.tables
       WHERE table_schema = 'public' AND table_name = $1
     )`,
    [tableName]
  );
  return res.rows[0].exists as boolean;
}

async function columnExists(client: PoolClient, tableName: string, columnName: string): Promise<boolean> {
  const res = await client.query(
    `SELECT EXISTS (
       SELECT FROM information_schema.columns
       WHERE table_schema = 'public' AND table_name = $1 AND column_name = $2
     )`,
    [tableName, columnName]
  );
  return res.rows[0].exists as boolean;
}

async function addColumnIfMissing(
  client: PoolClient,
  table: string,
  column: string,
  definition: string
): Promise<void> {
  if (!(await columnExists(client, table, column))) {
    await client.query(`ALTER TABLE ${table} ADD COLUMN ${column} ${definition};`);
    console.log(`   ↳ Added column: ${table}.${column}`);
  }
}

// =============================================================
// DB INIT — Safe idempotent schema management
// Creates tables fresh if they don't exist.
// Migrates existing tables by adding missing columns.
// =============================================================
export async function initDb(): Promise<void> {
  const client = await pool.connect();
  try {
    // Enable required extensions
    await client.query(`CREATE EXTENSION IF NOT EXISTS "uuid-ossp";`);
    await client.query(`CREATE EXTENSION IF NOT EXISTS cube;`);
    await client.query(`CREATE EXTENSION IF NOT EXISTS earthdistance;`);

    // ── USERS TABLE ──────────────────────────────────────────
    if (!(await tableExists(client, 'users'))) {
      await client.query(`
        CREATE TABLE users (
          id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
          firebase_uid  VARCHAR(128) UNIQUE NOT NULL,
          name          VARCHAR(255) NOT NULL DEFAULT 'Anonymous',
          email         VARCHAR(255),
          role          VARCHAR(20)  NOT NULL DEFAULT 'normal',
          fcm_token     TEXT,
          last_lat      DOUBLE PRECISION,
          last_lng      DOUBLE PRECISION,
          created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
          updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
        );
      `);
      console.log('   ✅ Created table: users');
    } else {
      // Migrate existing users table
      await addColumnIfMissing(client, 'users', 'role',      `VARCHAR(20) NOT NULL DEFAULT 'normal'`);
      await addColumnIfMissing(client, 'users', 'fcm_token', `TEXT`);
      await addColumnIfMissing(client, 'users', 'last_lat',  `DOUBLE PRECISION`);
      await addColumnIfMissing(client, 'users', 'last_lng',  `DOUBLE PRECISION`);
      await addColumnIfMissing(client, 'users', 'updated_at',`TIMESTAMPTZ DEFAULT NOW()`);
      console.log('   ✅ Migrated table: users');
    }
    await client.query(`CREATE INDEX IF NOT EXISTS idx_users_firebase_uid ON users(firebase_uid);`);
    await client.query(`CREATE INDEX IF NOT EXISTS idx_users_role ON users(role);`);

    // ── INCIDENTS TABLE ──────────────────────────────────────
    if (!(await tableExists(client, 'incidents'))) {
      await client.query(`
        CREATE TABLE incidents (
          id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
          reporter_uid    VARCHAR(128),
          message         TEXT NOT NULL,
          incident_type   VARCHAR(50)  NOT NULL DEFAULT 'Unknown',
          severity        VARCHAR(20)  NOT NULL DEFAULT 'MODERATE',
          confidence      INTEGER      NOT NULL DEFAULT 50,
          ai_summary      TEXT,
          lat             DOUBLE PRECISION,
          lng             DOUBLE PRECISION,
          address         TEXT,
          status          VARCHAR(20)  NOT NULL DEFAULT 'ACTIVE',
          assigned_to     VARCHAR(128),
          resolved_at     TIMESTAMPTZ,
          resolved_by     VARCHAR(128),
          created_at      TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
          updated_at      TIMESTAMPTZ  NOT NULL DEFAULT NOW()
        );
      `);
      console.log('   ✅ Created table: incidents');
    } else {
      // Migrate existing incidents table — add missing columns
      await addColumnIfMissing(client, 'incidents', 'reporter_uid',        `VARCHAR(128)`);
      await addColumnIfMissing(client, 'incidents', 'message',             `TEXT DEFAULT ''`);
      await addColumnIfMissing(client, 'incidents', 'incident_type',       `VARCHAR(50) DEFAULT 'Unknown'`);
      await addColumnIfMissing(client, 'incidents', 'severity',            `VARCHAR(20) DEFAULT 'MODERATE'`);
      await addColumnIfMissing(client, 'incidents', 'confidence',          `INTEGER DEFAULT 50`);
      await addColumnIfMissing(client, 'incidents', 'ai_summary',          `TEXT`);
      await addColumnIfMissing(client, 'incidents', 'lat',                 `DOUBLE PRECISION`);
      await addColumnIfMissing(client, 'incidents', 'lng',                 `DOUBLE PRECISION`);
      await addColumnIfMissing(client, 'incidents', 'address',             `TEXT`);
      await addColumnIfMissing(client, 'incidents', 'status',              `VARCHAR(20) DEFAULT 'ACTIVE'`);
      await addColumnIfMissing(client, 'incidents', 'assigned_to',         `VARCHAR(128)`);
      await addColumnIfMissing(client, 'incidents', 'resolved_at',         `TIMESTAMPTZ`);
      await addColumnIfMissing(client, 'incidents', 'resolved_by',         `VARCHAR(128)`);
      await addColumnIfMissing(client, 'incidents', 'updated_at',          `TIMESTAMPTZ DEFAULT NOW()`);
      await addColumnIfMissing(client, 'incidents', 'corroboration_count', `INTEGER NOT NULL DEFAULT 1`);
      await addColumnIfMissing(client, 'incidents', 'escalation_count',    `INTEGER NOT NULL DEFAULT 0`);
      await addColumnIfMissing(client, 'incidents', 'last_escalated_at',   `TIMESTAMPTZ`);
      console.log('   ✅ Migrated table: incidents');
    }
    // Create indexes only after columns are guaranteed to exist
    if (await columnExists(client, 'incidents', 'status')) {
      await client.query(`CREATE INDEX IF NOT EXISTS idx_incidents_status ON incidents(status);`);
    }
    if (await columnExists(client, 'incidents', 'created_at')) {
      await client.query(`CREATE INDEX IF NOT EXISTS idx_incidents_created ON incidents(created_at DESC);`);
    }
    if (await columnExists(client, 'incidents', 'severity')) {
      await client.query(`CREATE INDEX IF NOT EXISTS idx_incidents_severity ON incidents(severity);`);
    }
    if (await columnExists(client, 'incidents', 'reporter_uid')) {
      await client.query(`CREATE INDEX IF NOT EXISTS idx_incidents_reporter ON incidents(reporter_uid);`);
    }

    // ── SOS ALERTS TABLE ─────────────────────────────────────
    if (!(await tableExists(client, 'sos_alerts'))) {
      await client.query(`
        CREATE TABLE sos_alerts (
          id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
          user_uid      VARCHAR(128) NOT NULL,
          lat           DOUBLE PRECISION NOT NULL,
          lng           DOUBLE PRECISION NOT NULL,
          status        VARCHAR(20)  NOT NULL DEFAULT 'ACTIVE',
          responded_by  VARCHAR(128),
          message       TEXT,
          name          VARCHAR(255),
          phone         VARCHAR(30),
          accuracy      DOUBLE PRECISION,
          altitude      DOUBLE PRECISION,
          anonymous     BOOLEAN DEFAULT FALSE,
          created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
          updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
        );
      `);
      console.log('   ✅ Created table: sos_alerts');
    } else {
      await addColumnIfMissing(client, 'sos_alerts', 'responded_by', `VARCHAR(128)`);
      await addColumnIfMissing(client, 'sos_alerts', 'updated_at',   `TIMESTAMPTZ DEFAULT NOW()`);
      await addColumnIfMissing(client, 'sos_alerts', 'message',      `TEXT`);
      await addColumnIfMissing(client, 'sos_alerts', 'name',         `VARCHAR(255)`);
      await addColumnIfMissing(client, 'sos_alerts', 'phone',        `VARCHAR(30)`);
      await addColumnIfMissing(client, 'sos_alerts', 'accuracy',     `DOUBLE PRECISION`);
      await addColumnIfMissing(client, 'sos_alerts', 'altitude',     `DOUBLE PRECISION`);
      await addColumnIfMissing(client, 'sos_alerts', 'anonymous',    `BOOLEAN DEFAULT FALSE`);
      console.log('   ✅ Migrated table: sos_alerts');
    }
    await client.query(`CREATE INDEX IF NOT EXISTS idx_sos_status ON sos_alerts(status);`);
    await client.query(`CREATE INDEX IF NOT EXISTS idx_sos_user   ON sos_alerts(user_uid);`);

    // ── INCIDENT UPDATES TABLE ───────────────────────────────
    // Note: No FK on incident_id — legacy incidents table may have non-UUID PK
    if (!(await tableExists(client, 'incident_updates'))) {
      await client.query(`
        CREATE TABLE incident_updates (
          id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
          incident_id   TEXT NOT NULL,
          author_uid    VARCHAR(128) NOT NULL,
          message       TEXT NOT NULL,
          update_type   VARCHAR(30) NOT NULL DEFAULT 'UPDATE',
          created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
        );
      `);
      console.log('   ✅ Created table: incident_updates');
    }
    await client.query(`CREATE INDEX IF NOT EXISTS idx_updates_incident ON incident_updates(incident_id);`);

    // ── TRIGGER FUNCTION ─────────────────────────────────────
    await client.query(`
      CREATE OR REPLACE FUNCTION update_updated_at_column()
      RETURNS TRIGGER AS $$
      BEGIN NEW.updated_at = NOW(); RETURN NEW; END;
      $$ language 'plpgsql';
    `);

    for (const [trigger, table] of [
      ['update_users_updated_at', 'users'],
      ['update_incidents_updated_at', 'incidents'],
      ['update_sos_updated_at', 'sos_alerts'],
    ]) {
      await client.query(`
        DO $$ BEGIN
          IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = '${trigger}') THEN
            CREATE TRIGGER ${trigger} BEFORE UPDATE ON ${table}
              FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
          END IF;
        END $$;
      `);
    }

    console.log('✅ [DB] Schema initialization complete');
  } catch (err) {
    console.error('🔴 [DB] Schema init failed:', (err as Error).message);
    throw err;
  } finally {
    client.release();
  }
}

export async function query(text: string, params?: unknown[]) {
  const start = Date.now();
  const res = await pool.query(text, params);
  const duration = Date.now() - start;
  if (duration > 500) {
    console.warn(`🟡 [DB] Slow query (${duration}ms): ${text.slice(0, 80)}...`);
  }
  return res;
}

export async function getClient(): Promise<PoolClient> {
  return pool.connect();
}

export default pool;
