import {
  Button,
  ButtonItem,
  Focusable,
  PanelSection,
  PanelSectionRow,
  TextField,
  afterPatch,
  appDetailsClasses,
  basicAppDetailsSectionStylerClasses,
  createReactTreePatcher,
  findInReactTree,
  joinClassNames,
  playSectionClasses,
  staticClasses,
} from "@decky/ui";
import { callable, definePlugin, routerHook } from "@decky/api";
import { useEffect, useState } from "react";
import { FaCloudDownloadAlt } from "react-icons/fa";

/* ------------------------------------------------------------------ backend */

interface Settings {
  host: string;
  sunshine_port: number;
  sunshine_user: string;
  sunshine_pass: string;
  sunshine_app: string;
  shortcut_appid: number;
  resolved_host?: string;
  moonlight_installed?: boolean;
  has_password?: boolean;
}

const getSettings = callable<[], Settings>("get_settings");
const setSettings = callable<[patch: Partial<Settings>], Settings>("set_settings");
const getHostStatus = callable<[], { ok: boolean; host?: string; hostname?: string; state?: string; busy?: boolean; reason?: string }>("get_host_status");
const prepareStream = callable<[appid: number, game_name: string], { ok: boolean; step?: string; error?: string; host?: string; app?: string }>("prepare_stream");
// The plugin UI runs inside Steam's JS context, whose console cannot be read
// from the build host, so the patch reports each step through the backend and
// they land in the journal. This is what located every placement bug.
const diag = callable<[message: string], boolean>("diag");

const RUNNER = "/storage/homebrew/plugins/ducktale-stream/runner/ducktale-stream-run.sh";
const SHORTCUT_NAME = "DUCKTALE Stream";

/* --------------------------------------------------------------- Steam side */

// Created ONCE and generic: it carries no per-game data. Everything about the
// game travels through the backend's launch file, because this Steam build
// silently drops the "VAR=value %command%" env prefix of a shortcut's launch
// options - the very thing that kills MoonDeck's runner on this device.
async function ensureShortcut(current: number): Promise<number> {
  if (current) {
    const overview = (window as any).appStore?.GetAppOverviewByAppID(current);
    if (overview) return current;
  }
  const appid: number = await (window as any).SteamClient.Apps.AddShortcut(
    SHORTCUT_NAME, RUNNER, "", "");
  if (!appid) throw new Error("AddShortcut returned nothing");
  await (window as any).SteamClient.Apps.SetShortcutName(appid, SHORTCUT_NAME);
  await (window as any).SteamClient.Apps.SetAppHidden?.(appid, true);
  await setSettings({ shortcut_appid: appid });
  return appid;
}

// Steam itself knows which machines have the game installed: per_client_data
// lists every client of the account, clientid "0" being this device. Verified
// on device: DayZ reports {clientid:"0", name:"This machine"} alongside
// {clientid:"6442...", name:"PC-MARC", installed:true}.
function installedOnHost(appid: number): { yes: boolean; where: string } {
  try {
    const remote = (window as any).appStore?.GetAppOverviewByAppID(appid)?.remote_per_client_data;
    for (const client of Array.from((remote ?? []) as any[])) {
      if (client?.installed) return { yes: true, where: client?.client_name || "PC" };
    }
  } catch (e) {
    console.error("[ducktale-stream] installedOnHost", e);
  }
  return { yes: false, where: "" };
}

