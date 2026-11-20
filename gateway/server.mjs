#!/usr/bin/env node
/**
 * Local Anthropic-compatible gateway.
 *
 *   Claude Code / Claude Desktop
 *        -> http://127.0.0.1:8788/v1/messages
 *        -> provider (DeepSeek, Tencent Hunyuan, Alibaba Bailian, OpenRouter)
 *
 * Features on top of a plain ANTHROPIC_BASE_URL:
 *   - model routing (opus -> heavy, haiku/background -> cheap)
 *   - provider presets in gateway/providers/*.json
 *   - request log with real token counts, cache hits and cost
 *   - sanitizing of blocks some providers reject (documents, cache_control)
 *   - retries on 429/5xx, hard timeout, optional daily budget
 *   - /v1/messages/count_tokens fallback
 *
 * Zero dependencies: Node 22 built-ins only.
 */
import http from 'node:http';
import https from 'node:https';
import { once } from 'node:events';
import { createHash } from 'node:crypto';
import { appendFileSync, existsSync, mkdirSync, readFileSync, unlinkSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { loadConfig, providerKey } from './lib/config.mjs';
import { costOf, currencySymbol, dayKey, isPeak, priceKey, webCostOf } from './lib/pricing.mjs';
import { pickRoute, isVisionModel } from './lib/routing.mjs';
import { pruneContext } from './lib/context.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const CFG = loadConfig({ gatewayDir: HERE, env: process.env });
const HOST = CFG.listen.host;
const PORT = Number(CFG.listen.port);
const TLS_PORT = Number(process.env.GATEWAY_TLS_PORT || 443);
const LOG = resolve(CFG.dir, CFG.logFile);
const RETRYABLE = new Set([408, 429, 500, 502, 503, 504]);
const STARTED = Date.now();
const CUR = CFG.currency;
const SYM = currencySymbol(CUR);
const PID_FILE = resolve(CFG.dir, 'logs', 'gateway.pid');
const USES_PEAK = Object.values(CFG.pricing || {}).some((p) => p && p.peak && p.offPeak);

mkdirSync(dirname(LOG), { recursive: true });

// ---------------------------------------------------------------- spend log

function pathFor(rel) {
  return resolve(CFG.dir, rel);
}

let spentToday = 0;
if (existsSync(LOG)) {
  for (const line of readFileSync(LOG, 'utf8').split('\n')) {
    if (!line.trim()) continue;
    try {
      const r = JSON.parse(line);
      if (r.day === dayKey() && r.cost && (!r.currency || r.currency === CUR)) spentToday += r.cost;
    } catch { /* torn line from a crash, ignore */ }
  }
}

const stats = { requests: 0, errors: 0 };

// ------------------------------------------------------- uploaded files cache
// DeepSeek only: Claude Code resends the same PDF on every turn. Upload once.
const FILE_CACHE = pathFor(CFG.files?.cacheFile || 'logs/files.json');
let fileCache = {};
try { fileCache = JSON.parse(readFileSync(FILE_CACHE, 'utf8')); } catch { /* first run */ }
function saveFileCache() {
  try { writeFileSync(FILE_CACHE, JSON.stringify(fileCache, null, 2)); } catch (e) { console.error('file cache write failed:', e.message); }
}

const MAX_UPLOAD = 100 * 1024 * 1024;
const EXT = {
  'application/pdf': '.pdf',
  'application/msword': '.doc',
  'application/vnd.openxmlformats-officedocument.wordprocessingml.document': '.docx',
  'application/vnd.ms-powerpoint': '.ppt',
  'application/vnd.openxmlformats-officedocument.presentationml.presentation': '.pptx',
};

function purposeFor(media = '') {
  if (/pdf|officedocument|msword|ms-powerpoint/.test(media)) {
    return CFG.files?.documentPurpose || 'rich_layout_recognition';
  }
  return 'user_data';
}

function clientKey(headersIn) {
  const raw = headersIn?.['x-api-key'] || headersIn?.authorization || '';
  return String(raw).replace(/^Bearer\s+/i, '');
}

function apiKey(headersIn) {
  if (CFG.auth.mode === 'passthrough') return clientKey(headersIn);
  return providerKey(CFG, process.env);
}

function safeName(title, media) {
  const base = String(title || 'attachment').replace(/[^\w.\- ]+/g, '_').slice(0, 60).trim() || 'attachment';
  return base + (EXT[media] && !base.toLowerCase().endsWith(EXT[media]) ? EXT[media] : '');
}

async function ensureFile(b64, media, title, headersIn) {
  const hash = createHash('sha256').update(media).update('\0').update(b64).digest('hex');
  const hit = fileCache[hash];
  if (hit?.id) return { id: hit.id, reused: true };

  const buf = Buffer.from(b64, 'base64');
  if (buf.length > MAX_UPLOAD) throw new Error(`file is ${buf.length} bytes, limit ${MAX_UPLOAD}`);

  const purpose = purposeFor(media);
  const form = new FormData();
  form.append('purpose', purpose); // must precede the file field
  form.append('file', new Blob([buf], { type: media }), safeName(title, media));

  const key = apiKey(headersIn);
  if (!key) throw new Error(`no API key: set ${CFG.auth.env} (or auth.mode="passthrough")`);

  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), CFG.files?.timeoutMs ?? 120000);
  try {
    const res = await fetch(CFG.files?.uploadUrl || 'https://api.deepseek.com/files', {
      method: 'POST',
      headers: { authorization: `Bearer ${key}` },
      body: form,
      signal: ctrl.signal,
    });
    const text = await res.text();
    if (!res.ok) throw new Error(`${res.status} ${text.replace(/\s+/g, ' ').slice(0, 200)}`);
    const j = JSON.parse(text);
    if (!j.id) throw new Error('response has no file id');
    fileCache[hash] = { id: j.id, purpose, bytes: j.bytes || buf.length, name: j.filename, ts: Date.now() };
    saveFileCache();
    console.log(`  uploaded ${j.filename || 'file'} (${j.bytes || buf.length} B, ${purpose}) -> ${j.id}`);
    return { id: j.id, reused: false };
  } finally {
    clearTimeout(timer);
  }
}

