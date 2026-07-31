# Renderer: Polygonal 3D, Kit-Piece Geometry, and Effekseer — Roadmap

> **Intent, not status.** This document describes what we mean to build and why.
> For what is actually implemented right now, read the generated
> [`docs/ENGINE-STATE.md`](../ENGINE-STATE.md) (gated by G4); for how the engine
> works, `docs/SPEC.md`. Where this document and those disagree, they win.

Status: **proposed, nothing implemented.** Written 30.07.2026 from a feasibility
pass over [`presentation/viewport_3d.lua`](../../presentation/viewport_3d.lua).
Supersedes nothing; extends the analysis in
[`widescreen-performance-study.md`](widescreen-performance-study.md), which
studied resolution scaling of the *existing* raycaster and deliberately did not
consider replacing it.

**Gameplay is explicitly out of scope for everything below.** The world model
(`session.mapGrid` as a 2D char grid, tile-locked position, four cardinal
facings, step-triggered events) is unchanged by every step in this roadmap.
This is a presentation-power roadmap, not an engine redesign.

---

## 1. Why — what the raycaster structurally cannot do

[`viewport_3d.lua`](../../presentation/viewport_3d.lua) is a textured DDA
raycaster with a GPU floor/ceiling pass. It is not an approximation of 3D: it
does correct perspective projection, per-column depth, a z-buffer,
painter-sorted billboards, bilinear vertex lighting from a light texture,
distance fog with panorama layers, and baked composite wall tiles. What it
cannot have, by construction:

| Missing capability | Why the raycaster can't | Wanted? |
|---|---|---|
| **Z axis** — stairs, pits, multi-height rooms | One wall height, one floor plane, baked into `lineHeight = 170.6667 / dist` | **No** — out of scope, see §8.3 |
| **Non-orthogonal geometry** — arches, columns, diagonals | DDA only intersects axis-aligned unit cells | **Yes** — §5 |
| **Free camera** — analog movement, pitch | Camera is tile-locked; interpolated between cells during a 0.15s transition | **No** — out of scope, see §8.3 |
| **Real meshes** — 3D props and characters | Sprites are column-sliced billboards | **Yes**, selectively — §5, §7 |
| **Real lighting** — normals, directional shading | Light is a per-vertex color grid; Y-facing walls get a flat `0.76` multiplier | **Yes** — falls out of §4+§5 |

The perceived payoff is concentrated in the last row. A flat-lit model looks
like a flat-lit quad; a *lit* arch reads as architecture. Geometry is the
enabler, normals are the product.

---

## 2. The seam — why this is contained

The renderer's entire interface is one function, `viewport_3d.draw(session)`,
called from three places:

- [`engine/scene_host.lua:329`](../../engine/scene_host.lua:329) — map world
- [`presentation/renderer.lua:619,801`](../../presentation/renderer.lua:619) — map + battle backdrop
- [`engine/cli_tools.lua`](../../engine/cli_tools.lua) — `preview-map`, `preview-fog`, screenshot suite

It reads `session.mapGrid`, player position/facing, and `currentMapData`
(tileset, fog, light, materials, events), and writes pixels. Nothing reads back
from it. The "engine never requires presentation" non-negotiable is genuinely
upheld.

**Consequence:** a renderer replacement that keeps the tile-grid world model is
a file swap behind an unchanged function signature.

---

## 3. Prerequisite — the gate blind spot

**No gate covers the world view.** This is the single largest risk in this
roadmap and the reason §9 puts gate work first.

| Gate | Covers the renderer? |
|---|---|
| G1 `validate` | No — data/registry cross-references only |
| G2 golden battle | No — simulation logs |
| G3 golden UI | No — `tools/golden/scene_map.log` is a 17-line **event trace** (`open_window`, `set_cursor`); it never sees a pixel |
| G4 ENGINE-STATE | No — doc currency |

The only thing that rendered the world for inspection was
[`cli.runScreenshots`](../../engine/cli_tools.lua:331), which produced PNGs
that nothing compared. Per the project's own rule — *"enforce with gates, not
vigilance"* — the first work item was promoting those captures to a real
byte-compared gate.

This was not optional bookkeeping. Every subsequent step in this roadmap is a
change whose regressions would otherwise be invisible to every gate. The repo's
history already shows what that costs: the golden battle log broke for ~10
commits before anyone noticed.

**Closed 30.07.2026 by G5** (`tools/golden/check-screens.ps1`, 122 reference
frames). Verified two ways: two consecutive harness runs produced byte-identical
output, and a deliberate one-constant change to the raycaster's Y-facing wall
shading turned exactly the 16 world-rendering frames red (`map`, `battle`, and
`dialogue`, which draws over the map backdrop) while **G3 stayed fully green** —
demonstrating both that the blind spot was real and that it is now covered.

### 3.1 Determinism is the shared prerequisite

The screenshot harness already pins `love.timer.getTime`, seeds
`math.randomseed(12345)`, and settles animations through explicit seams. Any
effect runtime added under §6 must be driven by that same harness clock rather
than its own wall clock.

**This is one piece of work that buys two things:** deterministic effect
playback makes the screenshot gate possible *and* makes the editor's
`preview-anim` filmstrip correct. Do not build them separately.

---

## 4. Strategy B — polygonal 3D in LOVE, same world model

Replace the raycaster with real geometry, keeping the char-grid world model
exactly as it is.

