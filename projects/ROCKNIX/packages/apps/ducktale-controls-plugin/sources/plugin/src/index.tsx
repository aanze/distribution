import { callable, definePlugin } from "@decky/api";
import {
  PanelSection, PanelSectionRow, SliderField,
  DropdownItem, ButtonItem, TextField
} from "@decky/ui";
import { useState, useEffect, useRef, FC, ReactNode } from "react";
import { FaCog, FaPlus, FaPen, FaTrash, FaChevronDown, FaChevronRight } from "react-icons/fa";


declare const SteamClient: {
  GameSessions: {
    RegisterForAppLifetimeNotifications: (cb: (e: {unAppID: number, bRunning: boolean}) => void) => {unregister: () => void};
  };
};

declare const appStore: {
  GetAppOverviewByAppID: (appId: number) => { display_name: string } | null;
};


interface CpuPolicyInfo {
  available_frequencies: number[];
  governor: string;
  max_freq: number;
  min_freq: number;
}
type CpuInfo = { [key: string]: CpuPolicyInfo };

interface GpuInfo {
  available_frequencies: number[];
  governor: string;
  max_freq: number;
  min_freq: number;
}

interface FanCurve { speeds: number[]; temps: number[]; profile: string; }

interface Preset {
  [key: string]: number | string | { speeds: number[]; temps: number[] };
  gpu_max: number; gpu_min: number;
  fan_mode: string; fan_pwm: number;
}

interface CurvePoint { temp: number; speed: number; }


const getCpuInfo = callable<[], CpuInfo>("get_cpu_info");
const getGpuInfo = callable<[], GpuInfo>("get_gpu_info");
const getTemps = callable<[], { cpu: number; gpu: number }>("get_temps");
const setCpuMaxFreq = callable<[policy: number, freq: number], boolean>("set_cpu_max_freq");
const setGpuMaxFreq = callable<[freq: number], boolean>("set_gpu_max_freq");
const getPresets = callable<[], string[]>("get_presets");
const getPreset = callable<[name: string], Preset | null>("get_preset");
const savePreset = callable<[name: string, settings: string], boolean>("save_preset");
const renamePreset = callable<[oldName: string, newName: string], boolean>("rename_preset");
const deletePreset = callable<[name: string], boolean>("delete_preset");
const applyPreset = callable<[name: string], boolean>("apply_preset");
const getCurrentSettings = callable<[], Preset>("get_current_settings");
const getFanCurve = callable<[], FanCurve>("get_fan_curve");
const saveFanCurve = callable<[speeds: string, temps: string], boolean>("set_fan_curve");
const setFanProfile = callable<[profile: string], boolean>("set_fan_profile");
const getGameProfile = callable<[gameId: string], string | null>("get_game_profile");
const setGameProfile = callable<[gameId: string, presetName: string], boolean>("set_game_profile");
const getChargeMode = callable<[], { available: boolean; mode: string }>("get_charge_mode");
const applyChargeMode = callable<[mode: string], { available: boolean; mode: string }>("set_charge_mode");
const getGamepadProfile = callable<[], { available: boolean; profile: string }>("get_gamepad_profile");
const applyGamepadProfile = callable<[profile: string], { available: boolean; profile: string }>("set_gamepad_profile");

// --- GPU Driver Manager (swappable Mesa Turnip / Vulkan) ------------------- //
type GpuDrv = { id: string; mesa_version: string; channel: string; favorite: boolean; is_default: boolean; path: string };
type GpuCatEntry = { id: string; mesa_version: string; channel: string; notes?: string };
type GpuList = { available: boolean; default: string; drivers: GpuDrv[]; per_game: Record<string, string> };
const getGpuDrivers = callable<[], GpuList>("get_gpu_drivers");
const getGpuCatalog = callable<[refresh: boolean], { available: boolean; drivers: GpuCatEntry[]; error?: string }>("get_gpu_catalog");
const installGpuDriver = callable<[id: string], { ok: boolean; message: string }>("install_gpu_driver");
const removeGpuDriver = callable<[id: string], { ok: boolean }>("remove_gpu_driver");
const setGpuDefault = callable<[id: string], GpuList>("set_gpu_default");
const setGpuFavorite = callable<[id: string, on: boolean], GpuList>("set_gpu_favorite");
const verifyGpuDriver = callable<[id: string], { ok: boolean; message: string }>("verify_gpu_driver");
// The canonical "global" profile is owned by the ROCKNIX Perf Control tool
// (its profiles.json "active"). We read it as the source of truth and write it
// back when the user picks a profile here, so the two tools never disagree and a
// selection survives a game launch/exit.
const getActiveProfile = callable<[], string | null>("get_active_profile");
const setActiveProfile = callable<[name: string], boolean>("set_active_profile");


const state = {
  runningAppId: 0,
  runningGameName: "",
  activePreset: "Default",  // what's actually applied to hardware
  preGamePreset: "Default", // preset active before a game launched (restored on exit)
};

let switching = false;

