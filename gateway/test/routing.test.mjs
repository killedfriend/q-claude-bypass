import test from 'node:test';
import assert from 'node:assert/strict';
import { pickRoute } from '../lib/routing.mjs';

const cfg = {
  models: { main: 'main-model', heavy: 'heavy-model', cheap: 'cheap-model' },
  vision: ['main-model'],
  routing: { opusToHeavy: true, haikuToCheap: true, cheapWithoutTools: true },
  cheapProfile: { effort: 'low', thinking: 'disabled', maxTokens: 4096 },
};

const tool = { name: 'Read', input_schema: { type: 'object' } };

test('opus maps to the heavy model', () => {
  const body = { model: 'claude-opus-4-5', tools: [tool], messages: [] };
  const r = pickRoute(cfg, body);
  assert.equal(r.name, 'heavy');
  assert.equal(r.model, 'heavy-model');
});

test('haiku maps to the cheap model', () => {
  const body = { model: 'claude-haiku-4-5', tools: [tool], messages: [] };
  const r = pickRoute(cfg, body);
  assert.equal(r.name, 'cheap');
  assert.equal(r.model, 'cheap-model');
  assert.equal(body.output_config.effort, 'low');
  assert.equal(body.thinking.type, 'disabled');
  assert.equal(body.max_tokens, 4096);
});

test('a request without tools uses the cheap model', () => {
  const body = { model: 'claude-sonnet-4-5[1m]', messages: [] };
  const r = pickRoute(cfg, body);
  assert.equal(r.name, 'cheap');
});

test('a normal tool request uses main', () => {
  const body = { model: 'claude-sonnet-4-5[1m]', tools: [tool], messages: [] };
  const r = pickRoute(cfg, body);
  assert.equal(r.name, 'main');
  assert.equal(r.model, 'main-model');
});

test('an image on a non-vision heavy route falls back to main', () => {
  const body = {
    model: 'claude-opus-4-5',
    tools: [tool],
    messages: [{ role: 'user', content: [{ type: 'image', source: { type: 'base64', data: '' } }] }],
  };
  const r = pickRoute(cfg, body);
  assert.equal(r.name, 'main');
  assert.equal(r.model, 'main-model');
  assert.ok(r.applied.some((x) => x.startsWith('images:')));
});

test('images without a vision model are reported, not hidden', () => {
  const textOnly = { ...cfg, vision: [] };
  const body = {
    model: 'claude-opus-4-5',
    tools: [tool],
    messages: [{ role: 'user', content: [{ type: 'image', source: { type: 'base64', data: '' } }] }],
  };
  const r = pickRoute(textOnly, body);
  assert.ok(r.applied.some((x) => x.includes('no vision-capable model')));
});
