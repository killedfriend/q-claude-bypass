import test from 'node:test';
import assert from 'node:assert/strict';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { loadConfig, normalizeProviderId, PROVIDER_IDS } from '../lib/config.mjs';

const GATEWAY = dirname(dirname(fileURLToPath(import.meta.url)));

for (const id of PROVIDER_IDS) {
  test(`provider preset ${id} loads`, () => {
    const cfg = loadConfig({ gatewayDir: GATEWAY, env: { GATEWAY_PROVIDER: id } });
    assert.equal(cfg.provider, id);
    assert.match(cfg.upstream, /^https:\/\//);
    assert.ok(cfg.models.main);
    assert.ok(cfg.models.heavy);
    assert.ok(cfg.models.cheap);
    assert.ok(cfg.publicModels.includes('claude-sonnet-4-5[1m]'));
    assert.ok(cfg.auth.env);
  });
}

test('provider id is case-insensitive and path-safe', () => {
  assert.equal(normalizeProviderId('OpenRouter'), 'openrouter');
  assert.equal(normalizeProviderId('../escape'), null);
  assert.equal(normalizeProviderId('my-provider'), 'my-provider');
});

test('unknown provider fails with a clear error', () => {
  assert.throws(
    () => loadConfig({ gatewayDir: GATEWAY, env: { GATEWAY_PROVIDER: 'nope' } }),
    /provider "nope" not found/
  );
});

test('environment port overrides the config file', () => {
  const cfg = loadConfig({ gatewayDir: GATEWAY, env: { GATEWAY_PROVIDER: 'deepseek', GATEWAY_PORT: '9999' } });
  assert.equal(cfg.listen.port, 9999);
});

test('config directory is the gateway directory', () => {
  const cfg = loadConfig({ gatewayDir: GATEWAY, env: { GATEWAY_PROVIDER: 'deepseek' } });
  assert.equal(cfg.dir, GATEWAY);
  assert.equal(cfg.logFile, 'logs/requests.jsonl');
});

test('provider client map exists for direct and gateway modes', () => {
  for (const id of PROVIDER_IDS) {
    const cfg = loadConfig({ gatewayDir: GATEWAY, env: { GATEWAY_PROVIDER: id } });
    assert.ok(cfg.client.direct.model, `${id} direct model`);
    assert.ok(cfg.client.gateway.model, `${id} gateway model`);
    assert.equal(cfg.client.gateway.model, 'claude-sonnet-4-5[1m]');
  }
});

test('provider files are valid JSON in the expected place', () => {
  for (const id of PROVIDER_IDS) {
    const path = join(GATEWAY, 'providers', `${id}.json`);
    const raw = loadConfig({ gatewayDir: GATEWAY, env: { GATEWAY_PROVIDER: id } });
    assert.equal(raw.provider, id);
    assert.ok(path.endsWith(`${id}.json`));
  }
});
