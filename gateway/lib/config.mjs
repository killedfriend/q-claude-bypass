import { existsSync, readFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';

export const PROVIDER_IDS = ['deepseek', 'tencent', 'alibaba', 'openrouter'];

function readJson(path) {
  return JSON.parse(readFileSync(path, 'utf8').replace(/^\uFEFF/, ''));
}

function normalizeAuth(auth, env) {
  if (!auth) return { mode: 'gateway', header: 'authorization', scheme: 'Bearer ', env: 'DEEPSEEK_API_KEY' };
  if (typeof auth === 'string') {
    // Backwards compatibility with the DeepSeek-only config format.
    return {
      mode: auth,
      header: 'authorization',
      scheme: 'Bearer ',
      env: env.DEEPSEEK_API_KEY ? 'DEEPSEEK_API_KEY' : 'DEEPSEEK_API_KEY',
    };
  }
  return {
    mode: auth.mode || 'gateway',
    header: auth.header || 'authorization',
    scheme: auth.scheme == null ? 'Bearer ' : String(auth.scheme),
    env: auth.env || 'DEEPSEEK_API_KEY',
  };
}

export function normalizeProviderId(value) {
  const id = String(value || '').trim().toLowerCase();
  // Presets live in gateway/providers, but a project may add its own file.
  return /^[a-z0-9][a-z0-9_-]*$/.test(id) ? id : null;
}

/**
 * Load the shared gateway config and merge the selected provider overlay.
 *
 *   gateway/config.json          transport, routing, logging, limits
 *   gateway/providers/<id>.json  upstream, auth, models, prices, capabilities
 *
 * GATEWAY_CONFIG and GATEWAY_PROVIDER override the defaults, which keeps tests
 * and the installer from having to rewrite files in the repository.
 */
export function loadConfig({ gatewayDir, configPath, providerName, env = process.env } = {}) {
  const explicit = configPath || env.GATEWAY_CONFIG;
  const basePath = explicit ? resolve(explicit) : join(gatewayDir, 'config.json');
  if (!existsSync(basePath)) throw new Error(`config not found: ${basePath}`);

  const base = readJson(basePath);
  const name = normalizeProviderId(providerName || env.GATEWAY_PROVIDER || base.provider || 'deepseek');
  if (!name) throw new Error(`unknown provider "${providerName || env.GATEWAY_PROVIDER || base.provider}"`);

  const providerPath = join(dirname(basePath), 'providers', `${name}.json`);
  if (!existsSync(providerPath)) throw new Error(`provider "${name}" not found: ${providerPath}`);
  const provider = readJson(providerPath);

  const merged = {
    ...provider,
    ...base,
    dir: dirname(basePath),
    configPath: basePath,
    provider: name,
    displayName: provider.name || name,
    upstream: provider.upstream || base.upstream,
    models: provider.models || base.models,
    publicModels: base.publicModels || provider.publicModels,
    routing: { ...(base.routing || {}), ...(provider.routing || {}) },
    context: { ...(base.context || {}), ...(provider.context || {}) },
    limits: { ...(base.limits || {}), ...(provider.limits || {}) },
    listen: { ...(base.listen || {}), ...(provider.listen || {}) },
    auth: normalizeAuth(provider.auth || base.auth, env),
  };

  if (env.GATEWAY_PORT) merged.listen.port = Number(env.GATEWAY_PORT);
  if (env.GATEWAY_HOST) merged.listen.host = env.GATEWAY_HOST;
  if (env.GATEWAY_UPSTREAM) merged.upstream = env.GATEWAY_UPSTREAM;
  if (env.GATEWAY_LOG) merged.logFile = env.GATEWAY_LOG;

  merged.upstream = String(merged.upstream || '').replace(/\/+$/, '');
  merged.currency = String(merged.currency || 'USD').toUpperCase();
  merged.documents = merged.documents || 'native';
  merged.vision = Array.isArray(merged.vision) ? merged.vision : [];
  merged.pricing = merged.pricing && typeof merged.pricing === 'object' ? merged.pricing : {};

  validateConfig(merged);
  return merged;
}

export function validateConfig(cfg) {
  if (!/^https?:\/\//i.test(cfg.upstream)) {
    throw new Error(`provider "${cfg.provider}" has an invalid upstream URL: ${cfg.upstream}`);
  }
  if (!cfg.models || !cfg.models.main || !cfg.models.heavy || !cfg.models.cheap) {
    throw new Error(`provider "${cfg.provider}" must define models.main, models.heavy and models.cheap`);
  }
  if (!Array.isArray(cfg.publicModels) || cfg.publicModels.length === 0) {
    throw new Error('publicModels must be a non-empty array');
  }
  if (!cfg.auth || !cfg.auth.env) {
    throw new Error('auth.env is required (the environment variable that holds the provider API key)');
  }
  if (!['gateway', 'passthrough'].includes(cfg.auth.mode)) {
    throw new Error(`auth.mode must be "gateway" or "passthrough", got "${cfg.auth.mode}"`);
  }
  if (!['deepseek-files', 'native', 'none'].includes(cfg.documents)) {
    throw new Error(`documents must be "deepseek-files", "native" or "none", got "${cfg.documents}"`);
  }
  if (cfg.cacheControl && !['strip', 'keep'].includes(cfg.cacheControl)) {
    throw new Error(`cacheControl must be "strip" or "keep", got "${cfg.cacheControl}"`);
  }
  return cfg;
}

export function providerKey(cfg, env = process.env) {
  return env[cfg.auth.env] || '';
}
