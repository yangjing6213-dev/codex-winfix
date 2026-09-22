---
name: codex-winfix
description: Use when Windows Codex reports that terminal, file editing, or subagent tools are unavailable, especially with `code-mode host exited during handshake`, CWD forwarding, malformed model configuration, or app-server reload symptoms.
---

# Codex WinFix

Use this skill to recover the Windows Codex tool chain without weakening the
sandbox or exposing credentials. It targets the failure family where Desktop
starts Code Mode from a project directory but the CLI/host handshake fails.

## Recovery order

1. **Inspect before changing anything.** Record OS, Codex CLI/Desktop versions,
   current directory, `config.toml`/`config.yaml` presence, Git status, and the
   exact error. Do not print API keys, tokens, cookies, or full private logs.
2. **Check configuration.** Confirm a valid TOML file, one active
   `model_provider`, the requested model, a readable local model catalog when
   the provider's `/v1/models` response is incompatible, `wire_api = "responses"`,
   `requires_openai_auth = true`, and `sandbox_mode = "workspace-write"`.
   Keep `agents.enabled = true` (or the equivalent valid `[agents]` table).
3. **Check the launch path.** If the error is CWD-dependent, use a small native
   Windows shim as `CODEX_CLI_PATH`. The shim must forward all arguments,
   launch the real `codex.exe`, set a stable user-profile working directory,
   preserve the exit code, and keep `CODEX_REAL_CLI_PATH` explicit.
4. **Back up before applying.** Copy `config.toml` with a timestamp. Make only
   the smallest required edits. Never switch to `danger-full-access`, disable
   the sandbox, guess an API key, or modify the registry as a first response.
5. **Reload and verify.** Fully restart Codex Desktop so app-server reloads the
   configuration. Then verify, in order: config parse, app-server initialize,
   one terminal command, one file create/edit/read/delete in the target test
   directory, and one real subagent call. A UI banner alone is not proof.
6. **Classify residual warnings.** `TERM=dumb`, an optional MCP server missing
   `CODEX_WINDOWS_REGISTERED_CORE`, or unavailable optional integrations are
   separate from the core terminal/file/subagent result. Report them without
   treating them as the root cause unless a verification actually fails.

## Minimal command

From this skill directory, run the script in diagnosis mode first:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Repair-CodexWinFix.ps1
```

Only apply changes after reviewing the diagnosis:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Repair-CodexWinFix.ps1 -Apply -ProjectPath "$HOME\Downloads\demo"
```

The script is intentionally conservative. It creates a backup, updates only the
root model/provider/catalog/sandbox/agent settings, refuses to overwrite an
existing shim source unless `-Force` is explicit, and never stores secret values
in output or repository files.

## Stop conditions

Stop and report `BLOCKED` when the config cannot be parsed, the real CLI path is
unknown, authentication is invalid, the remote provider is unavailable, or a
verification step fails. Do not claim the tools are fixed from a successful
config edit alone.
