function blockTextLen(content) {
  if (typeof content === 'string') return content.length;
  if (!Array.isArray(content)) return 0;
  let n = 0;
  for (const b of content) if (b && typeof b.text === 'string') n += b.text.length;
  return n;
}

/**
 * Elide the text of old tool results so long sessions stop resending hundreds
 * of thousands of tokens every turn. Messages and tool_use/tool_result pairs
 * are never dropped, so the transcript stays valid. The elision is
 * deterministic, which keeps the provider prefix cache warm.
 */
export function pruneContext(cfg, body, env = process.env) {
  const c = cfg?.context;
  if (!c || !c.enabled) return { elided: 0, savedChars: 0 };

  const maxChars = Number(env.GATEWAY_MAX_CHARS || c.maxChars || 500000);
  let size = JSON.stringify(body).length;
  if (size <= maxChars) return { elided: 0, savedChars: 0 };

  const results = [];
  for (const msg of body.messages || []) {
    if (!Array.isArray(msg.content)) continue;
    for (const b of msg.content) if (b && b.type === 'tool_result') results.push(b);
  }

  const keep = c.keepRecentToolResults ?? 6;
  const candidates = results.slice(0, Math.max(0, results.length - keep));
  let elided = 0;
  let savedChars = 0;

  for (const b of candidates) {
    const len = blockTextLen(b.content);
    if (len < (c.elideAboveChars ?? 4000)) continue;
    b.content = [{ type: 'text', text: `[tool output elided by gateway: ${len} chars]` }];
    elided++;
    savedChars += len;
    if (size - savedChars <= maxChars) break;
  }
  return { elided, savedChars };
}
