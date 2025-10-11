// tests/integration/api/health-check.spec.js
import request from 'supertest';
import app, { shutdown } from '../../../src/server.js'; // idem

describe('HTTP healthcheck', () => {
    afterAll(async () => { await shutdown(); });

    it('responds with the default message', async () => {
        const res = await request(app).get('/api/v1/health');
        expect(res.status).toBe(200);
        expect(res.body).toEqual(expect.objectContaining({ ok: true }));
    });
});
