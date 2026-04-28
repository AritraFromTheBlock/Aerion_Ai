require('dotenv').config();
const { Pool } = require('pg');
const p = new Pool({
  host: process.env.DB_HOST,
  port: 5432,
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
  database: process.env.DB_NAME,
  ssl: { rejectUnauthorized: false }
});

async function run() {
  // Add created_at column using updated_at as backfill
  await p.query(`
    ALTER TABLE incidents ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ DEFAULT NOW();
  `);
  // Backfill created_at from updated_at for existing rows
  await p.query(`
    UPDATE incidents SET created_at = updated_at WHERE created_at IS NULL;
  `);
  // Make id column sequence-compatible and also add uuid alias for new rows
  console.log('✅ Added created_at to incidents table');
  
  const r = await p.query("SELECT column_name FROM information_schema.columns WHERE table_name = 'incidents' ORDER BY ordinal_position");
  console.log('Final columns:', r.rows.map(x => x.column_name).join(', '));
  p.end();
}

run().catch(e => { console.error(e.message); p.end(); });
