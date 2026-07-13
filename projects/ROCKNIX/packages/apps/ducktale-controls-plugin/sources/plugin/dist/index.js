const manifest = {"name":"DUCKTALE-CONTROLS"};
const API_VERSION = 2;
const internalAPIConnection = window.__DECKY_SECRET_INTERNALS_DO_NOT_USE_OR_YOU_WILL_BE_FIRED_deckyLoaderAPIInit;
if (!internalAPIConnection) {
    throw new Error('[@decky/api]: Failed to connect to the loader as as the loader API was not initialized. This is likely a bug in Decky Loader.');
}
let api;
try {
    api = internalAPIConnection.connect(API_VERSION, manifest.name);
}
catch {
    api = internalAPIConnection.connect(1, manifest.name);
    console.warn(`[@decky/api] Requested API version ${API_VERSION} but the running loader only supports version 1. Some features may not work.`);
}
if (api._version != API_VERSION) {
    console.warn(`[@decky/api] Requested API version ${API_VERSION} but the running loader only supports version ${api._version}. Some features may not work.`);
}
const callable = api.callable;
const definePlugin = (fn) => {
    return (...args) => {
        return fn(...args);
    };
};

var DefaultContext = {
  color: undefined,
  size: undefined,
  className: undefined,
  style: undefined,
  attr: undefined
};
var IconContext = SP_REACT.createContext && /*#__PURE__*/SP_REACT.createContext(DefaultContext);

var _excluded = ["attr", "size", "title"];
function _objectWithoutProperties(e, t) { if (null == e) return {}; var o, r, i = _objectWithoutPropertiesLoose(e, t); if (Object.getOwnPropertySymbols) { var n = Object.getOwnPropertySymbols(e); for (r = 0; r < n.length; r++) o = n[r], -1 === t.indexOf(o) && {}.propertyIsEnumerable.call(e, o) && (i[o] = e[o]); } return i; }
function _objectWithoutPropertiesLoose(r, e) { if (null == r) return {}; var t = {}; for (var n in r) if ({}.hasOwnProperty.call(r, n)) { if (-1 !== e.indexOf(n)) continue; t[n] = r[n]; } return t; }
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
function ownKeys(e, r) { var t = Object.keys(e); if (Object.getOwnPropertySymbols) { var o = Object.getOwnPropertySymbols(e); r && (o = o.filter(function (r) { return Object.getOwnPropertyDescriptor(e, r).enumerable; })), t.push.apply(t, o); } return t; }
function _objectSpread(e) { for (var r = 1; r < arguments.length; r++) { var t = null != arguments[r] ? arguments[r] : {}; r % 2 ? ownKeys(Object(t), true).forEach(function (r) { _defineProperty(e, r, t[r]); }) : Object.getOwnPropertyDescriptors ? Object.defineProperties(e, Object.getOwnPropertyDescriptors(t)) : ownKeys(Object(t)).forEach(function (r) { Object.defineProperty(e, r, Object.getOwnPropertyDescriptor(t, r)); }); } return e; }
function _defineProperty(e, r, t) { return (r = _toPropertyKey(r)) in e ? Object.defineProperty(e, r, { value: t, enumerable: true, configurable: true, writable: true }) : e[r] = t, e; }
function _toPropertyKey(t) { var i = _toPrimitive(t, "string"); return "symbol" == typeof i ? i : i + ""; }
function _toPrimitive(t, r) { if ("object" != typeof t || !t) return t; var e = t[Symbol.toPrimitive]; if (void 0 !== e) { var i = e.call(t, r); if ("object" != typeof i) return i; throw new TypeError("@@toPrimitive must return a primitive value."); } return ("string" === r ? String : Number)(t); }
function Tree2Element(tree) {
  return tree && tree.map((node, i) => /*#__PURE__*/SP_REACT.createElement(node.tag, _objectSpread({
    key: i
  }, node.attr), Tree2Element(node.child)));
}
function GenIcon(data) {
  return props => /*#__PURE__*/SP_REACT.createElement(IconBase, _extends({
    attr: _objectSpread({}, data.attr)
  }, props), Tree2Element(data.child));
}
function IconBase(props) {
  var elem = conf => {
    var {
        attr,
        size,
        title
      } = props,
      svgProps = _objectWithoutProperties(props, _excluded);
    var computedSize = size || conf.size || "1em";
    var className;
    if (conf.className) className = conf.className;
    if (props.className) className = (className ? className + " " : "") + props.className;
    return /*#__PURE__*/SP_REACT.createElement("svg", _extends({
      stroke: "currentColor",
      fill: "currentColor",
      strokeWidth: "0"
    }, conf.attr, attr, svgProps, {
      className: className,
      style: _objectSpread(_objectSpread({
        color: props.color || conf.color
      }, conf.style), props.style),
      height: computedSize,
      width: computedSize,
      xmlns: "http://www.w3.org/2000/svg"
    }), title && /*#__PURE__*/SP_REACT.createElement("title", null, title), props.children);
  };
  return IconContext !== undefined ? /*#__PURE__*/SP_REACT.createElement(IconContext.Consumer, null, conf => elem(conf)) : elem(DefaultContext);
}

