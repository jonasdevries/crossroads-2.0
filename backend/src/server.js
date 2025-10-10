import express from 'express';
import transactions from './routes/transactions.js';
import cashflows from './routes/cashflows.js';
import { close as closeDb } from './lib/db.js';

const app = express();
app.use(express.json());

app.get('/api/v1/health', (req, res) => res.json({ ok: true }));
app.use('/api/v1/transactions', transactions);
app.use('/api/v1/cashflows',     cashflows);

// error handler
app.use((err, req, res, next) => {
    const status = err.status || 500;
    const payload = err.payload || { error: { code: 'internal', message: 'Internal error' } };
    res.status(status).json(payload);
});

// Only listen if started directly
const port = process.env.PORT || 3000;
if (import.meta.url === `file://${process.argv[1]}`) {
    app.listen(port, () => console.log(`API listening on :${port}`));
}

// For tests
export async function shutdown() {
    try { await closeDb(); } catch {}
}

export default app;
