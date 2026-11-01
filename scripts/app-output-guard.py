#!/usr/bin/env python3
"""Validate a macOS app output and refuse to replace its live executable.

Uses public libproc executable paths instead of command-line substring matching;
relative argv[0], spaces, regex metacharacters and symlink aliases stay safe.
No UI, authorization, process termination, or destination writes occur here.
"""
import ctypes
import os
from pathlib import Path
import plistlib
import sys


class OutputGuardError(Exception):
    def __init__(self, message, code=2):
        super().__init__(message)
        self.code = code


def process_executables():
    if sys.platform != "darwin":
        raise OutputGuardError("App output checks require macOS.", 3)
    try:
        lib = ctypes.CDLL("/usr/lib/libproc.dylib", use_errno=True)
        lib.proc_listallpids.argtypes = [ctypes.c_void_p, ctypes.c_int]
        lib.proc_listallpids.restype = ctypes.c_int
        lib.proc_pidpath.argtypes = [ctypes.c_int, ctypes.c_void_p, ctypes.c_uint32]
        lib.proc_pidpath.restype = ctypes.c_int
        count = lib.proc_listallpids(None, 0)
        if count <= 0:
            raise OutputGuardError("Unable to enumerate live processes; output was not changed.", 3)
        capacity = count + 256
        for _ in range(3):
            pids = (ctypes.c_int * capacity)()
            count = lib.proc_listallpids(pids, ctypes.sizeof(pids))
            if count <= 0:
                raise OutputGuardError("Process enumeration failed; output was not changed.", 3)
            if count < capacity:
                break
            capacity *= 2
        else:
            raise OutputGuardError("Process list kept growing; retry after closing the target App.", 3)
        for pid in pids[:count]:
            if pid <= 0:
                continue
            buffer = ctypes.create_string_buffer(4096)  # PROC_PIDPATHINFO_MAXSIZE
            if lib.proc_pidpath(pid, buffer, len(buffer)) > 0:
                try:
                    yield pid, Path(os.fsdecode(buffer.value)).resolve()
                except OSError:
                    continue  # A process/path can disappear during enumeration.
    except (OSError, AttributeError) as error:
        raise OutputGuardError("Unable to inspect running executables; output was not changed: " + str(error), 3) from error


def check_destination(raw_path, expected_id):
    path = Path(raw_path)
    if path.suffix.lower() != ".app" or not expected_id:
        raise OutputGuardError("Expected a .app output path and a nonempty Bundle ID.")
    destination = path.resolve()
    executable_name = "DailyToDo"
    if destination.exists():
        info_path = destination / "Contents/Info.plist"
        try:
            with info_path.open("rb") as stream:
                info = plistlib.load(stream)
        except (OSError, ValueError, plistlib.InvalidFileException) as error:
            raise OutputGuardError("Refusing to replace an output without a valid App Info.plist: " + str(path)) from error
        if not isinstance(info, dict) or info.get("CFBundleIdentifier") != expected_id or info.get("CFBundleExecutable") not in {"DailyToDo", "TodoDesktop"}:
            raise OutputGuardError("Refusing to replace an unrelated App or executable: " + str(path))
        executable_name = info["CFBundleExecutable"]
    executable = (destination / "Contents/MacOS" / executable_name).resolve()
    for pid, running in process_executables():
        if running == executable:
            raise OutputGuardError(f"请先退出目标 App（PID {pid}）；未修改输出：{path}", 3)


def main():
    if len(sys.argv) != 3:
        print("Usage: app-output-guard.py output.app expected-bundle-id", file=sys.stderr)
        return 2
    try:
        check_destination(sys.argv[1], sys.argv[2])
        return 0
    except (OutputGuardError, OSError, RuntimeError) as error:
        print(str(error), file=sys.stderr)
        return error.code if isinstance(error, OutputGuardError) else 3


if __name__ == "__main__":
    sys.exit(main())