LOVE 11.5 provides everything required: `newMesh` with a custom vertex format,
`setDepthMode("lequal", true)`, `setMeshCullMode`, custom vertex shaders (so we
supply our own view/projection matrices), and `drawInstanced` for repeated
geometry. No compute shaders — not needed here.

**Approach:**

- Build a static mesh per map from `mapGrid` on load: wall quads for each solid
  cell face adjacent to floor, plus floor and ceiling quads. A 40x40 map is a
  few thousand triangles, built once per map load, not per frame.
- **The tileset atlases carry over verbatim.** `data/tilesets.json` addresses
  64x64 cells by `[row, col]`; a wall quad samples the same cell a raycast
  column samples today. No art re-authoring. The composite baking in
  [`getCompositeTileCanvas`](../../presentation/viewport_3d.lua:336) survives
  unchanged as a texture source.
- Vertex lighting gets *simpler*: `sampleLight()` already interpolates a
  per-corner RGB grid, which is literally vertex colour. It becomes a mesh
  vertex attribute instead of a per-column Lua computation.
- Fog becomes ordinary depth-based fragment fog, **deleting an entire class of
  problem** — the current three-way duplication (`drawFogBackground`,
  per-column `drawFogLayers`, per-sprite `calcFogAlpha`) exists only because
  walls must repaint fog per column to avoid revealing floor pixels behind
  them. That constraint disappears with a depth buffer.
- Billboards stay billboards, and get simpler: the manual z-buffer and
  per-stripe scissor loop is replaced by camera-facing quads with depth test.
- Resolution independence is free. `widescreen-performance-study.md`'s central
  cost — 480 CPU-side draw calls for 480 columns — ceases to exist.

**Deliberately kept:** render into the existing 256x144 viewport region of the
256x240 canvas, scaled 3x at the end. The low framebuffer resolution is what
reconciles polygonal geometry with hand-authored pixel art, and it lands the
result natively in the PS1-era register rather than fighting it. **Do not render
the world at native window resolution.**

**Estimated scope:** ~1,200 lines rewritten, one file, three call sites
unchanged, zero data-schema changes, zero art changes, zero engine changes.

### 4.1 Verified: what is NOT coupled to the raycaster

Checked 30.07.2026, because both looked like hidden coupling that would widen
the blast radius. Neither is.

**Battle placement is independent of the projection.** Every value
[`battler_geometry.lua`](../../presentation/battler_geometry.lua) resolves comes
from `battle_layout.get()` (the `BATTLE_LAYOUT` table, overridable from
`engine.json` `battleLayout`) or from `windowLayout.party` via `ui.toPx` — all
authored screen-space pixels in the 256x240 canvas. **No file outside
`viewport_3d.lua` references the projection constants** (`170.6667`,
`85.3333`); they do not leak. `fallbackY = 70` resembles the raycaster's centre
row but is a fallback *screen position*, and `viewportOverlayW/H` are overlay
dimensions, not projection math.

Battlers composite on top of whatever the backdrop is, so replacing the
backdrop changes nothing they compute. What may want re-tuning is
**composition** — a different FOV and real geometry change what is visible
behind the enemy row, so `enemyY`, `enemyStartX` and `enemyInfoOffsetY` are
authoring adjustments in the Engine editor. That is data, not code, and it
therefore does not touch the owner-supervised battle files.

**`door_transition.lua` needs no changes.** The module is a clean state machine
of phase timing and alpha curves. The hack is entirely in its ~8-line consumer
at [`viewport_3d.lua:760`](../../presentation/viewport_3d.lua:760), which takes
`approachProgress()` and applies a screen-space scale about pivot (128, 72) to
fake crossing a threshold.

`approachProgress()` already returns a normalized, eased 0..1 curve — exactly
the right input for a real camera dolly. Under §4, delete the scale at the call
site and feed the same value to a forward camera translation. The effect the
scale was approximating becomes the real thing once §5 supplies a modelled
doorframe to move through.

---

## 5. Kit-piece models — geometry as a tileset variant

### 5.1 The schema already has the right shape

`data/tilesets.json` is structured as weighted variant pools per structural
role — `base.walls[]`, `base.floors[]`, `base.ceilings[]`, `doors[]`,
`features[]` — each entry being `{id, role, weight, atlas:[row,col]}` plus
properties like `emitsLight`, `requiresAdjacentFloor`, `injectProbability`.
SPEC §1.8 established this as the authoring surface.

**A kit piece is that same entry with a `model` field where `atlas` is today.**
Nothing about the pool structure, the role taxonomy, the weights, the
light-emission fields, or the editor's Variant Pools list has to change.

This is an additive field on an existing registry — the extension shape the
non-negotiables ask for. It needs no compatibility shim, because it is not a
migration of existing data: an entry with a `model` draws a mesh, an entry with
only `atlas` draws a textured quad, and every existing tileset keeps rendering
exactly as it does now.

### 5.2 Hybrid, not all-model

Do **not** replace wall/floor/ceiling geometry with models. Procedural textured
quads remain the structural bulk — they are free, they reuse all nine existing
atlases, and a flat corridor wall gains nothing from being a mesh. Spend models
where silhouette does the work:

- **Wall features** (torches, sconces, banners, rubble) — already a role with
  `injectProbability` and `emitsLight`
