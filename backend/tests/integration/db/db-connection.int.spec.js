import {closePool, getPool} from "../../helpers/db.js"

const skipDbTests = process.env.SKIP_DB_TESTS === '1';
const describeIfDb = skipDbTests ? describe.skip : describe;

if (skipDbTests) {
  console.warn(
    'Skipping database connectivity specs because SKIP_DB_TESTS=1. Start Supabase locally and rerun to execute them.'
  );
}

describe('database connectivity', () => {
    let pool;

    beforeAll(async () => {
        pool = getPool();
        try {
            await pool.query('select 1');
        } catch (e) {
            // Handige diagnose
            // eslint-disable-next-line no-console
            console.error('DB connect failed:', {
                DATABASE_URL: process.env.DATABASE_URL,
                DATABASE_SSL: process.env.DATABASE_SSL,
                message: e?.message,
            });
            throw e;
        }
    });

    afterAll(async () => {
        await closePool();
    });

    it('runs a simple query on Postgres', async () => {
        const { rows } = await pool.query('select 1 as ok');
        expect(rows[0].ok).toBe(1);
    });
});


describe('database connectivity', () => {
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
