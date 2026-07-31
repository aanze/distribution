import os
import json
import glob
import asyncio
import subprocess
import decky

CPU_BASE = "/sys/devices/system/cpu/cpufreq/policy{}"
FAN_PLATFORM = "/sys/devices/platform/pwm-fan"
FAN_CONF = "/storage/.config/fancontrol.conf"

# Perf Control (the ROCKNIX Tools app) owns the canonical "active" profile name
# in this file. We read it as the source of truth and write it back when the user
# picks a profile in Steam, so the two tools stay in sync and a selection
# survives a game launch/exit. Absent => Perf Control not installed (best-effort).
PERFCONTROL_STORE = "/storage/.config/perfcontrol/profiles.json"

DEFAULT_FAN_CURVE = {"speeds": [51, 51, 153], "temps": [40000, 60000, 80000]}


# --- shelling out to the system helpers ------------------------------------- #
# Decky runs plugin backends from its OWN PyInstaller bundle, which on ROCKNIX
# is an x86 build executed under FEX. The bundle exports PYTHONHOME/PYTHONPATH
# and LD_LIBRARY_PATH=/tmp/_MEIxxxxxx, and that directory ships x86 copies of
# libreadline/libtinfo. Anything we spawn inherits them, so:
#   * a system python3 helper gets its stdlib hijacked (urllib then raises
#     "unknown url type: https"), and
#   * /bin/bash - resolved through FEX's x86 view - loads the BUNDLE's
#     libreadline instead of the system one and dies before running a single
#     line: "/bin/bash: symbol lookup error: undefined symbol:
#     rl_trim_arg_from_keyseq" (device-observed 2026-07-25: every gamepad
#     profile / charging mode switch was a silent no-op because of this).
# So every helper we run gets a CLEANED environment. Never call subprocess
# directly here - use _run().
_DIRTY_ENV_KEYS = ("PYTHONHOME", "PYTHONPATH", "PYTHONSTARTUP", "PYTHONEXECUTABLE",
                   "PYTHONNOUSERSITE", "LD_LIBRARY_PATH", "LD_PRELOAD")


def _clean_env():
    env = dict(os.environ)
    for k in _DIRTY_ENV_KEYS:
        env.pop(k, None)
    # PyInstaller stashes the pre-bundle value here when there was one.
    orig = env.pop("LD_LIBRARY_PATH_ORIG", None)
    if orig:
        env["LD_LIBRARY_PATH"] = orig
    return env


# FEX does not just emulate x86 - it presents its own x86 ROOTFS, and that
# rootfs SHADOWS /etc and /bin. A helper script we spawn therefore gets the
# rootfs's x86 /bin/sh (that is where the libreadline above comes from) and,
# worse, a /etc/profile.d that is NOT ROCKNIX's: get_setting/set_setting simply
# do not exist there. Device-observed 2026-07-25: with only the environment
# cleaned, charge-mode ran far enough to switch the hardware and then died on
# "set_setting: command not found" - the mode applied but was never persisted,
# so the QAM dropdown snapped back to the previous value.
#
# systemd-run hands the command to PID 1, which forks it NATIVELY: outside FEX,
# real rootfs, clean environment. --pipe gives us stdout/stderr back and --wait
# propagates the helper's exit status (verified on device: 0/1/3 all propagate,
# ~10 ms overhead). Fall back to a direct call if systemd-run is ever absent.
_SYSTEMD_RUN = "/usr/bin/systemd-run"


def _native_cmd(cmd):
    if os.path.exists(_SYSTEMD_RUN):
        return [_SYSTEMD_RUN, "--quiet", "--wait", "--collect", "--pipe", "--"] + cmd
    return cmd


