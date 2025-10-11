import pg from 'pg';
const { Pool } = pg;

// Leest DATABASE_URL uit .env.dev (dev) of .env.test (tests)
export const pool = new Pool({
    connectionString: process.env.DATABASE_URL,
    ssl: false, // lokaal geen SSL
});

export async function closePool() {
    await pool.end();
}
