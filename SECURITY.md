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

## Supported versions

Only the latest release is supported with security fixes. This is a
demonstration project; there is no SLA and no bug bounty.
