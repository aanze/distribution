# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026 ROCKNIX (https://github.com/ROCKNIX)
#
# Perf Control - hardware discovery and safe sysfs access.
#
# Everything is best-effort and self-discovering: nothing is hard-coded to a
# single device, so the same code works on SM8250/8550/8650/8750. All writes
# clamp the requested value to what the hardware actually advertises, so a bad
# value (e.g. from a foreign profile file) can never reach sysfs.

import glob
import os

import pc_config as C


# --------------------------------------------------------------------------- #
# low level helpers
# --------------------------------------------------------------------------- #
def _read(path):
    try:
        with open(path) as fh:
            return fh.read().strip()
    except Exception:
        return None


def _read_int(path):
    v = _read(path)
    try:
        return int(v)
    except (TypeError, ValueError):
        return None


def _write(path, value):
    """Write value to a sysfs node. Returns True on success."""
    try:
        with open(path, "w") as fh:
            fh.write(str(value))
        return True
    except Exception as exc:
        C.log("write FAILED %s <- %s (%s)" % (path, value, exc))
        return False


def _read_freq_list(path):
    """Parse a space-separated frequency list, return sorted ascending ints."""
    raw = _read(path)
    if not raw:
        return []
    out = []
    for tok in raw.split():
        try:
            out.append(int(tok))
        except ValueError:
            pass
    return sorted(set(out))


def _snap(value, allowed):
    """Snap value to the nearest entry in `allowed` (sorted). Clamp if empty."""
    if not allowed:
        return value
    if value <= allowed[0]:
        return allowed[0]
    if value >= allowed[-1]:
        return allowed[-1]
    best = allowed[0]
    for f in allowed:
        if abs(f - value) < abs(best - value):
            best = f
    return best


# --------------------------------------------------------------------------- #
# CPU clusters (cpufreq policies)
# --------------------------------------------------------------------------- #
def list_cpu_policies():
    """Discover cpufreq policies, sorted by max frequency ascending.

    Returns a list of dicts keyed by the *policy number* (matching the Decky
    plugin's cpu_policyN_* convention), plus a cosmetic cluster label.
    """
    pols = []
    for path in sorted(glob.glob(os.path.join(C.CPUFREQ_ROOT, "policy*"))):
        name = os.path.basename(path)            # e.g. "policy7"
        try:
            num = int(name[len("policy"):])
        except ValueError:
            continue
        avail = _read_freq_list(os.path.join(path, "scaling_available_frequencies"))
        cmin = _read_int(os.path.join(path, "cpuinfo_min_freq"))
        cmax = _read_int(os.path.join(path, "cpuinfo_max_freq"))
        if not avail and cmin and cmax:
            avail = [cmin, cmax]
        pols.append({
            "num": num,
            "path": path,
            "cpus": _read(os.path.join(path, "affected_cpus")) or "",
            "cpuinfo_min": cmin if cmin is not None else (avail[0] if avail else 0),
            "cpuinfo_max": cmax if cmax is not None else (avail[-1] if avail else 0),
            "avail": avail,
            "scaling_min": _read_int(os.path.join(path, "scaling_min_freq")),
            "scaling_max": _read_int(os.path.join(path, "scaling_max_freq")),
            "governor": _read(os.path.join(path, "scaling_governor")),
            "cur": _read_int(os.path.join(path, "scaling_cur_freq")),
        })
    pols.sort(key=lambda p: p["cpuinfo_max"])
    _label_clusters(pols)
    return pols


def _label_clusters(pols):
    """Attach Little / Mid / Big style labels based on relative max freq."""
    n = len(pols)
    if n == 0:
        return
    if n == 1:
        pols[0]["label"] = "CPU"
        return
    pols[0]["label"] = "Little"
    pols[-1]["label"] = "Big"
    for p in pols[1:-1]:
        p["label"] = "Mid"
    # Disambiguate multiple Mids: Mid 1, Mid 2, ...
    mids = [p for p in pols if p["label"] == "Mid"]
    if len(mids) > 1:
        for i, p in enumerate(mids, 1):
            p["label"] = "Mid %d" % i


def available_governors():
    for path in glob.glob(os.path.join(C.CPUFREQ_ROOT, "policy*", "scaling_available_governors")):
        raw = _read(path)
        if raw:
            return raw.split()
    return []