// Bumped on every EXPLICIT user preset action (select/create/rename/delete).
// Async resolvers (panel-mount resolve, game-lifetime baseline reads) capture
// the epoch before their await and drop their result if it changed underneath:
// a resolve issued BEFORE the user's pick otherwise lands AFTER it and snaps
// the dropdown back to the previous profile while the hardware runs the new
// one (fan audibly changes, display doesn't) until re-picked.
let selectionEpoch = 0;

// Same class of race as selectionEpoch, for the two selectors that read their
// state back from a system helper (Charging mode, Gamepad profile).
//
// Picking a dropdown option REMOUNTS the QAM panel, and the mount effect reads
// each state exactly once. So a pick races its own remount: the helper needs a
// few hundred ms to persist the setting (systemd-run -> script -> systemctl),
// the remount's read lands first and returns the PREVIOUS value, and since
// nothing re-reads afterwards the dropdown stays stuck on it forever while the
// hardware runs the value the user picked. Device-observed 2026-07-25 on
// Charging mode: switched to Battery care, setting/daemon/thresholds all
// correct on device, dropdown still showing Bypass.
//
// Module scope on purpose: component state does NOT survive the remount, these
// guards must. inFlight > 0 means a user pick is still resolving -> its value
// wins over any read that resolves meanwhile.
const picks: { [k: string]: { value: string; inFlight: number } } = {
  charge: { value: "", inFlight: 0 },
  gamepad: { value: "", inFlight: 0 },
};

// Value a state read should display: the in-flight pick if there is one.
function pickOr(key: string, fresh: string): string {
  const p = picks[key];
  return p.inFlight > 0 && p.value ? p.value : fresh;
}


// Detect which saved preset matches the live hardware clocks (per-policy CPU max
// + GPU max). Lets the panel reflect a profile applied OUTSIDE the plugin (e.g.
// the ROCKNIX "Perf Control" Tools app) instead of always defaulting the label
// to "Default". Returns null when the live clocks match no saved preset.
async function detectActivePreset(): Promise<string | null> {
  try {
    const [names, cpu, gpu] = await Promise.all([getPresets(), getCpuInfo(), getGpuInfo()]);
    const liveCpu: { [k: string]: number } = {};
    for (const p of Object.keys(cpu)) liveCpu[p] = cpu[p]?.max_freq ?? -1;
    for (const name of names) {
      const preset = await getPreset(name);
      if (!preset) continue;
      let defined = 0;
      let ok = true;
      for (const p of Object.keys(liveCpu)) {
        const want = (preset as any)[`cpu_policy${p}_max`];
        if (want == null) continue;
        defined++;
        if (want !== liveCpu[p]) { ok = false; break; }
      }
      const gmax = (preset as any).gpu_max;
      if (ok && gmax != null) { defined++; if (gmax !== gpu.max_freq) ok = false; }
      if (ok && defined >= 2) return name;
    }
  } catch (e) {
    // best-effort: fall back to the remembered preset on any error
  }
  return null;
}


// Resolve the user's current "global" profile. Perf Control's saved "active"
// name is the single source of truth (it persists across reboots and is what the
// boot quirk re-applies); only when that is unavailable do we fall back to
// matching the live hardware clocks. Using the saved NAME — instead of always
// reverse-matching clocks — is what stops a game exit from reverting an
// underclock to "Default" when the live clocks momentarily differ.
async function resolveActivePreset(): Promise<string | null> {
  try {
    const a = await getActiveProfile();
    if (a) return a;
  } catch (e) {
    // Perf Control not present / unreadable -> fall back to clock matching
  }
  return await detectActivePreset();
}


function getPolicyLabels(cpuInfo: CpuInfo): { [key: string]: string } {
  const policies = Object.keys(cpuInfo).sort((a, b) => Number(a) - Number(b));
  if (policies.length === 1) return { [policies[0]]: "CPU" };
  const sorted = [...policies].sort((a, b) => {
    const maxA = cpuInfo[a]?.available_frequencies?.slice(-1)[0] ?? 0;
    const maxB = cpuInfo[b]?.available_frequencies?.slice(-1)[0] ?? 0;
    return maxA - maxB;
  });
  const labels: { [key: string]: string } = {};
  sorted.forEach((p, i) => {
    if (sorted.length === 2) {
      labels[p] = i === 0 ? "Little" : "Big";
    } else if (sorted.length === 3) {
      labels[p] = i === 0 ? "Little" : i === 1 ? "Mid" : "Big";
    } else {
      labels[p] = `Cluster ${p}`;
    }
  });
  return labels;
}

const DEFAULT_FAN_CURVE: CurvePoint[] = [
  { temp: 40000, speed: 51 },
  { temp: 60000, speed: 51 },
  { temp: 80000, speed: 153 },
];


