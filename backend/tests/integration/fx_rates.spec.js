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

            // Ruim alle paren op die we in tests gebruiken, gefilterd op de test-timestamps
            const PAIRS = [
                ['EUR', 'USD'],
                ['EUR', 'GBP'],
                ['GBP', 'USD'],
                ['CAD', 'EUR'],
            ];

            for (const [a, b] of PAIRS) {
                await pool.query(
                    `delete from public.fx_rates
           where ccy_from = $1 and ccy_to = $2 and ts = any($3::timestamptz[])`,
                    [a, b, timestamps]
                );
            }
        }

        await closePool();
    });

    // ---------------------------------------------------------
    // Bestaande test 1: inverse on-the-fly via upsert
    // ---------------------------------------------------------
    it('fx_convert gebruikt inverse on-the-fly wanneer alleen to->from is aangeleverd (via upsert)', async () => {
        const pool = getPool();
        const t = new Date().toISOString();
        insertedTimestamps.add(t);

        // Alleen USD->EUR aanleveren @ 0.8; upsert normaliseert + inverteert naar (EUR->USD=1.25)
        await pool.query(`select public.fx_rates_upsert($1,$2,$3,$4)`, ['USD', 'EUR', t, 0.8000000000]);

        const { rows } = await pool.query(
            `select public.fx_convert(100::numeric, 'EUR','USD',$1,'EUR') as out`,
            [t]
        );
        expect(Number(rows[0].out)).toBeCloseTo(125, 9);
    });

    // ---------------------------------------------------------
    // Bestaande test 2: latest expanded newest-wins
    // ---------------------------------------------------------
    it('latest expanded levert beide richtingen; newest wins per paar', async () => {
        const pool = getPool();

        // Schone lei voor EUR/USD
        await pool.query(`delete from public.fx_rates where ccy_from='EUR' and ccy_to='USD'`);

        const base = new Date('2024-10-02T00:00:00.000Z');
        const t_old = new Date(base.getTime() + 1000).toISOString(); // 00:00:01Z
        const t_new = new Date(base.getTime() + 5000).toISOString(); // 00:00:05Z
        insertedTimestamps.add(t_old);
        insertedTimestamps.add(t_new);

        // Oudere USD->EUR 1.10 → wordt opgeslagen als (EUR->USD ~= 0.9090909091)
        await pool.query(`select public.fx_rates_upsert($1,$2,$3,$4)`, ['USD', 'EUR', t_old, 1.1000000000]);

        // Check expanded: moet EUR->USD tonen met 1/1.10 op t_old
        let { rows: oldEurUsd } = await pool.query(
            `select ts, rate from public.fx_rates_latest_expanded
       where ccy_from='EUR' and ccy_to='USD'`
        );
        expect(new Date(oldEurUsd[0].ts).toISOString()).toBe(t_old);
        expect(Number(oldEurUsd[0].rate)).toBeCloseTo(1 / 1.10, 10);

        // Nieuwere EUR->USD (1.25)
        await pool.query(`select public.fx_rates_upsert($1,$2,$3,$4)`, ['EUR', 'USD', t_new, 1.2500000000]);

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
        expect(Number(usdEurNew[0].rate)).toBeCloseTo(1 / 1.25, 10);
    });

    // ---------------------------------------------------------
    // Nieuw: Identity & edge amounts
    // ---------------------------------------------------------
    it('identity & edge amounts', async () => {
        const pool = getPool();
        const t = '2024-10-02T00:00:00Z';
        insertedTimestamps.add(t);

        await pool.query(`select public.fx_rates_upsert('EUR','USD',$1,$2)`, [t, 1.25]);

        const id1 = await pool.query(
            `select public.fx_convert(123.45::numeric,'EUR','EUR',$1,'EUR') as out`,
            [t]
        );
        expect(Number(id1.rows[0].out)).toBeCloseTo(123.45, 10);

        const z = await pool.query(`select public.fx_convert(0::numeric,'EUR','USD',$1,'EUR') as out`, [t]);
        expect(Number(z.rows[0].out)).toBeCloseTo(0, 10);

        const neg = await pool.query(
            `select public.fx_convert(-100::numeric,'EUR','USD',$1,'EUR') as out`,
            [t]
        );
        expect(Number(neg.rows[0].out)).toBeCloseTo(-125, 10);
    });

    // ---------------------------------------------------------
    // Nieuw: Timestamp exactheid
    // ---------------------------------------------------------
    it('timestamp must match exactly', async () => {
        const pool = getPool();
        const base = new Date('2030-01-01T00:00:00.000Z'); // ver weg van andere tests
        const t_hit  = new Date(base.getTime() + 0).toISOString();
        const t_miss = new Date(base.getTime() + 1000).toISOString();
        insertedTimestamps.add(t_hit);
        // t_miss wordt niet geschreven, maar ruim ‘m toch op voor de zekerheid
        insertedTimestamps.add(t_miss);

        // clean slate op beide ts
        await pool.query(
            `delete from public.fx_rates where ccy_from='EUR' and ccy_to='USD' and ts = any($1::timestamptz[])`,
            [[t_hit, t_miss]]
        );

        await pool.query(`select public.fx_rates_upsert('EUR','USD',$1,$2)`, [t_hit, 1.25]);

        // exact t_hit werkt
        const ok = await pool.query(
            `select public.fx_convert(1,'EUR','USD',$1,'EUR') as out`, [t_hit]
        );
        expect(Number(ok.rows[0].out)).toBeCloseTo(1.25, 10);

        // t_miss (andere seconde) moet falen
        await expect(
            pool.query(`select public.fx_convert(1,'EUR','USD',$1,'EUR')`, [t_miss])
        ).rejects.toThrow(/FX missing/i);
    });


    // ---------------------------------------------------------
    // Nieuw: Pivot padcompleetheid & direct beats pivot
    // ---------------------------------------------------------
    it('pivot requires both legs; direct beats pivot', async () => {
        const pool = getPool();
        const t = '2024-10-02T00:00:00Z';
        insertedTimestamps.add(t);

        // Clean slate
        await pool.query(`delete from public.fx_rates where ccy_from='EUR' and ccy_to='USD'`);
        await pool.query(`delete from public.fx_rates where ccy_from='EUR' and ccy_to='GBP'`);
        await pool.query(`delete from public.fx_rates where ccy_from='GBP' and ccy_to='USD'`);

        // Alleen EUR/GBP bestaat → pivot GBP->EUR (leg1) beschikbaar, maar leg2 (EUR->USD) ontbreekt
        await pool.query(`select public.fx_rates_upsert('EUR','GBP',$1,$2)`, [t, 0.90]);

        await expect(
            pool.query(`select public.fx_convert(100,'GBP','USD',$1,'EUR') as out`, [t])
        ).rejects.toThrow(/FX missing/i);

        // Voeg EUR/USD toe → pivot kan nu; voor EUR->USD wint *direct* over pivot
        await pool.query(`select public.fx_rates_upsert('EUR','USD',$1,$2)`, [t, 1.30]);

        const directBeats = await pool.query(
            `select public.fx_convert(100,'EUR','USD',$1,'GBP') as out`, [t]
        );
        expect(Number(directBeats.rows[0].out)).toBeCloseTo(130, 10);
    });


    // ---------------------------------------------------------
    // Nieuw: Upsert idempotent & richting-onafhankelijk
    // ---------------------------------------------------------
    it('upsert is idempotent and direction-agnostic', async () => {
        const pool = getPool();
        const t = '2024-10-02T00:00:00Z';
        insertedTimestamps.add(t);

        await pool.query(`delete from public.fx_rates where ccy_from='EUR' and ccy_to='USD'`);

        await pool.query(`select public.fx_rates_upsert('EUR','USD',$1,$2)`, [t, 1.25]);
        await pool.query(`select public.fx_rates_upsert('USD','EUR',$1,$2)`, [t, 0.80]); // inverse van 1.25

        const { rows } = await pool.query(
            `select ts, rate from public.fx_rates where ccy_from='EUR' and ccy_to='USD' and ts=$1`,
            [t]
        );
        expect(rows).toHaveLength(1);
        expect(Number(rows[0].rate)).toBeCloseTo(1.25, 10);
    });

    // ---------------------------------------------------------
    // Nieuw: Latest expanded → exact 2 richtingen per paar
    // ---------------------------------------------------------
    it('latest_expanded returns exactly two directions per pair', async () => {
        const pool = getPool();
        const t1 = '2024-10-02T00:00:00Z';
        const t2 = '2024-10-02T00:00:05Z';
        insertedTimestamps.add(t1);
        insertedTimestamps.add(t2);

        await pool.query(`delete from public.fx_rates where ccy_from='EUR' and ccy_to='USD'`);
        await pool.query(`select public.fx_rates_upsert('EUR','USD',$1,$2)`, [t1, 1.20]);
        await pool.query(`select public.fx_rates_upsert('EUR','USD',$1,$2)`, [t2, 1.30]);

        const { rows } = await pool.query(
            `select * from public.fx_rates_latest_expanded
       where (ccy_from, ccy_to) in (('EUR','USD'),('USD','EUR'))`
        );
        expect(rows).toHaveLength(2);

        const eurusd = rows.find((r) => r.ccy_from === 'EUR' && r.ccy_to === 'USD');
        const usdeur = rows.find((r) => r.ccy_from === 'USD' && r.ccy_to === 'EUR');
        expect(Number(eurusd.rate)).toBeCloseTo(1.30, 10);
        expect(Number(usdeur.rate)).toBeCloseTo(1 / 1.30, 10);

        const t2ms = new Date(t2).getTime();
        expect(new Date(eurusd.ts).getTime()).toBe(t2ms);
        expect(new Date(usdeur.ts).getTime()).toBe(t2ms);

    });

    // ---------------------------------------------------------
    // Nieuw: Constraint smoke test
    // ---------------------------------------------------------
    it('constraint: direct non-canonical insert fails; upsert succeeds', async () => {
        const pool = getPool();
        const t = '2024-10-02T00:00:00Z';
        insertedTimestamps.add(t);

        await expect(
            pool.query(
                `insert into public.fx_rates(ccy_from,ccy_to,ts,rate) values ('USD','EUR',$1,0.8)`,
                [t]
            )
        ).rejects.toThrow(/fx_rates_canonical_chk/i);

        await pool.query(`select public.fx_rates_upsert('USD','EUR',$1,$2)`, [t, 0.8]);

        const { rows } = await pool.query(
            `select rate from public.fx_rates where ccy_from='EUR' and ccy_to='USD' and ts=$1`,
            [t]
        );
        expect(Number(rows[0].rate)).toBeCloseTo(1.25, 10);
    });

    // ---------------------------------------------------------
    // Nieuw: Precisie/afronding
    // ---------------------------------------------------------
    it('precision: high-precision rate stays stable', async () => {
        const pool = getPool();
        const t = '2024-10-02T00:00:00Z';
        insertedTimestamps.add(t);

        const r = 1.2345678901; // past in numeric(20,10)
        await pool.query(`delete from public.fx_rates where ccy_from='EUR' and ccy_to='USD'`);
        await pool.query(`select public.fx_rates_upsert('EUR','USD',$1,$2)`, [t, r]);

        const { rows } = await pool.query(
            `select public.fx_convert(100::numeric,'EUR','USD',$1,'EUR') as out`,
            [t]
        );
        expect(Number(rows[0].out)).toBeCloseTo(100 * r, 9);
    });
});