def set_cpu_policy(num, fmin=None, fmax=None):
    """Set scaling_min/max_freq for a policy, snapping to advertised freqs."""
    path = os.path.join(C.CPUFREQ_ROOT, "policy%d" % num)
    avail = _read_freq_list(os.path.join(path, "scaling_available_frequencies"))
    cmin = _read_int(os.path.join(path, "cpuinfo_min_freq"))
    cmax = _read_int(os.path.join(path, "cpuinfo_max_freq"))
    ok = True
    if fmax is not None:
        target = _snap(int(fmax), avail) if avail else max(cmin or 0, min(int(fmax), cmax or int(fmax)))
        # Raise max first if needed, so min<=max ordering never blocks the write.
        ok = _write(os.path.join(path, "scaling_max_freq"), target) and ok
    if fmin is not None:
        target = _snap(int(fmin), avail) if avail else max(cmin or 0, min(int(fmin), cmax or int(fmin)))
        ok = _write(os.path.join(path, "scaling_min_freq"), target) and ok
    return ok


def set_cpu_governor(num, governor):
    path = os.path.join(C.CPUFREQ_ROOT, "policy%d" % num, "scaling_governor")
    return _write(path, governor)


def reset_cpu_policy(num):
    """Restore a policy's caps to the hardware min/max."""
    path = os.path.join(C.CPUFREQ_ROOT, "policy%d" % num)
    cmin = _read_int(os.path.join(path, "cpuinfo_min_freq"))
    cmax = _read_int(os.path.join(path, "cpuinfo_max_freq"))
    if cmax is not None:
        _write(os.path.join(path, "scaling_max_freq"), cmax)
    if cmin is not None:
        _write(os.path.join(path, "scaling_min_freq"), cmin)


# --------------------------------------------------------------------------- #
# GPU (devfreq)
# --------------------------------------------------------------------------- #
def find_gpu():
    """Return the GPU devfreq dict, or None."""
    cand = None
    for path in sorted(glob.glob(os.path.join(C.DEVFREQ_ROOT, "*"))):
        base = os.path.basename(path).lower()
        nm = (_read(os.path.join(path, "name")) or "").lower()
        if "gpu" in base or "gpu" in nm or "3d00000" in base:
            cand = path
            break
    if cand is None and os.path.isdir(C.GPU_DEVFREQ_FALLBACK):
        cand = C.GPU_DEVFREQ_FALLBACK
    if cand is None:
        return None
    avail = _read_freq_list(os.path.join(cand, "available_frequencies"))
    return {
        "path": cand,
        "avail": avail,
        "min": _read_int(os.path.join(cand, "min_freq")),
        "max": _read_int(os.path.join(cand, "max_freq")),
        "cur": _read_int(os.path.join(cand, "cur_freq")),
        "governor": _read(os.path.join(cand, "governor")),
    }


def set_gpu(fmin=None, fmax=None):
    gpu = find_gpu()
    if not gpu:
        return False
    avail = gpu["avail"]
    ok = True
    if fmax is not None:
        target = _snap(int(fmax), avail) if avail else int(fmax)
        ok = _write(os.path.join(gpu["path"], "max_freq"), target) and ok
    if fmin is not None:
        target = _snap(int(fmin), avail) if avail else int(fmin)
        ok = _write(os.path.join(gpu["path"], "min_freq"), target) and ok
    return ok


def reset_gpu():
    gpu = find_gpu()
    if not gpu or not gpu["avail"]:
        return
    _write(os.path.join(gpu["path"], "max_freq"), gpu["avail"][-1])
    _write(os.path.join(gpu["path"], "min_freq"), gpu["avail"][0])


# --------------------------------------------------------------------------- #
# Fan / thermal
# --------------------------------------------------------------------------- #
def find_fan():
    """Return the hwmon dir that owns pwm1, or None."""
    for pwm in sorted(glob.glob(os.path.join(C.HWMON_ROOT, "hwmon*", "pwm1"))):
        return os.path.dirname(pwm)
    return None


def fan_rpm():
    fan = find_fan()
    if not fan:
        return None
    return _read_int(os.path.join(fan, "fan1_input"))


def thermal_zones():
    """Return [(type, milli_c), ...] for cpu/gpu zones."""
    out = []
    for ztype in sorted(glob.glob(os.path.join(C.THERMAL_ROOT, "thermal_zone*", "type"))):
        t = _read(ztype) or ""
        if t.startswith("cpu-") or t.startswith("cpuss") or t.startswith("gpuss"):
            temp = _read_int(os.path.join(os.path.dirname(ztype), "temp"))
            if temp is not None:
                out.append((t, temp))
    return out


def max_temp():
    zones = thermal_zones()
    if not zones:
        return None
    return max(t for _, t in zones)