function record(entry) {
  const rec = {
    ts: new Date().toISOString(),
    day: dayKey(),
    provider: CFG.provider,
    currency: CUR,
    ...entry,
  };
  try { appendFileSync(LOG, JSON.stringify(rec) + '\n'); } catch (e) { console.error('log write failed:', e.message); }
  if (rec.cost && rec.currency === CUR) spentToday += rec.cost;
  stats.requests++;
  if (rec.status >= 400) stats.errors++;

  const t = new Date().toLocaleTimeString('en-GB', { hour12: false });
  const cache = rec.cacheRead ? `+${rec.cacheRead}c` : '';
  const money = rec.cost != null ? ` ${CUR} ${rec.cost.toFixed(4)}` : '';
  const web = rec.webSearch || rec.webFetch ? ` web=${rec.webSearch}/${rec.webFetch}` : '';
  const pruned = rec.pruned ? ` pruned=${rec.pruned}(${Math.round(rec.prunedChars / 1000)}k)` : '';
  const err = rec.err ? `  ERR ${rec.err}` : '';
  console.log(
    `${t} ${String(rec.route).padEnd(5)} ${rec.status} ${(rec.ms / 1000).toFixed(1)}s ` +
    `in=${rec.in}${cache} out=${rec.out}${money}${web}${pruned}${err}`
  );
}

// ------------------------------------------------------------------ helpers

function sendJson(res, status, obj, extraHeaders = {}) {
  const body = JSON.stringify(obj);
  res.writeHead(status, {
    'content-type': 'application/json; charset=utf-8',
    'content-length': Buffer.byteLength(body),
    ...extraHeaders,
  });
  res.end(body);
}

function sendError(res, status, type, message) {
  sendJson(res, status, { type: 'error', error: { type, message } });
}

function readBody(req, limit = 64 * 1024 * 1024) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    let size = 0;
    req.on('data', (c) => {
      size += c.length;
      if (size > limit) { reject(new Error(`request body over ${limit} bytes`)); req.destroy(); return; }
      chunks.push(c);
    });
    req.on('end', () => resolve(Buffer.concat(chunks)));
    req.on('error', reject);
  });
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

