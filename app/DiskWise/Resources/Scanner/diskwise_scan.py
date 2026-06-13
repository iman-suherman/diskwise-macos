#!/usr/bin/env python3
"""
DiskWise filesystem scanner.

Emits JSON-lines on stdout for the DiskWise app to parse.
Writes human-readable verbose logs to --log-file for Terminal tailing.
"""

from __future__ import annotations

import argparse
import json
import os
import stat
import subprocess
import sys
import time
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Callable, Iterator, Optional

BATCH_SIZE = 250

VISIBLE_BULK_DIRS = {
    "node_modules",
    "vendor",
    "venv",
    "Pods",
    "bower_components",
    "target",
    "build",
    "dist",
    "DerivedData",
}

HIDDEN_BULK_DIRS = {
    ".venv",
    "__pycache__",
    ".next",
    ".turbo",
    ".build",
    ".gradle",
}

USER_LIBRARY_BULK_DIRS = {
    "Containers",
    "Caches",
    "Group Containers",
    "Logs",
    "Saved Application State",
    "HTTPStorages",
    "WebKit",
    "Developer",
    "Mail",
    "Messages",
    "Safari",
    "Metadata",
    "Biome",
    "Daemon Containers",
    "Application Scripts",
    "CloudStorage",
    "CoreFollowUp",
    "Preferences",
    "Spelling",
    "Translation",
    "UnifiedAssetFramework",
}

SKIP_SYSTEM_PREFIXES = (
    "/System",
    "/Library",
    "/Applications",
    "/private/var",
)


@dataclass
class ScannedEntry:
    path: str
    size: int
    is_directory: bool
    extension: Optional[str]
    created_at: Optional[float]
    modified_at: Optional[float]
    accessed_at: Optional[float]

    def to_json(self) -> dict:
        return {
            "path": self.path,
            "size": self.size,
            "isDirectory": self.is_directory,
            "extensionName": self.extension,
            "createdAt": self.created_at,
            "modifiedAt": self.modified_at,
            "lastAccessed": self.accessed_at,
        }


class ScanContext:
    def __init__(self, log_file: Optional[Path], verbose: bool) -> None:
        self.log_file = log_file
        self.verbose = verbose
        self.scanned_count = 0
        self.indexed_bytes = 0
        self._log_handle = None
        if log_file is not None:
            log_file.parent.mkdir(parents=True, exist_ok=True)
            self._log_handle = log_file.open("w", encoding="utf-8")

    def close(self) -> None:
        if self._log_handle is not None:
            self._log_handle.close()
            self._log_handle = None

    def emit(self, payload: dict) -> None:
        print(json.dumps(payload, separators=(",", ":")), flush=True)

    def log(self, message: str) -> None:
        timestamp = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S")
        line = f"[{timestamp}] {message}"
        if self.verbose and self._log_handle is not None:
            self._log_handle.write(line + "\n")
            self._log_handle.flush()

    def progress(
        self,
        *,
        operation: str,
        current_path: str,
        detail: Optional[str] = None,
        directories_processed: Optional[int] = None,
        directories_total: Optional[int] = None,
        identified_directories: Optional[list[str]] = None,
        active_directories: Optional[list[str]] = None,
        completed_directories: Optional[list[str]] = None,
        force: bool = False,
    ) -> None:
        if not force and self.scanned_count % BATCH_SIZE != 0:
            return
        payload = {
            "type": "progress",
            "scannedCount": self.scanned_count,
            "bytesIndexed": self.indexed_bytes,
            "operation": operation,
            "currentPath": current_path,
        }
        if detail is not None:
            payload["detail"] = detail
        if directories_processed is not None:
            payload["directoriesProcessed"] = directories_processed
        if directories_total is not None:
            payload["directoriesTotal"] = directories_total
        if identified_directories is not None:
            payload["identifiedDirectories"] = identified_directories
        if active_directories is not None:
            payload["activeDirectories"] = active_directories
        if completed_directories is not None:
            payload["completedDirectories"] = completed_directories
        self.emit(payload)

    def record(self, entry: ScannedEntry) -> None:
        if not entry.is_directory:
            self.indexed_bytes += entry.size
        self.scanned_count += 1
        self.emit({"type": "file", **entry.to_json()})


