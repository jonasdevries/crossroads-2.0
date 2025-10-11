import request from 'supertest';
import app, { shutdown as apiShutdown } from '../../../src/server.js';
import { getPool, closePool } from '../../helpers/db.js';

afterAll(async () => {
    await closePool();
    await apiShutdown(); // sluit de API-PG pool
});

// TODO refactor deze test: niet alleen met api werken en niet met db data

describe('API idempotency — /cashflows', () => {
    let user_id, account_location_id;

    beforeAll(async () => {
        const pool = getPool();
        const { rows: u } = await pool.query(`select id from public.users where email='jonas@good-it.be'`);
        if (!u.length) throw new Error('User seed ontbreekt.');
        user_id = u[0].id;

        const { rows: l } = await pool.query(`
      select id from public.locations
      where user_id=$1 and name='Kluis'
    `, [user_id]);
        if (!l.length) throw new Error('Location "Kluis" ontbreekt.');
        account_location_id = l[0].id;
    });

    afterAll(async () => {
        await closePool();
        await apiShutdown();
    });

    it('POST /cashflows is idempotent via Idempotency-Key', async () => {
        const key = `idem-cf-${Date.now()}`;

        const payload = {
            user_id,
            account_location_id,
            type: 'deposit',
            amount: 2500,
            currency: 'EUR',
            occurred_at: '2025-01-03T09:00:00Z',
            note: 'API CF idem test'
        };

        const r1 = await request(app)
            .post('/api/v1/cashflows')
            .set('Idempotency-Key', key)
            .send(payload);

        expect([200,201]).toContain(r1.status); // 201 bij eerste create, 200 als er al bestond
        const created = r1.body;
        expect(created).toHaveProperty('id');
        const id = created.id;

        // Zelfde call opnieuw → 200 replay
        const r2 = await request(app)
            .post('/api/v1/cashflows')
            .set('Idempotency-Key', key)
            .send(payload);

        expect(r2.status).toBe(200);
        expect(r2.body).toMatchObject({ id, idempotent: true });
    });
});
