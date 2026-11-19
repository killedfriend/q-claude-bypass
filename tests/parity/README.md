# Parity harness

This optional harness answers one question: after a Claude Code update, do the
features this project depends on still work with the selected provider?

It makes several real model calls and costs tokens. It writes temporary files
in this directory, including hook input and generated notes.

```powershell
.\tests\parity\run-parity.ps1
```

The script starts Claude Code through `qclaude-gw.ps1`, so the gateway must be
configured for the provider you want to test.

Checks:

- MCP tool call;
- project skill;
- Edit and Write tools;
- `PreToolUse` hook;
- custom subagent;
- `--continue`;
- plan mode does not write files.

This is an educational project. Do not run it in a repository with sensitive
data: the model receives file contents and prompts.
