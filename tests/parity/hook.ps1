$raw = [Console]::In.ReadToEnd()
if ($raw) {
    Add-Content -Path (Join-Path $PSScriptRoot 'hook-input.jsonl') -Value $raw -Encoding UTF8
}
Add-Content -Path (Join-Path $PSScriptRoot 'hook-fired.txt') -Value ("fired " + (Get-Date -Format o)) -Encoding UTF8
