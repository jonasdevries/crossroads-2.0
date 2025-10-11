/**
 * Integration tests voor /dev/db routes.
 * Vereist draaiende lokale Supabase (DATABASE_URL -> 54322)
 * Zet SKIP_DB_TESTS=1 om deze spec te skippen.
 */
import express from 'express';
import request from 'supertest';
import { jest } from '@jest/globals';

import devDbRouter from '../../src/routes/devDb.js';
import { pool } from '../../src/db/pool.js';

const skip = process.env.SKIP_DB_TESTS === '1';
const describeIf = skip ? describe.skip : describe;

if (skip) {
    // eslint-disable-next-line no-console
    console.warn('Skipping devDb specs: SKIP_DB_TESTS=1');
}

describeIf('devDb routes', () => {
    let app;

    beforeAll(() => {
        // Maak een kleine app en mount de dev router op dezelfde path
        app = express();
        app.use(express.json());
        app.use('/dev/db', devDbRouter);
    });

    afterAll(async () => {
        // Pool afsluiten zodat Jest niet blijft hangen
        try {
            await pool.end();
        } catch (_) {}
    });

    it('GET /dev/db/health: geeft ok:true en basis DB-info terug', async () => {
        const res = await request(app).get('/dev/db/health').expect(200);

        expect(res.body).toHaveProperty('ok', true);
        expect(res.body).toHaveProperty('db');           // db-naam
        expect(typeof res.body.db).toBe('string');
        expect(res.body).toHaveProperty('version');      // postgres versie-string
        expect(typeof res.body.version).toBe('string');
        expect(res.body).toHaveProperty('public_tables'); // aantal tabellen in public
        expect(Number.isFinite(Number(res.body.public_tables))).toBe(true);
        expect(res.body).toHaveProperty('now');          // timestamptz
        expect(!Number.isNaN(Date.parse(res.body.now))).toBe(true);
    });

    it('GET /dev/db/time: geeft huidige tijd terug', async () => {
        const res = await request(app).get('/dev/db/time').expect(200);

        expect(res.body).toHaveProperty('now');
        expect(!Number.isNaN(Date.parse(res.body.now))).toBe(true);
    });

    it('GET /dev/db/health: 500 bij DB-fout met duidelijke hint', async () => {
        // Forceer 1 mislukte query
        const spy = jest.spyOn(pool, 'query').mockRejectedValueOnce(new Error('boom'));

        const res = await request(app).get('/dev/db/health').expect(500);
        expect(res.body).toEqual(
            expect.objectContaining({
                ok: false,
                error: expect.stringMatching(/boom/i),
                hint: expect.stringMatching(/DATABASE_URL|supabase/i),
            })
        );

        spy.mockRestore();
    });
});
