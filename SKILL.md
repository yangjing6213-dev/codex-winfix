---
name: codex-winfix
description: Use when Windows Codex or Codex Desktop reports unavailable terminal, file editing, or subagent tools, especially with code-mode host handshake failures, GPT-5.6+ model-only failures, CWD-dependent startup, mixed Codex installations, encrypted WindowsApps plugin-cache copies, or thread-not-found errors after an app-server reload.
---

# Codex WinFix

Use this skill to diagnose the Windows Codex tool chain while preserving the
workspace sandbox and active development sessions. The app-server is a shared
control plane: one Desktop process can own several projects and task shells.

## Non-negotiable safety rule

Never run Stop-Process against ChatGPT.exe, codex.exe, codex-cwd-shim.exe, or
codex-code-mode-host.exe from an active Codex task. Never overwrite a fixed shim
path while Desktop is running. Doing so can leave the UI showing "running"
while the old task handle is gone, producing thread not found and interrupting
unrelated projects.

Stage a new versioned shim and let the user perform one normal Desktop restart
when active projects are safe to pause.

## Recovery

1. **Collect evidence first.** Record OS, Desktop/CLI versions, project path,
   exact error, process paths and parent relationships, config.toml or
   config.yaml status, and the model/provider A/B result. Never print keys,
   tokens, cookies, private logs, or full environment dumps.
2. **Classify the failure.**
   - code-mode host exited during handshake before the first command means
     Code Mode initialization failed.
   - GPT-5.5 works while GPT-5.6+ fails in the same project and account:
     inspect the model-specific Code Mode/provider route.
   - plugin_marketplace_folder_write_failed or
     bundled_plugins_marketplace_resolve_failed plus Encrypted files under
     WindowsApps indicates a plugin-cache copy failure.
   - C: and E: Codex installations in the process chain indicate path mixing.
   - thread not found after a repair attempt indicates an app-server reload or
     stale UI handle; it is not proof that the rollout file was deleted.
3. **Apply only reversible changes.** Back up config.toml. Keep
   sandbox_mode = "workspace-write", the intended provider/model,
   wire_api = "responses", and enabled agents. Build a versioned native shim
   that:
   - starts the real codex.exe from a stable user-profile CWD;
   - forwards raw arguments and standard handles;
   - sets CODEX_CLI_PATH and CODEX_REAL_CLI_PATH to the real CLI;
   - removes other Codex installs from the child PATH;
   - sets CODEX_CODE_MODE_HOST_PATH beside that CLI and TERM=xterm-256color.

   Set only the user-level CODEX_CLI_PATH to the new versioned shim. Do not
   stop current processes, replace the locked old shim, edit system variables,
   or change the registry as a first response.
4. **Handle the plugin cache only when logs prove it is involved.** Preserve
   existing complete caches. If the WindowsApps source is encrypted and the
   final cache is absent, copy file bytes into a new staging directory, verify
   marketplace.json and
   codex-app-tools\.codex-plugin\plugin.json, then promote it. Do not delete
   old staging directories during an active session.
5. **Reload safely.** After active work is safe, fully quit and reopen Desktop
   normally. Do not use an in-task process kill as a substitute.
6. **Verify the behavior.** Run one terminal command, create/read/update/delete
   a harmless test file in the target directory, and make one real subagent
   call. Report each result as PASS, PARTIAL, BLOCKED, or NOT_RUN.

## Minimal use

Diagnosis:

~~~powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Repair-CodexWinFix.ps1
~~~

Safe staging:

~~~powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Repair-CodexWinFix.ps1 -Apply -StageOnly -ProjectPath "$HOME\Downloads\demo"
~~~

When Desktop is fully closed, run the normal apply command to back up and
update config.toml and the user-level environment:

~~~powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Repair-CodexWinFix.ps1 -Apply -ProjectPath "$HOME\Downloads\demo"
~~~

The script does not restart Desktop, kill processes, overwrite the active
shim, or store secret values. A UI banner or a successful config edit alone is
not a repair result.

## Stop conditions

Stop with BLOCKED when the config cannot be parsed, the real CLI is unknown,
the provider/authentication is unavailable, the target path is unsafe, a
versioned shim cannot be built, or any required verification fails. Keep the
original process state and backups for review.

## Reference

The model-specific symptom and Windows CWD shim workaround are tracked in
openai/codex#32759:
https://github.com/openai/codex/issues/32759
