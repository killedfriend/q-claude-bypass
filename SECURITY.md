# Security policy

> **Educational, non-commercial project.** It is provided “as is”, without
> warranty. Do not deploy it as a production service.

## Reporting

Open a private security advisory in the GitHub repository, or contact the
maintainers through the repository profile. Do not open a public issue for an
active vulnerability.

Include:

- affected version or commit;
- a minimal reproduction;
- impact;
- whether a provider key, prompt or file could be exposed.

Do not include real API keys, cookies, prompts, customer data or personal
paths. Redact logs before sending them.

## Threat model

The gateway is designed for a single-user desktop:

- it binds to `127.0.0.1` by default;
- in `auth.mode: gateway` it ignores the client credential and uses the
  environment key;
- any local process that can reach the port can use the gateway and spend
  credits;
- logs contain metadata (models, tokens, tool names, errors);
- `GATEWAY_DUMP=1` writes full prompts and file data to
  `gateway/logs/last-request.json`.

Do not expose the port to a network, do not run it on a shared machine without
additional authentication, and do not enable dumps on sensitive data.

## Secrets

- Never commit `.env`, provider files with keys, `.pfx` files or logs.
- API keys are stored in user environment variables by the installer.
- If a key leaks, revoke it in the provider console and replace the user
  variable.
- The MITM helper creates a local CA and a certificate private key. Treat the
  PFX as a secret and remove it with `desktop/mitm/teardown-mitm.ps1`.

## macOS MITM

The macOS installer can configure the same interception with OpenSSL, the
System keychain and `pfctl`:

- local CA `CN=QClaude Local CA` and a leaf certificate for
  `api.anthropic.com`;
- `/etc/hosts` entry `127.0.0.1 api.anthropic.com`;
- `/etc/pf.anchors/com.qclaude` plus references in `/etc/pf.conf`;
- pf redirect `443 → 8443` and a root LaunchDaemon `com.qclaude.pf` to restore
  it at boot;
- gateway TLS listener on `127.0.0.1:8443` running as the desktop user.

This modifies machine-wide network rules and the System keychain. Use
`--no-mitm` to skip it, and `macos/uninstall.sh` to remove it. The macOS flow is
an MVP and has not been validated in a live Claude Desktop GUI.

## Automatic MITM

The Windows installer enables a local MITM for Claude Desktop by default:

- it creates and trusts `CN=QClaude Local CA` in the machine Trusted Root store;
- it issues a certificate for `api.anthropic.com`;
- it changes the machine `hosts` file to `127.0.0.1 api.anthropic.com`;
- it stores a PFX with a known local passphrase in the install directory;
- the gateway listens on `127.0.0.1:443` while it is running.

This is a machine-wide interception of `api.anthropic.com`. If the gateway is
stopped, applications that rely on that host cannot connect. Use `-NoMitm` to
skip it. Uninstall removes the hosts entry, certificates and PFX; if UAC is
cancelled, the install directory is kept so cleanup can be retried. Do not
combine this with a corporate TLS-inspection proxy or VPN without understanding
the certificate chain.

## Supported versions

Only the latest release is supported with security fixes. This is a
demonstration project; there is no SLA and no bug bounty.