const FanCurveEditor: FC<{
  points: CurvePoint[];
  onChange: (points: CurvePoint[]) => void;
  disabled: boolean;
}> = ({ points, onChange, disabled }) => {

  const updateTemp = (index: number, temp: number) => {
    const updated = [...points];
    updated[index] = { ...updated[index], temp };
    updated.sort((a, b) => a.temp - b.temp);
    onChange(enforceMonotonic(updated));
  };

  const updateSpeed = (index: number, speed: number) => {
    const updated = [...points];
    updated[index] = { ...updated[index], speed };
    onChange(enforceMonotonic(updated));
  };

  const addPoint = () => {
    const last = points[points.length - 1];
    const secondLast = points.length >= 2 ? points[points.length - 2] : last;
    const newTemp = Math.min(Math.round((secondLast.temp + last.temp) / 2) + 5000, 100000);
    const newSpeed = Math.min(Math.round((secondLast.speed + last.speed) / 2), 255);
    const updated = [...points, { temp: newTemp, speed: newSpeed }];
    updated.sort((a, b) => a.temp - b.temp);
    onChange(enforceMonotonic(updated));
  };

  const removePoint = (index: number) => {
    if (points.length <= 2) return;
    onChange(points.filter((_, i) => i !== index));
  };

  return (
    <div>
      {points.map((pt, i) => (
        <div key={i}>
          <PanelSectionRow>
            <SliderField
              label={`Point ${i} - Temp`}
              description={`${pt.temp / 1000}°C`}
              value={pt.temp}
              min={30000} max={100000} step={1000}
              disabled={disabled}
              onChange={(val) => updateTemp(i, val)}
            />
          </PanelSectionRow>
          <PanelSectionRow>
            <SliderField
              label={`Point ${i} - Speed`}
              description={`PWM ${pt.speed} (${Math.round(pt.speed / 255 * 100)}%)`}
              value={pt.speed}
              min={0} max={255} step={1}
              disabled={disabled}
              onChange={(val) => updateSpeed(i, val)}
            />
          </PanelSectionRow>
          {points.length > 2 && (
            <PanelSectionRow>
              <ButtonItem layout="below" disabled={disabled} onClick={() => removePoint(i)}>
                <FaTrash /> Remove Point {i}
              </ButtonItem>
            </PanelSectionRow>
          )}
        </div>
      ))}
      <PanelSectionRow>
        <ButtonItem layout="below" disabled={disabled} onClick={addPoint}>
          <FaPlus /> Add Point
        </ButtonItem>
      </PanelSectionRow>
    </div>
  );
};

function enforceMonotonic(points: CurvePoint[]): CurvePoint[] {
  const result = points.map((p) => ({ ...p }));
  for (let i = 1; i < result.length; i++) {
    if (result[i].speed < result[i - 1].speed) result[i].speed = result[i - 1].speed;
  }
  for (let i = result.length - 2; i >= 0; i--) {
    if (result[i].speed > result[i + 1].speed) result[i].speed = result[i + 1].speed;
  }
  return result;
}


// Collapsible PanelSection: @decky/ui has no native collapse, so we draw a
// focusable header row (title + chevron) that toggles a controlled `open` flag
// and conditionally renders the body. Used to keep the heavy Underclocking and
// Fan Curve sections folded away by default.
const Collapsible: FC<{
  title: string;
  open: boolean;
  onToggle: () => void;
  children: ReactNode;
}> = ({ title, open, onToggle, children }) => (
  <PanelSection>
    <PanelSectionRow>
      <ButtonItem layout="below" onClick={onToggle}>
        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", width: "100%" }}>
          <span>{title}</span>
          {open ? <FaChevronDown /> : <FaChevronRight />}
        </div>
      </ButtonItem>
    </PanelSectionRow>
    {open && children}
  </PanelSection>
);