- **Doors and arches** — currently baked flat into the composite canvas
- **Structural `opening` cells** (SPEC §1.7) — the renderer's own comment
  concedes these "borrow the door row as a stand-in arch/gate frame." This is
  an acknowledged gap and the best possible first model.
- **Floor fixtures** — pillars, altars, braziers, stairs-as-scenery

### 5.3 Model format

**OBJ + MTL, not glTF.** OBJ is ~150 lines of Lua to parse and is the correct
format for static, non-animated kit pieces. glTF buys skinning and scene
hierarchy that §8.1 declines. Parse at map load into a mesh cache keyed the way
`atlasCache` already is; draw repeated pieces with `drawInstanced`.

### 5.4 The real cost is consistency, not modelling

The owner is a skilled 3D modeller, so sourcing is not the constraint. What
must be decided up front and written down:

- **Texel density standard** — so a 64px atlas cell and a model's texture read
  at the same scale
- **Kit tiling rules** — pieces must meet cleanly at cell boundaries
- **Nearest filtering, no smoothing**, matching every other texture in the
  project

### 5.5 Prerequisite: weighted variant resolution

SPEC §1.8 flags this as still open: *"the pools are real now, but nothing picks
between variants by weight yet."* Models make the gap far more visible — four
identical arches in a row reads much worse than four identical wall textures.
**Fix this as part of §5, not after it.**

---

## 6. Effekseer

### 6.1 What it replaces

From `data/animations.json` (28 entries, 8 track kinds):

| Track kind | Instances | Subsumed by Effekseer? |
|---|---|---|
| `particles` | 18 | **Yes, completely** |
| `tint` | 14 | Mostly |
| `gradient_map` | 11 | **Yes** |
| `blend` | 10 | **Yes** |
| `force_field` | 4 | **Yes** |
| `transform` | 14 | **No** — battler choreography (`step_forward_party`, `enemy_slide_in`, `swap_in/out`) |
| `shake` | 5 | No — screen/camera level |
| `screen_flash` | 4 | No — screen level |

So [`animation_player.lua`](../../presentation/animation_player.lua) does not go
away; it gets **thin**. It keeps owning timing, per-target instances, anchors,
completion callbacks, and the transform/shake/flash tracks, and delegates the
entire visual layer. The particle/tint/gradient/blend/force-field machinery —
the bulk of the interesting code — is what leaves.

### 6.2 An `.efk` is an asset, not data

This must be recorded deliberately or it will be re-litigated against the
non-negotiables every time someone reads them.

The objection: an `.efk` is an opaque binary the validator cannot inspect,
which looks like it violates "data drives the engine."

The resolution: **this category already exists.** `assets/` holds 28MB of
opaque PNGs and MIDI that G1 never inspects, and `tools/asset-gen/` is
deliberately outside the editor, staged and promoted by hand. Effekseer is the
same shape — an external authoring tool producing binaries promoted into
`assets/`. G1 does for effects exactly what it does for art: validate that the
referenced file exists and the id resolves.

What stays in `animations.json` is the **reference plus timing, anchor and
choreography** — still data, still editor-authored, still validated.

**When this lands, record the call in SPEC §1.2.**

### 6.3 The editor previews it through the real engine

[`cli.runPreviewAnim`](../../engine/cli_tools.lua:49) already loads an
animation, steps it at a fixed 0.05s interval, renders each step to a canvas,
encodes every frame to PNG base64, and returns a **frames array** the editor
plays back. `anim-editor.js` and the `/preview-anim` endpoint are already wired
to it.

If Effekseer renders inside LOVE, it previews in the editor through this
pipeline with **no new architecture** — same loop, same encode, same endpoint.
The editor renders nothing itself and must continue to render nothing itself.

The one condition is §3.1: Effekseer's stepping must be driven by that explicit
`step` value, not its own clock.

### 6.4 Battle first — Strategy B is not a prerequisite

Effekseer is natively 3D and wants view/projection matrices. The raycaster has
no matrices to give it (it has camera *vectors* and hand-derived projection
constants, which is not the same thing).

But the battle scene is 2D-composited at a known screen layout, so an
**orthographic screen-space camera is sufficient there** — and all 28 current
animation entries live in battle. World-space effects (a torch flame in the
dungeon) do need §4's matrices.

This decouples Effekseer from the renderer rewrite. See §9.

Note: this touches `animation_player.lua` and `renderer.lua`, **not**
`engine/battle.lua` or `engine/scenes/battle.lua`, so it stays outside the
owner-supervised files.

### 6.5 Risks, in order

1. **A native build dependency in a project that has none.** Effekseer's
   runtime is C++; LOVE's LuaJIT FFI means the Lua side needs no build step,
   but a DLL must be compiled. Today the editor is explicitly "no build step"
   and everything runs from a LOVE binary. This changes distribution and
   affects whether the gates run on a clean machine. **Resolved 30.07.2026 —
   see §6.5.1.**
2. **GL state pollution.** Effekseer's GL renderer issues its own OpenGL calls;
   LOVE caches GL state and assumes nothing else touches it. Interleaving
   without disciplined save/restore produces corruption that is genuinely nasty
   to debug. This was the classic failure mode and the most likely place to
   lose a week. **Resolved 30.07.2026 — see §6.5.1b.**
3. **Determinism** — see §3.1.
4. **Missing-DLL behaviour.** Gates run headless. "Fail loud, never silently"
   argues for a hard error; practicality argues for effects-disabled-but-
   playable. **Decide once, write it down.**

