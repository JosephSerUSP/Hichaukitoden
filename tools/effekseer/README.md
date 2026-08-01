# Effekseer spike (30.07.2026)

> **Spike output that answered the go/no-go question.** This directory is the
> feasibility spike that decided Effekseer was worth wiring in — it exists to
> answer the questions in
> [`docs/design/renderer-3d-roadmap.md`](../../docs/design/renderer-3d-roadmap.md)
> §6, not to serve as the current status of the integration. **Effekseer is now
> wired into the engine**: `presentation/effekseer.lua` drives it as an
> animation track type (`effekseer` in `data/animations.json`), it is
> previewed in the editor, and a frozen fixture effect is covered by G5. For
> what exists today, read `presentation/effekseer.lua` and
> `docs/design/renderer-3d-roadmap.md` §6, not this file — the technical
> findings below (build recipe, z-order trap, GL state guard) remain accurate
> and are still the reference for anyone touching the shim, but the framing
> ("nothing calls this", "engine wiring... has not started") describes the
> state as of the spike, not now.

## What it answered

| Question | Answer |
|---|---|
| Does Effekseer expose a C API LuaJIT FFI can bind? | **No** — zero `extern "C"` in the runtime. A shim is required (§6.5.1) |
| Can the runtime be built without MSVC? | **Yes** — MinGW-w64, keeping the dependency to a ~250MB MSYS2 install (§6.5.1a) |
| Does the shim load and initialise against LOVE's own GL context? | **Yes** |
| Does an effect actually render inside a LOVE frame? | **Yes** — see `spike/spike-result.png` |
| Does Effekseer corrupt LOVE's cached GL state? | **No, once guarded** (§6.5.2) |

That last one was the risk most likely to sink this, so it was tested hardest:
`spike/main.lua` draws LOVE content before *and* after the effect, and exercises
a **custom shader, a scissor, an additive blend mode and a render-to-canvas**
across the effect draw — the states LOVE actually caches. All render correctly.

## Files

| File | What |
|---|---|
| `efk_shim.cpp` | The `extern "C"` wrapper. Plain ints/floats only; every `RefPtr`/vtable stays sealed C++-side. Separate entry points own screen-overlay and world-camera draws |
| `spike/main.lua` | LOVE harness: FFI-loads the DLL, plays an effect, auto-captures and exits |
| `spike/conf.lua` | 800x600 window for the harness |
| `spike/canvas-main.lua` | The one that matters for step 2: effect into a 256x240 canvas with a screen-space ortho camera |
| `spike/spike-result.png` | Proof frame: effect + LOVE state intact |
| `spike/spike-zorder-bug.png` | The batch-flush bug, for comparison |
| `spike/spike-canvas-256x240.png` | Effect rendering inside the game's real canvas |

## Authoring scale (read before making effects)

`efk_load_effect(path, magnification)` exists because effects are authored in
world units, and under a 1-unit-per-pixel camera a 3D-scale effect renders about
20px across.

**Magnification is a workaround, not the fix.** Scaling up yields soft, linearly
filtered gradients that fight hand-authored pixel art. Author effects **at game
scale** — particles sized in the tens of pixels, small crisp textures, hard
edges over soft gradients. Cheap now, expensive to retrofit across a finished
library. See roadmap §6.5.1d.

The built DLL is **not** committed (6.4MB build artifact, gitignored). Build it
with the recipe in roadmap §6.5.1a, then:

```bash
g++ -shared -O2 -o effekseer_shim.dll efk_shim.cpp \
  -I <efk>/Dev/Cpp/Effekseer -I <efk>/Dev/Cpp/EffekseerRendererGL \
  -I <efk>/Dev/Cpp/EffekseerRendererCommon \
  -L <build>/Dev/Cpp/Effekseer -L <build>/Dev/Cpp/EffekseerRendererGL \
  -L <build>/Dev/Cpp/EffekseerRendererCommon \
  -lEffekseerRendererGL -lEffekseerRendererCommon -lEffekseer -lopengl32 -lgdi32 \
  -static -static-libgcc -static-libstdc++ -Wl,--exclude-all-symbols
```

