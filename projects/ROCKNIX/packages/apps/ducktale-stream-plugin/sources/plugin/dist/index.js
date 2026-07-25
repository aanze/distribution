const manifest = {"name":"DUCKTALE-STREAM"};
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
const routerHook = api.routerHook;
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
    var attr = props.attr,
      size = props.size,
      title = props.title,
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
function FaCloudDownloadAlt (props) {
  return GenIcon({"attr":{"viewBox":"0 0 640 512"},"child":[{"tag":"path","attr":{"d":"M537.6 226.6c4.1-10.7 6.4-22.4 6.4-34.6 0-53-43-96-96-96-19.7 0-38.1 6-53.3 16.2C367 64.2 315.3 32 256 32c-88.4 0-160 71.6-160 160 0 2.7.1 5.4.2 8.1C40.2 219.8 0 273.2 0 336c0 79.5 64.5 144 144 144h368c70.7 0 128-57.3 128-128 0-61.9-44-113.6-102.4-125.4zm-132.9 88.7L299.3 420.7c-6.2 6.2-16.4 6.2-22.6 0L171.3 315.3c-10.1-10.1-2.9-27.3 11.3-27.3H248V176c0-8.8 7.2-16 16-16h48c8.8 0 16 7.2 16 16v112h65.4c14.2 0 21.4 17.2 11.3 27.3z"},"child":[]}]})(props);
}

