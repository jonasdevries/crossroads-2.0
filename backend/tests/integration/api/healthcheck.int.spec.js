import request from 'supertest';
import app, { shutdown as apiShutdown } from '../../../src/server.js';

const skipHttpTests = process.env.SKIP_HTTP_TESTS === '1';
const describeIfHttp = skipHttpTests ? describe.skip : describe;

describe('HTTP healthcheck', () => {
    it('responds with the default message', async () => {
        const response = await request(app).get('/api/v1/health');
        expect(response.status).toBe(200);
        expect(response.body).toEqual(expect.objectContaining({ ok: true }));
    });

        afterAll(async () => {
            await apiShutdown();
        });
});