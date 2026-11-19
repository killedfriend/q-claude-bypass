#!/usr/bin/env node
/**
 * Spend report from gateway/logs/requests.jsonl.
 *   node gateway/report.mjs           last 14 days
 *   node gateway/report.mjs 30        last 30 days
 */
import { existsSync, readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { currencySymbol } from './lib/pricing.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const LOG = join(HERE, 'logs', 'requests.jsonl');
const days = Number(process.argv[2] || 14);

if (!existsSync(LOG)) {
  console.log('no log yet:', LOG);
  process.exit(0);
}

const rows = [];
for (const line of readFileSync(LOG, 'utf8').split('\n')) {
  if (!line.trim()) continue;
  try { rows.push(JSON.parse(line)); } catch { /* ignore torn line */ }
}

const cutoff = new Date(Date.now() - days * 86400e3).toISOString().slice(0, 10);
const byDay = new Map();
const byModel = new Map();
const byProvider = new Map();
const currencies = new Set();

for (const r of rows) {
  if ((r.day || '') < cutoff) continue;
  const cur = r.currency || 'USD';
  currencies.add(cur);
  const d = byDay.get(r.day) || { req: 0, inp: 0, cache: 0, out: 0, cost: 0, err: 0, cur };
  d.req++;
  d.inp += r.in || 0;
  d.cache += r.cacheRead || 0;
  d.out += r.out || 0;
  d.cost += r.cost || 0;
  if ((r.status || 0) >= 400) d.err++;
  byDay.set(r.day, d);

  const key = r.upModel || r.route || '?';
  const m = byModel.get(key) || { req: 0, inp: 0, cache: 0, out: 0, cost: 0, cur };
  m.req++;
  m.inp += r.in || 0;
  m.cache += r.cacheRead || 0;
  m.out += r.out || 0;
  m.cost += r.cost || 0;
  byModel.set(key, m);

  const p = byProvider.get(r.provider || '?') || { req: 0, cost: 0, cur };
  p.req++;
  p.cost += r.cost || 0;
  byProvider.set(r.provider || '?', p);
}

const k = (n) => (n >= 1000 ? `${(n / 1000).toFixed(1)}k` : String(n));
const money = (n, cur) => (n > 0 ? `${currencySymbol(cur)}${n.toFixed(4)}` : '-');

console.log(`\nBy day (last ${days}, ${[...currencies].join('/') || 'USD'})`);
console.log('date        req   input    cache   output       cost  err  cur');
for (const [day, d] of [...byDay].sort()) {
  console.log(
    `${day}  ${String(d.req).padStart(4)}  ${k(d.inp).padStart(7)}  ${k(d.cache).padStart(7)}  ${k(d.out).padStart(7)}  ${money(d.cost, d.cur).padStart(9)}  ${String(d.err).padStart(3)}  ${d.cur}`
  );
}

console.log('\nBy model');
console.log('model                     req   input    cache   output       cost');
for (const [model, m] of [...byModel].sort((a, b) => b[1].cost - a[1].cost)) {
  console.log(
    `${model.padEnd(24)}  ${String(m.req).padStart(4)}  ${k(m.inp).padStart(7)}  ${k(m.cache).padStart(7)}  ${k(m.out).padStart(7)}  ${money(m.cost, m.cur).padStart(9)}`
  );
}

console.log('\nBy provider');
for (const [provider, p] of [...byProvider].sort((a, b) => b[1].cost - a[1].cost)) {
  console.log(`${provider.padEnd(16)}  ${String(p.req).padStart(4)}  ${money(p.cost, p.cur).padStart(9)}`);
}

const totals = [...byDay.values()];
const total = totals.reduce((s, d) => s + d.cost, 0);
const cacheRead = totals.reduce((s, d) => s + d.cache, 0);
const allInput = totals.reduce((s, d) => s + d.inp + d.cache, 0);
console.log(`\ntotal ${money(total, [...currencies][0] || 'USD')}   cache hit share ${((cacheRead / Math.max(1, allInput)) * 100).toFixed(1)}%`);
if (total === 0) console.log('cost is 0 because pricing for this provider is not filled in');
if (currencies.size > 1) console.log('warning: log contains multiple currencies; totals are additive only for display');