function walk(node, fn) {
  if (Array.isArray(node)) { for (const v of node) walk(v, fn); return; }
  if (node && typeof node === 'object') {
    fn(node);
    for (const k of Object.keys(node)) walk(node[k], fn);
  }
}

// --------------------------------------------------------- document handling

async function convertDocument(b, ctx, notes, headersIn) {
  const src = b.source || {};
  if (src.type === 'file') { ctx.usedFiles = true; return b; }
  if (src.type !== 'base64') { notes.push(`document:${src.type}-kept`); return b; }

  const media = src.media_type || 'application/pdf';

  // Plain text needs no upload: DeepSeek accepts a text document source.
  if (media.startsWith('text/')) {
    notes.push('document:text-inline');
    return { type: 'text', text: Buffer.from(src.data || '', 'base64').toString('utf8') };
  }

  if (CFG.documents !== 'deepseek-files' || !CFG.files) {
    notes.push('document:not-supported');
    return { type: 'text', text: `[attachment omitted: ${b.title || media} is not supported by provider "${CFG.provider}"]` };
  }

  try {
    const { id, reused } = await ensureFile(src.data, media, b.title, headersIn);
    ctx.usedFiles = true;
    if (reused) ctx.reused++; else ctx.uploads++;

    if (ctx.seen?.has(id)) {
      notes.push('document:dedup');
      return { type: 'text', text: `[document already attached: ${b.title || media}]` };
    }
    ctx.seen?.add(id);

    notes.push(reused ? 'document:file-cached' : 'document:file-uploaded');
    const out = { type: 'document', source: { type: 'file', file_id: id } };
    if (b.title) out.title = b.title;
    return out;
  } catch (e) {
    notes.push('document:upload-failed');
    return { type: 'text', text: `[attachment omitted: Files API upload failed (${e.message})]` };
  }
}

// Documents arrive nested: Claude Code's Read tool returns them inside
// tool_result.content, and DeepSeek ignores document blocks below the top
// level of a user message. Lift them out and make siblings of the tool_result.
async function convertDocuments(blocks, ctx, notes, headersIn, depth = 0, hoist = null) {
  if (!Array.isArray(blocks) || depth > 8) return;
  for (let i = 0; i < blocks.length; i++) {
    const b = blocks[i];
    if (!b || typeof b !== 'object') continue;
    if (b.type === 'document') {
      const converted = await convertDocument(b, ctx, notes, headersIn);
      if (converted.type === 'document' && depth > 0 && hoist) {
        hoist.push(converted);
        blocks[i] = { type: 'text', text: `[${b.title || 'attachment'} is attached to this message as a document block]` };
        notes.push('document:hoisted');
      } else {
        blocks[i] = converted;
      }
      continue;
    }
    if (Array.isArray(b.content)) await convertDocuments(b.content, ctx, notes, headersIn, depth + 1, hoist);
  }
}

function stripDocuments(blocks, notes, depth = 0) {
  if (!Array.isArray(blocks) || depth > 8) return;
  for (let i = 0; i < blocks.length; i++) {
    const b = blocks[i];
    if (!b || typeof b !== 'object') continue;
    if (b.type === 'document') {
      const src = b.source || {};
      if (src.type === 'base64' && String(src.media_type || '').startsWith('text/')) {
        blocks[i] = { type: 'text', text: Buffer.from(src.data || '', 'base64').toString('utf8') };
        notes.push('document:text-inline');
      } else {
        blocks[i] = {
          type: 'text',
          text: `[attachment omitted: ${b.title || src.media_type || 'document'} is not supported by provider "${CFG.provider}"]`,
        };
        notes.push('document:not-supported');
      }
      continue;
    }
    if (Array.isArray(b.content)) stripDocuments(b.content, notes, depth + 1);
  }
}