### 6.5.1 Spike finding (30.07.2026): there is no C API — a shim is required

Checked against a shallow clone of the official
`github.com/effekseer/Effekseer` repository.

**Finding: `extern "C"` appears nowhere in `Dev/Cpp/Effekseer` or
`Dev/Cpp/EffekseerRendererGL`.** The runtime is C++-only and idiomatically so:
`Manager::Create()` returns a `ManagerRef` (an intrusive smart pointer; 117
`RefPtr<` uses in the core alone), and the API is delivered through
pure-virtual interfaces. **LuaJIT FFI cannot bind this directly** — FFI speaks
C ABI, not C++ vtables, name mangling or smart pointers.

**This is not fatal, because the usable surface is handle-based.**
`Effekseer.Base.Pre.h:106` declares `typedef int Handle`, and the calls that
matter reduce to plain scalars:

```
Handle Play(const EffectRef&, float x, float y, float z)
void   Update(float deltaFrame)
void   UpdateHandle(Handle, float deltaFrame)
```

So a C shim's FFI surface is **ints and floats**; every RefPtr, vtable and
template stays sealed inside the shim. Estimated **15-25 exported functions**:
create/destroy manager and renderer, load/release effect, play/stop/exists,
update, draw, set view and projection matrices, set a handle's transform.

**This is the vendor's own pattern for non-C++ hosts** — EffekseerForUnity
wraps the same runtime in an `extern "C"` layer for P/Invoke. Writing one is
the expected integration path, not a workaround.

**Revised cost:** the shim is small and mechanical. It does not change the
week-vs-month question the way a missing API would have; risk §6.5.2 (GL state)
is now the dominant unknown.

**Corroborated while checking:** `EffekseerRendererGL` issues its own GL state
calls (`glUseProgram`, `glBindBuffer`, VAO binds) directly in its `.cpp` files.
Risk §6.5.2 is real and observed, not theoretical.

### 6.5.1a Build verified (30.07.2026): MinGW-w64 builds the runtime cleanly

Toolchain installed and the runtime built end to end. **No MSVC required** —
this matters, because it keeps the native dependency to a ~250MB MSYS2 install
rather than a multi-GB Visual Studio workload.

Toolchain: MSYS2 (`winget install MSYS2.MSYS2`), then

```
pacman -S mingw-w64-x86_64-gcc mingw-w64-x86_64-cmake mingw-w64-x86_64-make
```

giving g++ 16.1.0, CMake 4.4.0, Ninja 1.13.2, target `x86_64-w64-mingw32`.

**Clone (order matters, both flags are required):**

```
git -c core.longpaths=true clone --depth 1 https://github.com/effekseer/Effekseer.git
```

- Without `core.longpaths=true` the checkout dies on Windows `MAX_PATH` inside
  `Dev/Editor/EffekseerCoreGUI/IO/mqoToEffekseerModelConverter/...`.
- **Do not sparse-checkout only `Dev/Cpp`.** It looks right (the Editor is
  dead weight) but the root `cmake/` directory defines `filterfolder`
  (`cmake/FilterFolder.cmake`), used by every library's `CMakeLists.txt`, so
  configure fails with `Unknown CMake command "filterfolder"`.
- **Clone to a short path.** A deep parent directory blows CMake's
  `CMAKE_OBJECT_PATH_MAX` (250 chars) during try-compile.

**Configure — every one of these flags is load-bearing:**

```
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_EXAMPLES=OFF -DBUILD_TOOLS=OFF -DBUILD_VIEWER=OFF \
  -DBUILD_EDITOR=OFF -DBUILD_TEST=OFF \
  -DBUILD_GL=ON -DBUILD_DX9=OFF -DBUILD_DX11=OFF -DBUILD_DX12=OFF \
  -DNETWORK_ENABLED=OFF \
  -DUSE_OPENAL=OFF -DUSE_DSOUND=OFF -DUSE_XAUDIO2=OFF -DUSE_OSM=OFF
```

The sound flags are not optional housekeeping: `USE_OPENAL` defaults ON, and
without OpenAL present `Dev/Cpp/CMakeLists.txt:167` does
`set_property(TARGET EffekseerSoundAL ...)` on a target that was never
created, and configure fails. We do not want Effekseer's audio anyway — LOVE
owns sound.

```
cmake --build build --target Effekseer EffekseerRendererGL
```

**Result:** 92 targets, clean apart from one benign `stb_image` warning.

| Artifact | Size |
|---|---|
| `libEffekseer.a` | 1.5 MB |
| `libEffekseerRendererCommon.a` | 520 KB |
| `libEffekseerRendererGL.a` | 2.4 MB |

`nm -C libEffekseer.a` confirms `Effekseer::Manager::Create(int, bool)` and
`ManagerImplemented::Play(...)` present — as **mangled C++ symbols**, which is
both proof the libraries are linkable and a concrete restatement of why
§6.5.1's shim is unavoidable.

**Next:** write the `extern "C"` shim against these three static libraries and
link it into a single DLL for LuaJIT FFI.

**Remaining scope note:** the Editor, Viewer, Material tooling and the
DX/Vulkan/Metal renderers are all irrelevant and stay switched off.

### 6.5.1b Spike complete (30.07.2026): it runs inside LOVE, and GL state holds

The shim is written and working. See
[`tools/effekseer/`](../../tools/effekseer/) for the source, the LOVE harness
and the captured proof frame.

