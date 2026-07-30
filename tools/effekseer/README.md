# Effekseer spike (30.07.2026)

> **Spike output, not a wired-in feature.** Nothing in the engine calls any of
> this. It exists to answer the questions in
> [`docs/design/renderer-3d-roadmap.md`](../../docs/design/renderer-3d-roadmap.md)
> §6 before committing to a native dependency. Do not treat its presence as a
> decision that Effekseer is in.

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
| `efk_shim.cpp` | The `extern "C"` wrapper. 14 exported functions, ints and floats only; every `RefPtr`/vtable stays sealed C++-side |
| `spike/main.lua` | LOVE harness: FFI-loads the DLL, plays an effect, auto-captures and exits |
| `spike/conf.lua` | 800x600 window for the harness |
| `spike/spike-result.png` | The captured proof frame |

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
- Any engine wiring. Step 2 of the roadmap (Effekseer in battle behind an
  orthographic camera) has not started.
- Determinism plumbing. `efk_update` already takes an explicit delta in
  Effekseer frame units rather than reading a clock, which is what §3.1
  requires, but nothing drives it from the harness clock yet.
