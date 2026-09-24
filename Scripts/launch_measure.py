#!/usr/bin/env python3
"""Launch the built Appfold.app with its window closed and record RSS, CPU, and snapshot."""

import json
import os
import signal
import subprocess
import sys
import time


def pids():
    result = subprocess.run(["pgrep", "-x", "Appfold"], capture_output=True, text=True)
    if result.returncode not in (0, 1):
        return set()
    found = set()
    for line in result.stdout.split():
        if line.isdigit():
            found.add(int(line))
    return found


def parse_cputime(text):
    text = text.strip()
    if not text:
        return None
    parts = text.split(":")
    try:
        if len(parts) == 2:
            return int(parts[0]) * 60 + float(parts[1])
        if len(parts) == 3:
            return int(parts[0]) * 3600 + int(parts[1]) * 60 + float(parts[2])
        return float(text)
    except ValueError:
        return None


def ps_fields(pid):
    result = subprocess.run(
        ["ps", "-p", str(pid), "-o", "rss=,cputime=,state="],
        capture_output=True,
        text=True,
    )
    raw = result.stdout.strip()
    if result.returncode != 0 or not raw:
        return None
    parts = raw.split()
    if len(parts) < 2:
        return None
    try:
        rss = int(parts[0])
    except ValueError:
        return None
    cpu = parse_cputime(parts[1])
    state = parts[2] if len(parts) > 2 else ""
    return {"rss_kb": rss, "cpu_seconds": cpu, "state": state, "raw": raw}


def alive(pid):
    try:
        os.kill(pid, 0)
        return True
    except OSError:
        return False


def wait_for_new_pid(before, timeout):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        new = pids() - before
        if new:
            return sorted(new)[0]
        time.sleep(0.1)
    return None


def wait_for_snapshot(path, timeout):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if os.path.exists(path) and os.path.getsize(path) > 2:
            try:
                with open(path, "r", encoding="utf-8") as handle:
                    return json.load(handle)
            except json.JSONDecodeError:
                pass
        time.sleep(0.1)
    return None


def check_snapshot(snapshot):
    errors = []
    apps = snapshot.get("apps")
    if not isinstance(apps, list):
        return ["snapshot has no apps list"]
    process_count = snapshot.get("processCount")
    member_pids = []
    for app in apps:
        members = app.get("members") or []
        if not members:
            errors.append(f"app {app.get('name')} has no members")
        memory = sum(int(member.get("memoryBytes", 0)) for member in members)
        energy = sum(int(member.get("energy", 0)) for member in members)
        disk = sum(int(member.get("diskBytes", 0)) for member in members)
        network = sum(int(member.get("networkBytes", 0)) for member in members)
        cpu = sum(float(member.get("cpuPercent", 0)) for member in members)
        if int(app.get("memoryBytes", -1)) != memory:
            errors.append(f"{app.get('name')} memory {app.get('memoryBytes')} != {memory}")
        if int(app.get("energy", -1)) != energy:
            errors.append(f"{app.get('name')} energy mismatch")
        if int(app.get("diskBytes", -1)) != disk:
            errors.append(f"{app.get('name')} disk mismatch")
        if int(app.get("networkBytes", -1)) != network:
            errors.append(f"{app.get('name')} network mismatch")
        if abs(float(app.get("cpuPercent", 0)) - cpu) > 1e-4:
            errors.append(f"{app.get('name')} cpu {app.get('cpuPercent')} != {cpu}")
        for member in members:
            member_pids.append(int(member["pid"]))
    if len(member_pids) != len(set(member_pids)):
        errors.append("a process appears in more than one app")
    if process_count != len(member_pids):
        errors.append(f"processCount {process_count} != members {len(member_pids)}")
    if not any(len(app.get("members") or []) > 1 for app in apps):
        errors.append("no helper process was running, so app folding was not demonstrated")
    if len(apps) >= len(member_pids):
        errors.append(f"app rows {len(apps)} are not fewer than processes {len(member_pids)}")
    return errors


def stop(pid):
    if pid is None or not alive(pid):
        return
    try:
        os.kill(pid, signal.SIGTERM)
    except OSError:
        return
    deadline = time.monotonic() + 2
    while time.monotonic() < deadline and alive(pid):
        time.sleep(0.1)
    if alive(pid):
        try:
            os.kill(pid, signal.SIGKILL)
        except OSError:
            pass


def summarize(snapshot):
    apps = snapshot.get("apps") or []
    ranked = sorted(apps, key=lambda app: float(app.get("cpuPercent") or 0), reverse=True)
    lines = [
        f"processes {snapshot.get('processCount')} apps {len(apps)}",
        f"systemCPU {snapshot.get('systemCPUPercent')} memory {snapshot.get('systemMemoryUsedBytes')}/{snapshot.get('systemMemoryTotalBytes')}",
        f"diskBps {snapshot.get('systemDiskBytesPerSecond')} netBps {snapshot.get('systemNetworkBytesPerSecond')}",
    ]
    for app in ranked[:8]:
        lines.append(
            f"  {app.get('name')} members={len(app.get('members') or [])} "
            f"cpu={app.get('cpuPercent')} mem={app.get('memoryBytes')} "
            f"energy={app.get('energy')} disk={app.get('diskBytes')} net={app.get('networkBytes')}"
        )
    return "\n".join(lines)


