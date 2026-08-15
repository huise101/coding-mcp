#!/usr/bin/env python3
"""Execute one remote command over SSH using Paramiko.

This script intentionally has no --password argument. Use SSH keys, an
environment variable set by a local wrapper, or an interactive prompt.
"""

from __future__ import annotations

import argparse
import getpass
import os
import shlex
import sys


def load_paramiko():
    try:
        import paramiko  # type: ignore
    except ImportError:
        print(
            "Paramiko is required. Install it with: python -m pip install --user paramiko",
            file=sys.stderr,
        )
        raise SystemExit(2)
    return paramiko


def load_env_file(path: str | None) -> None:
    if not path:
        return
    with open(path, "r", encoding="utf-8") as handle:
        for raw_line in handle:
            line = raw_line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, value = line.split("=", 1)
            key = key.strip()
            value = value.strip().strip('"').strip("'")
            if key and key not in os.environ:
                os.environ[key] = value


def prompt_if_tty(value: str | None, prompt: str, secret: bool = False) -> str | None:
    if value:
        return value
    if not sys.stdin.isatty():
        return None
    if secret:
        return getpass.getpass(prompt)
    return input(prompt).strip()


def require_value(value: str | None, name: str) -> str:
    if value:
        return value
    raise SystemExit(
        f"Missing {name}. Set REMOTE_{name.upper()} or pass --{name.replace('_', '-')}."
    )


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Run a remote command via Paramiko.")
    parser.add_argument("--env-file", help="Optional KEY=VALUE profile file")
    parser.add_argument("--host")
    parser.add_argument("--port", type=int)
    parser.add_argument("--user")
    parser.add_argument("--key", help="SSH private key path")
    parser.add_argument("--workdir")
    parser.add_argument("--cmd")
    parser.add_argument("--cmd-file", help="Read the remote command from a local text file")
    parser.add_argument("--password-env", default="REMOTE_PASSWORD")
    parser.add_argument("--timeout", type=int, default=20)
    parser.add_argument("--pty", action="store_true", help="Allocate a pseudo-tty")
    parser.add_argument(
        "--strict-host-key",
        action="store_true",
        help="Reject unknown host keys instead of auto-adding them for convenience",
    )
    return parser


def read_command(args: argparse.Namespace) -> str:
    if args.cmd_file:
        with open(args.cmd_file, "r", encoding="utf-8") as handle:
            command = handle.read()
    else:
        command = args.cmd or os.environ.get("REMOTE_CMD")
    if not command or not command.strip():
        raise SystemExit("Missing command. Pass --cmd, --cmd-file, or set REMOTE_CMD.")
    workdir = args.workdir if args.workdir is not None else os.environ.get("REMOTE_WORKDIR", "")
    if workdir:
        return f"cd {shlex.quote(workdir)} && {command}"
    return command


def main() -> int:
    args = build_parser().parse_args()
    load_env_file(args.env_file)

    host = require_value(prompt_if_tty(args.host or os.environ.get("REMOTE_HOST"), "Host: "), "host")
    user = require_value(prompt_if_tty(args.user or os.environ.get("REMOTE_USER"), "User: "), "user")
    port = args.port or int(os.environ.get("REMOTE_PORT", "22"))
    key = args.key or os.environ.get("REMOTE_KEY")
    password = os.environ.get(args.password_env)
    if not password and not key:
        password = prompt_if_tty(None, "SSH password (blank to try key/agent): ", secret=True)
        if password == "":
            password = None

    command = read_command(args)
    paramiko = load_paramiko()

    ssh = paramiko.SSHClient()
    ssh.load_system_host_keys()
    if args.strict_host_key:
        ssh.set_missing_host_key_policy(paramiko.RejectPolicy())
    else:
        ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())

    connect_kwargs = {
        "hostname": host,
        "port": port,
        "username": user,
        "timeout": args.timeout,
        "banner_timeout": args.timeout,
        "auth_timeout": args.timeout,
    }
    if key:
        connect_kwargs["key_filename"] = os.path.expanduser(key)
    if password:
        connect_kwargs["password"] = password
        if not key:
            connect_kwargs["look_for_keys"] = False
            connect_kwargs["allow_agent"] = False

    try:
        ssh.connect(**connect_kwargs)
        stdin, stdout, stderr = ssh.exec_command(command, get_pty=args.pty)
        stdin.close()
        out = stdout.read().decode("utf-8", "replace")
        err = stderr.read().decode("utf-8", "replace")
        exit_status = stdout.channel.recv_exit_status()

        if out:
            print(out, end="" if out.endswith("\n") else "\n")
        if err.strip():
            print("===== STDERR =====", file=sys.stderr)
            print(err, end="" if err.endswith("\n") else "\n", file=sys.stderr)
        return int(exit_status)
    finally:
        ssh.close()


if __name__ == "__main__":
    raise SystemExit(main())
