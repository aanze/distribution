# ROCKNIX Control — aanze fork

Vendored fork of [thefiqs/rocknix-control](https://github.com/thefiqs/rocknix-control)
(the Decky/Steam plugin for CPU/GPU/fan control). We ship and own this so it
installs automatically with Decky, stays compatible with our Perf Control tool,
and doesn't depend on the upstream Decky store.

## Our changes vs upstream (`src/index.tsx`)

1. **Detect the live preset on load** (`detectActivePreset`): the panel reflects
   whatever profile is actually applied — including one set outside Steam by the
   ROCKNIX *Perf Control* Tools app — instead of always showing "Default".
2. **Restore the pre-game preset on game exit** (`preGamePreset`): quitting a
   game no longer force-applies "Default" (which clobbered the user's / Perf
   Control's selection); it restores whatever was active before the game.

## Rebuilding `dist/index.js`

Needs Node ≥ 20 and pnpm 9 (via corepack):

```sh
corepack prepare pnpm@9 --activate
pnpm install --frozen-lockfile
pnpm build          # rollup -c  ->  dist/index.js
```

Commit the regenerated `dist/index.js`. The ROCKNIX image build does **not**
build this — it ships the prebuilt `dist/index.js` (see the package's
`makeinstall_target`) and the boot hook `rocknix-control-deploy` copies the
payload into `/storage/homebrew/plugins/rocknix-control/` when Decky is present.
