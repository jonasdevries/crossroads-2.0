const path = require('path');
const dotenv = require('dotenv');

const envFile = process.env.JEST_ENV_FILE || '.env.test';

dotenv.config({
  path: path.resolve(process.cwd(), envFile),
  override: true
});

if (!process.env.DATABASE_URL) {
  process.env.DATABASE_URL =
    'postgresql://postgres:postgres@127.0.0.1:54322/postgres';
}
