import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import net from 'node:net';
import { spawn } from 'node:child_process';
import { mkdtemp, mkdir, readFile, writeFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = dirname(dirname(dirname(fileURLToPath(import.meta.url))));
const GATEWAY_DIR = join(ROOT, 'gateway');

async function freePort() {
  const server = net.createServer();
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  const port = server.address().port;
  await new Promise((resolve) => server.close(resolve));
  return port;
}

async function waitFor(url, attempts = 100) {
  let last;
  for (let i = 0; i < attempts; i++) {
    try {
      const res = await fetch(url);
      if (res.ok) return res;
    } catch (e) { last = e; }
    await new Promise((r) => setTimeout(r, 100));
  }
  throw last || new Error(`timeout waiting for ${url}`);
}

function fakeUpstream() {
  const requests = [];
  const server = http.createServer(async (req, res) => {
    let raw = '';
    for await (const chunk of req) raw += chunk;
    const body = JSON.parse(raw);
    requests.push({ url: req.url, headers: req.headers, body });

    if (body.stream) {
      res.writeHead(200, { 'content-type': 'text/event-stream' });
      res.write('event: message_start\ndata: {"type":"message_start","message":{"usage":{"input_tokens":10,"output_tokens":1}}}\n\n');
      res.write('event: content_block_delta\ndata: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"stream-ok"}}\n\n');
      res.write('event: message_delta\ndata: {"type":"message_delta","usage":{"output_tokens":5}}\n\n');
      res.end();
      return;
    }

    res.writeHead(200, { 'content-type': 'application/json' });
    res.end(JSON.stringify({
      id: 'msg_test',
      type: 'message',
      role: 'assistant',
      model: body.model,
      content: [{ type: 'text', text: 'ok' }],
      stop_reason: 'end_turn',
      usage: { input_tokens: 10, cache_read_input_tokens: 0, output_tokens: 5 },
    }));
  });
  return { server, requests };
}

test('gateway proxies, routes, logs and streams', async () => {
  const fake = fakeUpstream();
  await new Promise((resolve) => fake.server.listen(0, '127.0.0.1', resolve));
  const fakePort = fake.server.address().port;

  const port = await freePort();
  const dir = await mkdtemp(join(tmpdir(), 'qclaude-test-'));
  await mkdir(join(dir, 'providers'), { recursive: true });

  const base = JSON.parse(await readFile(join(GATEWAY_DIR, 'config.json'), 'utf8'));
  base.provider = 'mock';
  base.listen.port = port;
  base.logFile = 'logs/requests.jsonl';
  base.publicModels = ['claude-sonnet-4-5[1m]', 'claude-opus-4-5', 'claude-haiku-4-5'];
  base.routing = { opusToHeavy: true, haikuToCheap: true, cheapWithoutTools: true };
  base.limits = { dailyBudget: 0, maxRetries: 0, timeoutMs: 30000 };
  await writeFile(join(dir, 'config.json'), JSON.stringify(base, null, 2));

  const provider = {
    name: 'Mock Provider',
    upstream: `http://127.0.0.1:${fakePort}`,
    currency: 'USD',
    auth: { mode: 'gateway', header: 'authorization', scheme: 'Bearer ', env: 'MOCK_API_KEY' },
    models: { main: 'mock-main', heavy: 'mock-heavy', cheap: 'mock-cheap' },
    vision: ['mock-main', 'mock-heavy', 'mock-cheap'],
    documents: 'native',
    cacheControl: 'keep',
    cheapProfile: { effort: 'low', maxTokens: 4096 },
    pricing: {
      'mock-main': { input: 1, cacheRead: 0, output: 2 },
      'mock-heavy': { input: 1, cacheRead: 0, output: 2 },
      'mock-cheap': { input: 1, cacheRead: 0, output: 2 },
    },
    client: { direct: { model: 'mock-main' }, gateway: { model: 'claude-sonnet-4-5[1m]' } },
  };
  await writeFile(join(dir, 'providers', 'mock.json'), JSON.stringify(provider, null, 2));

  const child = spawn(process.execPath, ['gateway/server.mjs'], {
    cwd: ROOT,
    env: {
      ...process.env,
      GATEWAY_CONFIG: join(dir, 'config.json'),
      GATEWAY_PROVIDER: 'mock',
      GATEWAY_PORT: String(port),
      MOCK_API_KEY: 'test-secret',
    },
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  let output = '';
  child.stdout.on('data', (d) => { output += d; });
  child.stderr.on('data', (d) => { output += d; });

  try {
    try {
      await waitFor(`http://127.0.0.1:${port}/health`);
    } catch (e) {
      throw new Error(`gateway did not start: ${e.message}\n${output}`);
    }

    const health = await (await fetch(`http://127.0.0.1:${port}/health`)).json();
    assert.equal(health.provider, 'mock');
    assert.equal(health.upstream, `http://127.0.0.1:${fakePort}`);
    assert.equal(health.keyConfigured, true);

    const models = await (await fetch(`http://127.0.0.1:${port}/v1/models`)).json();
    assert.ok(models.data.some((m) => m.id === 'claude-sonnet-4-5[1m]'));

    const post = (body) => fetch(`http://127.0.0.1:${port}/v1/messages`, {
      method: 'POST',
      headers: { 'content-type': 'application/json', 'anthropic-version': '2023-06-01' },
      body: JSON.stringify(body),
    });

    const first = await post({
      model: 'claude-sonnet-4-5[1m]',
      max_tokens: 32,
      tools: [{ name: 'Read', input_schema: { type: 'object' } }],
      system: [{ type: 'text', text: 'cache me', cache_control: { type: 'ephemeral' } }],
      messages: [{ role: 'user', content: 'hi' }],
    });
    assert.equal(first.status, 200);
    await first.json();
    assert.equal(fake.requests[0].url, '/v1/messages');
    assert.equal(fake.requests[0].headers.authorization, 'Bearer test-secret');
    assert.equal(fake.requests[0].body.model, 'mock-main');
    assert.equal(fake.requests[0].body.system[0].cache_control.type, 'ephemeral');

    await post({
      model: 'claude-opus-4-5',
      max_tokens: 32,
      tools: [{ name: 'Read', input_schema: { type: 'object' } }],
      messages: [{ role: 'user', content: 'hi' }],
    });
    assert.equal(fake.requests[1].body.model, 'mock-heavy');

    await post({
      model: 'claude-sonnet-4-5[1m]',
      max_tokens: 32,
      messages: [{ role: 'user', content: 'background call' }],
    });
    assert.equal(fake.requests[2].body.model, 'mock-cheap');
    assert.equal(fake.requests[2].body.output_config.effort, 'low');

    const stream = await post({
      model: 'claude-haiku-4-5',
      max_tokens: 32,
      stream: true,
      tools: [{ name: 'Read', input_schema: { type: 'object' } }],
      messages: [{ role: 'user', content: 'hi' }],
    });
    assert.equal(stream.status, 200);
    const text = await stream.text();
    assert.match(text, /message_start/);
    assert.match(text, /stream-ok/);
    assert.equal(fake.requests[3].body.model, 'mock-cheap');

    const count = await (await fetch(`http://127.0.0.1:${port}/v1/messages/count_tokens`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ messages: [{ role: 'user', content: 'hello' }] }),
    })).json();
    assert.ok(count.input_tokens >= 1);

    const log = await readFile(join(dir, 'logs', 'requests.jsonl'), 'utf8');
    assert.match(log, /"provider":"mock"/);
    assert.match(log, /"upModel":"mock-main"/);

    const after = await (await fetch(`http://127.0.0.1:${port}/health`)).json();
    assert.ok(after.spentToday > 0);
  } finally {
    child.kill();
    await Promise.race([
      new Promise((resolve) => child.once('exit', resolve)),
      new Promise((resolve) => setTimeout(resolve, 3000)),
    ]);
    if (typeof fake.server.closeAllConnections === 'function') fake.server.closeAllConnections();
    await new Promise((resolve) => fake.server.close(resolve));
    await rm(dir, { recursive: true, force: true });
  }
});
