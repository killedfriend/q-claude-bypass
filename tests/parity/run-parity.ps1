# Parity harness: proves the Claude Code features we rely on still work on DeepSeek.
# Run after every `claude update`:  .\parity\run-parity.ps1
# Exit code 0 = all checks passed, 1 = something broke.

$ErrorActionPreference = 'Continue'
$root = $PSScriptRoot
$repo = Split-Path (Split-Path $root -Parent) -Parent
$q = Join-Path $repo 'qclaude-gw.ps1'

if (-not (Test-Path $q)) { throw "launcher not found: $q" }

Set-Location $root
Remove-Item hook-fired.txt, hook-input.jsonl, note.txt, note2.txt -ErrorAction SilentlyContinue
Set-Content -Path hello.txt -Value 'alpha beta gamma' -Encoding ASCII

function Invoke-Claude {
    param([string]$Prompt, [string]$Tools, [string[]]$Extra, [int]$MaxTurns = 6)
    $a = @('-p', $Prompt, '--output-format', 'json', '--max-turns', "$MaxTurns")
    if ($Tools) { $a += @('--allowedTools', $Tools) }
    if ($Extra) { $a += $Extra }
    $raw = (& $q @a 2>&1 | Out-String)
    $i = $raw.IndexOf('{')
    if ($i -lt 0) { return [pscustomobject]@{ Error = $true; Result = "NO JSON: $($raw -replace '\s+',' ')" } }
    $j = $raw.Substring($i) | ConvertFrom-Json
    return [pscustomobject]@{ Error = [bool]$j.is_error; Result = [string]$j.result }
}

$checks = @()

# 1. MCP server tool
$r = Invoke-Claude "Use the mcp__audit__echo tool with text 'ping' and reply with exactly what it returns." 'mcp__audit__echo,Read'
$checks += [pscustomobject]@{ Feature = 'MCP tool'; Pass = (-not $r.Error -and $r.Result -match 'echo:ping'); Detail = $r.Result }

# 2. Project skill
$r = Invoke-Claude "Use the hello skill, follow its instructions, and reply with what it tells you." 'Skill,Read'
$checks += [pscustomobject]@{ Feature = 'Skill'; Pass = (-not $r.Error -and $r.Result -match 'SKILL-OK'); Detail = $r.Result }

# 3. Edit tool
$r = Invoke-Claude "Read hello.txt, replace the word alpha with omega, then reply DONE." 'Read,Edit'
$body = if (Test-Path hello.txt) { Get-Content hello.txt -Raw } else { '' }
$checks += [pscustomobject]@{ Feature = 'Edit'; Pass = ($body -match 'omega'); Detail = $body.Trim() }

# 4. Write tool + PreToolUse hook
$r = Invoke-Claude "Write a file named note.txt containing exactly: hi" 'Write'
$note = if (Test-Path note.txt) { (Get-Content note.txt -Raw).Trim() } else { '' }
$checks += [pscustomobject]@{ Feature = 'Write'; Pass = ($note -eq 'hi'); Detail = $note }
$checks += [pscustomobject]@{ Feature = 'Hook PreToolUse'; Pass = (Test-Path hook-fired.txt); Detail = $(if (Test-Path hook-fired.txt) { 'fired' } else { 'not fired' }) }

# 5. Custom subagent
$r = Invoke-Claude "Use the echoer subagent and reply with exactly what it returned." 'Agent,Task,Read'
$checks += [pscustomobject]@{ Feature = 'Subagent'; Pass = (-not $r.Error -and $r.Result -match 'BANANA'); Detail = $r.Result }

# 6. Session resume
$null = Invoke-Claude "Remember the number 41. Reply OK." $null
$r = Invoke-Claude "What number did I ask you to remember? Reply with digits only." $null @('--continue')
$checks += [pscustomobject]@{ Feature = '--continue'; Pass = (-not $r.Error -and $r.Result -match '41'); Detail = $r.Result }

# 7. Plan mode must not write files
$r = Invoke-Claude "Propose a plan for adding a README.md here. Do not create any files." $null @('--permission-mode','plan') 15
$checks += [pscustomobject]@{ Feature = 'Plan mode'; Pass = (-not $r.Error -and -not (Test-Path README.md) -and $r.Result.Length -gt 0); Detail = 'no files created' }

# Report
$checks | Format-Table Feature, Pass, Detail -AutoSize | Out-String -Width 200 | Write-Host

$failed = @($checks | Where-Object { -not $_.Pass })
if ($failed.Count -gt 0) {
    Write-Host "$($failed.Count) of $($checks.Count) checks FAILED" -ForegroundColor Red
    exit 1
}
Write-Host "all $($checks.Count) checks passed" -ForegroundColor Green
exit 0
