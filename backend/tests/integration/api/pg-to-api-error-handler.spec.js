import express from 'express';
import request from 'supertest';
import {pgToApiError} from "../../../src/lib/pg-to-api-error.js";

function buildTestApp() {
    const app = express();
    app.get('/boom/:kind', (req, _res, next) => {
        const { kind } = req.params;
        const messages = {
            fx: 'FX missing: EUR->JPY at 2024-01-01 (pivot=EUR)',
            dup: 'duplicate key value violates unique constraint "transactions_ext_id_key"',
            check: 'violates check constraint "tx_price_semantics_chk"',
            other: 'some unexpected low-level PG error',
        };
        next(new Error(messages[kind] ?? messages.other));
    });

    // centrale error handler die pgToApiError gebruikt
    app.use((err, _req, res, _next) => {
        const mapped = pgToApiError(err); // geeft apiError(...) terug
        res.status(mapped.status).json(mapped.payload);
    });

    return app;
}

describe('pgToApiError (integratie via Express error handler)', () => {
    const app = buildTestApp();

    it('fx → 422 + fx_missing', async () => {
        const r = await request(app).get('/boom/fx').expect(422);
        expect(r.body).toEqual(
            expect.objectContaining({
                error: expect.objectContaining({ code: 'fx_missing' }),
            })
        );
    });

    it('dup → 409 + conflict', async () => {
        const r = await request(app).get('/boom/dup').expect(409);
        expect(r.body).toEqual(
            expect.objectContaining({
                error: expect.objectContaining({ code: 'conflict' }),
            })
        );
    });

    it('check → 400 + bad_request', async () => {
        const r = await request(app).get('/boom/check').expect(400);
        expect(r.body).toEqual(
            expect.objectContaining({
                error: expect.objectContaining({ code: 'bad_request' }),
            })
        );
    });

    it('other → 500 + internal met details.pg', async () => {
        const r = await request(app).get('/boom/other').expect(500);
        expect(r.body).toEqual(
            expect.objectContaining({
                error: expect.objectContaining({
                    code: 'internal',
                    message: 'Unexpected error',
                    details: { pg: 'some unexpected low-level PG error' },
                }),
            })
        );
    });
});
