// tests/unit/api/error-handler.spec.js
import request from 'supertest';
import app from '../../../src/server.js';
import { apiError } from '../../../src/lib/errors.js';

describe('API error handler', () => {
    it('passes through status and payload from apiError()', async () => {
        // test-only route die bewust een apiError gooit
        app.get('/__test__/boom-api', (req, res, next) => {
            next(apiError(418, 'teapot', 'short and stout', { hint: '☕' }));
        });

        const r = await request(app).get('/__test__/boom-api');
        expect(r.status).toBe(418);
        expect(r.body).toEqual({
            error: { code: 'teapot', message: 'short and stout', details: { hint: '☕' } },
        });
    });

    it('falls back to 500 + default payload on generic Error', async () => {
        app.get('/__test__/boom-generic', (req, res, next) => {
            next(new Error('kaboom'));
        });

        const r = await request(app).get('/__test__/boom-generic');
        expect(r.status).toBe(500);
        // jouw server.js default payload:
        // { error: { code: 'internal', message: 'Internal error' } }
        expect(r.body).toEqual({
            error: { code: 'internal', message: 'Internal error' },
        });
    });
});
