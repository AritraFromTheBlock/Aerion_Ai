-- =============================================
-- ARION AI — LiveCrisis Database Schema v2
-- Cloud SQL PostgreSQL
-- Run this to initialize OR migrate the database.
-- All statements use IF NOT EXISTS / addColumnIfMissing
-- patterns so it is safe to re-run on existing DBs.
-- =============================================

-- =============================================
-- EXTENSIONS
-- =============================================
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS cube;
CREATE EXTENSION IF NOT EXISTS earthdistance;

-- =============================================
-- USERS TABLE
-- =============================================
CREATE TABLE IF NOT EXISTS users (
    id           UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    firebase_uid VARCHAR(128) UNIQUE NOT NULL,
    name         VARCHAR(255) NOT NULL DEFAULT 'Anonymous',
    email        VARCHAR(255),
    role         VARCHAR(20)  NOT NULL DEFAULT 'normal'
                     CHECK (role IN ('normal', 'emergency')),
    fcm_token    TEXT,
    last_lat     DOUBLE PRECISION,
    last_lng     DOUBLE PRECISION,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_users_firebase_uid ON users(firebase_uid);
CREATE INDEX IF NOT EXISTS idx_users_role          ON users(role);

-- =============================================
-- INCIDENTS TABLE
-- =============================================
CREATE TABLE IF NOT EXISTS incidents (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    reporter_uid        VARCHAR(128),
    message             TEXT NOT NULL,
    incident_type       VARCHAR(50)  NOT NULL DEFAULT 'Unknown',
    severity            VARCHAR(20)  NOT NULL DEFAULT 'MODERATE'
                            CHECK (severity IN ('LOW', 'MODERATE', 'HIGH', 'CRITICAL')),
    confidence          INTEGER      NOT NULL DEFAULT 50
                            CHECK (confidence BETWEEN 0 AND 100),
    ai_summary          TEXT,
    lat                 DOUBLE PRECISION,
    lng                 DOUBLE PRECISION,
    address             TEXT,
    status              VARCHAR(20)  NOT NULL DEFAULT 'ACTIVE'
                            CHECK (status IN ('ACTIVE', 'RESOLVED', 'FALSE_ALARM', 'IN_PROGRESS')),
    assigned_to         VARCHAR(128),
    resolved_at         TIMESTAMPTZ,
    resolved_by         VARCHAR(128),
    corroboration_count INTEGER NOT NULL DEFAULT 1,
    escalation_count    INTEGER NOT NULL DEFAULT 0,
    last_escalated_at   TIMESTAMPTZ,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_incidents_status   ON incidents(status);
CREATE INDEX IF NOT EXISTS idx_incidents_severity  ON incidents(severity);
CREATE INDEX IF NOT EXISTS idx_incidents_reporter  ON incidents(reporter_uid);
CREATE INDEX IF NOT EXISTS idx_incidents_created   ON incidents(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_incidents_location  ON incidents
    USING GIST (ll_to_earth(lat, lng))
    WHERE lat IS NOT NULL AND lng IS NOT NULL;

-- =============================================
-- SOS ALERTS TABLE
-- =============================================
CREATE TABLE IF NOT EXISTS sos_alerts (
    id           UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_uid     VARCHAR(128) NOT NULL,
    lat          DOUBLE PRECISION NOT NULL,
    lng          DOUBLE PRECISION NOT NULL,
    status       VARCHAR(20)  NOT NULL DEFAULT 'ACTIVE'
                     CHECK (status IN ('ACTIVE', 'RESOLVED', 'CANCELLED')),
    responded_by VARCHAR(128),
    message      TEXT,
    name         VARCHAR(255),
    phone        VARCHAR(30),
    accuracy     DOUBLE PRECISION,
    altitude     DOUBLE PRECISION,
    anonymous    BOOLEAN DEFAULT FALSE,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_sos_status ON sos_alerts(status);
CREATE INDEX IF NOT EXISTS idx_sos_user   ON sos_alerts(user_uid);

-- =============================================
-- INCIDENT UPDATES TABLE  (timeline)
-- Note: incident_id is TEXT (not FK) to support
-- anonymous/temp IDs gracefully.
-- =============================================
CREATE TABLE IF NOT EXISTS incident_updates (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    incident_id TEXT        NOT NULL,
    author_uid  VARCHAR(128) NOT NULL,
    message     TEXT        NOT NULL,
    update_type VARCHAR(30) NOT NULL DEFAULT 'UPDATE'
                    CHECK (update_type IN ('UPDATE','RESOLVED','ASSIGNED','STATUS_CHANGE','SAFE_MARK')),
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_updates_incident ON incident_updates(incident_id);

-- =============================================
-- AUTO-UPDATE updated_at trigger
-- =============================================
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ language 'plpgsql';

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'update_users_updated_at') THEN
    CREATE TRIGGER update_users_updated_at
      BEFORE UPDATE ON users
      FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'update_incidents_updated_at') THEN
    CREATE TRIGGER update_incidents_updated_at
      BEFORE UPDATE ON incidents
      FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'update_sos_updated_at') THEN
    CREATE TRIGGER update_sos_updated_at
      BEFORE UPDATE ON sos_alerts
      FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
  END IF;
END $$;
