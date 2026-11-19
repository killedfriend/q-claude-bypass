#Requires -RunAsAdministrator
# Creates a local CA, issues a cert for api.anthropic.com, trusts the CA,
# and points api.anthropic.com at localhost.
$ErrorActionPreference = 'Stop'
$log = Join-Path $PSScriptRoot 'setup.log'
Start-Transcript -Path $log -Force | Out-Null

try {
    $here = $PSScriptRoot
    $pfx = Join-Path $here 'api.anthropic.com.pfx'
    $pfxPass = 'qclaude'

    Write-Host '1/3 CA' -ForegroundColor Cyan
    $ca = Get-ChildItem Cert:\LocalMachine\My |
        Where-Object { $_.Subject -eq 'CN=QClaude Local CA' } |
        Select-Object -First 1

    if (-not $ca) {
        $ca = New-SelfSignedCertificate `
            -Subject 'CN=QClaude Local CA' `
            -CertStoreLocation Cert:\LocalMachine\My `
            -KeyUsage CertSign, CRLSign, DigitalSignature `
            -TextExtension @('2.5.29.19={text}CA=true&pathlength=1') `
            -NotAfter (Get-Date).AddYears(5) `
            -KeyExportPolicy Exportable
        Write-Host "  created CA $($ca.Thumbprint)"
    } else {
        Write-Host "  reusing CA $($ca.Thumbprint)"
    }

    $trusted = Get-ChildItem Cert:\LocalMachine\Root |
        Where-Object { $_.Thumbprint -eq $ca.Thumbprint }
    if (-not $trusted) {
        $tmp = Join-Path $here 'ca.cer'
        Export-Certificate -Cert $ca -FilePath $tmp -Type CERT | Out-Null
        Import-Certificate -FilePath $tmp -CertStoreLocation Cert:\LocalMachine\Root | Out-Null
        Remove-Item $tmp -Force
        Write-Host '  imported into Trusted Root'
    } else {
        Write-Host '  already trusted'
    }

    Write-Host '2/3 leaf certificate' -ForegroundColor Cyan
    Get-ChildItem Cert:\LocalMachine\My |
        Where-Object { $_.Subject -eq 'CN=api.anthropic.com' } |
        ForEach-Object { Remove-Item -Path $_.PSPath -Force }

    $leaf = New-SelfSignedCertificate `
        -Subject 'CN=api.anthropic.com' `
        -DnsName 'api.anthropic.com', '*.anthropic.com' `
        -Signer $ca `
        -CertStoreLocation Cert:\LocalMachine\My `
        -TextExtension @('2.5.29.19={text}CA=false', '2.5.29.37={text}1.3.6.1.5.5.7.3.1') `
        -NotAfter (Get-Date).AddYears(2) `
        -KeyExportPolicy Exportable

    $pwd = ConvertTo-SecureString -String $pfxPass -AsPlainText -Force
    Export-PfxCertificate -Cert $leaf -FilePath $pfx -Password $pwd | Out-Null
    Write-Host "  leaf $($leaf.Thumbprint)"
    Write-Host "  pfx  $pfx (passphrase: $pfxPass)"

    Write-Host '3/3 hosts file' -ForegroundColor Cyan
    $hosts = "$env:SystemRoot\System32\drivers\etc\hosts"
    $lines = Get-Content $hosts | Where-Object { $_ -notmatch 'qclaude-mitm' -and $_ -notmatch '^\s*127\.0\.0\.1\s+api\.anthropic\.com\s*$' }
    $lines += ''
    $lines += '# qclaude-mitm'
    $lines += '127.0.0.1 api.anthropic.com'
    Set-Content -Path $hosts -Value $lines -Encoding ASCII
    Write-Host '  hosts updated'

    Write-Host ''
    Write-Host "DONE. Start the gateway with GATEWAY_TLS_PFX=$pfx" -ForegroundColor Green
}
catch {
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace
}
finally {
    Stop-Transcript | Out-Null
}
