import { Router } from 'express';
import { query } from '../lib/pool.js';
import { apiError, pgToApiError } from '../lib/pg-to-api-error.js';

const router = Router();

router.post('/', async (req, res, next) => {
    try {
        const idem = req.header('Idempotency-Key');
        if (!idem) throw apiError(400, 'bad_request', 'Idempotency-Key header is required');
        const b = req.body || {};
        const required = ['user_id','type','amount','currency','occurred_at'];
        for (const k of required) if (b[k] === undefined || b[k] === null)
            throw apiError(400, 'bad_request', `Missing field: ${k}`);

        const found = await query(`select id from public.cashflows where ext_id = $1`, [idem]);
        if (found.rowCount) return res.status(200).json({ id: found.rows[0].id, idempotent: true });

        const { rows } = await query(
            `insert into public.cashflows (
                user_id, broker_id, account_location_id, asset_id, jurisdiction_id,
                type, amount, currency, occurred_at, note, ext_id
            )
             values ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11)
             returning id`,
            [
                b.user_id, b.broker_id ?? null, b.account_location_id ?? null, b.asset_id ?? null, b.jurisdiction_id ?? null,
                b.type, b.amount, String(b.currency).toUpperCase(), b.occurred_at, b.note ?? null, idem
            ]
        );
        res.status(201).json({ id: rows[0].id, idempotent: false });
    } catch (e) { next(pgToApiError(e)); }
});

export default router;