**Result: every question step 1 existed to answer is answered, favourably.**

- `efk_shim.cpp` — 14 exported `extern "C"` functions, ints and floats only,
  every `RefPtr`/vtable sealed C++-side. The 15-25 estimate in §6.5.1 held.
- Built as a **single self-contained 6.4MB DLL** depending only on `KERNEL32`,
  `msvcrt` and `OPENGL32`. (`-static` is required; without it the DLL drags in
  `libwinpthread-1.dll` and stops being one file.)
- `ffi.load` succeeds, `efk_init` succeeds **against LOVE's own GL context**,
  an effect loads and plays, and 116 instances render inside a normal
  `love.draw`.
- Clean shutdown, no crash on exit.

**GL state — the dominant remaining risk — holds.** A `GLStateGuard` around
each draw saves/restores program, VAO, array + element buffer bindings, active
texture unit, 2D texture binding, blend/depth-test/cull-face enables and the
depth write mask. `glGetIntegerv` is GL 1.1 and links directly; the setters are
GL 2.0+ and resolve at runtime through `wglGetProcAddress`.

This was tested harder than "do simple shapes still draw", because that proves
almost nothing. The harness runs a **custom shader, a scissor, an additive
blend mode and a render-to-canvas** across the effect draw — the states LOVE
actually caches. All render correctly afterwards.

**Caveat, honestly held:** this is one effect in a simple scene. It is strong
evidence the approach is sound, not proof the guard is complete. The saved set
is the thing to extend first if LOVE ever renders wrongly *after* an effect —
and step 2 should add a G5 frame covering an effect, so a regression here is
caught by a gate rather than by eye.

**Revised risk ranking for §6.5:** with 1 and 2 both resolved, the remaining
open items are the *decisions* (missing-DLL behaviour, effects-as-asset in
SPEC §1.2), not technical unknowns. The dependency question is now a product
call, not an engineering gamble.

### 6.5.1c Prior art: `gittup/EffekseerForLove` (reviewed 30.07.2026)

Not usable as a dependency, but it paid for itself in one finding.

**Why not usable:**

- Pinned to **Effekseer 1.60c2** (2021). Current is 1.7x. Effects authored in a
  modern Effekseer editor are not guaranteed to load in a 1.60 runtime — which
  matters here, since the whole point is authoring in current tooling.
- It is a **Lua C module** (`require('effekseer')`), not FFI, so it links
  against the Lua C API and couples to LOVE's LuaJIT ABI. Our shim's FFI
  approach has strictly less coupling.
- Built with **tup**, an unusual build system, and its documented targets are
  Linux / macOS / love.js / cross-compile-to-macOS. **No native Windows build.**
- Last commit May 2024.

**What was worth taking:**

1. **The batch-flush requirement — a real bug our spike had and did not
   notice.** LOVE batches draw calls; without flushing before the effect draw,
   effects render *behind* everything LOVE queued that frame. Reproduced and
   fixed: `tools/effekseer/spike/spike-zorder-bug.png` vs `spike-result.png`.
   LOVE 11.5 exposes `love.graphics.flushBatch()` directly (EffekseerForLove
   pokes `setColorMask` to force a flush, because its target lacks it).
2. **A screen-space orthographic camera recipe** for step 2 — build
   `OrthographicRH(w, h, -512, 512)`, then set `Values[3][0] = -1`, negate
   `Values[1][1]` and set `Values[3][1] = 1` to put the origin at top-left in
   LOVE's coordinate system. This is the non-obvious part of §6.4 and is now
   answered rather than needing derivation.
3. **Confirmation, not a gap, on vertex attribute arrays.** They reset every
   `GL_VERTEX_ATTRIB_ARRAY_ENABLED` around the draw — but only under
   `#ifdef __EMSCRIPTEN__`, because love.js does not use VAOs, so Effekseer has
   no previous VAO to restore. On desktop, restoring the VAO binding implicitly
   restores attribute state, which is what §6.5.1b's guard does and why it
   passed. **The condition under which our guard would break is now known: a GL
   path without VAOs.** If a web build is ever wanted, that is the code to port.

**Method note worth keeping.** The z-order probe initially appeared to pass,
because it drew a text label between the quad and the effect and the font
texture switch forced a flush anyway. Any intervening state change masks this
bug. Draw-order tests must put the shape under test immediately before the
foreign draw call, with nothing in between.

### 6.5.1d Canvas + screen-space camera verified (30.07.2026)

The remaining structural unknown for step 2: this game does not render to the
backbuffer. Everything goes into a **256x240 LOVE Canvas** which is scaled 3x at
the end. If effects cannot land *in that canvas*, step 2 does not work no matter
what else was proven.

**They can.** `tools/effekseer/spike/canvas-main.lua` binds the 256x240 canvas,
draws with an identity view plus the §6.5.1c orthographic recipe (1 unit = 1
pixel, origin top-left), and the effect renders inside the canvas, above the
LOVE geometry drawn before it, with LOVE drawing correctly after it. The
framebuffer binding survives Effekseer's draw — see
`spike/spike-canvas-256x240.png`.

Confirms in passing that §6.4's "an orthographic screen-space camera is
sufficient for battle" is not merely plausible: effects are positioned in
**canvas pixel coordinates**, so `efk_play(id, x, y, 0)` takes exactly the
numbers `battler_geometry.anchor()` already returns. That is the whole
integration seam for step 2.

