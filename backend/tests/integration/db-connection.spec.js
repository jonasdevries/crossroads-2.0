const { getPool, closePool } = require('../helpers/db');

const skipDbTests = process.env.SKIP_DB_TESTS === '1';
const describeIfDb = skipDbTests ? describe.skip : describe;

if (skipDbTests) {
  console.warn(
    'Skipping database connectivity specs because SKIP_DB_TESTS=1. Start Supabase locally and rerun to execute them.'
  );
}

describeIfDb('database connectivity', () => {
  beforeAll(async () => {
    const pool = getPool();
    await pool.query('select 1');
  });

  afterAll(async () => {
    await closePool();
  });

  it('runs a simple query on Postgres', async () => {
    const pool = getPool();
    const { rows } = await pool.query('select 1 as result');
    expect(rows[0].result).toBe(1);
  });
});
