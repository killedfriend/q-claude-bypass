import { priceKey } from './pricing.mjs';

export function isVisionModel(cfg, model) {
  const key = priceKey(model);
  return (cfg.vision || []).some((m) => priceKey(m) === key);
}

/**
 * Choose the upstream model and apply the cheap-call profile in place.
 * The requested model name is what Claude Code sent (public Claude name);
 * the returned model is what the provider will actually serve.
 */
export function pickRoute(cfg, body) {
  const requested = String(body.model || '');
  const hasTools = Array.isArray(body.tools) && body.tools.length > 0;
  const hasImages = (body.messages || []).some(
    (m) => Array.isArray(m.content) && m.content.some((b) => b && b.type === 'image')
  );

  let name = 'main';
  if (cfg.routing?.opusToHeavy && /opus/i.test(requested)) name = 'heavy';
  else if (cfg.routing?.haikuToCheap && /haiku/i.test(requested)) name = 'cheap';
  else if (cfg.routing?.cheapWithoutTools && !hasTools) name = 'cheap';

  let model = cfg.models[name];
  const applied = [];

  // Some models silently drop image blocks: no error, no image tokens, just a
  // confident hallucination. Never let an image reach a non-vision model when
  // a vision-capable route exists.
  if (hasImages && !isVisionModel(cfg, model)) {
    const fallback = cfg.models.main;
    if (isVisionModel(cfg, fallback)) {
      applied.push(`images: ${name}->main`);
      name = 'main';
      model = fallback;
    } else {
      applied.push('images: no vision-capable model configured');
    }
  }

  if (name === 'cheap' && cfg.cheapProfile) {
    const p = cfg.cheapProfile;
    if (p.effort) {
      body.output_config = { ...(body.output_config || {}), effort: p.effort };
      applied.push(`effort=${p.effort}`);
    }
    if (p.thinking) {
      body.thinking = { type: p.thinking };
      applied.push(`thinking=${p.thinking}`);
    }
    if (p.maxTokens && !body.max_tokens) body.max_tokens = p.maxTokens;
  }

  return { name, model, requested, hasTools, hasImages, applied };
}
