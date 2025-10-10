import pg from 'pg';
const { Pool } = pg;

let pool;

function buildConfig() {
    const url = process.env.DATABASE_URL;
    if (!url) throw new Error('DATABASE_URL is undefined. Set it in .env.test and ensure dotenv/config runs.');
    const cfg = { connectionString: url };
    const wantSsl = process.env.DATABASE_SSL === '1' || process.env.PGSSLMODE === 'require';
    if (wantSsl) cfg.ssl = { rejectUnauthorized: false };
    return cfg;
}

export function getPool() {
    if (!pool) {
        pool = new Pool(buildConfig());
        pool.on('error', (err) => console.error('[pg pool error]', err?.message || err));
    }
    return pool;
}
export async function closePool() {
    if (pool) { await pool.end(); pool = null; }
}
export default { getPool, closePool };