async function sanitize(body, headersIn, ctx) {
  const notes = [];
  // DeepSeek accepts cache_control but ignores it; some providers reject it.
  // OpenRouter passes it through and uses it for prompt caching.
  if (CFG.cacheControl !== 'keep') {
    walk(body, (o) => { if ('cache_control' in o) delete o.cache_control; });
  }

  if (CFG.documents === 'native') return notes;

  for (const msg of body.messages || []) {
    if (!Array.isArray(msg.content)) continue;
    if (CFG.documents === 'none') {
      stripDocuments(msg.content, notes);
      continue;
    }
    const hoisted = [];
    await convertDocuments(msg.content, ctx, notes, headersIn, 0, hoisted);
    if (!hoisted.length) continue;
    if (msg.role === 'user') {
      for (const h of hoisted) msg.content.push(h);
    } else {
      notes.push('document:dropped-non-user');
    }
  }

  if (ctx.usedFiles) {
    const beta = String(headersIn['anthropic-beta'] || '');
    if (!beta.includes('files-api-2025-04-14')) {
      headersIn['anthropic-beta'] = beta ? `${beta},files-api-2025-04-14` : 'files-api-2025-04-14';
    }
  }
  return notes;
}

// -------------------------------------------------------------- usage tap

function usageTap() {
  const u = { input: 0, cacheRead: 0, out: 0, thinking: 0, webSearch: 0, webFetch: 0, upCost: null };
  let buf = '';
  const apply = (o) => {
    const src = o?.message?.usage || o?.usage;
    if (!src) return;
    if (o.type === 'message_start' || o.type === 'message') {
      u.input = src.input_tokens || 0;
      u.cacheRead = src.cache_read_input_tokens || 0;
    }
    if (typeof src.output_tokens === 'number') u.out = src.output_tokens;
    const th = src.output_tokens_details?.thinking_tokens;
    if (typeof th === 'number') u.thinking = th;
    // OpenRouter reports the exact charge in usage.cost.
    if (typeof src.cost === 'number' && Number.isFinite(src.cost)) u.upCost = src.cost;
    // Server-side web search/fetch is billed per call, not per token.
    const s = src.server_tool_use;
    if (s) {
      if (typeof s.tool_search === 'number') u.webSearch = s.tool_search;
      else if (typeof s.web_search_requests === 'number') u.webSearch = s.web_search_requests;
      if (typeof s.tool_fetch === 'number') u.webFetch = s.tool_fetch;
      else if (typeof s.web_fetch_requests === 'number') u.webFetch = s.web_fetch_requests;
    }
  };
  return {
    u,
    push(text) {
      buf += text;
      let i;
      while ((i = buf.indexOf('\n')) >= 0) {
        const line = buf.slice(0, i).trim();
        buf = buf.slice(i + 1);
        if (!line.startsWith('data:')) continue;
        const payload = line.slice(5).trim();
        if (!payload || payload[0] !== '{') continue;
        try { apply(JSON.parse(payload)); } catch { /* partial/non-JSON event */ }
      }
      if (buf.length > 4_000_000) buf = '';
    },
  };
}

// ---------------------------------------------------------------- upstream

function authHeaders(headersIn) {
  const auth = CFG.auth;
  const key = apiKey(headersIn);
  if (!key) {
    throw new Error(`no API key: set ${auth.env} (or auth.mode="passthrough" in the provider config)`);
  }
  return {
    [auth.header || 'authorization']: auth.scheme ? `${auth.scheme}${key}` : key,
  };
}

async function callUpstream(payload, headersIn, signal) {
  const url = CFG.upstream.replace(/\/+$/, '') + '/v1/messages';
  const headers = {
    'content-type': 'application/json',
    accept: headersIn.accept || 'application/json',
    'anthropic-version': headersIn['anthropic-version'] || '2023-06-01',
  };
  if (headersIn['anthropic-beta']) headers['anthropic-beta'] = headersIn['anthropic-beta'];
  Object.assign(headers, authHeaders(headersIn));
  const taken = new Set(Object.keys(headers).map((h) => h.toLowerCase()));
  for (const [name, value] of Object.entries(CFG.headers || {})) {
    if (!taken.has(name.toLowerCase())) headers[name] = value;
  }

  return fetch(url, { method: 'POST', headers, body: JSON.stringify(payload), signal });
}

