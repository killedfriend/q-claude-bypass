# Troubleshooting

> **Educational, non-commercial project.** Diagnostics can expose prompts,
> file contents and API metadata. Review logs before sharing them. Use at your
> own risk.

## First five checks

```powershell
# 1. Is the gateway alive?
Invoke-RestMethod http://127.0.0.1:8788/health

# 2. Which provider and routes are active?
(Invoke-RestMethod http://127.0.0.1:8788/health) | Format-List

# 3. What was the last request?
Get-Content gateway\logs\requests.jsonl -Tail 1

# 4. What was the last status and error field?
(Get-Content gateway\logs\requests.jsonl -Tail 1 | ConvertFrom-Json) | Select-Object status, err

# 5. Does the provider key work directly?
.\test-connection.ps1
```

If `/health` fails, the gateway is not running. Start it:

```powershell
.\gateway\start.ps1 -Background
```

or run it in the foreground to see errors:

```powershell
.\gateway\start.ps1
```

## 401 / 403 / invalid API key

Symptoms: `authentication_error`, `invalid_api_key`, `AccessDenied`, HTTP 401
or 403 in the log.

Causes and fixes:

1. **Key not in the process environment.** Open a new terminal after the
   installer saved the user variable, or set it explicitly:
   ```powershell
   $env:DASHSCOPE_API_KEY = 'sk-...'
   ```
2. **Wrong key for the endpoint.** Alibaba pay-as-you-go, Coding Plan and Token
   Plan keys are not interchangeable. Match key type and base URL.
3. **Wrong auth header.** DeepSeek and Alibaba use
   `Authorization: Bearer`; Tencent's gateway preset uses `x-api-key`. Check
   `auth.header` and `auth.scheme` in the provider file.
4. **Key disabled or out of credit.** Check the provider console.
5. **Key contains spaces or quotes.** Re-enter it with the hidden prompt; do not
   paste quotes into the variable.

Test without Claude Code:

```powershell
.\test-connection.ps1
```

## `claude-code:unrecognized_model`

Claude Code validates model names in some versions. The client-facing name must
look like a Claude model.

- Use the gateway: it exposes `claude-sonnet-4-5[1m]`, `claude-opus-4-5`,
  `claude-haiku-4-5` and maps them upstream.
- In direct mode, use the `client.direct` names from the provider preset. For
  DeepSeek these are Claude-like because DeepSeek maps them server-side.
- For Tencent/Alibaba/OpenRouter direct mode, if the client rejects a native
  model name, switch to gateway mode (`qclaude-gw.ps1`).

## `API Error: Invalid URL`

`ANTHROPIC_BASE_URL` must include a scheme:

```text
https://api.deepseek.com/anthropic
```

not `api.deepseek.com/anthropic`. The same applies to every provider.

## 404 / no route

- `POST /v1/messages` must be the final path. The gateway appends
  `/v1/messages` to `upstream`; do not include it in `upstream`.
- OpenRouter base URL is `https://openrouter.ai/api`, not
  `https://openrouter.ai/api/v1`.
- Alibaba base URL ends with `/apps/anthropic`, without an extra `/v1`.
- Check `/health` → `upstream` to see the resolved URL.

## 429 / rate limit

- The provider is throttling. Wait and retry.
- The gateway already retries 429 with backoff (`limits.maxRetries`).
- Reduce background calls: `CLAUDE_CODE_EFFORT_LEVEL`, smaller context, fewer
  parallel subagents.
- A gateway daily budget also returns 429:
  ```json
  { "limits": { "dailyBudget": 0 } }
  ```

## 5xx / timeout

- The gateway retries 408/429/500/502/503/504.
- `limits.timeoutMs` defaults to 10 minutes. Very long agent turns can exceed
  it; increase deliberately.
- Check provider status and the `err` field in the log.
- If the upstream is overloaded, switch provider or model.

## Streaming stops or tools do not run

- Some providers do not support every Anthropic SSE event. Check the raw
  response and the provider compatibility table.
- Ensure `documents` is `native` only if the provider accepts Anthropic
  `document` blocks. Otherwise use `none` (attachments are replaced with a
  short placeholder).
- Tool use requires the model to support Anthropic-style `tool_use` blocks.
  This is provider-specific.
- Test with a simple request first:
  ```powershell
  claude -p "Reply with exactly OK" --output-format text
  ```

## Images

- DeepSeek `deepseek-v4-pro` silently ignores images. The gateway reroutes
  image requests to `deepseek-flash` when possible; look for
  `images: heavy->main` in `applied`.
- If no vision model is configured, the log says
  `images: no vision-capable model configured`. The request still goes through;
  the model may hallucinate.
- For Tencent/Alibaba, check whether the selected model supports image input.
- Verify with a screenshot that contains a known number and ask the model to
  read it.

## PDF and documents

- DeepSeek accepts PDFs only through the Files API. Inline base64 `document`
  blocks are uploaded by the gateway.