#### Effects must be authored at game scale, not magnified

Effects are authored in world units. Under a 1-unit-per-pixel camera, an effect
built for a 3D scene renders about 20px across and reads as a speck. Effekseer's
`Effect::Create` takes a magnification, now exposed as
`efk_load_effect(path, magnification)` rather than silently hardcoded.

**But magnification is a workaround, not the answer.** At 8x the sample effect
fills the frame and is visibly soft and blurry: the effect's own textures are
linearly filtered, so scaling up yields smooth gradients that fight hand-authored
pixel art. The §4 point about the low framebuffer resolution reconciling 3D with
pixel art only holds when the source is authored at that resolution.

**Consequence for the owner, before authoring 28 effects:** author at game scale
(particles sized in the tens of pixels, textures small and crisp) rather than
authoring large and scaling down, and prefer hard-edged particle textures over
soft gradients. This is cheap to adopt now and expensive to retrofit across a
finished effect library — which is the main reason it is written down here
rather than discovered in step 2.

### 6.5.1e Step 2 landed (30.07.2026): Effekseer wired into the engine

Owner decisions taken: **wire it in for real**, and **degrade (do not raise)
when the shim DLL is absent**.

**Shape of the integration** — deliberately following the existing seams rather
than adding new ones:

- `presentation/effekseer.lua` — FFI binding. Loads the DLL under `pcall`,
  logs **once** and disables effects if absent. Presentation-only; the engine
  never calls it.
- **A new `effekseer` animation track type**, so effects are authored in
  `data/animations.json` alongside `particles`/`tint`/`transform` rather than
  through a parallel mechanism. G1 accepts the type and checks the reference.
- Spawning is one-shot at the track's `t0`. `animation_player` queues due
  spawns (`consumeEffekseerSpawns`) and the **drawers** resolve the anchor,
  preserving that module's stated invariant of knowing nothing about screen
  geometry. `effekseer.spawnFor(target, rect)` is the bridge, placed there
  because `battler_geometry` is the bottom of the dependency stack and may not
  reach upward.
- One `effekseer.draw()` per frame in `frame_renderer`, above battlers and
  reticles but **below damage popups and pictures** — a number must stay
  readable through whatever is going off behind it.
- `effekseer.update(dt)` rides the existing `renderer.update` tick, stepping
  from the caller's dt rather than any clock of Effekseer's own (§3.1).

**Because effects are `.efk` assets and G1 cannot read them, the reference is
checked instead**: a track must name a non-empty `effect`, and that file must
exist. A typo would otherwise be an effect that silently never plays.

#### The Y-flip bug, and why the spike could not have caught it

An effect anchored to an enemy's centre landed at **y=153 instead of y=78** —
an exact mirror about the canvas midline.

`EffekseerForLove`'s recipe negates Y to get a top-left origin because it draws
to the **backbuffer**. This game always renders into a **Canvas**, and an
OpenGL FBO's origin is already bottom-left, so the flip is applied for us and
negating again inverts everything.

**The spike played its test effect at (128, 120) — the exact centre of a
256x240 canvas — where a Y-flip is invisible.** The standalone canvas test in
§6.5.1d passed for that reason and only that reason. The bug surfaced the
moment a real anchor put an effect off-centre.

Two things worth keeping from that:

- **Centred test fixtures hide symmetric bugs.** Position probes must be
  off-centre in both axes.
- **G5 is what caught it.** The frame diff gave the exact centroid (71, 86)
  against the expected (73, 78), turning "looks wrong" into a measurement. The
  gate built in step 0 paid for itself on the first real change it saw.

#### Status

Plumbing is complete and verified in the real battle scene. **No `.efk` assets
are committed**, so nothing renders yet and all seven gates are green
unchanged. The 28 existing `animations.json` entries are untouched; migrating
them is §6.1's work and depends on effects being authored first (§6.5.1d:
author at game scale).

### 6.5.1f First authored effect (30.07.2026): scale and capture findings

`assets/effects/SecondRite/basic_attack.efkefc` is the first owner-authored
effect. `skill.attack`'s LOVE `particles` track is replaced by an `effekseer`
track referencing it — the first actual step of the §6.1 migration, not a demo.

`.efkefc` loads directly (it is a container and carries its own textures), so
no export-to-`.efk` step is needed.

#### Finding 1: the settle killed every short effect

The screenshot harness settles by advancing **one second** in a single step.
That is right for panels and gauges — at rest is what you want to capture — but
an effect at rest is an effect that has already finished, and this one lives
about 24 frames. Result: **G5 could not see effects at all**, which would have
quietly defeated the whole reason §6.5.1b wanted a G5 frame containing one.

Fixed by freezing effect time for the settle (`effekseer.setSuppressed`) and
advancing it afterwards by `EFFECT_CAPTURE_SECONDS = 0.15`, so effects are
captured mid-life and deterministically. Confirmed: with the fix, a probe
effect turns the battle frame red; without it, G5 reports a clean pass on a
frame that visibly contains an effect.