const getSettings = callable("get_settings");
const setSettings = callable("set_settings");
const getHostStatus = callable("get_host_status");
const prepareStream = callable("prepare_stream");
const RUNNER = "/storage/homebrew/plugins/ducktale-stream/runner/ducktale-stream-run.sh";
const SHORTCUT_NAME = "DUCKTALE Stream";
/* --------------------------------------------------------------- Steam side */
// The shortcut is created ONCE and is generic: it carries no per-game data.
// Everything about the game being launched goes through the backend's launch
// file. MoonDeck puts it in the shortcut's launch options as a "VAR=value
// %command%" env prefix, and on this Steam build those variables never reach
// the process - its runner dies on "Failed to parse runner type!" every time.
async function ensureShortcut(current) {
    if (current) {
        const overview = window.appStore?.GetAppOverviewByAppID(current);
        if (overview)
            return current; // still there, reuse it
    }
    const appid = await window.SteamClient.Apps.AddShortcut(SHORTCUT_NAME, RUNNER, "", "");
    if (!appid)
        throw new Error("AddShortcut returned nothing");
    await window.SteamClient.Apps.SetShortcutName(appid, SHORTCUT_NAME);
    // Hidden from the library: it is plumbing, not a game the user browses to.
    await window.SteamClient.Apps.SetAppHidden?.(appid, true);
    await setSettings({ shortcut_appid: appid });
    return appid;
}
// A game qualifies when Steam itself reports it installed on another machine.
// per_client_data lists every client of the account; clientid "0" is this
// device. Device-checked: DayZ shows {clientid:"0", name:"This machine"} and
// {clientid:"6442...", name:"PC-MARC", installed:true}.
function installedOnHost(appid) {
    try {
        const overview = window.appStore?.GetAppOverviewByAppID(appid);
        const remote = overview?.remote_per_client_data;
        if (!remote)
            return { yes: false, where: "" };
        for (const client of Array.from(remote)) {
            if (client?.installed)
                return { yes: true, where: client?.client_name || "PC" };
        }
    }
    catch (e) {
        console.error("[ducktale-stream] installedOnHost", e);
    }
    return { yes: false, where: "" };
}
async function launchStream(appid, name) {
    const staged = await prepareStream(appid, name);
    if (!staged.ok) {
        // Deliberately noisy: a silent no-op is exactly the failure mode that made
        // MoonDeck impossible to diagnose from the couch.
        window.SteamClient?.Toaster?.ToastNotification?.({
            title: "DUCKTALE Stream",
            body: `Échec (${staged.step}) : ${staged.error}`,
            duration: 8000,
        });
        console.error("[ducktale-stream] prepare_stream failed", staged);
        return;
    }
    const settings = await getSettings();
    const shortcut = await ensureShortcut(settings.shortcut_appid);
    // Steam runs it -> gamescope focuses it. That indirection is the only way to
    // get the Moonlight window in front: launched from the backend it streams
    // fine but stays behind the Steam UI (verified on device, X11 and Wayland).
    window.SteamClient.Apps.RunGame(String(shortcut), "", -1, 100);
}
/* ------------------------------------------------- button on the game page */
function StreamButton({ appid, name, where }) {
    return (SP_JSX.jsxs("button", { className: "ducktale-stream-button", style: {
            marginLeft: "8px", padding: "0 14px", minHeight: "40px",
            borderRadius: "2px", border: "none", cursor: "pointer",
            background: "rgba(255,255,255,.12)", color: "#fff",
            display: "flex", alignItems: "center", gap: "6px",
        }, onClick: () => launchStream(appid, name), title: `Streamer depuis ${where}`, children: [SP_JSX.jsx(FaCloudDownloadAlt, {}), " Stream"] }));
}
// Steam's React tree is not a stable API, so this looks for the node holding
// the game's action buttons and appends ours. Every failure path logs, so the
// anchor can be re-found from DevTools instead of guessed at.
function patchAppPage(props) {
    DFL.afterPatch(props.children.props, "renderFunc", (_, ret) => {
        const appid = Number(props.path?.split("/").pop());
        if (!appid)
            return ret;
        const { yes, where } = installedOnHost(appid);
        if (!yes)
            return ret;
        const overview = window.appStore?.GetAppOverviewByAppID(appid);
        const name = overview?.display_name || String(appid);
        const container = DFL.findInReactTree(ret, (node) => Array.isArray(node?.props?.children) &&
            node.props.children.some((child) => child?.props?.childFocusDisabled !== undefined || child?.props?.onOKActionDescription));
        if (!container) {
            console.warn("[ducktale-stream] action-button container not found for", appid);
            return ret;
        }
        if (!container.props.children.some((c) => c?.props?.className === "ducktale-stream-button")) {
            container.props.children.push(SP_JSX.jsx(StreamButton, { appid: appid, name: name, where: where }));
        }
        return ret;
    });
    return props;
}
/* ----------------------------------------------------------------- QAM page */
function Content() {
    const [settings, setLocal] = SP_REACT.useState(null);
    const [status, setStatus] = SP_REACT.useState("…");
    const [user, setUser] = SP_REACT.useState("");
    const [pass, setPass] = SP_REACT.useState("");
    const [app, setApp] = SP_REACT.useState(SHORTCUT_NAME);
    const [host, setHost] = SP_REACT.useState("");
    SP_REACT.useEffect(() => {
        getSettings().then((s) => {
            setLocal(s);
            setUser(s.sunshine_user || "");
            setApp(s.sunshine_app || SHORTCUT_NAME);
            setHost(s.host || "");
        }).catch(() => { });
        getHostStatus().then((h) => {
            setStatus(h.ok ? `${h.hostname} — ${h.busy ? "occupé" : "prêt"}` : `injoignable (${h.reason})`);
        }).catch(() => setStatus("injoignable"));
    }, []);
    const save = async () => {
        const saved = await setSettings({
            host, sunshine_user: user, sunshine_pass: pass, sunshine_app: app,
        });
        setLocal(saved);
        setPass("");
        getHostStatus().then((h) => setStatus(h.ok ? `${h.hostname} — ${h.busy ? "occupé" : "prêt"}` : `injoignable (${h.reason})`)).catch(() => { });
    };
    return (SP_JSX.jsxs(DFL.PanelSection, { title: "H\u00F4te de streaming", children: [SP_JSX.jsx(DFL.PanelSectionRow, { children: SP_JSX.jsxs("div", { style: { fontSize: "12px", opacity: 0.8 }, children: ["\u00C9tat : ", status, settings && !settings.moonlight_installed && " — /usr/bin/moonlight absent !"] }) }), SP_JSX.jsx(DFL.PanelSectionRow, { children: SP_JSX.jsx(DFL.TextField, { label: "Adresse (vide = celle de Moonlight)", value: host, onChange: (e) => setHost(e.target.value) }) }), SP_JSX.jsx(DFL.PanelSectionRow, { children: SP_JSX.jsx(DFL.TextField, { label: "Utilisateur Sunshine", value: user, onChange: (e) => setUser(e.target.value) }) }), SP_JSX.jsx(DFL.PanelSectionRow, { children: SP_JSX.jsx(DFL.TextField, { label: settings?.has_password ? "Mot de passe (enregistré)" : "Mot de passe Sunshine", bIsPassword: true, value: pass, onChange: (e) => setPass(e.target.value) }) }), SP_JSX.jsx(DFL.PanelSectionRow, { children: SP_JSX.jsx(DFL.TextField, { label: "Nom de l'app Sunshine", value: app, onChange: (e) => setApp(e.target.value) }) }), SP_JSX.jsx(DFL.PanelSectionRow, { children: SP_JSX.jsx(DFL.ButtonItem, { layout: "below", onClick: save, children: "Enregistrer" }) })] }));
}
var index = definePlugin(() => {
    const patch = routerHook.addPatch("/library/app/:appid", patchAppPage);
    return {
        name: "DUCKTALE-STREAM",
        titleView: SP_JSX.jsx("div", { className: DFL.staticClasses.Title, children: "DUCKTALE-STREAM" }),
        content: SP_JSX.jsx(Content, {}),
        icon: SP_JSX.jsx(FaCloudDownloadAlt, {}),
        onDismount() {
            routerHook.removePatch("/library/app/:appid", patch);
        },
    };
});

export { index as default };
//# sourceMappingURL=index.js.map