def main():
    if len(sys.argv) != 4:
        print("usage: launch_measure.py Appfold.app log-path snapshot-path", file=sys.stderr)
        return 2
    app, log_path, snap_path = sys.argv[1:]
    binary = os.path.join(app, "Contents", "MacOS", "Appfold")
    stdout_path = log_path + ".stdout"
    stderr_path = log_path + ".stderr"
    for path in (snap_path, stdout_path, stderr_path):
        if os.path.exists(path):
            os.remove(path)

    before = pids()
    launch = subprocess.run(
        [
            "open", "-n", "-g",
            "--stdout", stdout_path,
            "--stderr", stderr_path,
            "--env", f"APPFOLD_SNAPSHOT_PATH={snap_path}",
            app,
        ],
        capture_output=True,
        text=True,
    )
    method = "open"
    direct = None
    pid = wait_for_new_pid(before, 8)
    if pid is None:
        method = "executable"
        env = os.environ.copy()
        env["APPFOLD_SNAPSHOT_PATH"] = snap_path
        direct = subprocess.Popen(
            [binary],
            env=env,
            stdout=open(stdout_path, "w"),
            stderr=open(stderr_path, "w"),
        )
        pid = direct.pid

    lines = [
        f"launch_method {method}",
        f"open_return {launch.returncode}",
        f"open_stdout {launch.stdout.strip()}",
        f"open_stderr {launch.stderr.strip()}",
        f"pid {pid}",
    ]
    exit_code = 1
    try:
        if pid is None or not alive(pid):
            lines.append("FAIL process did not stay running")
        else:
            snapshot = wait_for_snapshot(snap_path, 15)
            first = ps_fields(pid)
            time.sleep(0.2)
            started = time.monotonic()
            before_cpu = ps_fields(pid)
            time.sleep(12)
            elapsed = time.monotonic() - started
            after_cpu = ps_fields(pid)
            # Prefer the snapshot written after samples have had time to repeat.
            latest = wait_for_snapshot(snap_path, 1) or snapshot
            lines.append(f"alive_after {alive(pid)}")
            lines.append(f"ps_first {first}")
            lines.append(f"ps_before {before_cpu}")
            lines.append(f"ps_after {after_cpu}")
            lines.append(f"elapsed_seconds {elapsed:.3f}")
            if latest is None:
                lines.append("FAIL snapshot missing")
            else:
                lines.append(summarize(latest))
                errors = check_snapshot(latest)
                rss_values = [item["rss_kb"] for item in (first, before_cpu, after_cpu) if item]
                if not rss_values:
                    errors.append("rss unreadable")
                else:
                    lines.append(f"rss_kb {rss_values} limit {80 * 1024}")
                    if max(rss_values) > 80 * 1024:
                        errors.append(f"rss {max(rss_values)} KB exceeds 80 MB")
                if before_cpu is None or after_cpu is None or before_cpu["cpu_seconds"] is None or after_cpu["cpu_seconds"] is None:
                    errors.append("cpu time unreadable")
                else:
                    cpu_delta = after_cpu["cpu_seconds"] - before_cpu["cpu_seconds"]
                    lines.append(f"cpu_delta_seconds {cpu_delta:.3f}")
                    if elapsed < 10:
                        errors.append(f"idle stretch was only {elapsed:.3f}s")
                    if cpu_delta >= 0.5:
                        errors.append(f"cpu time {cpu_delta:.3f}s over the idle stretch")
                    if cpu_delta < 0:
                        errors.append("cpu time went backwards")
                if not alive(pid):
                    errors.append("process exited during measurement")
                if errors:
                    lines.append("FAIL")
                    lines.extend(f"  {error}" for error in errors)
                else:
                    lines.append("PASS")
                    exit_code = 0
    finally:
        stop(pid if direct is None else direct.pid)
        for extra in pids() - before:
            stop(extra)
        try:
            with open(stdout_path, "r", encoding="utf-8", errors="replace") as handle:
                text = handle.read().strip()
                if text:
                    lines.append("stdout " + text[:2000])
        except OSError:
            pass
        try:
            with open(stderr_path, "r", encoding="utf-8", errors="replace") as handle:
                text = handle.read().strip()
                if text:
                    lines.append("stderr " + text[:4000])
        except OSError:
            pass
        os.makedirs(os.path.dirname(log_path) or ".", exist_ok=True)
        with open(log_path, "w", encoding="utf-8") as handle:
            handle.write("\n".join(lines) + "\n")
    return exit_code


if __name__ == "__main__":
    sys.exit(main())