function Content() {
  const [cpuInfo, setCpuInfo] = useState<CpuInfo | null>(null);
  const [gpuInfo, setGpuInfo] = useState<GpuInfo | null>(null);
  const [cpuMaxFreqs, setCpuMaxFreqs] = useState<{ [key: string]: number }>({});
  const [gpuMaxFreq, setGpuMaxFreqState] = useState<number>(0);
  const [liveCpuMax, setLiveCpuMax] = useState<{ [key: string]: number }>({});
  const [liveGpuMax, setLiveGpuMax] = useState<number>(0);
  const [temps, setTemps] = useState<{ cpu: number; gpu: number }>({ cpu: 0, gpu: 0 });

  const [presets, setPresetList] = useState<string[]>([]);
  const [selectedPreset, setSelectedPreset] = useState<string>(state.activePreset);
  const [editMode, setEditMode] = useState<boolean>(false);
  const [editName, setEditName] = useState<string>("");

  const [curvePoints, setCurvePoints] = useState<CurvePoint[]>(DEFAULT_FAN_CURVE);

  const [runningAppId, setRunningAppId] = useState<number>(state.runningAppId);
  const [gameName, setGameName] = useState<string>(state.runningGameName);

  const [chargeAvail, setChargeAvail] = useState<boolean>(false);
  const [chargeMode, setChargeMode] = useState<string>("preserve");

  const [gpuDrvAvail, setGpuDrvAvail] = useState<boolean>(false);
  const [gpuDefault, setGpuDefaultState] = useState<string>("stock");
  const [gpuDrivers, setGpuDrivers] = useState<GpuDrv[]>([]);
  const [gpuCatalog, setGpuCatalog] = useState<GpuCatEntry[]>([]);
  const [gpuMsg, setGpuMsg] = useState<string>("");
  const [showGpuDriver, setShowGpuDriver] = useState<boolean>(false);
  const [gpAvail, setGpAvail] = useState<boolean>(false);
  const [gpProfile, setGpProfile] = useState<string>("xbox-elite");

  // Underclocking + Fan Curve are folded away by default; the user opens them
  // on demand. Keeps the panel short — Presets and Power are the common knobs.
  const [showUnderclock, setShowUnderclock] = useState<boolean>(false);
  const [showFanCurve, setShowFanCurve] = useState<boolean>(false);

  useEffect(() => {
    getChargeMode().then((s) => {
      setChargeAvail(s.available); setChargeMode(pickOr("charge", s.mode));
    }).catch(() => {});
    getGamepadProfile().then((s) => {
      setGpAvail(s.available); setGpProfile(pickOr("gamepad", s.profile));
    }).catch(() => {});
    getGpuDrivers().then((d) => {
      setGpuDrvAvail(d.available);
      setGpuDefaultState(d.default || "stock");
      setGpuDrivers(d.drivers || []);
    }).catch(() => {});
  }, []);

  const refreshGpu = () =>
    getGpuDrivers().then((d) => {
      setGpuDrvAvail(d.available);
      setGpuDefaultState(d.default || "stock");
      setGpuDrivers(d.drivers || []);
    }).catch(() => {});

  const handleGpuDefault = (id: string) => {
    setGpuDefaultState(id);  // optimistic
    setGpuDefault(id).then((d) => {
      setGpuDefaultState(d.default || "stock"); setGpuDrivers(d.drivers || []);
    }).catch(() => {});
  };
  const handleGpuFavorite = (id: string, on: boolean) =>
    setGpuFavorite(id, on).then((d) => setGpuDrivers(d.drivers || [])).catch(() => {});
  const handleGpuRemove = (id: string) => {
    setGpuMsg(`Removing ${id}…`);
    removeGpuDriver(id).then(() => { setGpuMsg(""); refreshGpu(); }).catch(() => setGpuMsg("remove failed"));
  };
  const handleGpuVerify = (id: string) => {
    setGpuMsg("Verifying…");
    verifyGpuDriver(id).then((r) => setGpuMsg(r.message || (r.ok ? "OK" : "FAIL"))).catch(() => setGpuMsg("verify failed"));
  };
  const handleGpuCatalog = () => {
    setGpuMsg("Fetching catalog…");
    getGpuCatalog(true).then((c) => {
      setGpuCatalog(c.drivers || []);
      setGpuMsg(c.error ? `catalog: ${c.error}` : ((c.drivers && c.drivers.length) ? "" : "catalog empty / offline"));
    }).catch(() => setGpuMsg("catalog fetch failed"));
  };
  const handleGpuInstall = (id: string) => {
    setGpuMsg(`Installing ${id}…`);
    installGpuDriver(id).then((r) => { setGpuMsg(r.message); refreshGpu(); }).catch(() => setGpuMsg("install failed"));
  };

  const handleChargeMode = (mode: string) => {
    picks.charge.value = mode; picks.charge.inFlight++;
    setChargeMode(mode);  // optimistic
    applyChargeMode(mode)
      .then((s) => { setChargeAvail(s.available); picks.charge.value = s.mode; setChargeMode(s.mode); })
      .catch(() => {})
      .finally(() => { picks.charge.inFlight--; });
  };

  const handleGamepadProfile = (profile: string) => {
    picks.gamepad.value = profile; picks.gamepad.inFlight++;
    setGpProfile(profile);  // optimistic
    applyGamepadProfile(profile)
      .then((s) => { setGpAvail(s.available); picks.gamepad.value = s.profile; setGpProfile(s.profile); })
      .catch(() => {})
      .finally(() => { picks.gamepad.inFlight--; });
  };


  const refreshHardware = async () => {
    const [cpu, gpu, preset] = await Promise.all([getCpuInfo(), getGpuInfo(), getPreset(state.activePreset)]);
    setCpuInfo(cpu);
    setGpuInfo(gpu);
    const liveMax: { [key: string]: number } = {};
    for (const policy of Object.keys(cpu)) {
      liveMax[policy] = cpu[policy]?.max_freq ?? 0;
    }
    setLiveCpuMax(liveMax);
    setLiveGpuMax(gpu.max_freq);
    const presetMax: { [key: string]: number } = {};
    for (const policy of Object.keys(cpu)) {
      presetMax[policy] = (preset as any)?.[`cpu_policy${policy}_max`] ?? liveMax[policy];
    }
    setCpuMaxFreqs(presetMax);
    setGpuMaxFreqState((preset as any)?.gpu_max ?? gpu.max_freq);
  };

  const refreshPresets = async () => {
    const list = await getPresets();
    if (!list.includes("Default")) list.unshift("Default");
    setPresetList(list);
  };

  const refreshFanCurve = async () => {
    const curve = await getFanCurve();
    if (curve.speeds.length > 0 && curve.temps.length > 0) {
      const pts: CurvePoint[] = curve.temps.map((t, i) => ({
        temp: t, speed: curve.speeds[i] ?? 0,
      }));
      pts.sort((a, b) => a.temp - b.temp);
      setCurvePoints(pts);
    }
  };

  useEffect(() => {
    (async () => {
      // Reflect the canonical active profile (Perf Control's "active", or the
      // live clocks as a fallback) before drawing, so the dropdown isn't stale.
      // Guards, both needed (device-observed failure without them):
      // - epoch: a pick made while this read is in flight invalidates it;
      // - switching: picking a dropdown option REMOUNTS the QAM panel, so this
      //   effect re-runs AFTER the pick (fresh epoch) but can read the store
      //   BEFORE the pick's setActiveProfile write lands -> the stale name
      //   snapped the dropdown back until a second pick.
      const epoch = selectionEpoch;
      const detected = await resolveActivePreset();
      if (detected && epoch === selectionEpoch && !switching) {
        state.activePreset = detected;
        setSelectedPreset(detected);
      }
      await refreshHardware();
      await refreshPresets();
      await refreshFanCurve();
    })();
    let canonTick = 0;
    const interval = setInterval(() => {
      if (switching) return;  // skip entire tick during profile switch to avoid RPC queue buildup
      if (state.runningAppId !== runningAppIdRef.current) setRunningAppId(state.runningAppId);
      if (state.runningGameName !== gameNameRef.current) setGameName(state.runningGameName);
      // Re-read Perf Control's canonical "active" every 3rd tick. The mount
      // effect only resolves ONCE, but Steam keeps the QAM panel mounted
      // across openings — so a profile switched in the Perf Control Tools app
      // (ES) was never picked up and the dropdown showed a stale name until a
      // full Steam restart. Cheap RPC (single JSON read), guarded like the
      // mount path so an in-flight user pick can't be clobbered.
      if (++canonTick % 3 === 0 && state.runningAppId === 0) {
        const epoch = selectionEpoch;
        getActiveProfile().then((a) => {
          if (a && epoch === selectionEpoch && !switching && a !== state.activePreset) {
            state.activePreset = a;
            setSelectedPreset(a);
          }
        }).catch(() => {});
      }
      // Charging mode / gamepad profile: re-read every 20th tick (~20 s). The
      // mount effect resolves ONCE and Steam keeps this panel mounted across
      // openings, so without this the display never recovers from a lost race
      // and never picks up a change made outside Steam (ES menus). Rate-limited
      // because each read spawns a helper; skipped while a pick is resolving.
      if (canonTick % 20 === 0) {
        if (picks.charge.inFlight === 0) {
          getChargeMode().then((s) => {
            setChargeAvail(s.available);
            setChargeMode((prev) => (picks.charge.inFlight > 0 || prev === s.mode) ? prev : s.mode);
          }).catch(() => {});
        }
        if (picks.gamepad.inFlight === 0) {
          getGamepadProfile().then((s) => {
            setGpAvail(s.available);
            setGpProfile((prev) => (picks.gamepad.inFlight > 0 || prev === s.profile) ? prev : s.profile);
          }).catch(() => {});
        }
      }
      getTemps().then((t) => {
        setTemps((prev) => (prev.cpu === t.cpu && prev.gpu === t.gpu) ? prev : t);
      });
      getCpuInfo().then((cpu) => {
        const liveMax: { [key: string]: number } = {};
        for (const p of Object.keys(cpu)) liveMax[p] = cpu[p]?.max_freq ?? 0;
        setLiveCpuMax((prev) => {
          const keys = Object.keys(liveMax);
          if (keys.length === Object.keys(prev).length && keys.every((k) => prev[k] === liveMax[k])) return prev;
          return liveMax;
        });
      });
      getGpuInfo().then((gpu) => setLiveGpuMax((prev) => (prev === gpu.max_freq ? prev : gpu.max_freq)));
      if (state.activePreset !== selectedPresetRef.current && !switching) {
        setSelectedPreset(state.activePreset);
      }
    }, 1000);
    return () => clearInterval(interval);
  }, []);

  const saveRef = useRef({ editMode, cpuMaxFreqs, gpuMaxFreq, editName, selectedPreset });
  saveRef.current = { editMode, cpuMaxFreqs, gpuMaxFreq, editName, selectedPreset };

  const selectedPresetRef = useRef(selectedPreset);
  selectedPresetRef.current = selectedPreset;

  const runningAppIdRef = useRef(runningAppId);
  runningAppIdRef.current = runningAppId;

  const gameNameRef = useRef(gameName);
  gameNameRef.current = gameName;

  useEffect(() => {
    return () => {
      const { editMode, cpuMaxFreqs, gpuMaxFreq, editName, selectedPreset } = saveRef.current;
      if (editMode) {
        getCurrentSettings().then((current) => {
          for (const policy of Object.keys(cpuMaxFreqs)) {
            (current as any)[`cpu_policy${policy}_max`] = cpuMaxFreqs[policy];
          }
          current.gpu_max = gpuMaxFreq;
          const name = editName.trim() || selectedPreset;
          savePreset(name, JSON.stringify(current)).then(() => applyPreset(name));
        });
      }
    };
  }, []);


  const handleSelectPreset = async (name: string) => {
    if (name === selectedPreset) return;
    selectionEpoch++;
    switching = true;
    try {
      setSelectedPreset(name);
      state.activePreset = name;
      // Make this selection the profile restored on game exit (otherwise a
      // change made mid-game is lost when the game quits) AND persist it as the
      // canonical global so Perf Control agrees and it survives reboots.
      state.preGamePreset = name;
      // Persist the canonical store FIRST: picking a dropdown option remounts
      // the QAM panel, whose mount effect re-reads the store; when this write
      // landed after that read (it used to run last, after the hardware
      // apply), the dropdown snapped back to the previous profile until a
      // second pick (device-observed). Hardware apply comes after.
      await setActiveProfile(name);
      await applyPreset(name);
      await Promise.all([
        state.runningAppId > 0 ? setGameProfile(String(state.runningAppId), name) : Promise.resolve(),
        refreshHardware(),
        refreshFanCurve(),
      ]);
    } finally {
      switching = false;
    }
  };

  const handleCreatePreset = async () => {
    selectionEpoch++;
    const name = `Preset ${presets.length}`;
    const settings = await getCurrentSettings();
    await savePreset(name, JSON.stringify(settings));
    await refreshPresets();
    setSelectedPreset(name);
    state.activePreset = name;
    setEditName(name);
    setEditMode(true);
  };

  const handleExitEditMode = async () => {
    const trimmed = editName.trim();
    if (trimmed && trimmed !== selectedPreset) {
      const ok = await renamePreset(selectedPreset, trimmed);
      if (ok) {
        selectionEpoch++;
        setSelectedPreset(trimmed);
        state.activePreset = trimmed;
        await refreshPresets();
      }
    }
    const current = await getCurrentSettings();
    const name = trimmed || selectedPreset;
    for (const policy of Object.keys(cpuMaxFreqs)) {
      (current as any)[`cpu_policy${policy}_max`] = cpuMaxFreqs[policy];
    }
    current.gpu_max = gpuMaxFreq;
    await savePreset(name, JSON.stringify(current));
    await applyPreset(name);
    setEditMode(false);
  };

  const handleCancel = () => {
    setEditMode(false);
    refreshHardware();
    refreshFanCurve();
  };

  const handleDeletePreset = async () => {
    if (selectedPreset === "Default") return;
    selectionEpoch++;
    await deletePreset(selectedPreset);
    setSelectedPreset("Default");
    state.activePreset = "Default";
    setEditMode(false);
    await refreshPresets();
  };


  const handleCpuMaxChange = async (policy: string, index: number) => {
    const freqs = cpuInfo?.[policy]?.available_frequencies;
    if (!freqs) return;
    const freq = freqs[index];
    setCpuMaxFreqs((prev) => ({ ...prev, [policy]: freq }));
  };

  const handleGpuMaxChange = async (index: number) => {
    const freqs = gpuInfo?.available_frequencies;
    if (!freqs) return;
    const freq = freqs[index];
    setGpuMaxFreqState(freq);
  };

  const handleCurveChange = async (points: CurvePoint[]) => {
    setCurvePoints(points);
    const sorted = [...points].sort((a, b) => a.temp - b.temp);
    await saveFanCurve(JSON.stringify(sorted.map(p => p.speed)), JSON.stringify(sorted.map(p => p.temp)));
    const current = await getCurrentSettings();
    await savePreset(selectedPreset, JSON.stringify(current));
  };


  if (!cpuInfo || !gpuInfo) {
    return (
      <PanelSection title="DUCKTALE-CONTROLS">
        <PanelSectionRow><div>Loading...</div></PanelSectionRow>
      </PanelSection>
    );
  }

  return (
    <div>
      {runningAppId > 0 && (
        <PanelSection title={`Playing: ${gameName}`} />
      )}

      <PanelSection title="Presets">
        <PanelSectionRow>
          <DropdownItem
            rgOptions={presets.map((p) => ({ data: p, label: p }))}
            selectedOption={selectedPreset}
            onChange={(opt) => handleSelectPreset(opt.data)}
          />
        </PanelSectionRow>
        {!editMode ? (
          <>
            <PanelSectionRow>
              <ButtonItem layout="below" onClick={() => { setEditName(selectedPreset); setEditMode(true); }}>
                <FaPen /> Edit
              </ButtonItem>
            </PanelSectionRow>
            <PanelSectionRow>
              <ButtonItem layout="below" onClick={handleCreatePreset}>
                <FaPlus /> New Preset
              </ButtonItem>
            </PanelSectionRow>
          </>
        ) : (
          <>
            <PanelSectionRow>
              <TextField label="Rename Preset" value={editName} onChange={(e) => setEditName(e.target.value)} />
            </PanelSectionRow>
            <PanelSectionRow>
              <ButtonItem layout="below" onClick={handleExitEditMode}>Save</ButtonItem>
            </PanelSectionRow>
            <PanelSectionRow>
              <ButtonItem layout="below" onClick={handleCancel}>Cancel</ButtonItem>
            </PanelSectionRow>
            {selectedPreset !== "Default" && (
              <PanelSectionRow>
                <ButtonItem layout="below" onClick={handleDeletePreset}>Delete</ButtonItem>
              </PanelSectionRow>
            )}
          </>
        )}
      </PanelSection>

      {chargeAvail && (
        <PanelSection title="Power">
          <PanelSectionRow>
            <DropdownItem
              label="Charging mode"
              rgOptions={[
                { data: "full", label: "Full charge (100%)" },
                { data: "preserve", label: "Battery care (80%)" },
                { data: "bypass", label: "Bypass (run on AC)" },
              ]}
              selectedOption={chargeMode}
              onChange={(o) => handleChargeMode(o.data as string)}
            />
          </PanelSectionRow>
        </PanelSection>
      )}

      {gpAvail && (
        <PanelSection title="Controller">
          <PanelSectionRow>
            <DropdownItem
              label="Gamepad profile"
              rgOptions={[
                { data: "xbox-elite", label: "Xbox Elite (paddles)" },
                { data: "ds5", label: "DualSense Edge (paddles)" },
              ]}
              selectedOption={gpProfile}
              onChange={(o) => handleGamepadProfile(o.data as string)}
            />
          </PanelSectionRow>
        </PanelSection>
      )}

      <Collapsible
        title={`Underclocking${
          temps.cpu || temps.gpu
            ? ` · ${[
                temps.cpu ? `CPU ${(temps.cpu / 1000).toFixed(0)}°C` : "",
                temps.gpu ? `GPU ${(temps.gpu / 1000).toFixed(0)}°C` : "",
              ].filter(Boolean).join("  ")}`
            : ""
        }`}
        open={showUnderclock}
        onToggle={() => setShowUnderclock((v) => !v)}
      >
        {Object.keys(cpuInfo).sort((a, b) => Number(a) - Number(b)).map((policy) => {
          const info = cpuInfo[policy];
          if (!info || !info.available_frequencies.length) return null;
          const freqs = info.available_frequencies;
          const currentMax = cpuMaxFreqs[policy] ?? freqs[freqs.length - 1];
          const idx = freqs.indexOf(currentMax);
          const labels = getPolicyLabels(cpuInfo);
          const live = liveCpuMax[policy];
          const liveStr = live && live !== currentMax ? ` (${Math.round(live / 1000)} MHz)` : "";
          return (
            <PanelSectionRow key={policy}>
              <SliderField
                label={labels[policy]}
                description={`${Math.round(currentMax / 1000)} MHz${liveStr}`}
                value={idx >= 0 ? idx : freqs.length - 1}
                min={0} max={freqs.length - 1} step={1}
                disabled={!editMode}
                onChange={(i) => handleCpuMaxChange(policy, i)}
              />
            </PanelSectionRow>
          );
        })}
        <PanelSectionRow>
          {(() => {
            const freqs = gpuInfo.available_frequencies;
            const idx = freqs.indexOf(gpuMaxFreq);
            const liveStr = liveGpuMax && liveGpuMax !== gpuMaxFreq ? ` (${Math.round(liveGpuMax / 1000000)} MHz)` : "";
            return (
              <SliderField
                label="GPU"
                description={`${Math.round(gpuMaxFreq / 1000000)} MHz${liveStr}`}
                value={idx >= 0 ? idx : freqs.length - 1}
                min={0} max={freqs.length - 1} step={1}
                disabled={!editMode}
                onChange={(i) => handleGpuMaxChange(i)}
              />
            );
          })()}
        </PanelSectionRow>
      </Collapsible>

      <Collapsible
        title="Fan Curve"
        open={showFanCurve}
        onToggle={() => setShowFanCurve((v) => !v)}
      >
        <FanCurveEditor
          points={curvePoints}
          onChange={handleCurveChange}
          disabled={!editMode}
        />
      </Collapsible>

      {gpuDrvAvail && (
        <Collapsible
          title={`GPU Driver · ${(() => {
            const d = gpuDrivers.find((x) => x.id === gpuDefault);
            const ver = d ? ` · Mesa ${d.mesa_version}` : "";
            return `${gpuDefault === "stock" ? "stock" : gpuDefault}${ver}`;
          })()}`}
          open={showGpuDriver}
          onToggle={() => setShowGpuDriver((v) => !v)}
        >
          <PanelSectionRow>
            <DropdownItem
              label="Active driver"
              rgOptions={gpuDrivers.map((d) => ({
                data: d.id,
                label: d.id === "stock"
                  ? `Stock (system) · Mesa ${d.mesa_version}`
                  : `${d.id} · Mesa ${d.mesa_version}${d.favorite ? " ★" : ""}`,
              }))}
              selectedOption={gpuDefault}
              onChange={(o) => handleGpuDefault(o.data as string)}
            />
          </PanelSectionRow>
          {gpuDrivers.filter((d) => d.id !== "stock").map((d) => (
            <PanelSectionRow key={d.id}>
              <ButtonItem layout="below" onClick={() => handleGpuFavorite(d.id, !d.favorite)}>
                {d.favorite ? "★" : "☆"} {d.id}
              </ButtonItem>
              <ButtonItem layout="below" onClick={() => handleGpuRemove(d.id)}>
                <FaTrash /> Remove
              </ButtonItem>
            </PanelSectionRow>
          ))}
          <PanelSectionRow>
            <ButtonItem layout="below" onClick={() => handleGpuVerify(gpuDefault)}>
              Verify active
            </ButtonItem>
          </PanelSectionRow>
          <PanelSectionRow>
            <ButtonItem layout="below" onClick={handleGpuCatalog}>
              Refresh catalog (online)
            </ButtonItem>
          </PanelSectionRow>
          {gpuCatalog
            .filter((c) => !gpuDrivers.some((d) => d.id === c.id))
            .map((c) => (
              <PanelSectionRow key={c.id}>
                <ButtonItem layout="below" onClick={() => handleGpuInstall(c.id)}>
                  ⬇ {c.id} · {c.mesa_version} ({c.channel})
                </ButtonItem>
              </PanelSectionRow>
            ))}
          {gpuMsg && (
            <PanelSectionRow>
              <div style={{ fontSize: "0.8em", opacity: 0.8, padding: "0 16px" }}>{gpuMsg}</div>
            </PanelSectionRow>
          )}
        </Collapsible>
      )}
    </div>
  );
}

