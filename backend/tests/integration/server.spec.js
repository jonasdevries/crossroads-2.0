// Integration tests voor de Express server (zonder echte listen())
import request from 'supertest';
import app, { shutdown } from '../../src/server.js';

describe('server', () => {
    afterAll(async () => {
        // Sluit eventuele DB pools/handles netjes
        await shutdown();
    });

    it('GET /api/v1/health -> 200 { ok: true }', async () => {
        const res = await request(app).get('/api/v1/health').expect(200);
        expect(res.body).toEqual({ ok: true });
    });

    it('unknown route -> 404 JSON fout', async () => {
        const res = await request(app).get('/__does_not_exist__').expect(404);
        expect(res.body).toEqual(
            expect.objectContaining({
                error: expect.objectContaining({
                    code: 'not_found',
                    message: expect.any(String),
                }),
            })
        );
    });

    it('error handler vangt thrown errors en geeft 500', async () => {
        // Voeg tijdelijk een route toe die een error gooit
        app.get('/__boom', (_req, _res, next) => next(new Error('boom')));

        const res = await request(app).get('/__boom').expect(500);

        // In je server zet je standaard payload { error: { code: 'internal', message: 'Internal error' } }
        expect(res.body).toEqual(
            expect.objectContaining({
                error: expect.objectContaining({
                    code: 'internal',
                    message: 'Internal error',
                }),
            })
        );

        // In non-production (waaronder NODE_ENV=test) voeg je debug info toe
        if (process.env.NODE_ENV !== 'production') {
            expect(res.body).toHaveProperty('debug');
            expect(res.body.debug).toEqual(
                expect.objectContaining({ message: 'boom' })
            );
        }
    });
});
