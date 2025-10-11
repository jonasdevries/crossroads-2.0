import request from 'supertest';
import app, { shutdown as apiShutdown } from '../../../src/server.js';
import { getPool, closePool } from '../../helpers/db.js';

// TODO refactor deze test: niet alleen met api werken en niet met db data

describe('API idempotency — /transactions', () => {
    let ctx;

    beforeAll(async () => {
        const pool = getPool();
        const { rows } = await pool.query(`
      select
        u.id as user_id,
        b.id as broker_id,
        l.id as location_id,
        a.id as asset_id
      from public.users u
      join public.brokers  b on b.user_id=u.id and b.name='Self Custody'
      join public.locations l on l.user_id=u.id and l.name='Kluis'
      join public.assets    a on a.unique_symbol='AG-1KG'
      where u.email='jonas@good-it.be'
    `);
        if (!rows.length) throw new Error('Seed context ontbreekt (user/broker/location/AG-1KG).');
        ctx = rows[0];
    });

    afterAll(async () => {
        await closePool();      // test-helper pool
        await apiShutdown();    // API-pool (sluit PG pool uit src/lib/pool.js)
    });

    it('POST /transactions is idempotent via Idempotency-Key', async () => {
        const key = `idem-tx-${Date.now()}`;

        const payload = {
            user_id: ctx.user_id,
            broker_id: ctx.broker_id,
            location_id: ctx.location_id,
            asset_id: ctx.asset_id,
            // listing_id: null,
            type: 'buy',
            quantity: 1.0,
            price: 123.45,
            fee_amount: 0,
            // fee_currency: null,
            traded_at: '2025-01-01T00:00:00Z',
            note: 'API idem test'
        };

        const r1 = await request(app)
            .post('/api/v1/transactions')
            .set('Idempotency-Key', key)
            .send(payload);

        expect(r1.status).toBe(201);
        expect(r1.body).toHaveProperty('id');
        expect(r1.body.idempotent).toBe(false);
        const id = r1.body.id;

        // exact dezelfde call opnieuw → 200 replay
        const r2 = await request(app)
            .post('/api/v1/transactions')
            .set('Idempotency-Key', key)
            .send(payload);

        expect(r2.status).toBe(200);
        expect(r2.body).toMatchObject({ id, idempotent: true });

        // Zelfde key met ANDERE payload → 409 (conflict) (optioneel; alleen als je die check implementeert)
        // const r3 = await request(app)
        //   .post('/api/v1/transactions')
        //   .set('Idempotency-Key', key)
        //   .send({ ...payload, price: 999.99 });
        // expect(r3.status).toBe(409);
    });
});
