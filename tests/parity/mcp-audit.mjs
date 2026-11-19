// Minimal MCP server over stdio, newline-delimited JSON-RPC.
// Exists only to prove Claude Code can call an MCP tool through DeepSeek.
import readline from 'node:readline';

const send = (o) => process.stdout.write(JSON.stringify(o) + '\n');
const rl = readline.createInterface({ input: process.stdin });

rl.on('line', (line) => {
  if (!line.trim()) return;
  let msg;
  try { msg = JSON.parse(line); } catch { return; }

  if (msg.method === 'initialize') {
    send({
      jsonrpc: '2.0',
      id: msg.id,
      result: {
        protocolVersion: msg.params?.protocolVersion || '2024-11-05',
        capabilities: { tools: {} },
        serverInfo: { name: 'audit', version: '1.0.0' },
      },
    });
    return;
  }

  if (msg.method === 'notifications/initialized') return;

  if (msg.method === 'tools/list') {
    send({
      jsonrpc: '2.0',
      id: msg.id,
      result: {
        tools: [{
          name: 'echo',
          description: 'Echo the given text back with an "echo:" prefix.',
          inputSchema: {
            type: 'object',
            properties: { text: { type: 'string', description: 'Text to echo' } },
            required: ['text'],
          },
        }],
      },
    });
    return;
  }

  if (msg.method === 'tools/call') {
    const text = msg.params?.arguments?.text ?? '';
    send({
      jsonrpc: '2.0',
      id: msg.id,
      result: { content: [{ type: 'text', text: `echo:${text}` }], isError: false },
    });
    return;
  }

  if (msg.id !== undefined) {
    send({ jsonrpc: '2.0', id: msg.id, error: { code: -32601, message: `unknown method ${msg.method}` } });
  }
});
