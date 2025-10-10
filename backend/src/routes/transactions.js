import { Router } from 'express';
import { query } from '../lib/db.js';
import { apiError, pgToApiError } from '../lib/errors.js';

const router = Router();

router.post('/', async (req, res, next) => {
    try {
        const idem = req.header('Idempotency-Key');
        if (!idem) throw apiError(400, 'bad_request', 'Idempotency-Key header is required');
        const b = req.body || {};
        const required = ['user_id','broker_id','location_id','asset_id','type','quantity','price','traded_at'];
        for (const k of required) if (b[k] === undefined || b[k] === null)
            throw apiError(400, 'bad_request', `Missing field: ${k}`);

        const found = await query(`select id from public.transactions where ext_id = $1`, [idem]);
        if (found.rowCount) return res.status(200).json({ id: found.rows[0].id, idempotent: true });

        const { rows } = await query(
            `insert into public.transactions (
                user_id, broker_id, location_id, asset_id, listing_id,
                type, quantity, price, fee_amount, fee_currency, traded_at, note, ext_id
            )
             values ($1,$2,$3,$4,$5,$6,$7,$8,coalesce($9,0),$10,$11,$12,$13)
             returning id`,
            [
                b.user_id, b.broker_id, b.location_id, b.asset_id, b.listing_id ?? null,
                b.type, b.quantity, b.price, b.fee_amount ?? 0, b.fee_currency ?? null,
                b.traded_at, b.note ?? null, idem
            ]
        );
        res.status(201).json({ id: rows[0].id, idempotent: false });
    } catch (e) { next(pgToApiError(e)); }
});

export default router;