**This is the second time a capture procedure hid the thing it was meant to
catch** (the first being §6.5.1c's self-flushing z-order probe). Both were
green-looking failures, which is the dangerous kind.

#### Finding 2: authored effects need a scale conversion

Effekseer node sizes are arbitrary units; the screen-space camera makes one
unit one canvas pixel. Measured, at 0.15s into this effect:

| magnification | rendered size |
|---|---|
| 1.0 | 5 x 5 px |
| **3.2** | **17 x 18 px** |
| 6.4 | 34 x 35 px |

Perfectly linear, so the conversion is a single constant. **3.2 puts a 16x16
source texture on 16x16 canvas pixels — one texel per pixel**, which is the
value that keeps pixel art crisp. Below it the texture is minified; above it,
interpolated and soft (§6.5.1d).

So the authored effect is about 3.2x too small for a 1-unit-per-pixel camera.
Two equivalent fixes, and the choice is the owner's:

- **Set `magnification: 3.2` on the track** (done for `skill.attack`). Keeps
  the Effekseer project as authored.
- **Author node sizes 3.2x larger** and leave magnification at 1. Makes the
  editor preview match the game, which matters more as the library grows.

The second is probably better long-term for exactly that reason, but it is a
decision about the effect library, not about the engine.

#### Scale is now ONE registry constant (30.07.2026, owner direction)

Superseding the per-track magnification above. The effect library is authored
to a scale shared with the owner's other commercial assets, so the conversion
to canvas pixels is a **property of the library, not of any one effect** —
which makes it registry data, editable in the Engine editor, not a number
copied onto every track.

- `data/engine.json` -> `effekseer.magnification` (currently **6.4**)
- A track's own `magnification` still exists and now **multiplies** the global
  rather than replacing it, so it means "this effect is bigger than house
  scale", and a track that wants house scale simply omits it.
- Exposed in the Engine editor through the existing `buildRecursiveForm` call
  beside `battleLayout`/`windowLayout` — schema-driven, no hand-written DOM.
- G1 rejects a non-positive value: it would collapse every effect at once,
  which is precisely the invisible whole-system breakage the validator exists
  to catch.

The owner halved the authoring scale (cells 4x -> 2x in Effekseer), so the
constant doubled 3.2 -> 6.4. Verified: the old 4x asset at 3.2 rendered
17x18 px; the new 2x asset at 6.4 renders 16x21 px, and the captured pixels are
hard-edged with no interpolation blur. Same on-screen size, same crispness --
the two changes cancel exactly, as expected.

**G1 caught a genuine modelling error during this change.** `system.heal` is a
system-class entry, and the validator requires `duration` on every track of
one. An `effekseer` track has no meaningful duration -- it is a one-shot spawn
at `t0` and the runtime owns the lifetime afterwards -- so the track type is
now explicitly exempt. Supplying a duration would have been worse than omitting
it: a number nothing reads, that reads as authoritative.

`system.heal`'s LOVE `particles` track is likewise replaced, by
`recovery_001.efkefc`. Two of the 28 entries are now migrated.

#### Coverage gap, needs an owner call

Battle's `screenshotScript` is `return, escape, down, return, down, return` —
it never resolves an attack, so `skill.attack` never plays during capture and
**G5 does not currently cover the effect**. Closing that means extending the
script so an attack lands, which adds new capture frames and therefore needs an
owner-signed `capture-screens.ps1` run. Worth doing before the migration gets
far: otherwise the 28 entries get ported with no gate watching any of them.

### 6.6 Why this ranks high

Two properties no other item on this roadmap has:

- It converts existing professional skill directly into game content, rather
  than into a skill or pipeline that must be built first.
- **It reduces lock-in of creative labour.** `animations.json` tracks are bound
  to this engine permanently — a bespoke schema and an 895-line player nothing
  else can read. `.efk` files run under Unity, Unreal, Godot and Cocos
  runtimes. The usual "external tool means lock-in" concern inverts here.

---

## 7. Wandering 3D townsfolk

The cheapest possible place to put 3D characters, and deliberately the last
step rather than a blocker for anything.

- Towns are `safe` maps with `ceilingStyle: "sky"` — no battle involvement, so
  the battler-placement/anchor system (SPEC §2.4) never sees them
- No `animation_player` involvement, no owner-supervised files
- The count is a handful, not the 65-actor roster
- Degradation is graceful: no model, and they stay billboards like every other
  map event

**Rigid-jointed, not skinned.** PS1-era characters used segmented limbs
rotating about pivots, with visible seams. That is both the target look and the
cheap path — rigid node-hierarchy animation is a small fraction of the work of
vertex skinning, with no bone palettes or inverse bind matrices. Period-correct
rather than a compromise.

**Wandering stays presentation-only.** Keep the event on its integer grid cell
for interaction and triggers; let the renderer interpolate its *visual*
position along a path. `session.mapGrid`, collision, step triggers and saves
never learn about it.

---

## 8. Considered and deferred

Recording *why*, because each of these will be raised again.

### 8.1 Skeletal 3D creatures — deferred on roster economics, not capability

**Not an engine limitation.** LOVE has no built-in glTF loader or skinning, but
it provides every primitive needed to implement one: custom vertex attributes
(bone indices and weights), `mat4` array uniforms (bone palettes), custom
vertex shaders, and glTF is JSON plus binary buffers, parseable in pure Lua. A
subset loader plus skinning shader plus playback is roughly 1,500-2,500 lines —
comparable to the dialogue-to-command-language migration, so bounded.

**Deferred because of the cast, not the code.** There are 65 actors with
`evolutions` on the schema, so the roster grows. Backing art today is 65 big
battlers, 34 small battlers and 83 portraits, all 2D. Skeletal creatures means
65+ rigged, textured, animated models against a roster designed to expand —
re-commissioning the entire cast of the game.

It would also invalidate the 29.07.2026 battler-placement unification (SPEC
§2.4), which is built around billboards with a known footprint and data-driven
feet/head/centre anchors. Skinned models have no fixed footprint.

And the art-direction argument inverts relative to §5: static architecture in
low-poly at 256x144 reads as deliberate period style, but **motion is exactly
what reveals interpolation** and makes smooth 3D clash with hand-authored pixel
art. Static kit pieces get the framebuffer's help; skinned creatures fight it.

**Owner decision (30.07.2026): creatures stay 2D, hand-authored.** Kept in
scope only for §7's townsfolk (rigid, not skinned) and potentially a single
set-piece boss.

Worth keeping: **rigid node-hierarchy animation** — a portcullis, a rotating
mechanism, a collapsing bridge. Roughly 10% of the work of skinning and it
covers most environmental motion. That belongs with §5, not here.

### 8.2 Leaving LOVE (Godot / Unity / three.js) — rejected

Discards ~23,500 lines of Lua, a 2,602-line validator, six gates, 30 golden
logs, and all of `tools/editor` — none of which is the renderer. The renderer
is ~5% of the codebase. Migrating engines to change 5% is not a migration.

The Electron shell in `main.js` is editor-only and is not a foothold for this.

### 8.3 Z-levels and free camera — out of scope, and not a renderer decision

`session.mapGrid` is a char grid persisted through `engine/savegame.lua`;
movement, collision, traps, the light bake, `data/maps.json` and the editor's
map/light/material layers all assume 2D cells and cardinal facing. Free analog
movement additionally invalidates the step-trigger model that traps and events
are built on — *"traps are ordinary events with a step trigger."*

This is an engine redesign wearing a renderer's clothes. It must be decided as
a **game design** question first, and never entered through the renderer.

---

## 9. Sequencing

| # | Step | Why here |
|---|---|---|
| 0 | Deterministic clock + screenshot gate (§3, §3.1) | Prerequisite for everything; closes the blind spot; one piece of work serves both the gate and editor preview |
| 1 | **Effekseer spike** — DLL loads, one effect on screen | An afternoon. Answers the only question that can sink §6 |
| 2 | **Effekseer in battle** (§6.4) — ortho camera + filmstrip preview | No renderer rewrite needed; all 28 entries live here |
| 3 | **Strategy B** (§4) — polygonal renderer, real matrices | The renderer rewrite |
| 4 | Effekseer in the world | Needs #3's matrices |
| 5 | Weighted variant resolution (§5.5), then kit pieces (§5) | |
| 6 | 3D townsfolk (§7) | |

Steps 1-2 are deliberately ahead of the renderer rewrite: they are independently
valuable, they do not depend on §4, and they front-load the work whose output
has value outside this project (§6.6).

---

## 10. Open decisions for the owner

1. ~~**Effekseer C API surface** — the go/no-go fact.~~ **Resolved 30.07.2026
   (§6.5.1): no C API exists; a ~15-25 function `extern "C"` shim is required,
   which is the vendor's own pattern for non-C++ hosts. Not a blocker.**
2. **Install a C++ toolchain** — now the actual blocker on step 1. Owner
   action; see `userPerform/README.md`. MinGW-w64 is sufficient and is the
   smaller install.
3. **Missing-DLL behaviour** — hard error or degrade? (§6.5.4)
4. **Texel density standard** for models vs. the 64px atlas (§5.4)
5. **SPEC §1.2 amendment** recording effects-as-asset (§6.2)

---

## 11. Scope calibration against prior migrations

Diffstats from twelve prior migrations in this repo:

| Migration | Date | Files | Delta lines |
|---|---|---|---|
| Data-authored windows (infrastructure) | 15.07 | 4 | +650 / -12 |
| Convert menu scenes to windows | 15.07 | 2 | +526 / -407 |
| Centralized animation player | 15.07 | 8 | +790 / -151 |
| Delete legacy replicas; flows canonical | 17.07 | 2 | +17 / -40 |
| Battle scene to windows | 18.07 | 8 | +373 / -245 |
| **Dialogue to command language** | 18.07 | **26** | **+2,736 / -1,958** |
| Dialogue scene to windows-drawn | 18.07 | 6 | +183 / -111 |
| Semantic tiles + lighting + editor | 22.07 | 10 | +377 / -19 |
| Item Creation to declarative windows | 25.07 | 5 | +283 / -653 |
| Reachability + coherence checks | 26.07 | 7 | +508 / -44 |
| Battler placement/anchor unification | 29.07 | 13 | +546 / -201 |
| Persistent dock (host-owned surface) | 29.07 | 11 | +629 / -316 |

Strategy B (~1,200 lines, one file, no schema change) sits comfortably inside
this envelope — smaller in blast radius than the dialogue migration and
touching fewer files than almost all of them.

Two lessons from that history apply directly:

1. **Every successful migration here narrowed something** — one window
   renderer, one animation player, one flow interpreter, one dock, one battler
   placement authority. §4 fits: it collapses three parallel shading paths
   (wall column / floor shader / sprite stripe, each with its own fog and light
   code) into one. §8.3 does the opposite, which is part of why it is deferred.
2. **The recurring failure mode is the ungated change.** Hence §3 first.
