#!/usr/bin/env python3
"""Upload and download files or directories over SFTP using Paramiko."""

from __future__ import annotations

import argparse
import getpass
import os
from pathlib import Path
import posixpath
import stat
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


def add_common_args(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--env-file", help="Optional KEY=VALUE profile file")
    parser.add_argument("--host")
    parser.add_argument("--port", type=int)
    parser.add_argument("--user")
    parser.add_argument("--key", help="SSH private key path")
    parser.add_argument("--password-env", default="REMOTE_PASSWORD")
    parser.add_argument("--timeout", type=int, default=20)
    parser.add_argument(
        "--strict-host-key",
        action="store_true",
        help="Reject unknown host keys instead of auto-adding them for convenience",
    )


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Transfer files via Paramiko SFTP.")
    subparsers = parser.add_subparsers(dest="action", required=True)

    upload = subparsers.add_parser("upload", help="Upload local path to remote path")
    add_common_args(upload)
    upload.add_argument("--local", required=True)
    upload.add_argument("--remote", required=True)

    download = subparsers.add_parser("download", help="Download remote path to local path")
    add_common_args(download)
    download.add_argument("--remote", required=True)
    download.add_argument("--local", required=True)
    return parser


def remote_norm(path: str) -> str:
    return path.replace("\\", "/")


def remote_is_dir(sftp, remote_path: str) -> bool:
    try:
        return stat.S_ISDIR(sftp.stat(remote_path).st_mode)
    except OSError:
        return False


def mkdir_p(sftp, remote_dir: str) -> None:
    remote_dir = remote_norm(remote_dir)
    if remote_dir in ("", ".", "/"):
        return
    absolute = remote_dir.startswith("/")
    current = "/" if absolute else ""
    for part in [p for p in remote_dir.strip("/").split("/") if p]:
        current = posixpath.join(current, part) if current else part
        try:
            mode = sftp.stat(current).st_mode
            if not stat.S_ISDIR(mode):
                raise RuntimeError(f"Remote path exists and is not a directory: {current}")
        except OSError:
            sftp.mkdir(current)


def upload_path(sftp, local_path: Path, remote_path: str) -> None:
    remote_path = remote_norm(remote_path)
    if not local_path.exists():
        raise SystemExit(f"Local path does not exist: {local_path}")

    if local_path.is_dir():
        mkdir_p(sftp, remote_path)
        for root, dirs, files in os.walk(local_path):
            root_path = Path(root)
            rel_root = root_path.relative_to(local_path)
            remote_root = remote_path
            if str(rel_root) != ".":
                remote_root = posixpath.join(remote_path, remote_norm(str(rel_root)))
            mkdir_p(sftp, remote_root)
            for directory in dirs:
                mkdir_p(sftp, posixpath.join(remote_root, directory))
            for filename in files:
                src = root_path / filename
                dst = posixpath.join(remote_root, filename)
                print(f"UPLOAD {src} -> {dst}")
                sftp.put(str(src), dst)
        return

    destination = remote_path
    if remote_is_dir(sftp, remote_path):
        destination = posixpath.join(remote_path, local_path.name)
    mkdir_p(sftp, posixpath.dirname(destination))
    print(f"UPLOAD {local_path} -> {destination}")
    sftp.put(str(local_path), destination)


def download_path(sftp, remote_path: str, local_path: Path) -> None:
    remote_path = remote_norm(remote_path)
    if remote_is_dir(sftp, remote_path):
        local_path.mkdir(parents=True, exist_ok=True)
        for attr in sftp.listdir_attr(remote_path):
            child_remote = posixpath.join(remote_path, attr.filename)
            child_local = local_path / attr.filename
            if stat.S_ISDIR(attr.st_mode):
                download_path(sftp, child_remote, child_local)
            else:
                child_local.parent.mkdir(parents=True, exist_ok=True)
                print(f"DOWNLOAD {child_remote} -> {child_local}")
                sftp.get(child_remote, str(child_local))
        return

    destination = local_path / posixpath.basename(remote_path) if local_path.is_dir() else local_path
    destination.parent.mkdir(parents=True, exist_ok=True)
    print(f"DOWNLOAD {remote_path} -> {destination}")
    sftp.get(remote_path, str(destination))


def connect(args: argparse.Namespace):
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
    ssh.connect(**connect_kwargs)
    return ssh


def main() -> int:
    args = build_parser().parse_args()
    ssh = connect(args)
    try:
        sftp = ssh.open_sftp()
        try:
            if args.action == "upload":
                upload_path(sftp, Path(args.local).resolve(), args.remote)
            elif args.action == "download":
                download_path(sftp, args.remote, Path(args.local).resolve())
            else:
                raise SystemExit(f"Unknown action: {args.action}")
        finally:
            sftp.close()
    finally:
        ssh.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
