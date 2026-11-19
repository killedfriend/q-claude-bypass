# Launcher: Claude Code with the selected provider as the model backend.
# Interactive:  .\qclaude.ps1
# Headless:     .\qclaude.ps1 -p "explain this repo" --output-format text
#
# No param() block on purpose: with one, PowerShell swallows "-p <prompt>"
# as a script parameter. Without it, every argument lands in $args verbatim.

. (Join-Path $PSScriptRoot 'env.ps1')

if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
    throw 'claude not found on PATH. Install: npm install -g @anthropic-ai/claude-code'
}

# Continue, not Stop: claude writes warnings to stderr, and PowerShell 5.1
# turns that into a terminating NativeCommandError. Exit code still propagates.
$ErrorActionPreference = 'Continue'
& claude @args
if ($null -ne $LASTEXITCODE) { exit $LASTEXITCODE }
