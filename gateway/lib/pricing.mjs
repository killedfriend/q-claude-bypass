/** Pricing helpers shared by the gateway and the spend report. */

export function dayKey(d = new Date()) {
  const p = (n) => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}`;
}

export function priceKey(model = '') {
  return String(model).replace(/\[.*\]$/, '');
}

// DeepSeek peak hours: Mon-Fri 09:00-12:00 and 14:00-18:00 Beijing (UTC+8).
// Chinese public holidays are not modelled; they bill as off-peak.
export function isPeak(now = new Date()) {
  const bj = new Date(now.getTime() + 8 * 3600e3);
  const dow = bj.getUTCDay();
  if (dow === 0 || dow === 6) return false;
  const h = bj.getUTCHours() + bj.getUTCMinutes() / 60;
  return (h >= 9 && h < 12) || (h >= 14 && h < 18);
}

export function currencySymbol(currency = 'USD') {
  if (currency === 'CNY' || currency === 'RMB') return '\u00a5';
  if (currency === 'EUR') return '\u20ac';
  return '$';
}

function roundCost(value) {
  return Number(Number(value).toFixed(6));
}

/**
 * Prefer the exact cost reported by the upstream (OpenRouter returns
 * usage.cost). Otherwise calculate from the provider price table.
 */
export function costOf(cfg, model, usage, upstreamCost) {
  if (Number.isFinite(upstreamCost) && upstreamCost >= 0) return roundCost(upstreamCost);

  const table = cfg?.pricing || {};
  const key = priceKey(model);
  const entry = table[key] || table[model];
  if (!entry || !usage) return null;

  const rate = entry.peak && entry.offPeak
    ? (isPeak() ? entry.peak : entry.offPeak)
    : entry;

  if (!rate.input && !rate.cacheRead && !rate.output) return null;

  const amount =
    ((usage.input_tokens || 0) * (rate.input || 0) +
      (usage.cache_read_input_tokens || 0) * (rate.cacheRead || 0) +
      (usage.output_tokens || 0) * (rate.output || 0)) / 1e6;

  return roundCost(amount);
}

export function webCostOf(cfg, { webSearch = 0, webFetch = 0 } = {}) {
  const p = cfg?.webPricing;
  if (!p) return 0;
  const amount = (webSearch * (p.search || 0) + webFetch * (p.fetch || 0)) / (p.unit || 1000);
  return amount > 0 ? roundCost(amount) : 0;
}