async function upstreamWithRetry(payload, headersIn, signal) {
  const max = CFG.limits.maxRetries ?? 2;
  let lastErr;
  for (let attempt = 0; attempt <= max; attempt++) {
    try {
      const up = await callUpstream(payload, headersIn, signal);
      if (up.ok || !RETRYABLE.has(up.status) || attempt === max) return up;
      await up.text().catch(() => {});
      lastErr = new Error(`upstream ${up.status}`);
    } catch (e) {
      if (e.name === 'AbortError') throw e;
      lastErr = e;
      if (attempt === max) throw e;
    }
    const wait = 400 * 2 ** attempt;
    console.log(`  retry ${attempt + 1}/${max} in ${wait}ms (${lastErr.message})`);
    await sleep(wait);
  }
  throw lastErr;
}

// ------------------------------------------------------------------ handler

async function handleMessages(req, res) {
  const t0 = Date.now();
  const raw = await readBody(req);
  let body;
  // Strip a UTF-8 BOM: PowerShell 5.1 tools write one, JSON.parse rejects it.
  try { body = JSON.parse(raw.toString('utf8').replace(/^\uFEFF/, '')); }
  catch { return sendError(res, 400, 'invalid_request_error', 'body is not valid JSON'); }

  if (CFG.limits.dailyBudget > 0 && spentToday >= CFG.limits.dailyBudget) {
    record({ route: 'budget', status: 429, ms: Date.now() - t0, in: 0, out: 0, stream: !!body.stream, err: `daily budget ${SYM}${CFG.limits.dailyBudget} reached` });
    return sendError(res, 429, 'rate_limit_error', `gateway daily budget of ${SYM}${CFG.limits.dailyBudget} reached (today: ${SYM}${spentToday.toFixed(4)})`);
  }

  const route = pickRoute(CFG, body);
  const headersIn = { ...req.headers };
  const fileCtx = { uploads: 0, reused: 0, usedFiles: false, seen: new Set() };
  const notes = await sanitize(body, headersIn, fileCtx);
  const prune = pruneContext(CFG, body);
  const stream = !!body.stream;

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), CFG.limits.timeoutMs ?? 600000);
  const onClose = () => controller.abort();
  res.on('close', onClose);

  const entry = {
    route: route.name,
    reqModel: route.requested,
    upModel: route.model,
    status: 0,
    ms: 0,
    stream,
    in: 0,
    cacheRead: 0,
    out: 0,
    thinking: 0,
    cost: null,
    upCost: null,
    webCost: 0,
    webSearch: 0,
    webFetch: 0,
    tools: (body.tools || []).map((t) => t?.name).filter(Boolean),
    toolTypes: [...new Set((body.tools || []).map((t) => t?.type || 'custom'))],
    applied: route.applied,
    notes,
    uploads: fileCtx.uploads,
    fileReuse: fileCtx.reused,
    pruned: prune.elided,
    prunedChars: prune.savedChars,
    err: null,
  };

  // Opt-in: GATEWAY_DUMP=1 writes the final upstream payload to logs/last-request.json.
  if (process.env.GATEWAY_DUMP) {
    try { writeFileSync(pathFor('logs/last-request.json'), JSON.stringify(body, null, 2)); }
    catch (e) { console.error('dump failed:', e.message); }
  }

  try {
    const up = await upstreamWithRetry({ ...body, model: route.model }, headersIn, controller.signal);
    entry.status = up.status;
    const baseHeaders = { 'x-gateway-route': route.name, 'x-gateway-model': route.model, 'x-gateway-provider': CFG.provider };

    if (!up.ok) {
      const text = await up.text();
      entry.err = `${up.status} ${text.slice(0, 300)}`.replace(/\s+/g, ' ');
      entry.ms = Date.now() - t0;
      record(entry);
      res.writeHead(up.status, { 'content-type': 'application/json; charset=utf-8', ...baseHeaders });
      return res.end(text);
    }

    if (stream) {
      res.writeHead(up.status, {
        'content-type': 'text/event-stream; charset=utf-8',
        'cache-control': 'no-cache',
        connection: 'keep-alive',
        'x-accel-buffering': 'no',
        ...baseHeaders,
      });
      const tap = usageTap();
      const dec = new TextDecoder();
      for await (const chunk of up.body) {
        tap.push(dec.decode(chunk, { stream: true }));
        if (!res.write(Buffer.from(chunk))) await once(res, 'drain');
      }
      res.end();
      entry.in = tap.u.input;
      entry.cacheRead = tap.u.cacheRead;
      entry.out = tap.u.out;
      entry.thinking = tap.u.thinking;
      entry.webSearch = tap.u.webSearch;
      entry.webFetch = tap.u.webFetch;
      entry.upCost = tap.u.upCost;
    } else {
      const buf = Buffer.from(await up.arrayBuffer());
      res.writeHead(up.status, {
        'content-type': up.headers.get('content-type') || 'application/json',
        'content-length': buf.length,
        ...baseHeaders,
      });
      res.end(buf);
      try {
        const j = JSON.parse(buf.toString('utf8'));
        entry.in = j.usage?.input_tokens || 0;
        entry.cacheRead = j.usage?.cache_read_input_tokens || 0;
        entry.out = j.usage?.output_tokens || 0;
        entry.thinking = j.usage?.output_tokens_details?.thinking_tokens || 0;
        if (typeof j.usage?.cost === 'number') entry.upCost = j.usage.cost;
        const s = j.usage?.server_tool_use;
        if (s) {
          entry.webSearch = s.tool_search ?? s.web_search_requests ?? 0;
          entry.webFetch = s.tool_fetch ?? s.web_fetch_requests ?? 0;
        }
      } catch { /* non-JSON 200 */ }
    }

    entry.cost = costOf(CFG, route.model, {
      input_tokens: entry.in,
      cache_read_input_tokens: entry.cacheRead,
      output_tokens: entry.out,
    }, entry.upCost);

    if (entry.upCost == null) {
      const webAmount = webCostOf(CFG, entry);
      if (webAmount > 0) {
        entry.webCost = webAmount;
        entry.cost = Number(((entry.cost || 0) + webAmount).toFixed(6));
      }
    }
    entry.ms = Date.now() - t0;
    record(entry);
  } catch (e) {
    entry.status = e.name === 'AbortError' ? 504 : 502;
    entry.err = `${e.name}: ${e.message}`;
    entry.ms = Date.now() - t0;
    record(entry);
    if (!res.headersSent) {
      sendError(res, entry.status, 'api_error', e.name === 'AbortError' ? 'upstream timeout' : e.message);
    } else {
      res.end();
    }
  } finally {
    clearTimeout(timer);
    res.off('close', onClose);
  }
}

