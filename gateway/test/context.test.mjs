import test from 'node:test';
import assert from 'node:assert/strict';
import { pruneContext } from '../lib/context.mjs';

function makeBody(results) {
  return {
    system: 'x'.repeat(100),
    messages: results.map((text, i) => ({
      role: 'user',
      content: [{ type: 'tool_result', tool_use_id: `t${i}`, content: text }],
    })),
  };
}

const cfg = {
  context: {
    enabled: true,
    maxChars: 500,
    keepRecentToolResults: 2,
    elideAboveChars: 100,
  },
};

test('old large tool results are elided, recent ones are kept', () => {
  const body = makeBody(['a'.repeat(300), 'b'.repeat(300), 'c'.repeat(300), 'd'.repeat(300)]);
  const r = pruneContext(cfg, body, {});
  assert.ok(r.elided >= 1);
  assert.equal(body.messages.length, 4);
  assert.match(body.messages[0].content[0].content[0].text, /elided by gateway/);
  assert.equal(body.messages[3].content[0].content, 'd'.repeat(300));
});

test('small bodies are untouched', () => {
  const body = makeBody(['short']);
  const r = pruneContext(cfg, body, {});
  assert.equal(r.elided, 0);
  assert.equal(body.messages[0].content[0].content, 'short');
});

test('disabled pruning is a no-op', () => {
  const body = makeBody(['a'.repeat(1000)]);
  const r = pruneContext({ context: { enabled: false } }, body, {});
  assert.equal(r.elided, 0);
  assert.equal(body.messages[0].content[0].content, 'a'.repeat(1000));
});
