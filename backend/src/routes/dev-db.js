import { Router } from 'express';
import { pool } from '../db/pool.js';

const router = Router();

/**
 * GET /dev/db/health
 * Doet 1 simpele query om connectie + rechten te checken.
 */
router.get('/health', async (req, res) => {
    try {
        const { rows } = await pool.query(
            `select now() as now,
              current_database() as db,
              version() as version,
              (select count(1) from pg_tables where schemaname='public') as public_tables`
        );
        res.json({ ok: true, ...rows[0] });
    } catch (e) {
        res.status(500).json({
            ok: false,
            error: e?.message || e?.code || 'unknown error',
            detail: (process.env.NODE_ENV !== 'production') ? String(e) : undefined,
            hint: 'Controleer DATABASE_URL en of Supabase local draait: npx supabase start',
        });
    }
});

/**
 * GET /dev/db/time
 * Handige no-op endpoint om latency te zien.
 */
router.get('/time', async (_req, res) => {
    const { rows } = await pool.query('select now() as now');
    res.json(rows[0]);
});

export default router;