export default definePlugin(() => {
  // Seed the baseline from the canonical active profile at plugin load. It
  // otherwise only resolves when the QAM panel mounts, so launching a game
  // without ever opening the panel would leave state.activePreset at the init
  // "Default".
  const seedEpoch = selectionEpoch;
  resolveActivePreset().then((p) => {
    if (p && seedEpoch === selectionEpoch) { state.activePreset = p; state.preGamePreset = p; }
  });

  const reg = SteamClient.GameSessions.RegisterForAppLifetimeNotifications(async (e: {unAppID: number, bRunning: boolean}) => {
    if (e.bRunning) {
      // Re-derive the real baseline from the canonical active profile BEFORE
      // applying any per-game profile. Launching a Steam game from the
      // EmulationStation "steam" category never opens the QAM (where this
      // resolves), so without it state.activePreset would still be the init
      // "Default" and get restored on exit — clobbering the system / Perf-Control
      // profile that the 095-perfcontrol boot quirk applied.
      const baselineEpoch = selectionEpoch;
      const live = await resolveActivePreset();
      // Drop the read if the user picked a preset while it was in flight —
      // their pick is newer truth than what we read.
      if (live && baselineEpoch === selectionEpoch) state.activePreset = live;
      state.preGamePreset = state.activePreset;  // remember the baseline before this game
      state.runningAppId = e.unAppID;
      const app = appStore.GetAppOverviewByAppID(e.unAppID);
      state.runningGameName = app?.display_name ?? String(e.unAppID);
      const preset = await getGameProfile(String(e.unAppID));
      if (preset) {
        state.activePreset = preset;
        applyPreset(preset);
      }
    } else {
      state.runningAppId = 0;
      state.runningGameName = "";
      // Restore the canonical global profile (Perf Control's "active"), falling
      // back to the pre-game snapshot, then "Default". Reading the saved NAME —
      // rather than relying on the pre-game snapshot alone — is what keeps an
      // underclock set mid-game (or set globally) from being dropped to
      // "Default" when the game exits.
      const restoreEpoch = selectionEpoch;
      const canonical = await getActiveProfile();
      // If the user picked a preset while this read was in flight, their pick
      // already applied AND persisted itself — restoring on top of it would
      // undo an explicit choice. Last pick wins.
      if (restoreEpoch !== selectionEpoch) return;
      const restore = canonical || state.preGamePreset || "Default";
      state.activePreset = restore;
      applyPreset(restore);
    }
  });

  return {
    name: "DUCKTALE-CONTROLS",
    title: <div>DUCKTALE-CONTROLS</div>,
    content: <Content />,
    icon: <FaCog />,
    onDismount() { reg.unregister(); }
  };
});
