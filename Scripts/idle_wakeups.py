#!/usr/bin/env python3
"""Fails when the built app, left idle, wakes more often or burns more processor than the idle budget in `Docs/performance.md`."""

import argparse
import ctypes
import os
import subprocess
import sys
import tempfile
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from perf_budget_audit import WAKEUP_FLOOR  # noqa: E402

# The most wakeups a second an idle app may take, the same line the static audit holds each timer to.
WAKEUPS_PER_SECOND = 1 / WAKEUP_FLOOR

# The most processor an idle app may use, as a percentage of one core.
CPU_PERCENT = 0.5

# Seconds the app is given to finish launching before counting starts.
SETTLE_SECONDS = 20

# Seconds over which wakeups and processor time are counted.
WINDOW_SECONDS = 60

APP = "dist/Uttrflow.app/Contents/MacOS/Uttrflow"

RUSAGE_INFO_V4 = 4


class RusageHead(ctypes.Structure):
    """The leading fields of `rusage_info_v4`, which every later version keeps in place."""

    _fields_ = [
        ("ri_uuid", ctypes.c_uint8 * 16),
        ("ri_user_time", ctypes.c_uint64),
        ("ri_system_time", ctypes.c_uint64),
        ("ri_pkg_idle_wkups", ctypes.c_uint64),
        ("ri_interrupt_wkups", ctypes.c_uint64),
    ]


class Timebase(ctypes.Structure):
    _fields_ = [("numer", ctypes.c_uint32), ("denom", ctypes.c_uint32)]


LIBPROC = ctypes.CDLL("/usr/lib/libproc.dylib", use_errno=True)
LIBSYSTEM = ctypes.CDLL("/usr/lib/libSystem.dylib")


def nanoseconds_per_tick():
    """Processor times in `rusage_info` are in Mach absolute-time ticks, which are not nanoseconds on Apple silicon."""
    timebase = Timebase()
    LIBSYSTEM.mach_timebase_info(ctypes.byref(timebase))
    return timebase.numer / timebase.denom


def sample(pid):
    """Reads one process's cumulative processor time, in seconds, and its two wakeup counters."""
    buffer = ctypes.create_string_buffer(1024)
    if LIBPROC.proc_pid_rusage(pid, RUSAGE_INFO_V4, buffer) != 0:
        raise OSError(ctypes.get_errno(), f"proc_pid_rusage({pid}) failed")
    head = RusageHead.from_buffer_copy(buffer)
    seconds = (head.ri_user_time + head.ri_system_time) * nanoseconds_per_tick() / 1e9
    return seconds, head.ri_interrupt_wkups, head.ri_pkg_idle_wkups


def measure(pid, settle, window):
    """Waits for the process to settle, then returns its wakeups a second, package-idle wakeups a second and percent of a core."""
    time.sleep(settle)
    start = time.monotonic()
    cpu_before, wakeups_before, idle_before = sample(pid)
    time.sleep(window)
    cpu_after, wakeups_after, idle_after = sample(pid)
    elapsed = time.monotonic() - start
    return (
        (wakeups_after - wakeups_before) / elapsed,
        (idle_after - idle_before) / elapsed,
        100 * (cpu_after - cpu_before) / elapsed,
    )


def judge(state, reading):
    """Prints one state's reading against the budget and returns the breaches."""
    wakeups, idle_wakeups, cpu = reading
    print(
        f"  {state}: {wakeups:.2f} wakeups/s ({idle_wakeups:.2f} from package idle), {cpu:.3f}% of a core"
        f" (budget {WAKEUPS_PER_SECOND:g}/s, {CPU_PERCENT:g}%)"
    )
    breaches = []
    if wakeups > WAKEUPS_PER_SECOND:
        breaches.append(f"{state}: {wakeups:.2f} wakeups a second, over {WAKEUPS_PER_SECOND:g}")
    if cpu > CPU_PERCENT:
        breaches.append(f"{state}: {cpu:.3f}% of a core, over {CPU_PERCENT:g}%")
    return breaches


def measure_command(command, settle, window, env=None):
    """Launches a command, measures it idle, and stops it."""
    process = subprocess.Popen(command, env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        reading = measure(process.pid, settle, window)
        if process.poll() is not None:
            raise RuntimeError(f"{command[0]} exited with {process.returncode} while it was measured")
        return reading
    finally:
        if process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()


def measure_app(app, settle, window):
    """The menu-bar-only state: onboarding finished, no window open, suggestions and updates off, in a throwaway container."""
    if not os.access(app, os.X_OK):
        raise RuntimeError(f"{app} is not built; run `make app` first")
    with tempfile.TemporaryDirectory(prefix="uttrflow-idle-") as container:
        env = dict(os.environ, UTTRFLOW_TEST_CONTAINER=container)
        return {"menu bar only": measure_command([app], settle, window, env)}


# A 20 Hz loop whose sleep sits in a called function, the shape the static audit cannot see.
HIDDEN_TIMER = "import time\ndef pause():\n    time.sleep(0.05)\nwhile True:\n    pause()\n"

# A process that does nothing at all.
QUIET = "import time\ntime.sleep(3600)\n"


def self_test():
    """Proves the measurement fails a hidden 20 Hz loop and passes a process that only sleeps."""
    failures = []
    if not judge("self-test, 20 Hz loop behind a helper", measure_command([sys.executable, "-c", HIDDEN_TIMER], 1, 5)):
        failures.append("a 20 Hz loop behind a helper function passed the budget")
    if judge("self-test, a process that only sleeps", measure_command([sys.executable, "-c", QUIET], 1, 5)):
        failures.append("a process that only sleeps failed the budget")
    return failures


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", default=APP, help="the app executable to launch")
    parser.add_argument("--settle", type=float, default=SETTLE_SECONDS, help="seconds to wait before counting")
    parser.add_argument("--window", type=float, default=WINDOW_SECONDS, help="seconds to count over")
    parser.add_argument("--self-test", action="store_true", help="prove the check bites, then measure the app")
    arguments = parser.parse_args()
    if arguments.settle < 0 or arguments.window <= 0:
        parser.error("--settle must be at least 0 and --window above 0")
    sys.stdout.reconfigure(line_buffering=True)
    print("Idle wakeups and processor time, read with proc_pid_rusage:")
    failures = self_test() if arguments.self_test else []
    try:
        readings = measure_app(arguments.app, arguments.settle, arguments.window)
    except (RuntimeError, OSError) as error:
        failures.append(str(error))
        readings = {}
    for state, reading in readings.items():
        failures += judge(state, reading)
    if failures:
        print("\nOver the idle budget in Docs/performance.md:", file=sys.stderr)
        for failure in failures:
            print(f"  ✗ {failure}", file=sys.stderr)
        return 1
    print("Within the idle budget.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