def du_bytes(path: str) -> int:
    try:
        result = subprocess.run(
            ["/usr/bin/du", "-sk", path],
            capture_output=True,
            text=True,
            check=False,
        )
        if result.returncode != 0:
            return enumerated_bytes(path)
        token = result.stdout.split()[0]
        return int(token) * 1024
    except (IndexError, ValueError, OSError):
        return enumerated_bytes(path)


def enumerated_bytes(path: str) -> int:
    total = 0
    for root, _, files in os.walk(path):
        for name in files:
            try:
                total += os.path.getsize(os.path.join(root, name))
            except OSError:
                continue
    return total


def stat_times(path: str) -> tuple[Optional[float], Optional[float], Optional[float]]:
    try:
        st = os.stat(path, follow_symlinks=False)
        return st.st_birthtime, st.st_mtime, st.st_atime
    except OSError:
        return None, None, None


def is_under_user_library(path: str) -> bool:
    parts = Path(path).parts
    try:
        users_index = parts.index("Users")
    except ValueError:
        return False
    return users_index + 2 < len(parts) and parts[users_index + 2] == "Library"


def should_summarize_directory(name: str, parent_path: str, mode: str) -> bool:
    if mode != "fast":
        return False
    if name in VISIBLE_BULK_DIRS or name == ".git" or name in USER_LIBRARY_BULK_DIRS:
        return True
    if is_under_user_library(parent_path) and name in USER_LIBRARY_BULK_DIRS:
        return True
    return False


def should_probe_hidden(parent_path: str, mode: str) -> bool:
    if mode != "fast":
        return False
    for prefix in SKIP_SYSTEM_PREFIXES:
        if parent_path.startswith(prefix):
            return False
    for marker in ("/node_modules/", "/vendor/", "/Pods/"):
        if marker in parent_path:
            return False
    return True


def should_summarize_app_bundle(path: str) -> bool:
    return path.endswith(".app") and os.path.isdir(path)


def effective_scan_root(root: str) -> str:
    normalized = os.path.realpath(root)
    if normalized == "/":
        data_root = "/System/Volumes/Data"
        if os.path.exists(data_root):
            return data_root
    return normalized


def expand_user_homes(users_path: str) -> list[str]:
    tasks: list[str] = []
    try:
        names = sorted(os.listdir(users_path))
    except OSError:
        return [users_path]
    for name in names:
        if name.startswith("."):
            continue
        home = os.path.join(users_path, name)
        if not os.path.isdir(home):
            continue
        try:
            children = sorted(
                entry
                for entry in os.listdir(home)
                if not entry.startswith(".") and os.path.isdir(os.path.join(home, entry))
            )
        except OSError:
            children = []
        if children:
            tasks.extend(os.path.join(home, child) for child in children)
        else:
            tasks.append(home)
    return tasks or [users_path]


def tiered_directories(scan_root: str) -> tuple[list[str], list[str]]:
    summarize: list[str] = []
    drill: list[str] = []
    try:
        names = sorted(os.listdir(scan_root))
    except OSError:
        return summarize, drill
    for name in names:
        path = os.path.join(scan_root, name)
        if not os.path.isdir(path):
            continue
        if name == "Users":
            drill.extend(expand_user_homes(path))
        else:
            summarize.append(name)
    return summarize, drill


def summarize_directory(path: str, ctx: ScanContext) -> ScannedEntry:
    created, modified, accessed = stat_times(path)
    size = du_bytes(path)
    ctx.log(f"Sized directory in one step: {path} ({size} bytes)")
    return ScannedEntry(
        path=path,
        size=size,
        is_directory=False,
        extension=None,
        created_at=created,
        modified_at=modified,
        accessed_at=accessed,
    )