def _run(cmd, timeout=10, capture=True):
    """Run a system helper natively, with a clean environment; never raise.

    Returns the CompletedProcess, or None if it could not be run. A non-zero
    exit is LOGGED: the failures this fixes were invisible precisely because
    the old call sites passed check=False and ignored the return code.
    """
    try:
        cp = subprocess.run(_native_cmd(cmd), env=_clean_env(), check=False,
                            timeout=timeout, capture_output=capture, text=True)
    except Exception as e:
        decky.logger.error(f"{cmd[0]} {' '.join(cmd[1:])} failed: {e}")
        return None
    if cp.returncode != 0:
        err = (cp.stderr or "").strip().replace("\n", " ")[:200] if capture else ""
        decky.logger.error(f"{cmd[0]} {' '.join(cmd[1:])} exited {cp.returncode}: {err}")
    return cp


def _discover_cpu_policies():
    policies = []
    cpufreq_dir = "/sys/devices/system/cpu/cpufreq"
    if os.path.isdir(cpufreq_dir):
        for entry in os.listdir(cpufreq_dir):
            if entry.startswith("policy"):
                try:
                    policies.append(int(entry.replace("policy", "")))
                except ValueError:
                    pass
    policies.sort()
    return policies


def _discover_gpu_devfreq():
    for entry in glob.glob("/sys/class/devfreq/*gpu*"):
        if os.path.exists(os.path.join(entry, "available_frequencies")):
            return entry
    for entry in glob.glob("/sys/class/devfreq/*"):
        if "gpu" in os.path.basename(entry).lower():
            return entry
    return None


CPU_POLICIES = _discover_cpu_policies()
GPU_BASE = _discover_gpu_devfreq()


def _find_fan_hwmon():
    pattern = os.path.join(FAN_PLATFORM, "hwmon", "hwmon*")
    for p in glob.glob(pattern):
        if os.path.exists(os.path.join(p, "pwm1")):
            return p
    return None


def _read(path):
    try:
        with open(path, "r") as f:
            return f.read().strip()
    except Exception as e:
        decky.logger.error(f"Read failed {path}: {e}")
        return None


def _write(path, value):
    try:
        with open(path, "w") as f:
            f.write(str(value))
        return True
    except Exception as e:
        decky.logger.error(f"Write failed {value} to {path}: {e}")
        return False


async def _aread(path):
    return await asyncio.to_thread(_read, path)


async def _awrite(path, value):
    return await asyncio.to_thread(_write, path, value)


_presets_cache = None


def _presets_path():
    return os.path.join(decky.DECKY_PLUGIN_SETTINGS_DIR, "presets.json")


def _build_default_preset():
    preset = {}
    for policy in CPU_POLICIES:
        base = CPU_BASE.format(policy)
        preset[f"cpu_policy{policy}_max"] = int(_read(os.path.join(base, "scaling_max_freq")) or 0)
        preset[f"cpu_policy{policy}_min"] = int(_read(os.path.join(base, "scaling_min_freq")) or 0)
    if GPU_BASE:
        preset["gpu_max"] = int(_read(os.path.join(GPU_BASE, "max_freq")) or 0)
        preset["gpu_min"] = int(_read(os.path.join(GPU_BASE, "min_freq")) or 0)
    preset["fan_mode"] = "auto"
    preset["fan_pwm"] = 0
    return preset


DEFAULT_PRESET = _build_default_preset()


def _load_presets():
    global _presets_cache
    if _presets_cache is not None:
        return _presets_cache
    path = _presets_path()
    if os.path.exists(path):
        try:
            with open(path, "r") as f:
                data = json.load(f)
        except Exception:
            data = {"presets": {}}
    else:
        data = {"presets": {}}
    if "Default" not in data["presets"]:
        data["presets"]["Default"] = DEFAULT_PRESET
        _save_presets(data)
    _presets_cache = data
    return data


def _save_presets(data):
    global _presets_cache
    os.makedirs(decky.DECKY_PLUGIN_SETTINGS_DIR, exist_ok=True)
    with open(_presets_path(), "w") as f:
        json.dump(data, f, indent=2)
    _presets_cache = data


