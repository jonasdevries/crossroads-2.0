// tests/unit/lib/errors.spec.js
import { apiError, pgToApiError } from '../../../src/lib/errors.js';

describe('lib/errors', () => {
    describe('apiError()', () => {
        it('wraps status/code/message/details in Error with payload', () => {
            const err = apiError(418, 'teapot', 'short and stout', { hint: '☕' });
            expect(err).toBeInstanceOf(Error);
            expect(err.message).toBe('short and stout');
            expect(err.status).toBe(418);
            expect(err.payload).toEqual({
                error: { code: 'teapot', message: 'short and stout', details: { hint: '☕' } },
            });
        });

        it('allows undefined details', () => {
            const err = apiError(400, 'bad_request', 'oops');
            expect(err.payload).toEqual({
                error: { code: 'bad_request', message: 'oops', details: undefined },
            });
        });
    });

    describe('pgToApiError()', () => {
        it('maps "FX missing" to 422 fx_missing', () => {
            const e = new Error('FX missing: EUR->JPY at 2024-01-01 (pivot=EUR)');
            const out = pgToApiError(e);
            expect(out.status).toBe(422);
            expect(out.payload.error.code).toBe('fx_missing');
            expect(out.payload.error.message).toMatch(/FX missing/i);
        });

        it('maps duplicate/ext_id conflicts to 409 conflict', () => {
            for (const msg of [
                'duplicate key value violates unique constraint "transactions_ext_id_key"',
                'duplicate key value violates unique constraint "cashflows_ext_id_key"',
                'ERROR: duplicate key value violates unique constraint "whatever"',
            ]) {
                const out = pgToApiError(new Error(msg));
                expect(out.status).toBe(409);
                expect(out.payload.error.code).toBe('conflict');
            }
        });

        it('maps domain/check violations to 400 bad_request', () => {
            const msgs = [
                'violates check constraint "txn_fee_currency_chk"',
                'violates check constraint "tx_price_semantics_chk"',
                'violates check constraint "fx_rates_canonical_chk"',
                'violates check constraint "cashflows_ccy_chk"',
                'violates check constraint "cashflows_type_min_rules_chk"',
            ];
            for (const msg of msgs) {
                const out = pgToApiError(new Error(msg));
                expect(out.status).toBe(400);


                expect(out.payload.error.code).toBe('bad_request');
                expect(out.payload.error.message).toMatch(/violates check/i);
            }
        });

        it('defaults to 500 internal with details.pg when no known pattern matches', () => {
            const raw = 'some unexpected low-level PG error';
            const out = pgToApiError(new Error(raw));
            expect(out.status).toBe(500);
            expect(out.payload.error.code).toBe('internal');
            expect(out.payload.error.message).toBe('Unexpected error');
            expect(out.payload.error.details).toEqual({ pg: raw });
        });

        it('handles falsy error/message safely (e = {})', () => {
            const out = pgToApiError({});
            expect(out.status).toBe(500);
            expect(out.payload.error.details).toEqual({ pg: '' });
        });
    });
});
