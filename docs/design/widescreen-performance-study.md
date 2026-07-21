# Widescreen Performance Study: 480×270 Map Renderer

> **Question:** How much more performance expensive would it be to expand the renderer to render a full 480×270 map (vs the current 256×240)?

---

## Design Approach: Viewport-Only Expansion

The widescreen mode **does not** reflow the UI or change the game's composition. The canvas becomes 480×270 (16:9), and the 3D viewport is the only thing that renders into the new screen area. The UI layout stays exactly as-authored at 256×240 — positioned relative to the original tile grid, centered within the wider canvas.

```
┌──────────────────────────────────────────────┐
│               480px wide                      │
│  ┌──────────────────────┐                     │
│  │   256×240 UI area    │    extra viewport   │
│  │   (tiles 0..31)      │    rendering only   │
│  │                      │    (tiles 32..59)   │
│  │  ┌──── UI ────┐      │                     │
│  │  │ windows    │      │                     │
│  │  │ panels     │      │                     │
│  │  │ text       │      │                     │
│  │  └────────────┘      │                     │
│  └──────────────────────┘                     │
└──────────────────────────────────────────────┘
```

The 3D viewport renders `480 × 270` — a wider horizontal FOV, more sky/floor visible top and bottom. Tile-based UI elements remain at 32×30 tiles (their current `ui.screenWidthTiles = 32`), centered on the 480-wide canvas at offset `(480 - 256) / 2 = 112` px from the left. No window positions, text layouts, or battle element coordinates need to change.

**What changes:**
- Game canvas size: 256×240 → 480×270
- 3D viewport dimensions: 256×144 → 480×270
- Wall raycast columns: 256 → 480
- Floor/ceiling shader: 256×144 → 480×270

**What stays the same:**
- All UI positions in tile coordinates (32×30 grid)
- Window geometries, text layouts, panel positions
- Party grid, enemy positions, battle layout
- All authored scene data

---

## Current Architecture (Baseline)

| Property | Current Value |
|---|---|
| Game resolution | `256 × 240` (4:3) — [`main.lua:42`](main.lua:42) |
| Viewport (3D map) | `256 × 144` — [`viewport_3d.lua:496`](presentation/viewport_3d.lua:496) |
| Tile size | 8×8 px — [`ui.lua:195`](presentation/ui.lua:195) |
| Screen tiles | 32 wide × 30 tall — [`ui.lua:197`](presentation/ui.lua:197) |
| Wall ray columns | 256 — [`viewport_3d.lua:598`](presentation/viewport_3d.lua:598) |
| Floor/ceiling pixels | 36,864 total (256×144) |
| Framebuffer | 256×240 canvas, scaled 3× to 768×720 window — [`conf.lua:5`](conf.lua:5) |

---

## Proposed Target: 480×270 (16:9 Widescreen)

- Width increases from **256 → 480** (1.875×)
- Height increases from **240 → 270** (1.125×)
- Aspect ratio changes from **4:3 → 16:9**
- **UI layout stays at 32×30 tiles**, centered within the wider canvas

---

## Performance Impact Breakdown

### 1. Wall Raycaster — CPU-bound (Lua loop)

The wall raycasting loop at [`viewport_3d.lua:598`](presentation/viewport_3d.lua:598) iterates once per screen column:

```lua
for x = 0, 255 do                    -- → 0, 479  (480 iterations)
    -- DDA raycast (up to 16 steps)
    -- Perp-wall distance calculation
    -- Atlas tile lookup
    -- drawFogLayers() per column
    -- GPU draw call per column
end
```

| Metric | 256 cols | 480 cols | Factor |
|---|---|---|---|
| Loop iterations | 256 | 480 | **1.88×** |
| DDA steps (max) | 4,096 | 7,680 | **1.88×** |
| drawFogLayers calls | 256 | 480 | **1.88×** |
| Draw calls per column | 256 | 480 | **1.88×** |

**Impact: ~1.88× more CPU work** for the wall raycaster. This is the most significant **CPU** bottleneck since each iteration involves Lua math operations, DDA stepping, and texture atlas quad updates.

### 2. Floor/Ceiling Shader — GPU-bound (pixel shader)

The fragment shader at [`viewport_3d.lua:302`](presentation/viewport_3d.lua:302) runs once per screen pixel in the viewport. The viewport would grow from 256×144 to 480×270:

| Metric | Current | 480×270 | Factor |
|---|---|---|---|
| Viewport pixels | 36,864 | 129,600 | **3.52×** |

The shader does per-pixel work including:
- `rowDist`, `cameraX`, `rayDir` computation
- World position reconstruction
- Atlas texture fetch + bilinear-ish variant
- Light texture fetch
- Fog alpha blending

**Impact: ~3.5× more GPU pixel work.** This is the single largest scaling factor. However, on modern GPUs (even integrated), a 129K-pixel shader pass is trivially small — this is unlikely to be a real bottleneck.

### 3. Sprite Billboard Rendering — CPU + GPU

The sprite rendering loop at [`viewport_3d.lua:804`](presentation/viewport_3d.lua:804) iterates per-stripe-per-sprite:

