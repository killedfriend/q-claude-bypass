# Contributing

> Educational, non-commercial project. Contributions that help the
> demonstration and documentation are welcome. Do not add features whose main
> purpose is to bypass provider billing, authentication or terms.

## Scope

Good contributions:

- a new provider preset with a documented Anthropic-compatible endpoint;
- documentation fixes in Russian, English or Chinese;
- tests for routing, pricing, context pruning or the HTTP layer;
- installer robustness on Windows 10/11;
- bug fixes with a minimal reproduction.

Out of scope:

- cracking, credential sharing, or bypassing paid access;
- bundling API keys or cookies;
- modifying Claude Code binaries;
- claims of official affiliation.

## Development

Requirements: Node.js 22+ for tests, PowerShell 5.1+ for the Windows scripts.

```powershell
npm test
node --check gateway\server.mjs
```

Parse all PowerShell files:

```powershell
Get-ChildItem -Recurse -Filter *.ps1 | ForEach-Object {
  $errors = $null
  [System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$null, [ref]$errors) | Out-Null
  if ($errors.Count) { throw "$($_.FullName): $($errors[0].Message)" }
}
```

Validate JSON:

```powershell
Get-ChildItem -Recurse -Filter *.json | ForEach-Object {
  Get-Content $_.FullName -Raw | ConvertFrom-Json | Out-Null
}
```

Build a release locally:

```powershell
.\scripts\build-release.ps1 -Version 1.0.2 -Repo killedfriend/q-claude-bypass
```

## Style

- Gateway and scripts: no external runtime dependencies.
- Keep `gateway/server.mjs` Node 22 built-ins only.
- PowerShell scripts must be ASCII-only messages so Windows PowerShell 5.1
  reads them correctly.
- Markdown: keep the three language versions in sync when behavior changes.
- Do not reformat unrelated files.

## Pull requests

1. Describe the problem and the behavior change.
2. Include the provider/model if relevant, without keys.
3. Run `npm test`.
4. Update `CHANGELOG.md` for user-visible changes.
5. Update the relevant docs in all three languages, or state which ones are
   pending.

## Security

Read [SECURITY.md](SECURITY.md). Do not put secrets in issues, logs or test
fixtures.
