const { Pool } = require('pg');

let pool;

const getPool = () => {
  if (!pool) {
    const connectionString = process.env.DATABASE_URL;

    if (!connectionString) {
      throw new Error(
        'DATABASE_URL is not defined. Set it in .env.test or export it before running tests.'
      );
    }

    pool = new Pool({ connectionString });
  }

  return pool;
};

const closePool = async () => {
  if (pool) {
    await pool.end();
    pool = undefined;
  }
};

module.exports = {
  getPool,
  closePool
};