function estimateTokens(body) {
  const text = JSON.stringify({ system: body.system ?? null, messages: body.messages ?? [] });
  return Math.max(1, Math.ceil(text.length / 3.6));
}

// ------------------------------------------------------------------- server

async function handleRequest(req, res) {
  const url = new URL(req.url, `http://${HOST}:${PORT}`);
  const path = url.pathname;

  try {
    if (req.method === 'GET' && (path === '/' || path === '/health')) {
      return sendJson(res, 200, {
        ok: true,
        name: 'qclaude-gateway',
        provider: CFG.provider,
        providerName: CFG.displayName,
        upstream: CFG.upstream,
        uptimeSec: Math.round((Date.now() - STARTED) / 1000),
        requests: stats.requests,
        errors: stats.errors,
        currency: CUR,
        spentToday: Number(spentToday.toFixed(4)),
        isPeak: USES_PEAK ? isPeak() : false,
        keyConfigured: Boolean(process.env[CFG.auth.env]),
        routes: CFG.models,
        publicModels: CFG.publicModels,
      });
    }

    if (req.method === 'GET' && path === '/v1/models') {
      // Claude Desktop's custom-3p sign-in validates the key against this
      // endpoint and drops ids it does not recognise as Anthropic models.
      const ids = CFG.publicModels || Object.values(CFG.models);
      const data = ids.map((id) => ({
        type: 'model',
        id,
        display_name: id,
        created_at: '2026-01-01T00:00:00Z',
        ...(id.includes('[1m]') ? { supports1m: true, context_window: 1000000 } : {}),
      }));
      return sendJson(res, 200, {
        data,
        has_more: false,
        first_id: data[0]?.id ?? null,
        last_id: data[data.length - 1]?.id ?? null,
      });
    }

    // Not every provider has count_tokens; Claude Code uses it for the meter.
    if (req.method === 'POST' && /\/v1\/messages\/count_tokens$/.test(path)) {
      const raw = await readBody(req);
      let body = {};
      try { body = JSON.parse(raw.toString('utf8')); } catch { /* estimate empty */ }
      const input = estimateTokens(body);
      record({ route: 'count', status: 200, ms: 0, in: input, out: 0, stream: false, approx: true });
      return sendJson(res, 200, { input_tokens: input });
    }

    if (req.method === 'POST' && /\/v1\/messages$/.test(path)) {
      return await handleMessages(req, res);
    }

    record({ route: '404', status: 404, ms: 0, in: 0, out: 0, stream: false, method: req.method, path });
    return sendError(res, 404, 'not_found_error', `no route for ${req.method} ${path}`);
  } catch (e) {
    console.error('unhandled:', e);
    if (!res.headersSent) sendError(res, 500, 'api_error', e.message);
    else res.end();
  }
}

