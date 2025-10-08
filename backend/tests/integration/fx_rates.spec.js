// backend/tests/fx_rates.spec.js
const { getPool, closePool } = require('../helpers/db');

const skipFxTests = process.env.SKIP_DB_TESTS === '1';
const describeIfFx = skipFxTests ? describe.skip : describe;

if (skipFxTests) {
    console.warn(
        'Skipping FX rate specs because SKIP_DB_TESTS=1. Start Supabase locally and rerun to execute them.'
    );
}

const TOLERANCE = 1e-9;

describeIfFx('FX convert & latest (canonical, no triggers)', () => {
    const insertedTimestamps = new Set();

    beforeAll(async () => {
        const pool = getPool();
        const { rows: curRows } = await pool.query(
            `select code from public.currencies where code in ('EUR','USD','CAD')`
        );
        const needed = ['EUR', 'USD', 'CAD'];
        const missing = needed.filter((c) => !curRows.find((r) => r.code === c));
        if (missing.length) {
            throw new Error(`Missing currencies required for FX test: ${missing.join(', ')}`);
        }
    });

    afterAll(async () => {
        const pool = getPool();

        if (insertedTimestamps.size > 0) {
            const timestamps = Array.from(insertedTimestamps);

            // Canonieke opslag betekent: EUR/USD zit als (EUR,USD) in de tabel.
            await pool.query(
                `delete from public.fx_rates
                 where ccy_from='EUR' and ccy_to='USD' and ts = any($1::timestamptz[])`,
                [timestamps]
            );
        }

        await closePool();
    });

    it('fx_convert gebruikt inverse on-the-fly wanneer alleen to->from is aangeleverd (via upsert)', async () => {
        const pool = getPool();
        const t = new Date().toISOString();
        insertedTimestamps.add(t);

        // Alleen USD->EUR aanleveren @ 0.8; upsert normaliseert + inverteert naar (EUR->USD=1.25)
        await pool.query(
            `select public.fx_rates_upsert($1,$2,$3,$4)`,
            ['USD','EUR', t, 0.8000000000]
        );

        const { rows } = await pool.query(
            `select public.fx_convert(100::numeric, 'EUR','USD',$1,'EUR') as out`,
            [t]
        );
        expect(Number(rows[0].out)).toBeCloseTo(125, 9);
    });

    it('latest expanded levert beide richtingen; newest wins per paar', async () => {
        const pool = getPool();

        // Schone lei voor EUR/USD
        await pool.query(
            `delete from public.fx_rates where ccy_from='EUR' and ccy_to='USD'`
        );

        const base = new Date('2024-10-02T00:00:00.000Z');
        const t_old = new Date(base.getTime() + 1000).toISOString(); // 00:00:01Z
        const t_new = new Date(base.getTime() + 5000).toISOString(); // 00:00:05Z
        insertedTimestamps.add(t_old);
        insertedTimestamps.add(t_new);

        // Oudere USD->EUR 1.10 → wordt opgeslagen als (EUR->USD ~= 0.9090909091)
        await pool.query(
            `select public.fx_rates_upsert($1,$2,$3,$4)`,
            ['USD','EUR', t_old, 1.1000000000]
        );

        // Check expanded: moet EUR->USD tonen met 1/1.10 op t_old
        let { rows: oldEurUsd } = await pool.query(
            `select ts, rate from public.fx_rates_latest_expanded
       where ccy_from='EUR' and ccy_to='USD'`
        );
        expect(new Date(oldEurUsd[0].ts).toISOString()).toBe(t_old);
        expect(Number(oldEurUsd[0].rate)).toBeCloseTo(1/1.10, 10);

        // Nieuwere EUR->USD (1.25)
        await pool.query(
            `select public.fx_rates_upsert($1,$2,$3,$4)`,
            ['EUR','USD', t_new, 1.2500000000]
        );

        // Expanded moet nu t_new tonen voor beide richtingen
        const { rows: eurUsdNew } = await pool.query(
            `select ts, rate from public.fx_rates_latest_expanded
       where ccy_from='EUR' and ccy_to='USD'`
        );
        expect(new Date(eurUsdNew[0].ts).toISOString()).toBe(t_new);
        expect(Number(eurUsdNew[0].rate)).toBeCloseTo(1.25, 10);

        const { rows: usdEurNew } = await pool.query(
            `select ts, rate from public.fx_rates_latest_expanded
             where ccy_from='USD' and ccy_to='EUR'`
        );
        expect(new Date(usdEurNew[0].ts).toISOString()).toBe(t_new);
        expect(Number(usdEurNew[0].rate)).toBeCloseTo(1/1.25, 10);
    });
});