- Nested documents inside `tool_result` are lifted to the top level for
  DeepSeek; otherwise the model answers `NO-DOCUMENT`.
- Uploaded files are cached in `gateway/logs/files.json` by SHA-256.
- `documents: "none"` providers replace the attachment with a placeholder. The
  model cannot read the PDF.
- `documents: "native"` passes the block through (OpenRouter supports PDFs).
- Files API parsing is billed by DeepSeek; check the console.

## Claude Desktop

Claude Desktop is the hardest part. It often ignores:

- process environment variables;
- `C:\Program Files\ClaudeCode\managed-settings.json` (CLI path);
- `HKLM\SOFTWARE\Policies\ClaudeCode` (logs `[managedConfig] type: 'none'`).

Options, from least to most invasive:

1. **CC Switch** — third-party local router with a Desktop panel. It keeps its
   own gateway on `127.0.0.1:15721`.
2. **Experimental policy** — run the installer with `-ConfigureDesktop`, or:
   ```powershell
   .\desktop\apply-desktop-policy.ps1   # administrator
   ```
   Restart Desktop and check whether it respects the settings.
3. **MITM** — the most reliable:
   ```powershell
   .\desktop\mitm\setup-mitm.ps1        # administrator
   ```
   It creates a local CA, trusts it, issues a certificate for
   `api.anthropic.com`, edits `hosts`, and writes a PFX for the gateway TLS
   listener. Then start the gateway with `GATEWAY_TLS_PFX` set (the helper
   `gateway\gw-env.ps1` finds the PFX automatically).

Rollback:

```powershell
.\desktop\mitm\teardown-mitm.ps1      # administrator
.\desktop\revert-all.ps1              # policy and managed settings
```

Do not combine MITM with a VPN or corporate TLS inspection without
understanding the certificate chain.

## Port 8788 already in use

```powershell
Get-NetTCPConnection -LocalPort 8788 -State Listen
.\gateway\start.ps1 -Stop
```

Or change the port in `gateway/config.json` and in
`~/.claude/settings.json` (`ANTHROPIC_BASE_URL`).

The gateway writes `gateway/logs/gateway.pid`. `start.ps1 -Stop` uses it first,
then falls back to the listening port.

## Node.js and npm

- Claude Code needs Node.js 22+ (`node --version`).
- If `npm install -g` fails with `EACCES`/`EPERM`, the installer retries into
  `%LOCALAPPDATA%\QClaudeCode\npm` and adds it to PATH.
- If `claude` is still not found, open a new terminal or run:
  ```powershell
  $env:Path += ";$env:LOCALAPPDATA\QClaudeCode\npm"
  ```
- `npm.ps1` may be blocked by execution policy; use `npm.cmd`.
- The portable Node fallback lives in
  `%LOCALAPPDATA%\QClaudeCode\tools\node`.

## winget / Claude Desktop install

- `winget` comes from App Installer. Update it from the Microsoft Store.
- Package ID: `Anthropic.Claude`.
- If winget fails, install manually from <https://claude.ai/download> and rerun
  the installer with `-SkipClaudeDesktop`.
- The installer does not need administrator rights for the core gateway; some
  winget/MSI paths may prompt.

## UAC and `-ConfigureDesktop`

`-ConfigureDesktop` writes to `C:\Program Files` and `HKLM`, so it needs
administrator rights. The installer starts an elevated PowerShell and waits.
If you cancel UAC, the rest of the installation still succeeds; only the
Desktop policy is skipped.

## Execution policy

If `.\install.ps1` is blocked:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
```

Do not change the machine-wide execution policy just for this project.

## Gateway logs and dumps

```powershell
Get-Content gateway\logs\requests.jsonl -Tail 20
```

Start the gateway in the foreground to see startup and unhandled errors:

```powershell
.\gateway\start.ps1 -Stop
.\gateway\start.ps1
```

Enable the full request dump temporarily:

```powershell
$env:GATEWAY_DUMP = '1'
.\gateway\start.ps1
```

The dump contains prompts, tool output and possibly file data. Delete
`logs\last-request.json` when done and unset `GATEWAY_DUMP`.

## Reset

Soft reset (keep apps and keys):

```powershell
.\gateway\start.ps1 -Stop
Remove-Item "$env:LOCALAPPDATA\QClaudeCode\gateway\logs" -Recurse -Force
```

Full reset:

```powershell
.\uninstall.ps1
```

Reinstall with the original provider or a new one:

```powershell
.\install.ps1 -Provider openrouter
```

## Still stuck

Collect:

- `GET /health` output;
- the last 5 lines of `requests.jsonl`;
- the exact error text from Claude Code;
- provider, model ID and endpoint (never the key);
- Node.js, Claude Code and Windows versions.

Open an issue in the repository with the collected data. Redact keys, tokens,
prompts and personal paths.