```lua
for stripeX = drawStartX, drawStartX + spriteWidth - 1 do
    if stripeX >= 0 and stripeX < 256 then     -- → < 480
```

| Metric | Current Max | 480×270 Max | Factor |
|---|---|---|---|
| Sprite stripe width (pixels) | ~256 | ~480 | **1.88×** |
| zBuffer checks per sprite | 256 | 480 | **1.88×** |
| Scissor + draw calls per sprite | ~same | ~same | **1.88×** (stripes) |

**Impact: ~1.88× more per-sprite work.** The number of sprites is unchanged, but each sprite can be wider on screen.

### 4. Framebuffer Operations — GPU

With the viewport-only approach, the canvas grows to 480×270, but UI is centered within it:

| Metric | Current | 480×270 | Factor |
|---|---|---|---|
| Canvas pixels | 61,440 | 129,600 | **2.11×** |
| Window scale | 3× (768×720) | 2× (960×540) or 3× (1440×810) | varies |

**Impact: ~2.1× more pixels for clear + blit.** The window scale factor can be reduced to compensate (e.g., 2× instead of 3× gives a 960×540 window, smaller than current).

### 5. UI System (Windows, Text, Panels) — CPU (Unchanged)

Under the viewport-only approach, the UI system at [`window_renderer.lua`](presentation/window_renderer.lua) is **completely unaffected**:

| Metric | Current | With viewport-only | Factor |
|---|---|---|---|
| Screen tiles | 32×30 | 32×30 | **1.0×** |
| UI element count | O(windows + panels) | O(windows + panels) | **1.0×** |
| Text strings | O(n) per window | O(n) per window | **1.0×** |
| Panel draws | O(1) per panel | O(1) per panel | **1.0×** |

**Impact: 1.0× (zero impact).** The UI is unaware of the wider canvas — it stays 32×30 tiles, centered. Only the 3D viewport behind it renders wider.

### 6. Battle Scene — CPU + GPU (Minimal Impact)

The battle scene draws through [`renderer.lua`](presentation/renderer.lua) which calls `viewport_3d.draw()` as the 3D background, then overlays enemy sprites and the party grid. Enemy and party positions are layout-defined (battleLayout), not resolution-dependent.

| Metric | Current | 480×270 | Factor |
|---|---|---|---|
| 3D background | 256×144 px | 480×270 px | **1.88–3.52×** |
| Enemy sprites | O(n_enemies) | O(n_enemies) | **1.0×** |
| Party grid (2×2) | O(4) cells | O(4) cells | **1.0×** |
| Damage popups | O(n_popups) | O(n_popups) | **1.0×** |

**Impact: ~1.0× on battle entities.** Only the 3D background rendering scales; the UI overlay is unaffected.

---

## Summary Table

| Subsystem | Type | Current | 480×270 | Scale Factor |
|---|---|---|---|---|
| Wall raycaster | **CPU** | 256 cols × DDA | 480 cols × DDA | **1.88×** |
| Floor/ceiling shader | **GPU** | 36,864 px | 129,600 px | **3.52×** |
| Sprite billboards | **CPU + GPU** | ~256 stripes/sprite | ~480 stripes/sprite | **1.88×** |
| Framebuffer clear+blit | **GPU** | 61,440 px | 129,600 px | **2.11×** |
| UI windows/panels | **CPU** | O(elements) | **No change** | **1.0×** |
| Battle sprites/grid | **CPU** | O(party+enemies) | **No change** | **1.0×** |
| **Blended estimate** | | | | **~1.9–2.5×** |

---

## Key Takeaways

### What scales the most:
1. **Floor/ceiling shader** (3.5× more pixels) — still trivially small for any GPU from the past 15 years
2. **Framebuffer operations** (2.1× more pixels) — negligible on modern hardware
3. **Wall raycaster + sprite loops** (1.88× more columns) — the **actual CPU bottleneck**

### What's NOT affected:
- Number of UI elements, windows, or scenes
- Number of enemies, party members, or battle entities
- Number of map events or sprites
- Any game logic (battle calculations, AI, event interpretation)

### Hardcoded Constants That Must Change

The current renderer has several hardcoded values that assume 256px width / 144px viewport:

| Location | Current | What it controls |
|---|---|---|
| [`viewport_3d.lua:598`](presentation/viewport_3d.lua:598) | `for x = 0, 255` | Wall raycast column count |
| [`viewport_3d.lua:328`](presentation/viewport_3d.lua:328) | `/ 256.0` in shader | Floor/ceiling camera projection |
| [`viewport_3d.lua:326`](presentation/viewport_3d.lua:326) | `70.0` (screen center Y) | Half viewport height for projection |
| [`viewport_3d.lua:672`](presentation/viewport_3d.lua:672) | `140` (projection constant) | Wall height scaling (`= 2 × center`) |
| [`viewport_3d.lua:822`](presentation/viewport_3d.lua:822) | `love.graphics.setScissor(0, 0, 256, 144)` | Sprite clipping bounds |
| [`main.lua:42`](presentation/main.lua:42) | `gameWidth, gameHeight = 256, 240` | Canvas size |
| [`conf.lua:5`](conf.lua:5) | `t.window.width = 768` | Initial window width |