def append_hidden_bulk(parent: str, ctx: ScanContext, results: list[ScannedEntry]) -> None:
    for name in sorted(HIDDEN_BULK_DIRS):
        child = os.path.join(parent, name)
        if not os.path.isdir(child):
            continue
        entry = summarize_directory(child, ctx)
        ctx.record(entry)
        results.append(entry)


def walk_directory(
    scan_root: str,
    mode: str,
    ctx: ScanContext,
    *,
    is_cancelled: Callable[[], bool],
) -> list[ScannedEntry]:
    results: list[ScannedEntry] = []
    root_path = Path(scan_root)

    if should_probe_hidden(scan_root, mode):
        ctx.progress(
            operation="probingHidden",
            current_path=scan_root,
            detail="Checking for hidden dependency folders",
            force=True,
        )
        append_hidden_bulk(scan_root, ctx, results)

    for dirpath, dirnames, filenames in os.walk(scan_root, topdown=True, followlinks=False):
        if is_cancelled():
            raise KeyboardInterrupt("cancelled")

        dirnames[:] = [name for name in dirnames if not name.startswith(".")]

        current = os.path.join(dirpath, "" if dirpath.endswith(os.sep) else "")
        current = dirpath

        for name in list(dirnames):
            child_path = os.path.join(dirpath, name)
            if should_summarize_app_bundle(child_path):
                entry = summarize_directory(child_path, ctx)
                ctx.record(entry)
                results.append(entry)
                dirnames.remove(name)
                ctx.progress(
                    operation="sizingDirectory",
                    current_path=child_path,
                    detail=f"Sized app bundle {name}",
                    force=True,
                )
                continue

            if should_summarize_directory(name, dirpath, mode):
                entry = summarize_directory(child_path, ctx)
                ctx.record(entry)
                results.append(entry)
                dirnames.remove(name)
                ctx.progress(
                    operation="sizingDirectory",
                    current_path=child_path,
                    detail=f"Sized {name} in one step",
                    force=True,
                )
                continue

            if should_probe_hidden(child_path, mode):
                append_hidden_bulk(child_path, ctx, results)

        for name in filenames:
            if is_cancelled():
                raise KeyboardInterrupt("cancelled")
            file_path = os.path.join(dirpath, name)
            try:
                st = os.stat(file_path, follow_symlinks=False)
            except OSError:
                continue
            if not stat.S_ISREG(st.st_mode):
                continue
            extension = Path(name).suffix.lstrip(".").lower() or None
            entry = ScannedEntry(
                path=file_path,
                size=int(st.st_size),
                is_directory=False,
                extension=extension,
                created_at=getattr(st, "st_birthtime", st.st_mtime),
                modified_at=st.st_mtime,
                accessed_at=st.st_atime,
            )
            ctx.record(entry)
            results.append(entry)
            ctx.progress(
                operation="enumeratingFiles",
                current_path=file_path,
            )

    ctx.progress(
        operation="enumeratingFiles",
        current_path=scan_root,
        detail=f"Finished indexing {root_path.name or scan_root}",
        force=True,
    )
    return results


