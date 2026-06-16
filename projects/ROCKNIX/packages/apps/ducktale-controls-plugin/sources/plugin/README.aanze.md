# DUCKTALE-CONTROLS — aanze fork

Vendored fork of [thefiqs/rocknix-control](https://github.com/thefiqs/rocknix-control)
(the Decky/Steam plugin for CPU/GPU/fan control), rebranded **DUCKTALE-CONTROLS**.
We ship and own this so it installs automatically with Decky, stays compatible
with our Perf Control tool, and doesn't depend on the upstream Decky store.

## Our changes vs upstream (`src/index.tsx`)

1. **Detect the live preset on load** (`detectActivePreset`): the panel reflects
   whatever profile is actually applied — including one set outside Steam by the
   ROCKNIX *Perf Control* Tools app — instead of always showing "Default".
2. **Restore the pre-game preset on game exit** (`preGamePreset`): quitting a
   game no longer force-applies "Default" (which clobbered the user's / Perf
   Control's selection); it restores whatever was active before the game.
3. **Bypass charging toggle** (`get/set_charge_bypass`): mirrors the ES "Bypass
   charging" toggle inside Steam. Shown as a top-level **Power** section.
4. **Rebrand + UI tidy**: renamed to DUCKTALE-CONTROLS; CPU + GPU sliders merged
   into one **Underclocking** section, and both Underclocking and **Fan Curve**
   are now `Collapsible` (folded by default) so Presets + Power are what's up
   front. Power sits above Underclocking.

> **Note (rename / migration):** the package is fully renamed
> `rocknix-control-plugin` → `ducktale-controls-plugin`; the on-device plugin
> folder is now `/storage/homebrew/plugins/ducktale-controls`. Decky keys a
> plugin's settings dir off its **folder name** (`DECKY_PLUGIN_SETTINGS_DIR =
> settings/<folder>`), so the folder rename moves the store from
> `settings/rocknix-control` to `settings/ducktale-controls`. The boot deploy
> (`ducktale-controls-deploy`) carries the old `presets.json` + `game_profiles.json`
> over once and removes the orphaned `rocknix-control` plugin so Decky doesn't
> list both. Perf Control's `pc_config.py` `PLUGIN_DIR` tracks the new folder.

> **TDP slider (investigated, not built):** SM8750 is Qualcomm ARM — no RAPL /
> `powercap` watt cap like the Steam Deck, so a true wattage TDP slider isn't
> possible. A *synthetic* one-slider "power level" mapping N steps to combined
> CPU+GPU max-freq caps is feasible (same sysfs as Perf Control), if ever wanted.

## Rebuilding `dist/index.js`

Needs Node ≥ 20 and pnpm 9 (via corepack):

```sh
corepack prepare pnpm@9 --activate
pnpm install --frozen-lockfile
pnpm build          # rollup -c  ->  dist/index.js
```

Commit the regenerated `dist/index.js`. The ROCKNIX image build does **not**
build this — it ships the prebuilt `dist/index.js` (see the package's
`makeinstall_target`) and the boot hook `ducktale-controls-deploy` copies the
payload into `/storage/homebrew/plugins/ducktale-controls/` when Decky is present.