def _parse_fan_conf():
    if not os.path.exists(FAN_CONF):
        return None
    content = _read(FAN_CONF)
    if not content:
        return None
    speeds = []
    temps = []
    for line in content.split("\n"):
        line = line.strip()
        if line.startswith("SPEEDS=("):
            vals = line.replace("SPEEDS=(", "").rstrip(")")
            speeds = [int(x) for x in vals.split()]
        elif line.startswith("TEMPS=("):
            vals = line.replace("TEMPS=(", "").rstrip(")")
            temps = [int(x) for x in vals.split()]
    if speeds and temps:
        pairs = list(dict.fromkeys(zip(temps, speeds)))
        pairs.sort()
        return {"speeds": [s for t, s in pairs], "temps": [t for t, s in pairs]}
    return None


def _write_fan_conf(speeds, temps):
    os.makedirs(os.path.dirname(FAN_CONF), exist_ok=True)
    pairs = sorted(zip(temps, speeds), reverse=True)
    desc_temps = [t for t, s in pairs]
    desc_speeds = [s for t, s in pairs]

    if 0 not in desc_temps:
        desc_temps.append(0)
        desc_speeds.append(0)

    content = f"SPEEDS=({' '.join(str(s) for s in desc_speeds)})\nTEMPS=({' '.join(str(t) for t in desc_temps)})\n"
    with open(FAN_CONF, "w") as f:
        f.write(content)


def _read_max_temp():
    max_temp = 0
    for zone in glob.glob("/sys/class/thermal/thermal_zone*/type"):
        zone_type = _read(zone)
        if zone_type and (zone_type.startswith("gpuss") or zone_type.startswith("cpuss")):
            temp_path = os.path.join(os.path.dirname(zone), "temp")
            val = _read(temp_path)
            if val:
                try:
                    max_temp = max(max_temp, int(val))
                except ValueError:
                    pass
    return max_temp


def _interpolate_pwm(temp, curve):
    temps = curve["temps"]
    speeds = curve["speeds"]
    if temp <= temps[0]:
        return speeds[0]
    if temp >= temps[-1]:
        return speeds[-1]
    for i in range(1, len(temps)):
        if temp <= temps[i]:
            t0, t1 = temps[i - 1], temps[i]
            s0, s1 = speeds[i - 1], speeds[i]
            if t1 == t0:
                return s1
            ratio = (temp - t0) / (t1 - t0)
            return int(s0 + ratio * (s1 - s0))
    return speeds[-1]


SYSTEM_CFG = "/storage/.config/system/configs/system.cfg"


def _get_system_setting(key, default=""):
    if not os.path.exists(SYSTEM_CFG):
        return default
    try:
        with open(SYSTEM_CFG, "r") as f:
            for line in f:
                if line.strip().startswith(key + "="):
                    return line.strip().split("=", 1)[1]
    except Exception:
        pass
    return default


def _set_system_setting(key, value):
    lines = []
    found = False
    if os.path.exists(SYSTEM_CFG):
        with open(SYSTEM_CFG, "r") as f:
            lines = f.readlines()
    with open(SYSTEM_CFG, "w") as f:
        for line in lines:
            if line.strip().startswith(key + "="):
                f.write(f"{key}={value}\n")
                found = True
            else:
                f.write(line)
        if not found:
            f.write(f"{key}={value}\n")



async def _aload_presets():
    return await asyncio.to_thread(_load_presets)


async def _asave_presets(data):
    return await asyncio.to_thread(_save_presets, data)


async def _awrite_fan_conf(speeds, temps):
    return await asyncio.to_thread(_write_fan_conf, speeds, temps)


async def _aget_system_setting(key, default=""):
    return await asyncio.to_thread(_get_system_setting, key, default)


async def _aset_system_setting(key, value):
    return await asyncio.to_thread(_set_system_setting, key, value)


async def _aread_max_temp():
    return await asyncio.to_thread(_read_max_temp)


