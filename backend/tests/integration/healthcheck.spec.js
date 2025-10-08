const request = require('supertest');
const { createServer } = require('../../index');

const skipHttpTests = process.env.SKIP_HTTP_TESTS === '1';
const describeIfHttp = skipHttpTests ? describe.skip : describe;

if (skipHttpTests) {
  console.warn(
    'Skipping HTTP integration specs because SKIP_HTTP_TESTS=1. Unset it to exercise the API.'
  );
}

describeIfHttp('HTTP healthcheck', () => {
  it('responds with the default message', async () => {
    const response = await request(createServer()).get('/');
    expect(response.status).toBe(200);
    expect(response.body).toEqual(
      expect.objectContaining({
        message: expect.stringContaining('Crossroads 2.0 backend is running')
      })
    );
  });
});
