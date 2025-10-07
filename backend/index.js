const http = require('http');

const PORT = process.env.PORT || 3000;

const requestListener = (req, res) => {
  res.writeHead(200, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify({ message: 'Crossroads 2.0 backend is running' }));
};

http.createServer(requestListener).listen(PORT, () => {
  console.log(`Backend listening on http://localhost:${PORT}`);
});