class Plugin:
    fan_hwmon = None
    _fan_curve = None
    _curve_task = None
    _apply_lock = None


    async def _fan_curve_loop(self):
        decky.logger.info("Fan curve loop started")
        last_pwm = -1
        try:
            while True:
                if not self._fan_curve or not self.fan_hwmon:
                    await asyncio.sleep(2)
                    continue
                temp = await _aread_max_temp()
                pwm = _interpolate_pwm(temp, self._fan_curve)
                pwm = max(0, min(255, pwm))
                if pwm != last_pwm:
                    await _awrite(os.path.join(self.fan_hwmon, "pwm1_enable"), 1)
                    await _awrite(os.path.join(self.fan_hwmon, "pwm1"), pwm)
                    decky.logger.info(f"Fan curve: temp={temp} -> pwm={pwm}")
                    last_pwm = pwm
                await asyncio.sleep(2)
        except asyncio.CancelledError:
            decky.logger.info("Fan curve loop cancelled")

    def _start_curve_loop(self):
        if self._curve_task is None or self._curve_task.done():
            self._curve_task = asyncio.get_event_loop().create_task(self._fan_curve_loop())
            decky.logger.info("Fan curve loop task created")

    async def _stop_curve_loop(self):
        if self._curve_task and not self._curve_task.done():
            self._curve_task.cancel()
            decky.logger.info("Fan curve loop task stopped")
        self._curve_task = None
        self._fan_curve = None
        if self.fan_hwmon:
            await _awrite(os.path.join(self.fan_hwmon, "pwm1_enable"), 2)


    # --- Charging mode (full / battery care / bypass) ---------------------- #
    # Mirrors the EmulationStation "Charging mode" selector so it can be changed
    # from inside Steam without returning to the desktop. Backed by the same
    # /usr/bin/charge-mode script (mainline charge_control_* firmware charge
    # limit for "battery care", charge_behaviour node for "bypass").
    async def get_charge_mode(self):
        node = "/sys/class/power_supply/battery/charge_behaviour"
        available = os.path.exists(node)
        mode = "preserve"
        if available:
            cp = await asyncio.to_thread(_run, ["/usr/bin/charge-mode", "status"], 10)
            for line in ((cp.stdout if cp else "") or "").splitlines():
                if line.startswith("mode:"):
                    m = line.split(":", 1)[1].strip()
                    if m:
                        mode = m
        return {"available": available, "mode": mode}

    async def set_charge_mode(self, mode):
        if mode not in ("full", "preserve", "bypass"):
            mode = "preserve"
        await asyncio.to_thread(_run, ["/usr/bin/charge-mode", mode], 10)
        return await self.get_charge_mode()

    # Mirrors the EmulationStation "Gamepad profile" selector so the controller
    # emulation can be switched from inside Steam. Backed by the same
    # /usr/bin/gamepad-profile script: xbox-elite exposes the AYN Odin 3 back
    # paddles as real buttons (P1/P3); ds5 is a plain DualSense (PlayStation
    # layout/prompts, no paddles -- the Odin 3 IMU is SLPI-owned so there is no
    # gyro). Only meaningful on
    # devices that ship the Odin 3 InputPlumber composite.
    async def get_gamepad_profile(self):
        node = "/usr/share/inputplumber/devices/01-ayn-controller.yaml"
        available = os.path.exists(node)
        profile = "xbox-elite"
        if available:
            cp = await asyncio.to_thread(_run, ["/usr/bin/gamepad-profile", "get"], 10)
            out = ((cp.stdout if cp else "") or "").strip()
            if out:
                profile = out
        return {"available": available, "profile": profile}

    async def set_gamepad_profile(self, profile):
        if profile not in ("xbox-elite", "ds5"):
            profile = "xbox-elite"
        # In a thread: the helper restarts InputPlumber and can take seconds -
        # blocking Decky's asyncio loop that long freezes every other plugin.
        await asyncio.to_thread(_run, ["/usr/bin/gamepad-profile", "set", profile], 25)
        return await self.get_gamepad_profile()

    # --- GPU Driver Manager (swappable Mesa Turnip / Vulkan) --------------- #
    # Mirrors the /usr/bin/gpu-driver CLI so the active Turnip driver can be
    # picked from inside Steam. The stock /usr driver is always present and is
    # the fallback; selecting a driver only changes what the GAME process loads
    # (VK_DRIVER_FILES), never the compositor. See packages/tools/gpu-driver.
    GPU_DRIVER_BIN = "/usr/bin/gpu-driver"

    def _gpu_driver_available(self):
        return os.path.exists(self.GPU_DRIVER_BIN)

    async def _gpu_run(self, args, timeout=20):
        # In a thread so a slow call (catalogue fetch / driver download) never
        # blocks Decky's asyncio loop -> no plugin reload/freeze. The clean
        # environment comes from _run() (see _clean_env: the bundle's
        # PYTHONHOME/PYTHONPATH used to hijack this CLI's stdlib).
        return await asyncio.to_thread(_run, [self.GPU_DRIVER_BIN] + args, timeout)

    async def get_gpu_drivers(self):
        if not self._gpu_driver_available():
            return {"available": False, "default": "stock", "drivers": [], "per_game": {}}
        out = await self._gpu_run(["list", "--json"])
        if not out or out.returncode != 0:
            return {"available": True, "default": "stock", "drivers": [], "per_game": {}}
        try:
            data = json.loads(out.stdout)
            data["available"] = True
            return data
        except Exception:
            return {"available": True, "default": "stock", "drivers": [], "per_game": {}}

    async def get_gpu_catalog(self, refresh: bool = False):
        if not self._gpu_driver_available():
            return {"available": False, "drivers": []}
        args = ["catalog", "--refresh", "--json"] if refresh else ["catalog", "--json"]
        out = await self._gpu_run(args, timeout=40)
        if not out or out.returncode != 0:
            return {"available": True, "drivers": [], "error": (out.stderr.strip() if out else "no output")}
        try:
            data = json.loads(out.stdout)
            data["available"] = True
            return data
        except Exception:
            return {"available": True, "drivers": []}

    async def install_gpu_driver(self, drv_id: str):
        out = await self._gpu_run(["install", drv_id], timeout=180)
        ok = bool(out and out.returncode == 0)
        return {"ok": ok, "message": (out.stdout or out.stderr).strip() if out else "failed"}

    async def remove_gpu_driver(self, drv_id: str):
        out = await self._gpu_run(["remove", drv_id])
        return {"ok": bool(out and out.returncode == 0)}

    async def set_gpu_default(self, drv_id: str):
        await self._gpu_run(["set-default", drv_id])
        return await self.get_gpu_drivers()

    async def set_gpu_favorite(self, drv_id: str, on: bool = True):
        args = ["favorite", drv_id] + ([] if on else ["--off"])
        await self._gpu_run(args)
        return await self.get_gpu_drivers()

    async def verify_gpu_driver(self, drv_id: str):
        out = await self._gpu_run(["verify", drv_id], timeout=40)
        return {"ok": bool(out and out.returncode == 0),
                "message": (out.stdout or "").strip() if out else "failed"}

    async def get_cpu_info(self):
        result = {}
        for policy in CPU_POLICIES:
            base = CPU_BASE.format(policy)
            freqs_raw = await _aread(os.path.join(base, "scaling_available_frequencies"))
            result[str(policy)] = {
                "available_frequencies": [int(x) for x in freqs_raw.split()] if freqs_raw else [],
                "governor": await _aread(os.path.join(base, "scaling_governor")),
                "min_freq": int(await _aread(os.path.join(base, "scaling_min_freq")) or 0),
                "max_freq": int(await _aread(os.path.join(base, "scaling_max_freq")) or 0),
            }
        return result

    async def set_cpu_max_freq(self, policy: int, freq: int):
        return await _awrite(os.path.join(CPU_BASE.format(policy), "scaling_max_freq"), freq)

    async def set_cpu_min_freq(self, policy: int, freq: int):
        return await _awrite(os.path.join(CPU_BASE.format(policy), "scaling_min_freq"), freq)

    async def set_cpu_governor(self, policy: int, governor: str):
        return await _awrite(os.path.join(CPU_BASE.format(policy), "scaling_governor"), governor)


    async def get_gpu_info(self):
        if not GPU_BASE:
            return {"error": "GPU devfreq not found", "available_frequencies": [], "governor": None, "min_freq": 0, "max_freq": 0}
        freqs_raw = await _aread(os.path.join(GPU_BASE, "available_frequencies"))
        return {
            "available_frequencies": [int(x) for x in freqs_raw.split()] if freqs_raw else [],
            "governor": await _aread(os.path.join(GPU_BASE, "governor")),
            "min_freq": int(await _aread(os.path.join(GPU_BASE, "min_freq")) or 0),
            "max_freq": int(await _aread(os.path.join(GPU_BASE, "max_freq")) or 0),
        }

    async def set_gpu_max_freq(self, freq: int):
        if not GPU_BASE:
            return False
        decky.logger.info(f"set_gpu_max_freq called with: {freq} (type: {type(freq).__name__})")
        result = await _awrite(os.path.join(GPU_BASE, "max_freq"), int(freq))
        decky.logger.info(f"set_gpu_max_freq result: {result}")
        return result

    async def set_gpu_min_freq(self, freq: int):
        if not GPU_BASE:
            return False
        return await _awrite(os.path.join(GPU_BASE, "min_freq"), freq)

    async def set_gpu_governor(self, governor: str):
        if not GPU_BASE:
            return False
        return await _awrite(os.path.join(GPU_BASE, "governor"), governor)


    async def get_temps(self):
        cpu_temp = 0
        gpu_temp = 0
        for zone in glob.glob("/sys/class/thermal/thermal_zone*/type"):
            zone_type = await _aread(zone)
            if not zone_type:
                continue
            temp_path = os.path.join(os.path.dirname(zone), "temp")
            val = await _aread(temp_path)
            if not val:
                continue
            try:
                t = int(val)
            except ValueError:
                continue
            if zone_type.startswith("cpuss"):
                cpu_temp = max(cpu_temp, t)
            elif zone_type.startswith("gpuss"):
                gpu_temp = max(gpu_temp, t)
        return {"cpu": cpu_temp, "gpu": gpu_temp}


    async def get_fan_info(self):
        if not self.fan_hwmon:
            return {"error": "Fan hwmon not found"}
        return {
            "pwm": int(await _aread(os.path.join(self.fan_hwmon, "pwm1")) or 0),
            "rpm": int(await _aread(os.path.join(self.fan_hwmon, "fan1_input")) or 0),
            "enable": int(await _aread(os.path.join(self.fan_hwmon, "pwm1_enable")) or 0),
            "curve_active": self._curve_task is not None and not self._curve_task.done(),
        }

    async def set_fan_speed(self, pwm: int):
        if not self.fan_hwmon:
            return False
        pwm = max(0, min(255, pwm))
        await _awrite(os.path.join(self.fan_hwmon, "pwm1_enable"), 1)
        return await _awrite(os.path.join(self.fan_hwmon, "pwm1"), pwm)

    async def set_fan_auto(self):
        if not self.fan_hwmon:
            return False
        return await _awrite(os.path.join(self.fan_hwmon, "pwm1_enable"), 2)


    async def get_fan_curve(self):
        profile = await _aget_system_setting("cooling.profile", "moderate")
        if profile == "custom":
            curve = _parse_fan_conf()
            if curve:
                return {**curve, "profile": "custom"}
        return {"speeds": DEFAULT_FAN_CURVE["speeds"][:], "temps": DEFAULT_FAN_CURVE["temps"][:], "profile": profile}

    async def set_fan_curve(self, speeds: str, temps: str):
        speeds_list = json.loads(speeds)
        temps_list = json.loads(temps)
        if len(speeds_list) != len(temps_list):
            return False
        for i in range(1, len(speeds_list)):
            if speeds_list[i] < speeds_list[i - 1]:
                return False
        for i in range(1, len(temps_list)):
            if temps_list[i] <= temps_list[i - 1]:
                return False
        await _awrite_fan_conf(speeds_list, temps_list)
        await _aset_system_setting("cooling.profile", "custom")
        self._fan_curve = {"speeds": speeds_list, "temps": temps_list}
        self._start_curve_loop()
        return True

    async def set_fan_profile(self, profile: str):
        await _aset_system_setting("cooling.profile", profile)
        if profile == "custom":
            curve = _parse_fan_conf()
            if curve:
                self._fan_curve = curve
                self._start_curve_loop()
        else:
            await self._stop_curve_loop()
        return True


    async def get_default_preset(self):
        preset = {}
        for policy in CPU_POLICIES:
            base = CPU_BASE.format(policy)
            preset[f"cpu_policy{policy}_max"] = int(await _aread(os.path.join(base, "scaling_max_freq")) or 0)
            preset[f"cpu_policy{policy}_min"] = int(await _aread(os.path.join(base, "scaling_min_freq")) or 0)
        if GPU_BASE:
            preset["gpu_max"] = int(await _aread(os.path.join(GPU_BASE, "max_freq")) or 0)
            preset["gpu_min"] = int(await _aread(os.path.join(GPU_BASE, "min_freq")) or 0)
        preset["fan_mode"] = "auto"
        preset["fan_curve"] = {
            "speeds": [51, 51, 153],
            "temps": [40000, 60000, 80000]
        }
        return preset


    async def get_presets(self):
        data = await _aload_presets()
        return list(data["presets"].keys())

    async def get_preset(self, name: str):
        data = await _aload_presets()
        return data["presets"].get(name)

    async def save_preset(self, name: str, settings: str):
        data = await _aload_presets()
        data["presets"][name] = json.loads(settings)
        await _asave_presets(data)
        return True

    async def rename_preset(self, old_name: str, new_name: str):
        data = await _aload_presets()
        if old_name in data["presets"] and new_name != old_name:
            data["presets"][new_name] = data["presets"].pop(old_name)
            await _asave_presets(data)
            return True
        return False

    async def delete_preset(self, name: str):
        if name == "Default":
            return False
        data = await _aload_presets()
        if name in data["presets"]:
            del data["presets"][name]
            await _asave_presets(data)
            return True
        return False

    async def apply_preset(self, name: str):
        if not self._apply_lock:
            self._apply_lock = asyncio.Lock()
        async with self._apply_lock:
            decky.logger.info(f"apply_preset called with: {name}")
            data = await _aload_presets()
            preset = data["presets"].get(name)
            if not preset:
                decky.logger.info(f"apply_preset: preset '{name}' not found. Available: {list(data['presets'].keys())}")
                return False
            for policy in CPU_POLICIES:
                max_key = f"cpu_policy{policy}_max"
                min_key = f"cpu_policy{policy}_min"
                if max_key in preset:
                    await self.set_cpu_max_freq(policy, preset[max_key])
                if min_key in preset:
                    await self.set_cpu_min_freq(policy, preset[min_key])
            if "gpu_max" in preset:
                await self.set_gpu_max_freq(preset["gpu_max"])
            if "gpu_min" in preset:
                await self.set_gpu_min_freq(preset["gpu_min"])
            if "fan_mode" in preset:
                if preset["fan_mode"] == "auto":
                    await self._stop_curve_loop()
                    await self.set_fan_auto()
                elif preset["fan_mode"] == "manual" and preset.get("fan_pwm") is not None:
                    await self._stop_curve_loop()
                    await self.set_fan_speed(preset["fan_pwm"])
            if "fan_curve" in preset:
                curve = preset["fan_curve"]
                self._fan_curve = {"speeds": curve["speeds"], "temps": curve["temps"]}
                await _awrite_fan_conf(curve["speeds"], curve["temps"])
                await _aset_system_setting("cooling.profile", "custom")
                self._start_curve_loop()
            return True

    async def get_current_settings(self):
        settings = {}
        for policy in CPU_POLICIES:
            base = CPU_BASE.format(policy)
            settings[f"cpu_policy{policy}_max"] = int(await _aread(os.path.join(base, "scaling_max_freq")) or 0)
            settings[f"cpu_policy{policy}_min"] = int(await _aread(os.path.join(base, "scaling_min_freq")) or 0)
        settings["gpu_max"] = int(await _aread(os.path.join(GPU_BASE, "max_freq")) or 0) if GPU_BASE else 0
        settings["gpu_min"] = int(await _aread(os.path.join(GPU_BASE, "min_freq")) or 0) if GPU_BASE else 0
        if self.fan_hwmon:
            enable = int(await _aread(os.path.join(self.fan_hwmon, "pwm1_enable")) or 0)
            if self._curve_task and not self._curve_task.done():
                settings["fan_mode"] = "curve"
            elif enable == 2:
                settings["fan_mode"] = "auto"
            else:
                settings["fan_mode"] = "manual"
            settings["fan_pwm"] = int(await _aread(os.path.join(self.fan_hwmon, "pwm1")) or 0)
        curve = _parse_fan_conf()
        settings["fan_curve"] = curve if curve else DEFAULT_FAN_CURVE
        return settings


    # --- Canonical active profile (shared with the ROCKNIX Perf Control tool) - #
    # Perf Control persists the user's global profile NAME in PERFCONTROL_STORE
    # ("active"). We use it as the single source of truth so a profile set here or
    # there is the one profile everywhere, and is restored on game exit instead of
    # silently reverting to "Default". Both are best-effort and never raise.
    async def get_active_profile(self):
        def _do():
            try:
                with open(PERFCONTROL_STORE) as f:
                    return json.load(f).get("active")
            except Exception:
                return None
        return await asyncio.to_thread(_do)

    async def set_active_profile(self, name: str):
        def _do():
            try:
                if not os.path.exists(PERFCONTROL_STORE):
                    return False  # Perf Control not installed -> nothing to sync
                with open(PERFCONTROL_STORE) as f:
                    data = json.load(f)
                if not isinstance(data, dict):
                    return False
                if data.get("active") == name:
                    return True
                data["active"] = name
                # Atomic, preserving every other key; match Perf Control's own
                # write format (indent=2, sort_keys) to minimise diff churn.
                tmp = PERFCONTROL_STORE + ".tmp"
                with open(tmp, "w") as f:
                    json.dump(data, f, indent=2, sort_keys=True)
                    f.flush()
                    os.fsync(f.fileno())
                os.replace(tmp, PERFCONTROL_STORE)
                return True
            except Exception as e:
                decky.logger.error(f"set_active_profile failed: {e}")
                return False
        return await asyncio.to_thread(_do)


    async def _main(self):
        self.fan_hwmon = _find_fan_hwmon()
        decky.logger.info(f"ROCKNIX Control loaded. Fan hwmon: {self.fan_hwmon}")
        decky.logger.info(f"Discovered CPU policies: {CPU_POLICIES}")
        decky.logger.info(f"Discovered GPU devfreq: {GPU_BASE}")
        _run(["systemctl", "stop", "fancontrol"], 10)
        decky.logger.info("fancontrol service stopped")
        profile = await _aget_system_setting("cooling.profile", "moderate")
        if profile == "custom":
            curve = _parse_fan_conf()
            if curve:
                self._fan_curve = curve
                self._start_curve_loop()

    async def _unload(self):
        await self._stop_curve_loop()
        if self.fan_hwmon:
            await _awrite(os.path.join(self.fan_hwmon, "pwm1_enable"), 2)
        _run(["systemctl", "start", "fancontrol"], 10)
        decky.logger.info("ROCKNIX Control unloaded.")