// THIS FILE IS AUTO GENERATED
function FaTrash (props) {
  return GenIcon({"attr":{"viewBox":"0 0 448 512"},"child":[{"tag":"path","attr":{"d":"M432 32H312l-9.4-18.7A24 24 0 0 0 281.1 0H166.8a23.72 23.72 0 0 0-21.4 13.3L136 32H16A16 16 0 0 0 0 48v32a16 16 0 0 0 16 16h416a16 16 0 0 0 16-16V48a16 16 0 0 0-16-16zM53.2 467a48 48 0 0 0 47.9 45h245.8a48 48 0 0 0 47.9-45L416 128H32z"},"child":[]}]})(props);
}function FaPlus (props) {
  return GenIcon({"attr":{"viewBox":"0 0 448 512"},"child":[{"tag":"path","attr":{"d":"M416 208H272V64c0-17.67-14.33-32-32-32h-32c-17.67 0-32 14.33-32 32v144H32c-17.67 0-32 14.33-32 32v32c0 17.67 14.33 32 32 32h144v144c0 17.67 14.33 32 32 32h32c17.67 0 32-14.33 32-32V304h144c17.67 0 32-14.33 32-32v-32c0-17.67-14.33-32-32-32z"},"child":[]}]})(props);
}function FaPen (props) {
  return GenIcon({"attr":{"viewBox":"0 0 512 512"},"child":[{"tag":"path","attr":{"d":"M290.74 93.24l128.02 128.02-277.99 277.99-114.14 12.6C11.35 513.54-1.56 500.62.14 485.34l12.7-114.22 277.9-277.88zm207.2-19.06l-60.11-60.11c-18.75-18.75-49.16-18.75-67.91 0l-56.55 56.55 128.02 128.02 56.55-56.55c18.75-18.76 18.75-49.16 0-67.91z"},"child":[]}]})(props);
}function FaCog (props) {
  return GenIcon({"attr":{"viewBox":"0 0 512 512"},"child":[{"tag":"path","attr":{"d":"M487.4 315.7l-42.6-24.6c4.3-23.2 4.3-47 0-70.2l42.6-24.6c4.9-2.8 7.1-8.6 5.5-14-11.1-35.6-30-67.8-54.7-94.6-3.8-4.1-10-5.1-14.8-2.3L380.8 110c-17.9-15.4-38.5-27.3-60.8-35.1V25.8c0-5.6-3.9-10.5-9.4-11.7-36.7-8.2-74.3-7.8-109.2 0-5.5 1.2-9.4 6.1-9.4 11.7V75c-22.2 7.9-42.8 19.8-60.8 35.1L88.7 85.5c-4.9-2.8-11-1.9-14.8 2.3-24.7 26.7-43.6 58.9-54.7 94.6-1.7 5.4.6 11.2 5.5 14L67.3 221c-4.3 23.2-4.3 47 0 70.2l-42.6 24.6c-4.9 2.8-7.1 8.6-5.5 14 11.1 35.6 30 67.8 54.7 94.6 3.8 4.1 10 5.1 14.8 2.3l42.6-24.6c17.9 15.4 38.5 27.3 60.8 35.1v49.2c0 5.6 3.9 10.5 9.4 11.7 36.7 8.2 74.3 7.8 109.2 0 5.5-1.2 9.4-6.1 9.4-11.7v-49.2c22.2-7.9 42.8-19.8 60.8-35.1l42.6 24.6c4.9 2.8 11 1.9 14.8-2.3 24.7-26.7 43.6-58.9 54.7-94.6 1.5-5.5-.7-11.3-5.6-14.1zM256 336c-44.1 0-80-35.9-80-80s35.9-80 80-80 80 35.9 80 80-35.9 80-80 80z"},"child":[]}]})(props);
}function FaChevronRight (props) {
  return GenIcon({"attr":{"viewBox":"0 0 320 512"},"child":[{"tag":"path","attr":{"d":"M285.476 272.971L91.132 467.314c-9.373 9.373-24.569 9.373-33.941 0l-22.667-22.667c-9.357-9.357-9.375-24.522-.04-33.901L188.505 256 34.484 101.255c-9.335-9.379-9.317-24.544.04-33.901l22.667-22.667c9.373-9.373 24.569-9.373 33.941 0L285.475 239.03c9.373 9.372 9.373 24.568.001 33.941z"},"child":[]}]})(props);
}function FaChevronDown (props) {
  return GenIcon({"attr":{"viewBox":"0 0 448 512"},"child":[{"tag":"path","attr":{"d":"M207.029 381.476L12.686 187.132c-9.373-9.373-9.373-24.569 0-33.941l22.667-22.667c9.357-9.357 24.522-9.375 33.901-.04L224 284.505l154.745-154.021c9.379-9.335 24.544-9.317 33.901.04l22.667 22.667c9.373 9.373 9.373 24.569 0 33.941L240.971 381.476c-9.373 9.372-24.569 9.372-33.942 0z"},"child":[]}]})(props);
}