async function launchStream(appid: number, name: string) {
  const staged = await prepareStream(appid, name);
  if (!staged.ok) {
    // Loud on purpose: a silent no-op is exactly what made MoonDeck impossible
    // to diagnose from the couch.
    (window as any).SteamClient?.Toaster?.ToastNotification?.({
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
  (window as any).SteamClient.Apps.RunGame(String(shortcut), "", -1, 100);
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

function StreamButton({ appid, name }: { appid: number; name: string }) {
  const [busy, setBusy] = useState(false);
  return (
    <>
      <style>
        {`.${CONTAINER_CLASS} {
             position: absolute;
             bottom: 2.8vw;
             right: 56px;
             z-index: 100;
           }`}
      </style>
      <Focusable className={joinClassNames(basicAppDetailsSectionStylerClasses.AppButtons, CONTAINER_CLASS)}>
        <Button
          disabled={busy}
          className={playSectionClasses.MenuButton}
          onClick={() => { setBusy(true); launchStream(appid, name).finally(() => setBusy(false)); }}
        >
          <span style={{ display: "flex", alignItems: "center", gap: "8px", whiteSpace: "nowrap" }}>
            <FaCloudDownloadAlt /> Stream
          </span>
        </Button>
      </Focusable>
    </>
  );
}

// Structure taken from MoonDeck's own route patch, the only shape proven
// against this Steam UI: addPatch hands over the TREE (reading the appid from
// props.path yields the literal ":appid", which is why the first attempt
// injected nothing), and the appid comes from the `overview` inside it.
function patchAppPage(tree: any) {
  const routeProps = findInReactTree(tree, (x: any) => x?.renderFunc);
  if (!routeProps) { diag("patch: renderFunc NOT found"); return tree; }

  let appid: number | undefined;
  let name: string | undefined;

  const handler = createReactTreePatcher([
    (inner: any) => {
      const children = findInReactTree(inner, (x: any) => x?.props?.children?.props?.overview)?.props?.children;
      const overview = children?.props?.overview;
      if (typeof overview?.appid !== "number") { diag("stage1: overview NOT found"); return null; }
      appid = overview.appid;
      name = typeof overview.display_name === "string" ? overview.display_name : String(appid);
      return children;
    },
  ], (_: any, ret?: any) => {
    if (typeof appid !== "number") return ret;
    if (!installedOnHost(appid).yes) return ret;   // host-installed games only

    const parent = findInReactTree(ret, (x: any) =>
      Array.isArray(x?.props?.children) &&
      x?.props?.className?.includes(appDetailsClasses.InnerContainer));
    if (!parent) { diag("render: InnerContainer NOT found"); return ret; }
    if (parent.props.children.some((c: any) => c?.props?.["data-ducktale-stream"])) return ret;

    parent.props.children.push(
      <div data-ducktale-stream="1">
        <StreamButton appid={appid} name={name ?? String(appid)} />
      </div>);
    diag(`render: button injected for ${appid}`);
    return ret;
  });

  afterPatch(routeProps, "renderFunc", handler);
  return tree;
}

/* ----------------------------------------------------------------- QAM page */

function Content() {
  const [settings, setLocal] = useState<Settings | null>(null);
  const [status, setStatus] = useState<string>("…");
  const [user, setUser] = useState("");
  const [pass, setPass] = useState("");
  const [app, setApp] = useState(SHORTCUT_NAME);
  const [host, setHost] = useState("");

  const refreshStatus = () =>
    getHostStatus()
      .then((h) => setStatus(h.ok ? `${h.hostname} — ${h.busy ? "occupé" : "prêt"}` : `injoignable (${h.reason})`))
      .catch(() => setStatus("injoignable"));

  useEffect(() => {
    getSettings().then((s) => {
      setLocal(s);
      setUser(s.sunshine_user || "");
      setApp(s.sunshine_app || SHORTCUT_NAME);
      setHost(s.host || "");
    }).catch(() => {});
    refreshStatus();
  }, []);

  const save = async () => {
    setLocal(await setSettings({ host, sunshine_user: user, sunshine_pass: pass, sunshine_app: app }));
    setPass("");
    refreshStatus();
  };

  return (
    <PanelSection title="Hôte de streaming">
      <PanelSectionRow>
        <div style={{ fontSize: "12px", opacity: 0.8 }}>
          État : {status}
          {settings && !settings.moonlight_installed && " — /usr/bin/moonlight absent !"}
        </div>
      </PanelSectionRow>
      <PanelSectionRow>
        <TextField label="Adresse (vide = celle de Moonlight)" value={host}
                   onChange={(e) => setHost(e.target.value)} />
      </PanelSectionRow>
      <PanelSectionRow>
        <TextField label="Utilisateur Sunshine" value={user}
                   onChange={(e) => setUser(e.target.value)} />
      </PanelSectionRow>
      <PanelSectionRow>
        <TextField label={settings?.has_password ? "Mot de passe (enregistré)" : "Mot de passe Sunshine"}
                   bIsPassword value={pass} onChange={(e) => setPass(e.target.value)} />
      </PanelSectionRow>
      <PanelSectionRow>
        <TextField label="Nom de l'app Sunshine" value={app}
                   onChange={(e) => setApp(e.target.value)} />
      </PanelSectionRow>
      <PanelSectionRow>
        <ButtonItem layout="below" onClick={save}>Enregistrer</ButtonItem>
      </PanelSectionRow>
    </PanelSection>
  );
}

export default definePlugin(() => {
  const patch = routerHook.addPatch("/library/app/:appid", patchAppPage);
  return {
    name: "DUCKTALE-STREAM",
    titleView: <div className={staticClasses.Title}>DUCKTALE-STREAM</div>,
    content: <Content />,
    icon: <FaCloudDownloadAlt />,
    onDismount() {
      routerHook.removePatch("/library/app/:appid", patch);
    },
  };
});
