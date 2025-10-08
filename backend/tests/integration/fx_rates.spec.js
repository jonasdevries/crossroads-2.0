const { getPool, closePool } = require('../helpers/db');

const skipFxTests = process.env.SKIP_DB_TESTS === '1';
const describeIfFx = skipFxTests ? describe.skip : describe;

if (skipFxTests) {
  console.warn(
    'Skipping FX rate specs because SKIP_DB_TESTS=1. Start Supabase locally and rerun to execute them.'
  );
}

const TOLERANCE = 1e-9;
const FROM = 'EUR';
const TO = 'USD';
const RATE = 1.23456789;

describeIfFx('FX inverse trigger (canonieke richting)', () => {
  const insertedTimestamps = new Set();

  beforeAll(async () => {
    const pool = getPool();
    const { rows: curRows } = await pool.query(
      `select code
       from public.currencies
       where code in ($1, $2)`,
      [FROM, TO]
    );

    const missing = [FROM, TO].filter(
      (code) => !curRows.find((row) => row.code === code)
    );

    if (missing.length) {
      throw new Error(
        `Missing currencies required for FX test: ${missing.join(', ')}`
      );
    }
  });

  afterAll(async () => {
    const pool = getPool();

    if (insertedTimestamps.size > 0) {
      const timestamps = Array.from(insertedTimestamps);

      await pool.query(
        `delete from public.fx_rates
         where (
           (ccy_from = $1 and ccy_to = $2)
           or (ccy_from = $2 and ccy_to = $1)
         )
         and ts = any($3::timestamptz[])`,
        [FROM, TO, timestamps]
      );
    }

    await closePool();
  });

  it('maakt inverse koers aan en werkt latest view bij', async () => {
    const pool = getPool();
    const ts = new Date().toISOString();
    insertedTimestamps.add(ts);

    await pool.query(
      `insert into public.fx_rates (ccy_from, ccy_to, ts, rate)
       values ($1, $2, $3, $4)
       on conflict (ccy_from, ccy_to, ts)
       do update set rate = excluded.rate`,
      [FROM, TO, ts, RATE]
    );

    const { rows: directRows } = await pool.query(
      `select ccy_from, ccy_to, ts, rate
       from public.fx_rates
       where ccy_from = $1
         and ccy_to = $2
         and ts = $3`,
      [FROM, TO, ts]
    );

    const { rows: inverseRows } = await pool.query(
      `select ccy_from, ccy_to, ts, rate
       from public.fx_rates
       where ccy_from = $1
         and ccy_to = $2
         and ts = $3`,
      [TO, FROM, ts]
    );

    expect(directRows).toHaveLength(1);
    expect(inverseRows).toHaveLength(1);

    const rateDirect = Number(directRows[0].rate);
    const rateInverse = Number(inverseRows[0].rate);
    const expectedInverse = 1 / RATE;

    expect(Math.abs(rateDirect - RATE)).toBeLessThan(TOLERANCE);
    expect(Math.abs(rateInverse - expectedInverse)).toBeLessThan(TOLERANCE);

    const { rows: latestDirect } = await pool.query(
      `select ccy_from, ccy_to, ts, rate
       from public.fx_rates_latest
       where ccy_from = $1
         and ccy_to = $2`,
      [FROM, TO]
    );

    const { rows: latestInverse } = await pool.query(
      `select ccy_from, ccy_to, ts, rate
       from public.fx_rates_latest
       where ccy_from = $1
         and ccy_to = $2`,
      [TO, FROM]
    );

    expect(latestDirect).toHaveLength(1);
    expect(latestInverse).toHaveLength(1);
    expect(new Date(latestDirect[0].ts).toISOString()).toBe(ts);
    expect(new Date(latestInverse[0].ts).toISOString()).toBe(ts);

    const ts2 = new Date(Date.parse(ts) + 1000).toISOString();
    const rate2 = 1.25;
    insertedTimestamps.add(ts2);

    await pool.query(
      `insert into public.fx_rates (ccy_from, ccy_to, ts, rate)
       values ($1, $2, $3, $4)
       on conflict (ccy_from, ccy_to, ts)
       do update set rate = excluded.rate`,
      [FROM, TO, ts2, rate2]
    );

    const { rows: inverseUpdated } = await pool.query(
      `select ts, rate
       from public.fx_rates
       where ccy_from = $1
         and ccy_to = $2
         and ts = $3`,
      [TO, FROM, ts2]
    );

    expect(inverseUpdated).toHaveLength(1);
    const expectedInverse2 = 1 / rate2;
    expect(Math.abs(Number(inverseUpdated[0].rate) - expectedInverse2)).toBeLessThan(
      TOLERANCE
    );

    const { rows: latestDirect2 } = await pool.query(
      `select ts, rate
       from public.fx_rates_latest
       where ccy_from = $1
         and ccy_to = $2`,
      [FROM, TO]
    );

    const { rows: latestInverse2 } = await pool.query(
      `select ts, rate
       from public.fx_rates_latest
       where ccy_from = $1
         and ccy_to = $2`,
      [TO, FROM]
    );

    expect(new Date(latestDirect2[0].ts).toISOString()).toBe(ts2);
    expect(new Date(latestInverse2[0].ts).toISOString()).toBe(ts2);
  });
});
