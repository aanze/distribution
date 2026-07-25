import {
  ButtonItem,
  PanelSection,
  PanelSectionRow,
  TextField,
  ToggleField,
  staticClasses,
  findInReactTree,
  afterPatch,
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

const RUNNER = "/storage/homebrew/plugins/ducktale-stream/runner/ducktale-stream-run.sh";
const SHORTCUT_NAME = "DUCKTALE Stream";

/* --------------------------------------------------------------- Steam side */

// The shortcut is created ONCE and is generic: it carries no per-game data.
// Everything about the game being launched goes through the backend's launch
// file. MoonDeck puts it in the shortcut's launch options as a "VAR=value
// %command%" env prefix, and on this Steam build those variables never reach
// the process - its runner dies on "Failed to parse runner type!" every time.
async function ensureShortcut(current: number): Promise<number> {
  if (current) {
    const overview = (window as any).appStore?.GetAppOverviewByAppID(current);
    if (overview) return current;   // still there, reuse it
  }
  const appid: number = await (window as any).SteamClient.Apps.AddShortcut(
    SHORTCUT_NAME, RUNNER, "", "");
  if (!appid) throw new Error("AddShortcut returned nothing");
  await (window as any).SteamClient.Apps.SetShortcutName(appid, SHORTCUT_NAME);
  // Hidden from the library: it is plumbing, not a game the user browses to.
  await (window as any).SteamClient.Apps.SetAppHidden?.(appid, true);
  await setSettings({ shortcut_appid: appid });
  return appid;
}

// A game qualifies when Steam itself reports it installed on another machine.
// per_client_data lists every client of the account; clientid "0" is this
// device. Device-checked: DayZ shows {clientid:"0", name:"This machine"} and
// {clientid:"6442...", name:"PC-MARC", installed:true}.
function installedOnHost(appid: number): { yes: boolean; where: string } {
  try {
    const overview = (window as any).appStore?.GetAppOverviewByAppID(appid);
    const remote = overview?.remote_per_client_data;
    if (!remote) return { yes: false, where: "" };
    for (const client of Array.from(remote as any[])) {
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
    // Deliberately noisy: a silent no-op is exactly the failure mode that made
    // MoonDeck impossible to diagnose from the couch.
    (window as any).SteamClient?.Toaster?.ToastNotification?.({
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
  (window as any).SteamClient.Apps.RunGame(String(shortcut), "", -1, 100);
}

/* ------------------------------------------------- button on the game page */

function StreamButton({ appid, name, where }: { appid: number; name: string; where: string }) {
  return (
    <button
      className="ducktale-stream-button"
      style={{
        marginLeft: "8px", padding: "0 14px", minHeight: "40px",
        borderRadius: "2px", border: "none", cursor: "pointer",
        background: "rgba(255,255,255,.12)", color: "#fff",
        display: "flex", alignItems: "center", gap: "6px",
      }}
      onClick={() => launchStream(appid, name)}
      title={`Streamer depuis ${where}`}
    >
      <FaCloudDownloadAlt /> Stream
    </button>
  );
}

// Steam's React tree is not a stable API, so this looks for the node holding
// the game's action buttons and appends ours. Every failure path logs, so the
// anchor can be re-found from DevTools instead of guessed at.
function patchAppPage(props: any) {
  afterPatch(props.children.props, "renderFunc", (_: any, ret: any) => {
    const appid = Number(props.path?.split("/").pop());
    if (!appid) return ret;

    const { yes, where } = installedOnHost(appid);
    if (!yes) return ret;

    const overview = (window as any).appStore?.GetAppOverviewByAppID(appid);
    const name = overview?.display_name || String(appid);

    const container = findInReactTree(ret, (node: any) =>
      Array.isArray(node?.props?.children) &&
      node.props.children.some((child: any) =>
        child?.props?.childFocusDisabled !== undefined || child?.props?.onOKActionDescription));

    if (!container) {
      console.warn("[ducktale-stream] action-button container not found for", appid);
      return ret;
    }
    if (!container.props.children.some((c: any) => c?.props?.className === "ducktale-stream-button")) {
      container.props.children.push(
        <StreamButton appid={appid} name={name} where={where} />);
    }
    return ret;
  });
  return props;
}

/* ----------------------------------------------------------------- QAM page */

function Content() {
  const [settings, setLocal] = useState<Settings | null>(null);
  const [status, setStatus] = useState<string>("…");
  const [user, setUser] = useState("");
  const [pass, setPass] = useState("");
  const [app, setApp] = useState(SHORTCUT_NAME);
  const [host, setHost] = useState("");

  useEffect(() => {
    getSettings().then((s) => {
      setLocal(s);
      setUser(s.sunshine_user || "");
      setApp(s.sunshine_app || SHORTCUT_NAME);
      setHost(s.host || "");
    }).catch(() => {});
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
    getHostStatus().then((h) =>
      setStatus(h.ok ? `${h.hostname} — ${h.busy ? "occupé" : "prêt"}` : `injoignable (${h.reason})`)
    ).catch(() => {});
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
