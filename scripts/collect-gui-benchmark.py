#!/usr/bin/env python3
"""Collect completed opt-in measurements of a live isolated validation process.

Reads only its own fixture/report/SQLite and process metrics; does not operate UI.
"""
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import re
import sqlite3
import statistics
import subprocess
import sys


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("identifier")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--interactions", action="store_true")
    args = parser.parse_args()
    if not re.fullmatch(r"[a-zA-Z0-9_-]{1,100}", args.identifier):
        parser.error("Invalid isolated fixture identifier")
    folder = Path.home() / "Library/Containers/local.tododesktop.validation/Data/Library/Application Support/TodoDesktop-UITests" / args.identifier
    report = json.loads((folder / "gui-probe.json").read_text())
    if report.get("configuration") != "release" or not report.get("idleSampleValid") or report.get("idleSeconds", 0) < 5:
        parser.error("The Release idle sample has not completed or is invalid")
    pid = int(report["processID"])
    command = subprocess.check_output(["ps", "-p", str(pid), "-o", "args="], text=True).strip()
    if "/DailyToDo-Validation.app/Contents/MacOS/DailyToDo" not in command or f"--ui-test={args.identifier}" not in command.split():
        parser.error("The report process is not the live matching validation app")
    report["residentBytesAtCollection"] = int(subprocess.check_output(["ps", "-p", str(pid), "-o", "rss="], text=True).strip()) * 1024
    report["rssMethod"] = "One ps rss snapshot (KiB multiplied by 1024), not peak or physical footprint"
    report["collectedAtUTC"] = datetime.now(timezone.utc).isoformat()
    report["hardwareModel"] = subprocess.check_output(["sysctl", "-n", "hw.model"], text=True).strip()
    report["processorModel"] = subprocess.check_output(["sysctl", "-n", "machdep.cpu.brand_string"], text=True).strip()
    report["seed"] = json.loads((folder / "fixture.json").read_text())
    if report.get("rules") != report["seed"]["rules"] or report.get("countdowns") != report["seed"]["countdowns"] or report.get("cardItems", 0) <= 0:
        parser.error("The GUI did not load the expected fixture data")
    with sqlite3.connect((folder / "TodoDesktop.sqlite").as_uri() + "?mode=ro", uri=True) as connection:
        report["storedTasksAfterStartup"] = connection.execute("SELECT COUNT(*) FROM ZTODOITEM").fetchone()[0]
    if args.interactions:
        samples = json.loads((folder / "gui-interactions.json").read_text())
        if not samples or any(s.get("processID") != pid or s.get("appBuild") != report["appBuild"] or not s.get("stateVerified") for s in samples):
            parser.error("The interaction samples are missing, stale or unverified")
        report["interactions"] = samples
        report["interactionSampleCount"] = len(samples)
        report["medianLayoutCheckpointMS"] = statistics.median(s["layoutCheckpointMS"] for s in samples)
        report["maxLayoutCheckpointMS"] = max(s["layoutCheckpointMS"] for s in samples)
        report["maxModelPublishedMS"] = max(s["modelPublishedMS"] for s in samples)
        report["interactionScope"] = "Async business command entry to native layout checkpoint; excludes initial input scheduling and compositor latency"
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(f"Collected {report['mode']}: {report['layoutReadyMS']:.1f} ms, idle {report['idleCPUPercent']:.3f}%, RSS {report['residentBytesAtCollection'] / 1048576:.1f} MiB")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError, subprocess.SubprocessError, sqlite3.Error) as error:
        print(f"GUI sample collection unavailable: {error}", file=sys.stderr)
        raise SystemExit(2)
