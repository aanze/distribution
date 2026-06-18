# System-wide screenshot + screen recording via DPU Concurrent WriteBack (CWB)

Branch: `aanze-screen-capture`. Target: AYN Odin 3 / SM8750 (Qualcomm, mainline kernel 7.0.11, `drm/msm` DPU).

## Goal
A screenshot + screen-record feature, surfaced in the ES Quick-Access (SELECT) menu, that captures the
**actual on-screen content system-wide** — including a single **continuous recording that spans
ES navigation → launching Steam → back**, i.e. across the compositor handoff.

## The hard constraint (why this needs a kernel driver)
Two compositors, never both running: ES + every emulator run on **sway/wlroots**; **Steam** runs on
**gamescope** after `start_steam.sh` does `systemctl stop sway` (gamescope `--backend drm`). Any
per-compositor capture (wlr-screencopy/`grim`/`wf-recorder` under sway; gamescope's PipeWire under Steam)
**dies at the handoff**. And **DRM is single-master**: only the active compositor can drive a DRM
writeback connector via an atomic commit, so an independent userspace recorder cannot grab the output,
and the kernel cannot inject a clone-mode WB into the master's atomic state. The only no-compromise
answer is an **out-of-band CWB capture inside the `drm/msm` driver**, exposed to userspace independent
of the DRM master, so it keeps capturing the live scanout regardless of which compositor owns the panel.

## Phase 0 — DONE (device-validated 2026-06-18)
The DRM writeback connector + clone mode already work on the panel (proven with a custom libdrm atomic
client, `/tmp/wbtest.c`): clone commit on the panel CRTC returned ret=0, the writeback out-fence
signalled, and a full 1080×1920 frame of the drawn content was captured (XRGB8888, stride 4352). So the
hardware datapath and mainline plumbing are good; only master-independence remains.

## Device DRM facts (card0)
- Panel = **DSI-1 connector 34**, mode 1080×1920@120 (also @60), on **CRTC 0 = id 105** (idx 0).
  Driven **dual-LM** (two 540px layer mixers via merge_3d) → single INTF.
- Writeback = **Writeback-1 connector 40**, encoder 39 "Virtual", crtc-cap mask 0x5 (CRTC 0/2),
  props `WRITEBACK_FB_ID`/`WRITEBACK_PIXEL_FORMATS`/`WRITEBACK_OUT_FENCE_PTR`. Hidden unless the client
  sets `DRM_CLIENT_CAP_WRITEBACK_CONNECTORS` (+ATOMIC).
- HW encoder = `/dev/video1` **`qcom-iris-encoder`** (V4L2 stateful, H.264/HEVC). decoder = video0.

## SM8750 DPU block budget (catalog `dpu_12_0_sm8750.h`) — dedicated CWB datapath exists
- Real-time: 8 pingpongs `PINGPONG_0..7`, DSPP 0..3, merge_3d 0..4, **6 CTLs `CTL_0..5`** (panel uses 1).
- **Capture-dedicated (separate from display):** 4 CWB pingpongs `PINGPONG_CWB_0..3`,
  4 CWB muxes `CWB_0..3`, writeback block **`WB_2`** (with `intr_wb_done` IRQ). → capture won't steal
  display resources, and there are spare CTLs.

## How mainline CWB works (what we reuse / bypass)
- `dpu_hw_cwb.c::dpu_hw_cwb_config(pp_idx, input)` programs a CWB mux: `CWB_MUX`=real-time pingpong index,
  `CWB_MODE`=tap point (`INPUT_MODE_LM_OUT` or `INPUT_MODE_DSPP_OUT`). Mainline always uses **LM_OUT**.
- `dpu_encoder.c::dpu_encoder_helper_phys_setup_cwb()` configures CWB mux `i` to tap real-time
  pingpong `i` (so dual-LM ⇒ 2 muxes ⇒ 2 CWB PPs ⇒ WB). This explains the Phase-0 center seam (the
  synthetic single-plane test mis-fed the right LM; a real compositor programs both LMs correctly).
- `dpu_encoder_phys_wb.c` is a full `dpu_encoder_phys`: its FB comes from a userspace `drm_writeback_job`,
  it sets up OT/QoS/outaddr/CWB/CTL in `prepare_for_kickoff`, adds WB to the CTL pending-flush, and
  completes on the `WB_DONE` IRQ (`dpu_encoder_phys_wb_done_irq`). **In mainline clone mode the WB shares
  the real-time CTL and is triggered by the same `trigger_start`** — that single-CTL coupling + the
  userspace-supplied FB are exactly the master dependency we must remove.

## Architecture decision: out-of-band CWB capture, own CTL (Strategy 2b)
Do NOT go through the drm_encoder/atomic/writeback-connector framework (it's master-bound). Instead a new
in-driver capture engine directly programs the CWB datapath and reads frames into a kernel-owned buffer
ring, exposed via a **V4L2 capture node** (`/dev/videoX`, `VIDIOC_*`/dma-buf), independent of the master.

Two ways to trigger the WB; chosen one first:
- **2a (hook the real-time CTL):** add WB+CWB to the real-time CTL's pending-flush on each kickoff
  (hook `_dpu_encoder_kickoff_phys`). Reuses the single-CTL clone path but **touches the hot display
  path** → risk to the compositor's frames. Rejected as primary.
- **2b (independent CTL) — CHOSEN:** give the capture its **own spare CTL** + a CWB PP + `WB_2` + CWB
  mux(es). Program the CWB mux to tap the active real-time LM(s) (concurrent live tap — read-only w.r.t.
  the real-time path), then **trigger our own CTL on the real-time vsync IRQ** to latch a frame into the
  next ring buffer. The real-time CTL/flush is never modified → display path untouched → lowest risk to
  stability, and fully master-independent. Slight tearing risk if WB latch races the frame; mitigated by
  triggering on vsync. Needs confirming the DPU supports an independent CTL driving WB off a concurrent
  tap (hardware is designed for concurrent capture; downstream SDE does this — see RE asks).

## Components to build (kernel patch `0506-ROCKNIX-dpu-cwb-capture.patch` + glue)
1. **Capture engine** in `drm/msm/disp/dpu1` (new `dpu_capture.c/.h`): arm/disarm, reserve CWB PP(s)+WB_2+
   CWB mux(es)+a CTL (init hw blocks directly from catalog, bypassing atomic RM since they're dedicated),
   program CWB mux tap of the live LM(s), WB outaddr=ring buffer, register on `WB_DONE` IRQ, hook a
   per-CRTC vsync callback to trigger the capture CTL.
2. **Buffer ring + IOMMU**: kernel dma-bufs mapped into the DPU address space (`msm_gem`/the DPU aspace)
   for WB output; handed to userspace via V4L2 (dmabuf export) or mmap.
3. **V4L2 capture device**: `/dev/videoX` advertising the panel resolution + XRGB8888/NV12; DQBUF delivers
   captured frames. (Userspace then feeds them to the Iris encoder = `/dev/video1`.)
4. **Userspace**: a `rocknix-screenrecord` start/stop that pipes V4L2 capture → Iris H.264 (gstreamer
   `v4l2src ! v4l2h264enc ! mp4mux ! filesink` or appsrc) → `/storage/roms/screenshots` (video subdir).
   Screenshot = single DQBUF → PNG. Reuse the existing `rocknix-screenshot`/mako pattern.
5. **UX**: ES Quick-Access (SELECT) menu start/stop + enable toggle (new ES patch, mirrors patch 009
   PERF CONTROL/bypass entries in `openQuitMenu_static`); a global `input_sense` record-toggle hotkey for
   in-game (the existing L1+B screenshot hotkey can be re-pointed at the CWB path).

## Open questions / risks
- Independent-CTL CWB trigger model (2b): exact CTL flush/start sequence + which IRQ to trigger on; does
  WB latch a clean frame off the concurrent LM tap when triggered async to the real-time CTL?
- Dual-LM stitching for the WB output (2 CWB PPs → one WB buffer; merge3d on the CWB path?).
- WB output buffer format/tiling vs what Iris encoder ingests (prefer linear NV12 to feed v4l2 encoder
  directly; else linear XRGB8888 + a convert).
- IOMMU mapping of the WB output into the DPU aspace from a kernel allocation.
- Mode/handoff: at the real sway→gamescope switch the CRTC re-modesets (panel timing may stay 1080×1920);
  capture engine must re-bind to the active CRTC/LMs after a modeset (re-read current pingpongs).

## Android RE (now high-value, user has rooted adb) — to de-risk the 2b trigger on THIS DPU
Android is single-compositor so it won't show master-independence, but its downstream SDE driver runs
**concurrent writeback on this exact DPU**, which is the risky mechanics we're hand-building:
- the CWB CTL flush/trigger sequence + which IRQ kicks the WB latch;
- CWB mux tap config (LM vs DSPP) + dual-LM → single-WB stitching;
- WB block output format/stride/UBWC for CWB;
- register offsets for `WB_2`/CWB PP/CWB mux on dpu_12_0 (cross-check the catalog bases).
Pull from: downstream kernel `sde_encoder_phys_wb.c`/`sde_hw_*` if available; `dmesg | grep -iE
'cwb|wb_done|sde_wb|wfd'`; `/d/dri/0/debug/`; how the composer HAL programs CWB for casting/recording.

## Phase plan
- [x] Phase 0 — HW writeback validated.
- [ ] Phase 1a — capture engine + V4L2 node + buffer ring (this branch). Target: `/dev/videoX` yields live
  frames while sway runs, AND keeps yielding across `systemctl stop sway`/gamescope.
- [ ] Phase 1b — confirm continuity across a real ES→Steam→ES handoff.
- [ ] Phase 2 — Iris H.264 encode pipeline + screenshot path + save dir.
- [ ] Phase 3 — ES SELECT menu + input_sense hotkey UX.

See memory: rocknix-screen-capture-feature, rocknix-device-runtime-notes, rocknix-personal-build-workflow.
