# steamlike — ROCKNIX Steam-style EmulationStation theme

Closest-feel-to-Steam-Big-Picture theme for the ROCKNIX EmulationStation
(Batocera-lineage) engine, `formatVersion 7`.

## Layout
- **System view** = a horizontal **tab carousel** across the top (Steam tab bar),
  a random-game **hero** backdrop (`{system:random:fanart}`), the focused
  system name + game count, clock and help bar.
- **Gamelist view** = Steam focused-game screen: full-bleed **hero**
  (`{game:fanart}`), game list on the left, big **logo** treatment
  (`{game:wheel}` → `{game:marquee}`), vertical **capsule cover**
  (`{game:image}`, 600×900) with **video** preview on top, and metadata.

## Art comes from SteamGridDB
The companion `sgdb-fetch` tool (package `themecfg`) downloads cover/hero/logo
into each system's `gamelist.xml`:

| Steam concept | gamelist tag | theme binding |
|---------------|--------------|----------------|
| capsule cover | `<image>`    | `{game:image}` |
| hero backdrop | `<fanart>`   | `{game:fanart}`|
| logo          | `<marquee>`  | `{game:wheel}` / `{game:marquee}` |

## v0.1 status / notes
- Tabs render as **text** (`logoText`) — no per-system logos shipped yet, so it
  works on a fresh install. Per-tab SVG logos are a later pass.
- "Tabs for PC / PS3 / Switch / Tools" map to systems today; user-chosen
  **collections-as-tabs** is the next step (Theme Manager GUI).
- Hero/scrim use `<size>1 1</size>` (stretch). Fine on 16:9 (Odin 3); revisit
  for other aspect ratios.

## Live iteration (no rebuild)
`~/scripts/steamlike-deploy.sh [IP] [--fetch "steam --limit 5"] [--logs]`
rsyncs this folder to `/storage/.config/emulationstation/themes/steamlike` and
restarts ES. First run: select **steamlike** in ES → UI Settings → Theme.