### GPU Rendering Feasibility

The current renderer is a **hybrid**: the wall raycaster runs in Lua (CPU) and issues per-column `love.graphics.draw` calls; the floor/ceiling is a GPU fragment shader; sprites are CPU-driven with per-stripe scissor + draw. A natural question is whether moving the **entire** raycasting pipeline to the GPU would solve the scaling problem.

#### Option A: Full GPU Raycaster (compute shader)

Write the DDA raycast as a compute shader that outputs to a texture, then draw that texture as a full-screen quad.

| Pro | Con |
|---|---|
| Raycast scales with GPU cores, not CPU single-thread | Requires LÖVE 11.x+ with compute shader support — **LÖVE does not expose compute shaders** |
| Wall loop becomes a single draw call (1 quad) instead of 480 | DDA branching in GPU is less efficient per-core than CPU (warp divergence) |
| Free up Lua CPU time for game logic | Significantly more complex to debug and iterate |

**Verdict: Not feasible with LÖVE 11.x.** LÖVE does not expose compute shaders. The closest alternative is a fragment-shader-only approach (Option B), which can do the wall raycast in a single full-screen pass but loses the DDA's early-out (you pay per pixel, not per column).

#### Option B: Full GPU Fragment Shader (single-pass raycaster)

Render the full 3D viewport with a single fragment shader that does the DDA raycast per pixel.

| Pro | Con |
|---|---|
| One draw call, no per-column driver overhead | Every pixel traces its own ray — 129,600 DDA loops instead of 480 |
| Scales to any resolution without CPU changes | No early-out: pixels behind a wall still trace to max depth |
| The floor/ceiling is already a shader, could merge | Sprite handling becomes complex (need per-pixel z-buffer) |
| | Shader complexity: branching in GLSL for DDA is fragile and hard to maintain |

**Verdict: Technically possible but slower than the current approach.** A per-pixel DDA executes ~129K raycasts instead of 480 — 270× more raycasts. Modern GPUs can handle this (it's effectively what id Tech did in the 90s), but for a 2D-pixel-art game running in LÖVE, it is dramatically worse performance than the CPU approach, not better.

#### Why the CPU approach is the right call for this codebase

Claude Code's protectiveness was well-founded. Here's why keeping the wall raycaster on the CPU — even at 480 columns — is the pragmatic choice:

1. **The DDA itself is negligible.** 480 DDA traces × 16 steps max = 7,680 iterations/frame — that's ~0.13ms of integer math on a single 3GHz core. The real cost is the **480 draw calls**, not the DDA math.

2. **Batching draw calls** (wider strips or a pre-built vertex buffer) eliminates the actual bottleneck without touching the algorithm. One change, big impact.

3. **The CPU approach is simple, debuggable, and proven.** The DDA is ~80 lines of clear Lua with no shader complexity. Moving it to GLSL would make it harder to maintain — adding widescreen support to the existing code is far less risky than rewriting the raycaster in a different paradigm.

4. **LÖVE's strength is CPU-side 2D rendering.** Its GPU pipeline is designed for sprite batching and simple shader effects, not ray-traced scenes. Fighting the framework's design costs more than it saves.

**Recommendation:** Keep the CPU raycaster. If the 480 draw calls prove costly (unlikely on any machine from the last 10 years), batch adjacent wall columns into 2–4px strips — this reduces draw calls to ~120–240 with no visual quality loss at pixel-art scale.

### Performance Bottleneck Analysis

**In practice, the wall raycaster's draw call overhead is the real bottleneck**, not the shader or the DDA math. Here's why:

1. The wall loop is **Lua code** running on a single CPU thread — each of the 480 columns involves DDA stepping (up to 16 iterations of Lua math), atlas quad creation, and a GPU draw call.
2. The DDA stepping is ~0.13ms/frame — invisible. The ~480 `love.graphics.draw` calls are what cost.
3. The floor/ceiling shader runs on the **GPU** in parallel — 129K pixels is negligible for any GPU made after 2010.

**Real-world estimate:** A 480×270 widescreen renderer would be approximately **1.9–2.5× more expensive** than the current 256×240 renderer. The actual user-visible impact would be:
- On a **low-end machine** (e.g., integrated Intel HD Graphics 2000-era): might drop from 60 FPS → 30–35 FPS during map exploration
- On any **dedicated GPU or modern integrated graphics** (2015+): no visible difference, still 60 FPS

### Optimization Strategies for Widescreen

If performance is a concern, several mitigations exist:

1. **Batch wall columns** — render strips 2–4px wide instead of 1px columns, reducing draw calls from 480 → ~120–240. Zero visual impact at pixel-art scale.
2. **Use a pre-built vertex buffer** — build one mesh containing all wall column quads with pre-computed UVs, submit a single draw call per frame instead of 480.
3. **Reduce max DDA depth** from 16 to 12 (shorter view distance compensates for wider FOV).
4. **Lower floor/ceiling shader quality** by reducing the atlas resolution variant in-shader.
5. **Optional 30 FPS mode** for map exploration (battle scene can stay at full rate since it's less viewport-dependent).