def scan_tiered_volume(
    scan_root: str,
    mode: str,
    ctx: ScanContext,
    *,
    is_cancelled: Callable[[], bool],
) -> list[ScannedEntry]:
    summarize_names, drill_paths = tiered_directories(scan_root)
    identified = summarize_names + [os.path.basename(path) or path for path in drill_paths]
    total = len(identified)
    completed: list[str] = []
    results: list[ScannedEntry] = []

    ctx.progress(
        operation="preparing",
        current_path=scan_root,
        detail=f"Identified {total} folders",
        directories_total=total,
        force=True,
    )
    ctx.log(f"Tiered scan starting at {scan_root} ({total} folders)")

    processed = 0
    for name in summarize_names:
        if is_cancelled():
            raise KeyboardInterrupt("cancelled")
        path = os.path.join(scan_root, name)
        ctx.log(f"Sizing top-level folder: {path}")
        entry = summarize_directory(path, ctx)
        ctx.record(entry)
        results.append(entry)
        processed += 1
        completed.append(name)
        ctx.progress(
            operation="sizingDirectory",
            current_path=path,
            detail=f"Sized {name}",
            directories_processed=processed,
            directories_total=total,
            force=True,
        )

    for drill_path in drill_paths:
        if is_cancelled():
            raise KeyboardInterrupt("cancelled")
        label = os.path.basename(drill_path) or drill_path
        ctx.log(f"Indexing drill folder: {drill_path}")
        ctx.progress(
            operation="enumeratingFiles",
            current_path=drill_path,
            detail=f"Indexing {label}",
            directories_processed=processed,
            directories_total=total,
            force=True,
        )
        batch = walk_directory(drill_path, mode, ctx, is_cancelled=is_cancelled)
        results.extend(batch)
        processed += 1
        completed.append(label)
        ctx.progress(
            operation="enumeratingFiles",
            current_path=drill_path,
            detail=f"Finished {label}",
            directories_processed=processed,
            directories_total=total,
            force=True,
        )

    ctx.progress(
        operation="enumeratingFiles",
        current_path=scan_root,
        detail=f"Finished mapping {total} folders",
        directories_processed=total,
        directories_total=total,
        force=True,
    )
    return results


def run_scan(
    root: str,
    mode: str,
    *,
    tiered: bool,
    ctx: ScanContext,
    is_cancelled: Callable[[], bool],
) -> list[ScannedEntry]:
    scan_root = effective_scan_root(root)
    if not os.path.exists(scan_root):
        raise FileNotFoundError(f"Scan root unavailable: {scan_root}")

    ctx.log(f"DiskWise scan started — root={scan_root} mode={mode} tiered={tiered}")
    ctx.progress(operation="preparing", current_path=scan_root, detail="Starting scan", force=True)

    started = time.time()
    if tiered and mode == "fast":
        results = scan_tiered_volume(scan_root, mode, ctx, is_cancelled=is_cancelled)
    else:
        results = walk_directory(scan_root, mode, ctx, is_cancelled=is_cancelled)

    duration = time.time() - started
    file_count = sum(1 for entry in results if not entry.is_directory)
    indexed_bytes = sum(entry.size for entry in results if not entry.is_directory)
    ctx.log(
        f"Scan complete — {file_count} entries, {indexed_bytes} bytes indexed in {duration:.1f}s"
    )
    ctx.emit(
        {
            "type": "done",
            "scannedFiles": file_count,
            "indexedBytes": indexed_bytes,
            "duration": duration,
            "mode": mode,
        }
    )
    return results


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="DiskWise filesystem scanner")
    parser.add_argument("--root", required=True, help="Volume or folder path to scan")
    parser.add_argument("--mode", choices=("fast", "deep"), default="fast")
    parser.add_argument(
        "--tiered",
        action="store_true",
        help="Use tiered fast volume scan (top-level du + Users drill-down)",
    )
    parser.add_argument("--log-file", help="Verbose human-readable log output path")
    parser.add_argument("--verbose", action="store_true", default=True)
    return parser.parse_args(argv)


def main(argv: Optional[list[str]] = None) -> int:
    args = parse_args(argv or sys.argv[1:])
    log_path = Path(args.log_file).expanduser() if args.log_file else None
    ctx = ScanContext(log_path, verbose=args.verbose)
    cancelled = {"value": False}

    def is_cancelled() -> bool:
        return cancelled["value"]

    try:
        run_scan(
            args.root,
            args.mode,
            tiered=args.tiered,
            ctx=ctx,
            is_cancelled=is_cancelled,
        )
        return 0
    except KeyboardInterrupt:
        ctx.log("Scan cancelled")
        ctx.emit({"type": "error", "message": "Scan was cancelled.", "cancelled": True})
        return 2
    except Exception as exc:  # noqa: BLE001 - report to host app
        ctx.log(f"Scan failed: {exc}")
        ctx.emit({"type": "error", "message": str(exc)})
        return 1
    finally:
        ctx.close()


if __name__ == "__main__":
    sys.exit(main())
