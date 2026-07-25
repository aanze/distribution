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
// The plugin UI runs inside Steam's JS context, whose console cannot be read
// from the build host, so the patch reports each step through the backend and
// they land in the journal. This is what located every placement bug.
const diag = callable("diag");
const RUNNER = "/storage/homebrew/plugins/ducktale-stream/runner/ducktale-stream-run.sh";
const SHORTCUT_NAME = "DUCKTALE Stream";
/* --------------------------------------------------------------- Steam side */
// Created ONCE and generic: it carries no per-game data. Everything about the
// game travels through the backend's launch file, because this Steam build
// silently drops the "VAR=value %command%" env prefix of a shortcut's launch
// options - the very thing that kills MoonDeck's runner on this device.
async function ensureShortcut(current) {
    if (current) {
        const overview = window.appStore?.GetAppOverviewByAppID(current);
        if (overview)
            return current;
    }
    const appid = await window.SteamClient.Apps.AddShortcut(SHORTCUT_NAME, RUNNER, "", "");
    if (!appid)
        throw new Error("AddShortcut returned nothing");
    await window.SteamClient.Apps.SetShortcutName(appid, SHORTCUT_NAME);
    await window.SteamClient.Apps.SetAppHidden?.(appid, true);
    await setSettings({ shortcut_appid: appid });
    return appid;
}
// Steam itself knows which machines have the game installed: per_client_data
// lists every client of the account, clientid "0" being this device. Verified
// on device: DayZ reports {clientid:"0", name:"This machine"} alongside
// {clientid:"6442...", name:"PC-MARC", installed:true}.
function installedOnHost(appid) {
    try {
        const remote = window.appStore?.GetAppOverviewByAppID(appid)?.remote_per_client_data;
        for (const client of Array.from((remote ?? []))) {
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
        // Loud on purpose: a silent no-op is exactly what made MoonDeck impossible
        // to diagnose from the couch.
        window.SteamClient?.Toaster?.ToastNotification?.({
            title: "DUCKTALE Stream",
            body: `Échec (${staged.step}) : ${staged.error}`,
            duration: 8000,
        });
        diag(`launch: prepare failed at ${staged.step}: ${staged.error}`);
        return;
    }
    const shortcut = await ensureShortcut((await getSettings()).shortcut_appid);
    diag(`launch: running shortcut ${shortcut} for ${name}`);
    // Steam runs it, so gamescope focuses it. Launching moonlight from the
    // backend streams correctly but stays behind the Steam UI - verified on
    // device in X11 and as a native Wayland client on gamescope-0.
    window.SteamClient.Apps.RunGame(String(shortcut), "", -1, 100);
}
/* ------------------------------------------------- button on the game page */
// Placement, learned the hard way (three failures on device, 2026-07-25):
//  * inserted in page flow it lands under the full-screen hero art, measured at
//    y=1609 in an 844px-tall window - off-screen;
//  * position:fixed is neutralised by a CSS transform on one of Steam's
//    ancestors, which re-anchors it (measured at y=1441, also off-screen);
//  * portalling it to the popup's <body> escapes both, but also escapes Steam's
//    focus tree: the gamepad could no longer reach ANY button and the device
//    went touch-only.
// So: stay in the React tree (gamepad keeps working) and lift it over the
// artwork with absolute CSS. This is MoonDeck's shape, and the only one that
// satisfies all three constraints.
const CONTAINER_CLASS = "ducktale-stream-container";
function StreamButton({ appid, name }) {
    const [busy, setBusy] = SP_REACT.useState(false);
    return (SP_JSX.jsxs(SP_JSX.Fragment, { children: [SP_JSX.jsx("style", { children: `.${CONTAINER_CLASS} {
             position: absolute;
             bottom: 2.8vw;
             right: 56px;
             z-index: 100;
           }` }), SP_JSX.jsx(DFL.Focusable, { className: DFL.joinClassNames(DFL.basicAppDetailsSectionStylerClasses.AppButtons, CONTAINER_CLASS), children: SP_JSX.jsx(DFL.Button, { disabled: busy, className: DFL.playSectionClasses.MenuButton, onClick: () => { setBusy(true); launchStream(appid, name).finally(() => setBusy(false)); }, children: SP_JSX.jsxs("span", { style: { display: "flex", alignItems: "center", gap: "8px", whiteSpace: "nowrap" }, children: [SP_JSX.jsx(FaCloudDownloadAlt, {}), " Stream"] }) }) })] }));
}
// Structure taken from MoonDeck's own route patch, the only shape proven
// against this Steam UI: addPatch hands over the TREE (reading the appid from
// props.path yields the literal ":appid", which is why the first attempt
// injected nothing), and the appid comes from the `overview` inside it.
function patchAppPage(tree) {
    const routeProps = DFL.findInReactTree(tree, (x) => x?.renderFunc);
    if (!routeProps) {
        diag("patch: renderFunc NOT found");
        return tree;
    }
    let appid;
    let name;
    const handler = DFL.createReactTreePatcher([
        (inner) => {
            const children = DFL.findInReactTree(inner, (x) => x?.props?.children?.props?.overview)?.props?.children;
            const overview = children?.props?.overview;
            if (typeof overview?.appid !== "number") {
                diag("stage1: overview NOT found");
                return null;
            }
            appid = overview.appid;
            name = typeof overview.display_name === "string" ? overview.display_name : String(appid);
            return children;
        },
    ], (_, ret) => {
        if (typeof appid !== "number")
            return ret;
        if (!installedOnHost(appid).yes)
            return ret; // host-installed games only
        const parent = DFL.findInReactTree(ret, (x) => Array.isArray(x?.props?.children) &&
            x?.props?.className?.includes(DFL.appDetailsClasses.InnerContainer));
        if (!parent) {
            diag("render: InnerContainer NOT found");
            return ret;
        }
        if (parent.props.children.some((c) => c?.props?.["data-ducktale-stream"]))
            return ret;
        parent.props.children.push(SP_JSX.jsx("div", { "data-ducktale-stream": "1", children: SP_JSX.jsx(StreamButton, { appid: appid, name: name ?? String(appid) }) }));
        diag(`render: button injected for ${appid}`);
        return ret;
    });
    DFL.afterPatch(routeProps, "renderFunc", handler);
    return tree;
}
/* ----------------------------------------------------------------- QAM page */
function Content() {
    const [settings, setLocal] = SP_REACT.useState(null);
    const [status, setStatus] = SP_REACT.useState("…");
    const [user, setUser] = SP_REACT.useState("");
    const [pass, setPass] = SP_REACT.useState("");
    const [app, setApp] = SP_REACT.useState(SHORTCUT_NAME);
    const [host, setHost] = SP_REACT.useState("");
    const refreshStatus = () => getHostStatus()
        .then((h) => setStatus(h.ok ? `${h.hostname} — ${h.busy ? "occupé" : "prêt"}` : `injoignable (${h.reason})`))
        .catch(() => setStatus("injoignable"));
    SP_REACT.useEffect(() => {
        getSettings().then((s) => {
            setLocal(s);
            setUser(s.sunshine_user || "");
            setApp(s.sunshine_app || SHORTCUT_NAME);
            setHost(s.host || "");
        }).catch(() => { });
        refreshStatus();
    }, []);
    const save = async () => {
        setLocal(await setSettings({ host, sunshine_user: user, sunshine_pass: pass, sunshine_app: app }));
        setPass("");
        refreshStatus();
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
