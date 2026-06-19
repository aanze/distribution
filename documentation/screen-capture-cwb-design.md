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

## Architecture decision: out-of-band CWB capture on the SHARED realtime CTL (Strategy 2a)
Do NOT go through the drm_encoder/atomic/writeback-connector framework (it's master-bound). Instead a new
in-driver capture engine directly programs the CWB datapath and reads frames into a kernel-owned buffer
ring, exposed via a **V4L2 capture node** (`/dev/videoX`, `VIDIOC_*`/dma-buf), independent of the master.

**Trigger model — settled by RE (2026-06-18), reversed from an earlier 2b guess:** concurrent writeback
is driven by the **realtime CTL**, NOT an independent one. Evidence: the mainline upstreaming series
("drm/msm/dpu: Reorder encoder kickoff for CWB") states *"the realtime encoder must always kickoff last
as it will call the trigger flush and start"*, and the SM8750 downstream SDE driver couples CWB to the
source display's CTL the same way (DCWB is a dedicated datapath, but still flushed/started by the source
CTL). There is **no truly-independent-CTL concurrent capture** — the WB latch must ride the realtime
frame's flush/start. So:
- **2a (CHOSEN): hook the realtime kickoff** (`_dpu_encoder_kickoff_phys`, before the master's
  `trigger_flush`/`trigger_start`). When capture is armed, program the CWB mux to tap the active realtime
  pingpong(s) at LM_OUT, program `WB_2` (outaddr = next ring buffer, format, ROI, bind DCWB pingpong),
  and add WB + DCWB-PP + CWB-mux bits to the **master CTL's** pending flush. The existing
  `trigger_flush`+`trigger_start` then kicks the WB alongside the display. WB_DONE IRQ → buffer ready →
  V4L2. This replicates EXACTLY what mainline clone-mode does internally (so it's well-trodden, not novel
  HW risk), just kernel-initiated instead of via a userspace WB-connector atomic commit → master-independent.
- **2b (REJECTED): own spare CTL triggered on vsync.** Looked lower-risk (never touches the display CTL)
  but the RE shows the HW/driver model latches the WB via the source CTL; an async own-CTL trigger would
  race the frame (tearing) and isn't how Qualcomm drives concurrent capture. Don't revisit without new
  evidence that DCWB can latch cleanly off an independent CTL.

Risk note for 2a: we DO add to the hot realtime CTL flush each frame. Mitigated by doing exactly the
mainline clone-mode ops (config_cwb + update_pending_flush_cwb + WB setup + update_pending_flush_wb) and
nothing else; guarded by an arm flag so zero overhead when not recording.

## Components to build (kernel patch `0506-ROCKNIX-dpu-cwb-capture.patch` + glue)
1. **Capture engine** in `drm/msm/disp/dpu1` (new `dpu_capture.c/.h`): arm/disarm; init the dedicated
   hw blocks directly from catalog (DCWB pingpong(s), `WB_2`, CWB mux(es)) bypassing atomic RM since
   they're free/dedicated; on each realtime kickoff (hook in `_dpu_encoder_kickoff_phys`) program the CWB
   mux tap of the live LM(s) + WB outaddr=next ring buffer + add WB/DCWB-PP/CWB-mux to the **master
   realtime CTL** pending flush; register on `WB_DONE` IRQ to advance the ring. No separate CTL.
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
- Exact replication of mainline clone-mode flush ordering in the kickoff hook (config_cwb +
  update_pending_flush_cwb + WB setup + update_pending_flush_wb on the master CTL) so the WB latches the
  same frame the display flushes; verify WB_DONE fires once per realtime frame while armed.
- Realtime-CTL ownership/locking: the hook runs under `dpu_enc->enc_spinlock`; keep our additions minimal
  and lock-safe. Arm flag gates all of it so non-recording frames are untouched.
- LM topology / stitching for the WB output (CWB mux even/odd LM↔mux/DCWB-PP pairing rule from the RE;
  Android drives the panel single-LM+DSC, mainline/sway may differ — re-read active hw_pp[] each frame).
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
- [x] **M1 driver written + compiles + patch applies** (`0506-ROCKNIX-dpu-cwb-capture.patch`):
  `dpu_capture.{c,h}` engine, `set_capture_active` CTL op, `_dpu_encoder_kickoff_phys` hook, kms
  init/destroy, Makefile. debugfs `/sys/kernel/debug/dpu_capture/{arm,status,frame.raw}`. Single kernel
  buffer (msm_gem WC, 1080x1920 XRGB8888 stride 4352), single-LM tap (rt_pp[0]), WB_DONE frame counter.
  All 4 touched objects compile clean against linux-7.0.11; patch verified via `patch -p1`/`git apply`.
  **Pending: build + flash + on-device test** (arm, check status frames>0, pull frame.raw -> PNG, confirm
  it's the live ES screen; then test continuity across `systemctl stop sway`/gamescope).
- [ ] M1.5 — dual-LM stitch (2 CWB muxes/DCWB pps), derive WxH from active mode, ring buffer.
- [ ] Phase 1b — confirm continuity across a real ES->Steam->ES handoff.
- [ ] Phase 1b — confirm continuity across a real ES→Steam→ES handoff.
- [ ] Phase 2 — Iris H.264 encode pipeline + screenshot path + save dir.
- [ ] Phase 3 — ES SELECT menu + input_sense hotkey UX.

See memory: rocknix-screen-capture-feature, rocknix-device-runtime-notes, rocknix-personal-build-workflow.