const server = http.createServer((req, res) => { void handleRequest(req, res); });

server.requestTimeout = 0;
server.headersTimeout = 0;
server.listen(PORT, HOST, () => {
  const actual = server.address()?.port ?? PORT;
  try { mkdirSync(dirname(PID_FILE), { recursive: true }); writeFileSync(PID_FILE, String(process.pid)); } catch { /* non-fatal */ }
  console.log('QClaude gateway  http://%s:%d', HOST, actual);
  console.log('provider %s (%s)', CFG.provider, CFG.displayName);
  console.log('upstream %s', CFG.upstream);
  console.log('routes   main=%s  heavy=%s  cheap=%s', CFG.models.main, CFG.models.heavy, CFG.models.cheap);
  console.log('spent    %s %s today  (%s)', CUR, spentToday.toFixed(4), USES_PEAK && isPeak() ? 'peak rates' : 'flat rates');
  console.log('log      %s', LOG);
  if (CFG.auth.mode === 'gateway' && !process.env[CFG.auth.env]) {
    console.log('WARNING  %s is not set — every request will fail with 502', CFG.auth.env);
  }
});

// Optional TLS listener for the Desktop MITM: api.anthropic.com -> 127.0.0.1:443.
// Windows uses a PFX; macOS/Linux use PEM key+cert.
const TLS_OPTS = process.env.GATEWAY_TLS_CERT && process.env.GATEWAY_TLS_KEY
  ? { cert: readFileSync(process.env.GATEWAY_TLS_CERT), key: readFileSync(process.env.GATEWAY_TLS_KEY) }
  : process.env.GATEWAY_TLS_PFX
    ? { pfx: readFileSync(process.env.GATEWAY_TLS_PFX), passphrase: process.env.GATEWAY_TLS_PASSPHRASE || '' }
    : null;

if (TLS_OPTS) {
  try {
    const tlsServer = https.createServer(TLS_OPTS, (req, res) => { void handleRequest(req, res); });
    tlsServer.requestTimeout = 0;
    tlsServer.headersTimeout = 0;
    tlsServer.on('tlsClientError', (e) => console.error('TLS client error:', e.message));
    tlsServer.listen(TLS_PORT, '127.0.0.1', () => {
      console.log('TLS      https://api.anthropic.com:%d', TLS_PORT);
    });
  } catch (e) {
    console.error('TLS listener failed:', e.message);
  }
}

function cleanup() {
  try { if (existsSync(PID_FILE) && readFileSync(PID_FILE, 'utf8').trim() === String(process.pid)) unlinkSync(PID_FILE); } catch { /* ignore */ }
}

for (const sig of ['SIGINT', 'SIGTERM']) {
  process.on(sig, () => {
    console.log('\nstopping, %d requests served', stats.requests);
    cleanup();
    server.close(() => process.exit(0));
    setTimeout(() => process.exit(0), 1500).unref();
  });
}
process.on('exit', cleanup);
