import express from 'express';
import devDbRoutes from './routes/devDb.js'; // <- toevoegen

import transactions from './routes/transactions.js';
import cashflows from './routes/cashflows.js';
import { close as closeDb } from './lib/db.js';

const app = express();
app.use(express.json());

// Mounten onder /dev/db (alleen in development kan ook)
const isDev = process.env.NODE_ENV !== 'production';

if(isDev) {
    app.use('/dev/db', devDbRoutes);
    console.log('🔧 Dev routes enabled at /dev/db');
}

app.get('/api/v1/health', (req, res) => res.json({ ok: true }));
app.use('/api/v1/transactions', transactions);
app.use('/api/v1/cashflows',     cashflows);

// error handler
app.use((err, req, res, next) => {
    const status = err.status || 500;
    const payload = err.payload || { error: { code: 'internal', message: 'Internal error' } };
    res.status(status).json(payload);
});

const port = process.env.PORT || 3000;
app.listen(port, () => console.log(`API listening on :${port}`));


// For tests
export async function shutdown() {
    try { await closeDb(); } catch {}
}

export default app;
