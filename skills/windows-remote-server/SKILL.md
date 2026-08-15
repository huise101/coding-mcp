---
name: windows-remote-server
description: Windows-first remote server operations without putting SSH credentials in chat. Use when Codex needs to connect from Windows to a remote Linux/server host, run SSH commands, inspect folders, install project environments, upload files, download server files, or work around blocked interactive SSH password prompts by using local profiles, Windows DPAPI-encrypted credentials, SSH keys, Paramiko, SCP, or SFTP.
---

# Windows Remote Server

## Principle

Use a local profile name in chat instead of pasting SSH host/password into the conversation.

The user should create a local profile once with `scripts/save_remote_profile.ps1`. That profile stores host/user/port/workdir in `.codex-remote/profiles/<profile>.env` and stores the password, if used, as a Windows DPAPI-encrypted credential XML in `.codex-remote/secrets/`. These local files must not be committed.

## Security Rules

- Never ask the user to paste passwords, private keys, tokens, or full secret-bearing config into chat if a local profile can be used.
- Never add a `--password` CLI flag to scripts. Passwords must come from SSH keys, Windows encrypted credential XML, an environment variable set by the wrapper, or an interactive prompt.
- Never print passwords or credential XML contents.
- Treat `.codex-remote/`, `.env`, key files, and credential XML files as local-only secrets.
- Ask before destructive remote actions: deletion, overwrite, reboot, service changes, firewall changes, `sudo`, package-manager system installs, or killing unknown processes.
- Start with harmless discovery: `pwd`, `whoami`, `hostname`, `ls -la`.

## Normal User Flow

1. If the user has no local profile, tell them to run:

```powershell
powershell -ExecutionPolicy Bypass -File .\skills\windows-remote-server\scripts\save_remote_profile.ps1 -Profile my-server
```

2. After the profile exists, ask the user to reference only the profile name:

```text
Use $windows-remote-server
profile: my-server
task: enter the default remote directory, run pwd and ls -la, then inspect the project environment
```

3. Run remote commands through the wrapper:

```powershell
powershell -ExecutionPolicy Bypass -File .\skills\windows-remote-server\scripts\invoke_remote.ps1 -Profile my-server -Command "pwd && ls -la"
```

4. Transfer files through the wrapper:

```powershell
powershell -ExecutionPolicy Bypass -File .\skills\windows-remote-server\scripts\transfer_remote.ps1 -Profile my-server -Action download -Remote "/remote/path/file.txt" -Local ".\downloads\file.txt"
```

Read `references/operation-flow.md` when the user asks how to set this up, upload it to GitHub, create profiles, run commands, upload/download files, or avoid leaking SSH credentials.

## Remote Work Procedure

1. Confirm the profile name and requested task.
2. Run a discovery command before changing anything:

```bash
echo "===== identity ====="
whoami; hostname; pwd
echo "===== files ====="
ls -la
```

3. Report the remote working directory being used.
4. For project setup, inspect project files first:
   - Python: `requirements.txt`, `pyproject.toml`, `environment.yml`
   - Node: `package.json`, `package-lock.json`, `pnpm-lock.yaml`, `yarn.lock`
   - GPU: `nvidia-smi`
5. Use the least invasive environment setup:
   - `python3 -m venv .venv && . .venv/bin/activate && python -m pip install -U pip`
   - `pip install -r requirements.txt`
   - `conda env create -f environment.yml` or `conda env update -f environment.yml --prune`
   - `npm ci` for `package-lock.json`
   - `corepack enable && pnpm install --frozen-lockfile` for `pnpm-lock.yaml`
6. Summarize stdout/stderr, exit status, remote path, and next command. Redact secrets.

## Bundled Scripts

- `scripts/save_remote_profile.ps1`: Create a local, gitignored profile without putting SSH credentials in chat.
- `scripts/invoke_remote.ps1`: Load a profile and execute a remote command.
- `scripts/transfer_remote.ps1`: Load a profile and upload/download files.
- `scripts/remote_profile.ps1`: Shared PowerShell profile/credential loader.
- `scripts/remote_exec.py`: Paramiko command executor.
- `scripts/transfer.py`: Paramiko SFTP upload/download helper.
