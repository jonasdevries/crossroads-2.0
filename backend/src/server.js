import express from 'express';
import devDbRoutes from './routes/dev-db.js';
import transactions from './routes/transactions.js';
import cashflows from './routes/cashflows.js';
import { close as closeDb } from './lib/db.js';
// import helmet from 'helmet';    // optional
// import cors from 'cors';        // optional
// import compression from 'compression'; // optional

const app = express();
app.use(express.json({ limit: '1mb' }));
// app.use(helmet());
// app.use(cors());
// app.use(compression());

const isDev = process.env.NODE_ENV !== 'production';

if (isDev) {
    app.use('/dev/db', devDbRoutes);
    console.log('🔧 Dev routes enabled at /dev/db');
}

app.get('/api/v1/health', (req, res) => res.json({ ok: true }));
app.use('/api/v1/transactions', transactions);
app.use('/api/v1/cashflows', cashflows);

// 404
app.use((req, res) => {
    res.status(404).json({ error: { code: 'not_found', message: 'Route not found' } });
});

// error handler
app.use((err, req, res, next) => {
    const status = err.status || 500;
    const payload = err.payload || { error: { code: 'internal', message: 'Internal error' } };
    if (isDev) payload.debug = { message: err.message, stack: err.stack };
    res.status(status).json(payload);
});

const port = process.env.PORT || 3000;

if (process.env.NODE_ENV !== 'test') {
    const server = app.listen(port, () => console.log(`API listening on :${port}`));

    const stop = async () => {
        try { await shutdown(); } finally {
            server.close(() => process.exit(0));
        }
    };
    process.on('SIGINT', stop);
    process.on('SIGTERM', stop);
}

// For tests
export async function shutdown() {
    try { await closeDb(); } catch {}
}

export default app;
