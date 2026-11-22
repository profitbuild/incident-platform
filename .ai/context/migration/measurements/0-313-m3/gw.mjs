// Fake gateway for #0-313 measurement 3: listens on a unix socket (and TCP 8080), logs each request, answers SSE.
import http from 'node:http';
import fs from 'node:fs';
const SOCK = process.env.SOCK;
const TOKEN = 'tok-m313-made-up';
const log = (o) => console.log(JSON.stringify({ t: new Date().toISOString(), ...o }));
const handler = (via) => (req, res) => {
  let n = 0;
  req.on('data', (c) => { n += c.length; });
  req.on('end', () => {
    const a = req.headers['authorization'] || '';
    const k = req.headers['x-api-key'] || '';
    log({ via, method: req.method, path: req.url, host: req.headers.host,
      authorization: a ? (a === `Bearer ${TOKEN}` ? 'bearer=token' : 'other') : 'none',
      xApiKey: k ? (k === TOKEN ? 'token' : 'other') : 'none', bodyBytes: n });
    if (req.method === 'POST' && req.url.startsWith('/v1/messages') && !req.url.includes('count_tokens')) {
      res.writeHead(200, { 'content-type': 'text/event-stream' });
      const ev = (e, d) => res.write(`event: ${e}\ndata: ${JSON.stringify(d)}\n\n`);
      ev('message_start', { type: 'message_start', message: { id: 'msg_m313', type: 'message', role: 'assistant',
        model: 'claude-fake', content: [], stop_reason: null, stop_sequence: null,
        usage: { input_tokens: 1, output_tokens: 1 } } });
      ev('content_block_start', { type: 'content_block_start', index: 0, content_block: { type: 'text', text: '' } });
      ev('content_block_delta', { type: 'content_block_delta', index: 0, delta: { type: 'text_delta', text: 'ok-m313' } });
      ev('content_block_stop', { type: 'content_block_stop', index: 0 });
      ev('message_delta', { type: 'message_delta', delta: { stop_reason: 'end_turn', stop_sequence: null },
        usage: { output_tokens: 1 } });
      ev('message_stop', { type: 'message_stop' });
      res.end();
    } else if (req.url.startsWith('/v1/messages/count_tokens')) {
      res.writeHead(200, { 'content-type': 'application/json' }); res.end('{"input_tokens":1}');
    } else {
      res.writeHead(404, { 'content-type': 'application/json' });
      res.end('{"type":"error","error":{"type":"not_found_error","message":"m313"}}');
    }
  });
};
try { fs.unlinkSync(SOCK); } catch {}
const srv = http.createServer(handler('unix'));
srv.on('connection', (c) => { log({ conn: 'open' }); c.on('close', () => log({ conn: 'close' })); });
srv.on('clientError', (e, c) => { log({ clientError: e.code || String(e), first: e.rawPacket ? e.rawPacket.subarray(0, 8).toString('hex') : null, sni: e.rawPacket ? (e.rawPacket.toString('latin1').match(/[a-z0-9.-]+\.(com|ai|invalid|internal)/) || [null])[0] : null }); c.destroy(); });
srv.listen(SOCK, () => { fs.chmodSync(SOCK, 0o777); log({ ready: SOCK }); });
if (process.env.TCP) { const t = http.createServer(handler('tcp')); t.listen(8080, '0.0.0.0', () => log({ ready: 'tcp:8080' })); }
