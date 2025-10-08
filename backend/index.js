const http = require('http');

const PORT = Number(process.env.PORT) || 3000;

const requestListener = (req, res) => {
  res.writeHead(200, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify({ message: 'Crossroads 2.0 backend is running' }));
};

const createServer = () => http.createServer(requestListener);

if (require.main === module) {
  const server = createServer();
  server.listen(PORT, () => {
    console.log(`Backend listening on http://localhost:${PORT}`);
  });
}

module.exports = {
  createServer,
  requestListener,
  PORT
};
