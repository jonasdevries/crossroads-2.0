import { pgToApiError } from '../../../src/lib/pg-to-api-error';

describe('pgToApiError (unit)', () => {
    it('geeft 422 fx_missing bij "FX missing"', () => {
        const out = pgToApiError(new Error('FX missing: EUR->JPY at 2024-01-01 (pivot=EUR)'));
        expect(out.status).toBe(422);
        expect(out.payload.error.code).toBe('fx_missing');
        expect(out.payload.error.message).toMatch(/FX missing/i);
    });

    it('geeft 409 conflict bij duplicate/ext_id errors', () => {
        for (const msg of [
            'duplicate key value violates unique constraint "transactions_ext_id_key"',
            'duplicate key value violates unique constraint "cashflows_ext_id_key"',
            'ERROR: duplicate key value violates unique constraint "whatever"',
        ]) {
            const out = pgToApiError(new Error(msg));
            expect(out.status).toBe(409);
            expect(out.payload.error.code).toBe('conflict');
            expect(out.payload.error.message).toMatch(/duplicate key/i);
        }
    });

    it('geeft 400 bad_request bij check/domain violations', () => {
        for (const msg of [
            'violates check constraint "txn_fee_currency_chk"',
            'violates check constraint "tx_price_semantics_chk"',
            'violates check constraint "fx_rates_canonical_chk"',
            'violates check constraint "cashflows_ccy_chk"',
            'violates check constraint "cashflows_type_min_rules_chk"',
        ]) {
            const out = pgToApiError(new Error(msg));
            expect(out.status).toBe(400);
            expect(out.payload.error.code).toBe('bad_request');
            expect(out.payload.error.message).toMatch(/violates check/i);
        }
    });

    it('valt terug op 500 internal met details.pg als niets matcht', () => {
        const raw = 'some unexpected low-level PG error';
        const out = pgToApiError(new Error(raw));
        expect(out.status).toBe(500);
        expect(out.payload.error.code).toBe('internal');
        expect(out.payload.error.message).toBe('Unexpected error');
        expect(out.payload.error.details).toEqual({ pg: raw });
    });

    it('handelt falsy error object veilig af ({} of null)', () => {
        const out1 = pgToApiError({});
        expect(out1.status).toBe(500);
        expect(out1.payload.error.details).toEqual({ pg: '' });

        const out2 = pgToApiError(null);
        expect(out2.status).toBe(500);
        expect(out2.payload.error.details).toEqual({ pg: '' });
    });
});
