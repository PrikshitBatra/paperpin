#!/usr/bin/env python3
"""Measure an existing macOS process without injecting work into its run loop."""
import argparse
import ctypes
import json
from pathlib import Path
import time

parser = argparse.ArgumentParser()
parser.add_argument("pid", type=int)
parser.add_argument("--seconds", type=int, default=300)
parser.add_argument("--warmup", type=int, default=30)
parser.add_argument("--output", required=True)
parser.add_argument("--board", help="Optional isolated Board.json to verify no idle saves")
args = parser.parse_args()
names = "user_time system_time pkg_idle_wkups interrupt_wkups pageins wired_size resident_size phys_footprint proc_start_abstime proc_exit_abstime child_user_time child_system_time child_pkg_idle_wkups child_interrupt_wkups child_pageins child_elapsed_abstime diskio_bytesread diskio_byteswritten cpu_time_qos_default cpu_time_qos_maintenance cpu_time_qos_background cpu_time_qos_utility cpu_time_qos_legacy cpu_time_qos_user_initiated cpu_time_qos_user_interactive billed_system_time serviced_system_time logical_writes lifetime_max_phys_footprint instructions cycles billed_energy serviced_energy interval_max_phys_footprint runnable_time".split()

class Usage(ctypes.Structure):
    _fields_ = [("uuid", ctypes.c_uint8 * 16)] + [(n, ctypes.c_uint64) for n in names]

libproc = ctypes.CDLL("/usr/lib/libproc.dylib", use_errno=True)
libproc.proc_pid_rusage.argtypes = [ctypes.c_int, ctypes.c_int, ctypes.c_void_p]

def sample():
    value = Usage()
    if libproc.proc_pid_rusage(args.pid, 4, ctypes.byref(value)):
        raise OSError(ctypes.get_errno(), "proc_pid_rusage failed")
    return {name: getattr(value, name) for name in names}

time.sleep(args.warmup)
def board_signature():
    if not args.board: return None
    stat = Path(args.board).stat()
    return [stat.st_ino, stat.st_mtime_ns, stat.st_size]
board_start = board_signature()
start = sample()
started = time.monotonic()
while (remaining := args.seconds - (time.monotonic() - started)) > 0:
    time.sleep(min(remaining, 45))
    print(f"Measured {time.monotonic() - started:.0f}/{args.seconds}s", flush=True)
end = sample()
elapsed = time.monotonic() - started
delta = {key: end[key] - start[key] for key in names}
result = {"pid": args.pid, "elapsed_seconds": elapsed,
          "cpu_percent_one_core": 100 * (delta["user_time"] + delta["system_time"]) / 1e9 / elapsed,
          "idle_wakeups": delta["pkg_idle_wkups"], "interrupt_wakeups": delta["interrupt_wkups"],
          "disk_write_bytes": delta["diskio_byteswritten"], "logical_write_bytes": delta["logical_writes"],
          "physical_memory_bytes": end["phys_footprint"], "resident_memory_bytes": end["resident_size"],
          "counter_deltas": delta,
          "limitations": "Process counters; excludes WindowServer/GPU attribution and is not battery-life measurement."}
if args.board:
    result["board_unchanged"] = board_start == board_signature()
with open(args.output, "w") as output:
    json.dump(result, output, indent=2)
print(json.dumps(result, indent=2))