const getCpuInfo = callable("get_cpu_info");
const getGpuInfo = callable("get_gpu_info");
const getTemps = callable("get_temps");
callable("set_cpu_max_freq");
callable("set_gpu_max_freq");
const getPresets = callable("get_presets");
const getPreset = callable("get_preset");
const savePreset = callable("save_preset");
const renamePreset = callable("rename_preset");
const deletePreset = callable("delete_preset");
const applyPreset = callable("apply_preset");
const getCurrentSettings = callable("get_current_settings");
const getFanCurve = callable("get_fan_curve");
const saveFanCurve = callable("set_fan_curve");
callable("set_fan_profile");
const getGameProfile = callable("get_game_profile");
const setGameProfile = callable("set_game_profile");
const getChargeMode = callable("get_charge_mode");
const applyChargeMode = callable("set_charge_mode");
const getGamepadProfile = callable("get_gamepad_profile");
const applyGamepadProfile = callable("set_gamepad_profile");
const getGpuDrivers = callable("get_gpu_drivers");
const getGpuCatalog = callable("get_gpu_catalog");
const installGpuDriver = callable("install_gpu_driver");
const removeGpuDriver = callable("remove_gpu_driver");
const setGpuDefault = callable("set_gpu_default");
const setGpuFavorite = callable("set_gpu_favorite");
const verifyGpuDriver = callable("verify_gpu_driver");
// The canonical "global" profile is owned by the ROCKNIX Perf Control tool
// (its profiles.json "active"). We read it as the source of truth and write it
// back when the user picks a profile here, so the two tools never disagree and a
// selection survives a game launch/exit.
const getActiveProfile = callable("get_active_profile");
const setActiveProfile = callable("set_active_profile");
const state = {
    runningAppId: 0,
    runningGameName: "",
    activePreset: "Default", // what's actually applied to hardware
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
// Detect which saved preset matches the live hardware clocks (per-policy CPU max
// + GPU max). Lets the panel reflect a profile applied OUTSIDE the plugin (e.g.
// the ROCKNIX "Perf Control" Tools app) instead of always defaulting the label
// to "Default". Returns null when the live clocks match no saved preset.
async function detectActivePreset() {
    try {
        const [names, cpu, gpu] = await Promise.all([getPresets(), getCpuInfo(), getGpuInfo()]);
        const liveCpu = {};
        for (const p of Object.keys(cpu))
            liveCpu[p] = cpu[p]?.max_freq ?? -1;
        for (const name of names) {
            const preset = await getPreset(name);
            if (!preset)
                continue;
            let defined = 0;
            let ok = true;
            for (const p of Object.keys(liveCpu)) {
                const want = preset[`cpu_policy${p}_max`];
                if (want == null)
                    continue;
                defined++;
                if (want !== liveCpu[p]) {
                    ok = false;
                    break;
                }
            }
            const gmax = preset.gpu_max;
            if (ok && gmax != null) {
                defined++;
                if (gmax !== gpu.max_freq)
                    ok = false;
            }
            if (ok && defined >= 2)
                return name;
        }
    }
    catch (e) {
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
async function resolveActivePreset() {
    try {
        const a = await getActiveProfile();
        if (a)
            return a;
    }
    catch (e) {
        // Perf Control not present / unreadable -> fall back to clock matching
    }
    return await detectActivePreset();
}
function getPolicyLabels(cpuInfo) {
    const policies = Object.keys(cpuInfo).sort((a, b) => Number(a) - Number(b));
    if (policies.length === 1)
        return { [policies[0]]: "CPU" };
    const sorted = [...policies].sort((a, b) => {
        const maxA = cpuInfo[a]?.available_frequencies?.slice(-1)[0] ?? 0;
        const maxB = cpuInfo[b]?.available_frequencies?.slice(-1)[0] ?? 0;
        return maxA - maxB;
    });
    const labels = {};
    sorted.forEach((p, i) => {
        if (sorted.length === 2) {
            labels[p] = i === 0 ? "Little" : "Big";
        }
        else if (sorted.length === 3) {
            labels[p] = i === 0 ? "Little" : i === 1 ? "Mid" : "Big";
        }
        else {
            labels[p] = `Cluster ${p}`;
        }
    });
    return labels;
}
const DEFAULT_FAN_CURVE = [
    { temp: 40000, speed: 51 },
    { temp: 60000, speed: 51 },
    { temp: 80000, speed: 153 },
];
const FanCurveEditor = ({ points, onChange, disabled }) => {
    const updateTemp = (index, temp) => {
        const updated = [...points];
        updated[index] = { ...updated[index], temp };
        updated.sort((a, b) => a.temp - b.temp);
        onChange(enforceMonotonic(updated));
    };
    const updateSpeed = (index, speed) => {
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
    const removePoint = (index) => {
        if (points.length <= 2)
            return;
        onChange(points.filter((_, i) => i !== index));
    };
    return (SP_JSX.jsxs("div", { children: [points.map((pt, i) => (SP_JSX.jsxs("div", { children: [SP_JSX.jsx(DFL.PanelSectionRow, { children: SP_JSX.jsx(DFL.SliderField, { label: `Point ${i} - Temp`, description: `${pt.temp / 1000}°C`, value: pt.temp, min: 30000, max: 100000, step: 1000, disabled: disabled, onChange: (val) => updateTemp(i, val) }) }), SP_JSX.jsx(DFL.PanelSectionRow, { children: SP_JSX.jsx(DFL.SliderField, { label: `Point ${i} - Speed`, description: `PWM ${pt.speed} (${Math.round(pt.speed / 255 * 100)}%)`, value: pt.speed, min: 0, max: 255, step: 1, disabled: disabled, onChange: (val) => updateSpeed(i, val) }) }), points.length > 2 && (SP_JSX.jsx(DFL.PanelSectionRow, { children: SP_JSX.jsxs(DFL.ButtonItem, { layout: "below", disabled: disabled, onClick: () => removePoint(i), children: [SP_JSX.jsx(FaTrash, {}), " Remove Point ", i] }) }))] }, i))), SP_JSX.jsx(DFL.PanelSectionRow, { children: SP_JSX.jsxs(DFL.ButtonItem, { layout: "below", disabled: disabled, onClick: addPoint, children: [SP_JSX.jsx(FaPlus, {}), " Add Point"] }) })] }));
};
function enforceMonotonic(points) {
    const result = points.map((p) => ({ ...p }));
    for (let i = 1; i < result.length; i++) {
        if (result[i].speed < result[i - 1].speed)
            result[i].speed = result[i - 1].speed;
    }
    for (let i = result.length - 2; i >= 0; i--) {
        if (result[i].speed > result[i + 1].speed)
            result[i].speed = result[i + 1].speed;
    }
    return result;
}
// Collapsible PanelSection: @decky/ui has no native collapse, so we draw a
// focusable header row (title + chevron) that toggles a controlled `open` flag
// and conditionally renders the body. Used to keep the heavy Underclocking and
// Fan Curve sections folded away by default.
const Collapsible = ({ title, open, onToggle, children }) => (SP_JSX.jsxs(DFL.PanelSection, { children: [SP_JSX.jsx(DFL.PanelSectionRow, { children: SP_JSX.jsx(DFL.ButtonItem, { layout: "below", onClick: onToggle, children: SP_JSX.jsxs("div", { style: { display: "flex", justifyContent: "space-between", alignItems: "center", width: "100%" }, children: [SP_JSX.jsx("span", { children: title }), open ? SP_JSX.jsx(FaChevronDown, {}) : SP_JSX.jsx(FaChevronRight, {})] }) }) }), open && children] }));
function Content() {
    const [cpuInfo, setCpuInfo] = SP_REACT.useState(null);
    const [gpuInfo, setGpuInfo] = SP_REACT.useState(null);
    const [cpuMaxFreqs, setCpuMaxFreqs] = SP_REACT.useState({});
    const [gpuMaxFreq, setGpuMaxFreqState] = SP_REACT.useState(0);
    const [liveCpuMax, setLiveCpuMax] = SP_REACT.useState({});
    const [liveGpuMax, setLiveGpuMax] = SP_REACT.useState(0);
    const [temps, setTemps] = SP_REACT.useState({ cpu: 0, gpu: 0 });
    const [presets, setPresetList] = SP_REACT.useState([]);
    const [selectedPreset, setSelectedPreset] = SP_REACT.useState(state.activePreset);
    const [editMode, setEditMode] = SP_REACT.useState(false);
    const [editName, setEditName] = SP_REACT.useState("");
    const [curvePoints, setCurvePoints] = SP_REACT.useState(DEFAULT_FAN_CURVE);
    const [runningAppId, setRunningAppId] = SP_REACT.useState(state.runningAppId);
    const [gameName, setGameName] = SP_REACT.useState(state.runningGameName);
    const [chargeAvail, setChargeAvail] = SP_REACT.useState(false);
    const [chargeMode, setChargeMode] = SP_REACT.useState("preserve");
    const [gpuDrvAvail, setGpuDrvAvail] = SP_REACT.useState(false);
    const [gpuDefault, setGpuDefaultState] = SP_REACT.useState("stock");
    const [gpuDrivers, setGpuDrivers] = SP_REACT.useState([]);
    const [gpuCatalog, setGpuCatalog] = SP_REACT.useState([]);
    const [gpuMsg, setGpuMsg] = SP_REACT.useState("");
    const [showGpuDriver, setShowGpuDriver] = SP_REACT.useState(false);
    const [gpAvail, setGpAvail] = SP_REACT.useState(false);
    const [gpProfile, setGpProfile] = SP_REACT.useState("xbox-elite");
    // Underclocking + Fan Curve are folded away by default; the user opens them
    // on demand. Keeps the panel short — Presets and Power are the common knobs.
    const [showUnderclock, setShowUnderclock] = SP_REACT.useState(false);
    const [showFanCurve, setShowFanCurve] = SP_REACT.useState(false);
    SP_REACT.useEffect(() => {
        getChargeMode().then((s) => { setChargeAvail(s.available); setChargeMode(s.mode); }).catch(() => { });
        getGamepadProfile().then((s) => { setGpAvail(s.available); setGpProfile(s.profile); }).catch(() => { });
        getGpuDrivers().then((d) => {
            setGpuDrvAvail(d.available);
            setGpuDefaultState(d.default || "stock");
            setGpuDrivers(d.drivers || []);
        }).catch(() => { });
    }, []);
    const refreshGpu = () => getGpuDrivers().then((d) => {
        setGpuDrvAvail(d.available);
        setGpuDefaultState(d.default || "stock");
        setGpuDrivers(d.drivers || []);
    }).catch(() => { });
    const handleGpuDefault = (id) => {
        setGpuDefaultState(id); // optimistic
        setGpuDefault(id).then((d) => {
            setGpuDefaultState(d.default || "stock");
            setGpuDrivers(d.drivers || []);
        }).catch(() => { });
    };
    const handleGpuFavorite = (id, on) => setGpuFavorite(id, on).then((d) => setGpuDrivers(d.drivers || [])).catch(() => { });
    const handleGpuRemove = (id) => {
        setGpuMsg(`Removing ${id}…`);
        removeGpuDriver(id).then(() => { setGpuMsg(""); refreshGpu(); }).catch(() => setGpuMsg("remove failed"));
    };
    const handleGpuVerify = (id) => {
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
    const handleGpuInstall = (id) => {
        setGpuMsg(`Installing ${id}…`);
        installGpuDriver(id).then((r) => { setGpuMsg(r.message); refreshGpu(); }).catch(() => setGpuMsg("install failed"));
    };
    const handleChargeMode = (mode) => {
        setChargeMode(mode); // optimistic
        applyChargeMode(mode).then((s) => { setChargeAvail(s.available); setChargeMode(s.mode); }).catch(() => { });
    };
    const handleGamepadProfile = (profile) => {
        setGpProfile(profile); // optimistic
        applyGamepadProfile(profile).then((s) => { setGpAvail(s.available); setGpProfile(s.profile); }).catch(() => { });
    };
    const refreshHardware = async () => {
        const [cpu, gpu, preset] = await Promise.all([getCpuInfo(), getGpuInfo(), getPreset(state.activePreset)]);
        setCpuInfo(cpu);
        setGpuInfo(gpu);
        const liveMax = {};
        for (const policy of Object.keys(cpu)) {
            liveMax[policy] = cpu[policy]?.max_freq ?? 0;
        }
        setLiveCpuMax(liveMax);
        setLiveGpuMax(gpu.max_freq);
        const presetMax = {};
        for (const policy of Object.keys(cpu)) {
            presetMax[policy] = preset?.[`cpu_policy${policy}_max`] ?? liveMax[policy];
        }
        setCpuMaxFreqs(presetMax);
        setGpuMaxFreqState(preset?.gpu_max ?? gpu.max_freq);
    };
    const refreshPresets = async () => {
        const list = await getPresets();
        if (!list.includes("Default"))
            list.unshift("Default");
        setPresetList(list);
    };
    const refreshFanCurve = async () => {
        const curve = await getFanCurve();
        if (curve.speeds.length > 0 && curve.temps.length > 0) {
            const pts = curve.temps.map((t, i) => ({
                temp: t, speed: curve.speeds[i] ?? 0,
            }));
            pts.sort((a, b) => a.temp - b.temp);
            setCurvePoints(pts);
        }
    };
    SP_REACT.useEffect(() => {
        (async () => {
            // Reflect the canonical active profile (Perf Control's "active", or the
            // live clocks as a fallback) before drawing, so the dropdown isn't stale.
            // Epoch-guarded: if the user picks a preset while this read is in
            // flight, the stale result must NOT snap the dropdown back.
            const epoch = selectionEpoch;
            const detected = await resolveActivePreset();
            if (detected && epoch === selectionEpoch) {
                state.activePreset = detected;
                setSelectedPreset(detected);
            }
            await refreshHardware();
            await refreshPresets();
            await refreshFanCurve();
        })();
        const interval = setInterval(() => {
            if (switching)
                return; // skip entire tick during profile switch to avoid RPC queue buildup
            if (state.runningAppId !== runningAppIdRef.current)
                setRunningAppId(state.runningAppId);
            if (state.runningGameName !== gameNameRef.current)
                setGameName(state.runningGameName);
            getTemps().then((t) => {
                setTemps((prev) => (prev.cpu === t.cpu && prev.gpu === t.gpu) ? prev : t);
            });
            getCpuInfo().then((cpu) => {
                const liveMax = {};
                for (const p of Object.keys(cpu))
                    liveMax[p] = cpu[p]?.max_freq ?? 0;
                setLiveCpuMax((prev) => {
                    const keys = Object.keys(liveMax);
                    if (keys.length === Object.keys(prev).length && keys.every((k) => prev[k] === liveMax[k]))
                        return prev;
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
    const saveRef = SP_REACT.useRef({ editMode, cpuMaxFreqs, gpuMaxFreq, editName, selectedPreset });
    saveRef.current = { editMode, cpuMaxFreqs, gpuMaxFreq, editName, selectedPreset };
    const selectedPresetRef = SP_REACT.useRef(selectedPreset);
    selectedPresetRef.current = selectedPreset;
    const runningAppIdRef = SP_REACT.useRef(runningAppId);
    runningAppIdRef.current = runningAppId;
    const gameNameRef = SP_REACT.useRef(gameName);
    gameNameRef.current = gameName;
    SP_REACT.useEffect(() => {
        return () => {
            const { editMode, cpuMaxFreqs, gpuMaxFreq, editName, selectedPreset } = saveRef.current;
            if (editMode) {
                getCurrentSettings().then((current) => {
                    for (const policy of Object.keys(cpuMaxFreqs)) {
                        current[`cpu_policy${policy}_max`] = cpuMaxFreqs[policy];
                    }
                    current.gpu_max = gpuMaxFreq;
                    const name = editName.trim() || selectedPreset;
                    savePreset(name, JSON.stringify(current)).then(() => applyPreset(name));
                });
            }
        };
    }, []);
    const handleSelectPreset = async (name) => {
        if (name === selectedPreset)
            return;
        selectionEpoch++;
        switching = true;
        try {
            setSelectedPreset(name);
            state.activePreset = name;
            // Make this selection the profile restored on game exit (otherwise a
            // change made mid-game is lost when the game quits) AND persist it as the
            // canonical global so Perf Control agrees and it survives reboots.
            state.preGamePreset = name;
            await applyPreset(name);
            await Promise.all([
                state.runningAppId > 0 ? setGameProfile(String(state.runningAppId), name) : Promise.resolve(),
                setActiveProfile(name),
                refreshHardware(),
                refreshFanCurve(),
            ]);
        }
        finally {
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
            current[`cpu_policy${policy}_max`] = cpuMaxFreqs[policy];
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
        if (selectedPreset === "Default")
            return;
        selectionEpoch++;
        await deletePreset(selectedPreset);
        setSelectedPreset("Default");
        state.activePreset = "Default";
        setEditMode(false);
        await refreshPresets();
    };
    const handleCpuMaxChange = async (policy, index) => {
        const freqs = cpuInfo?.[policy]?.available_frequencies;
        if (!freqs)
            return;
        const freq = freqs[index];
        setCpuMaxFreqs((prev) => ({ ...prev, [policy]: freq }));
    };
    const handleGpuMaxChange = async (index) => {
        const freqs = gpuInfo?.available_frequencies;
        if (!freqs)
            return;
        const freq = freqs[index];
        setGpuMaxFreqState(freq);
    };
    const handleCurveChange = async (points) => {
        setCurvePoints(points);
        const sorted = [...points].sort((a, b) => a.temp - b.temp);
        await saveFanCurve(JSON.stringify(sorted.map(p => p.speed)), JSON.stringify(sorted.map(p => p.temp)));
        const current = await getCurrentSettings();
        await savePreset(selectedPreset, JSON.stringify(current));
    };
    if (!cpuInfo || !gpuInfo) {
        return (SP_JSX.jsx(DFL.PanelSection, { title: "DUCKTALE-CONTROLS", children: SP_JSX.jsx(DFL.PanelSectionRow, { children: SP_JSX.jsx("div", { children: "Loading..." }) }) }));
    }
    return (SP_JSX.jsxs("div", { children: [runningAppId > 0 && (SP_JSX.jsx(DFL.PanelSection, { title: `Playing: ${gameName}` })), SP_JSX.jsxs(DFL.PanelSection, { title: "Presets", children: [SP_JSX.jsx(DFL.PanelSectionRow, { children: SP_JSX.jsx(DFL.DropdownItem, { rgOptions: presets.map((p) => ({ data: p, label: p })), selectedOption: selectedPreset, onChange: (opt) => handleSelectPreset(opt.data) }) }), !editMode ? (SP_JSX.jsxs(SP_JSX.Fragment, { children: [SP_JSX.jsx(DFL.PanelSectionRow, { children: SP_JSX.jsxs(DFL.ButtonItem, { layout: "below", onClick: () => { setEditName(selectedPreset); setEditMode(true); }, children: [SP_JSX.jsx(FaPen, {}), " Edit"] }) }), SP_JSX.jsx(DFL.PanelSectionRow, { children: SP_JSX.jsxs(DFL.ButtonItem, { layout: "below", onClick: handleCreatePreset, children: [SP_JSX.jsx(FaPlus, {}), " New Preset"] }) })] })) : (SP_JSX.jsxs(SP_JSX.Fragment, { children: [SP_JSX.jsx(DFL.PanelSectionRow, { children: SP_JSX.jsx(DFL.TextField, { label: "Rename Preset", value: editName, onChange: (e) => setEditName(e.target.value) }) }), SP_JSX.jsx(DFL.PanelSectionRow, { children: SP_JSX.jsx(DFL.ButtonItem, { layout: "below", onClick: handleExitEditMode, children: "Save" }) }), SP_JSX.jsx(DFL.PanelSectionRow, { children: SP_JSX.jsx(DFL.ButtonItem, { layout: "below", onClick: handleCancel, children: "Cancel" }) }), selectedPreset !== "Default" && (SP_JSX.jsx(DFL.PanelSectionRow, { children: SP_JSX.jsx(DFL.ButtonItem, { layout: "below", onClick: handleDeletePreset, children: "Delete" }) }))] }))] }), chargeAvail && (SP_JSX.jsx(DFL.PanelSection, { title: "Power", children: SP_JSX.jsx(DFL.PanelSectionRow, { children: SP_JSX.jsx(DFL.DropdownItem, { label: "Charging mode", rgOptions: [
                            { data: "full", label: "Full charge (100%)" },
                            { data: "preserve", label: "Battery care (80%)" },
                            { data: "bypass", label: "Bypass (run on AC)" },
                        ], selectedOption: chargeMode, onChange: (o) => handleChargeMode(o.data) }) }) })), gpAvail && (SP_JSX.jsx(DFL.PanelSection, { title: "Controller", children: SP_JSX.jsx(DFL.PanelSectionRow, { children: SP_JSX.jsx(DFL.DropdownItem, { label: "Gamepad profile", rgOptions: [
                            { data: "xbox-elite", label: "Xbox Elite (paddles)" },
                            { data: "ds5", label: "DualSense Edge (paddles)" },
                        ], selectedOption: gpProfile, onChange: (o) => handleGamepadProfile(o.data) }) }) })), SP_JSX.jsxs(Collapsible, { title: `Underclocking${temps.cpu || temps.gpu
                    ? ` · ${[
                        temps.cpu ? `CPU ${(temps.cpu / 1000).toFixed(0)}°C` : "",
                        temps.gpu ? `GPU ${(temps.gpu / 1000).toFixed(0)}°C` : "",
                    ].filter(Boolean).join("  ")}`
                    : ""}`, open: showUnderclock, onToggle: () => setShowUnderclock((v) => !v), children: [Object.keys(cpuInfo).sort((a, b) => Number(a) - Number(b)).map((policy) => {
                        const info = cpuInfo[policy];
                        if (!info || !info.available_frequencies.length)
                            return null;
                        const freqs = info.available_frequencies;
                        const currentMax = cpuMaxFreqs[policy] ?? freqs[freqs.length - 1];
                        const idx = freqs.indexOf(currentMax);
                        const labels = getPolicyLabels(cpuInfo);
                        const live = liveCpuMax[policy];
                        const liveStr = live && live !== currentMax ? ` (${Math.round(live / 1000)} MHz)` : "";
                        return (SP_JSX.jsx(DFL.PanelSectionRow, { children: SP_JSX.jsx(DFL.SliderField, { label: labels[policy], description: `${Math.round(currentMax / 1000)} MHz${liveStr}`, value: idx >= 0 ? idx : freqs.length - 1, min: 0, max: freqs.length - 1, step: 1, disabled: !editMode, onChange: (i) => handleCpuMaxChange(policy, i) }) }, policy));
                    }), SP_JSX.jsx(DFL.PanelSectionRow, { children: (() => {
                            const freqs = gpuInfo.available_frequencies;
                            const idx = freqs.indexOf(gpuMaxFreq);
                            const liveStr = liveGpuMax && liveGpuMax !== gpuMaxFreq ? ` (${Math.round(liveGpuMax / 1000000)} MHz)` : "";
                            return (SP_JSX.jsx(DFL.SliderField, { label: "GPU", description: `${Math.round(gpuMaxFreq / 1000000)} MHz${liveStr}`, value: idx >= 0 ? idx : freqs.length - 1, min: 0, max: freqs.length - 1, step: 1, disabled: !editMode, onChange: (i) => handleGpuMaxChange(i) }));
                        })() })] }), SP_JSX.jsx(Collapsible, { title: "Fan Curve", open: showFanCurve, onToggle: () => setShowFanCurve((v) => !v), children: SP_JSX.jsx(FanCurveEditor, { points: curvePoints, onChange: handleCurveChange, disabled: !editMode }) }), gpuDrvAvail && (SP_JSX.jsxs(Collapsible, { title: `GPU Driver · ${(() => {
                    const d = gpuDrivers.find((x) => x.id === gpuDefault);
                    const ver = d ? ` · Mesa ${d.mesa_version}` : "";
                    return `${gpuDefault === "stock" ? "stock" : gpuDefault}${ver}`;
                })()}`, open: showGpuDriver, onToggle: () => setShowGpuDriver((v) => !v), children: [SP_JSX.jsx(DFL.PanelSectionRow, { children: SP_JSX.jsx(DFL.DropdownItem, { label: "Active driver", rgOptions: gpuDrivers.map((d) => ({
                                data: d.id,
                                label: d.id === "stock"
                                    ? `Stock (system) · Mesa ${d.mesa_version}`
                                    : `${d.id} · Mesa ${d.mesa_version}${d.favorite ? " ★" : ""}`,
                            })), selectedOption: gpuDefault, onChange: (o) => handleGpuDefault(o.data) }) }), gpuDrivers.filter((d) => d.id !== "stock").map((d) => (SP_JSX.jsxs(DFL.PanelSectionRow, { children: [SP_JSX.jsxs(DFL.ButtonItem, { layout: "below", onClick: () => handleGpuFavorite(d.id, !d.favorite), children: [d.favorite ? "★" : "☆", " ", d.id] }), SP_JSX.jsxs(DFL.ButtonItem, { layout: "below", onClick: () => handleGpuRemove(d.id), children: [SP_JSX.jsx(FaTrash, {}), " Remove"] })] }, d.id))), SP_JSX.jsx(DFL.PanelSectionRow, { children: SP_JSX.jsx(DFL.ButtonItem, { layout: "below", onClick: () => handleGpuVerify(gpuDefault), children: "Verify active" }) }), SP_JSX.jsx(DFL.PanelSectionRow, { children: SP_JSX.jsx(DFL.ButtonItem, { layout: "below", onClick: handleGpuCatalog, children: "Refresh catalog (online)" }) }), gpuCatalog
                        .filter((c) => !gpuDrivers.some((d) => d.id === c.id))
                        .map((c) => (SP_JSX.jsx(DFL.PanelSectionRow, { children: SP_JSX.jsxs(DFL.ButtonItem, { layout: "below", onClick: () => handleGpuInstall(c.id), children: ["\u2B07 ", c.id, " \u00B7 ", c.mesa_version, " (", c.channel, ")"] }) }, c.id))), gpuMsg && (SP_JSX.jsx(DFL.PanelSectionRow, { children: SP_JSX.jsx("div", { style: { fontSize: "0.8em", opacity: 0.8, padding: "0 16px" }, children: gpuMsg }) }))] }))] }));
}
var index = definePlugin(() => {
    // Seed the baseline from the canonical active profile at plugin load. It
    // otherwise only resolves when the QAM panel mounts, so launching a game
    // without ever opening the panel would leave state.activePreset at the init
    // "Default".
    const seedEpoch = selectionEpoch;
    resolveActivePreset().then((p) => {
        if (p && seedEpoch === selectionEpoch) {
            state.activePreset = p;
            state.preGamePreset = p;
        }
    });
    const reg = SteamClient.GameSessions.RegisterForAppLifetimeNotifications(async (e) => {
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
            if (live && baselineEpoch === selectionEpoch)
                state.activePreset = live;
            state.preGamePreset = state.activePreset; // remember the baseline before this game
            state.runningAppId = e.unAppID;
            const app = appStore.GetAppOverviewByAppID(e.unAppID);
            state.runningGameName = app?.display_name ?? String(e.unAppID);
            const preset = await getGameProfile(String(e.unAppID));
            if (preset) {
                state.activePreset = preset;
                applyPreset(preset);
            }
        }
        else {
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
            if (restoreEpoch !== selectionEpoch)
                return;
            const restore = canonical || state.preGamePreset || "Default";
            state.activePreset = restore;
            applyPreset(restore);
        }
    });
    return {
        name: "DUCKTALE-CONTROLS",
        title: SP_JSX.jsx("div", { children: "DUCKTALE-CONTROLS" }),
        content: SP_JSX.jsx(Content, {}),
        icon: SP_JSX.jsx(FaCog, {}),
        onDismount() { reg.unregister(); }
    };
});

export { index as default };
//# sourceMappingURL=index.js.map