`-static` matters: without it the DLL pulls in `libwinpthread-1.dll` and stops
being a single self-contained file. As built it depends only on `KERNEL32`,
`msvcrt` and `OPENGL32`.

## The z-order trap (found via prior art, 30.07.2026)

**LOVE batches draw calls. You must flush its batch before drawing effects, or
they render behind everything LOVE queued that frame.**

```lua
love.graphics.flushBatch()   -- present in LOVE 11.5; call before efk_draw
efk.efk_draw(view, proj)
```

Credit where due: this came from
[`gittup/EffekseerForLove`](https://github.com/gittup/EffekseerForLove), which
documents it in `src/wrap/EffectManager.cpp`. That project has no
`flushBatch` available in its target and pokes `love.graphics.setColorMask`
instead, which forces a flush as a side effect. On 11.5 the direct call
exists, so use it.

`spike/spike-zorder-bug.png` is the failure and `spike/spike-result.png` the
fix, from the same harness with `FLUSH` toggled.

**Note on how nearly this was missed.** The first probe appeared to pass — but
it drew a text label between the quad and the effect, and switching to the font
texture makes LOVE flush anyway, hiding the bug. Any state change that forces a
batch flush will mask this. When testing draw ordering, the shape under test
must be the **last** LOVE call before `efk_draw`.

## The GL state guard

`GLStateGuard` in `efk_shim.cpp` saves and restores the program, VAO, array and
element buffer bindings, active texture unit, 2D texture binding, blend /
depth-test / cull-face enables, and the depth write mask around every
`efk_draw`. `glGetIntegerv` is GL 1.1 and links directly; the setters are GL
2.0+ and are resolved at runtime via `wglGetProcAddress` with a
`GetProcAddress` fallback.

**This is the load-bearing part of the integration.** If LOVE ever renders
incorrectly *after* an effect, look here first, and extend the saved set rather
than working around it at the call site.

## What is deliberately not here

- Effekseer's sound backends — all four are switched off at configure time.
  LOVE owns audio.
- Engine wiring. That now lives in `presentation/effekseer.lua` and the
  `effekseer` animation track type, not in this spike directory — see the
  callout at the top of this file.
- Determinism plumbing. `efk_update` already takes an explicit delta in
  Effekseer frame units rather than reading a clock, which is what §3.1
  requires, but nothing drives it from the harness clock yet.

## Determinism: the shim owns the RNG (01.08.2026)

**Rebuild the DLL if yours predates this** — `efk_set_random_seed` is a new
export, and without it effect playback is not reproducible.

Effekseer seeds every played instance from `Manager`'s rand func, which
defaults to `ManagerImplemented::Rand` -> plain `rand()`. That reads the C
runtime's **process-global** RNG state, which nothing in this project pins:
`math.randomseed` seeds LuaJIT's own PRNG, not `srand`. So the same effect
played from the same fixed clock rendered differently in every process, and
G5's fixture frame could never be byte-reproduced.

The shim now installs its own xorshift32 via `SetRandFunc` at `efk_init`, and
exposes `efk_set_random_seed(seed)`; the screenshot harness reseeds per scene
alongside `math.randomseed`. Verified: two consecutive full runs are 123/123
identical **including** the frame with a live effect, and changing the seed to
999 changes that frame and only that frame.

## World-camera pass (01.08.2026)

`efk_draw_world(view, projection, zNear, zFar)` is distinct from the late
screen-space overlay. It preserves LOVE's populated world depth attachment and
draws directly into the full 256x240 world canvas. Lua bridges the game's X/Y
floor, Z-up convention to Effekseer's conventional X/Z floor, Y-up axes. The
`env_mist` is gated visibly at its authored frame-400 opacity milestone while
the populated world depth attachment is preserved. `env_rain` loads, emits and
renders in the screen-space pass at frame 100, but produces no pixels through
the perspective pass even without textures or an axis-fixed sprite. It remains
a perspective-renderer compatibility follow-up.
