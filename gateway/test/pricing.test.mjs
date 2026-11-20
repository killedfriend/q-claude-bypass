import test from 'node:test';
import assert from 'node:assert/strict';
import { costOf, currencySymbol, isPeak, priceKey, webCostOf } from '../lib/pricing.mjs';

const cfg = {
  pricing: {
    'flat-model': { input: 2, cacheRead: 0.2, output: 8 },
    'deepseek-flash': {
      peak: { input: 2, cacheRead: 0.04, output: 8 },
      offPeak: { input: 1, cacheRead: 0.02, output: 4 },
    },
  },
  webPricing: { search: 5, fetch: 5, unit: 1000 },
};

test('model suffixes are removed for price lookup', () => {
  assert.equal(priceKey('deepseek-flash[1m]'), 'deepseek-flash');
  assert.equal(priceKey('anthropic/claude-sonnet-4.5'), 'anthropic/claude-sonnet-4.5');
});

test('flat pricing is calculated per million tokens', () => {
  const cost = costOf(cfg, 'flat-model', {
    input_tokens: 1000,
    cache_read_input_tokens: 2000,
    output_tokens: 500,
  });
  assert.equal(cost, 0.0064);
});

test('upstream cost wins when the provider reports it', () => {
  const cost = costOf(cfg, 'flat-model', { input_tokens: 1e6, output_tokens: 1e6 }, 0.1234567);
  assert.equal(cost, 0.123457);
});

test('missing pricing returns null, not zero', () => {
  assert.equal(costOf(cfg, 'unknown-model', { input_tokens: 10, output_tokens: 10 }), null);
});

test('web search cost is per call', () => {
  assert.equal(webCostOf(cfg, { webSearch: 2, webFetch: 1 }), 0.015);
  assert.equal(webCostOf(cfg, {}), 0);
});

test('DeepSeek peak hours are Beijing business hours', () => {
  // Monday 2026-11-16 10:00 Beijing = 02:00 UTC
  assert.equal(isPeak(new Date('2026-11-16T02:00:00Z')), true);
  // Monday 12:30 Beijing = 04:30 UTC
  assert.equal(isPeak(new Date('2026-11-16T04:30:00Z')), false);
  // Sunday
  assert.equal(isPeak(new Date('2026-11-15T02:00:00Z')), false);
});

test('currency symbols', () => {
  assert.equal(currencySymbol('CNY'), '\u00a5');
  assert.equal(currencySymbol('RUB'), '\u20bd');
  assert.equal(currencySymbol('USD'), '$');
  assert.equal(currencySymbol('EUR'), '\u20ac');
});
