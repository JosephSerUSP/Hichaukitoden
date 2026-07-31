-- Effekseer runtime binding (LuaJIT FFI over tools/effekseer/efk_shim.cpp).
--
-- WHY A SHIM: Effekseer exposes no C API -- its runtime is C++ with RefPtr
-- smart pointers and pure-virtual interfaces, which the C ABI cannot express.
-- The shim keeps all of that sealed C++-side and exports ints and floats. See
-- docs/design/renderer-3d-roadmap.md 6.5.1 and tools/effekseer/README.md.
--
-- DEGRADATION (owner decision, 30.07.2026): a missing or unloadable DLL logs
-- ONCE and disables effects; it does not raise. This deliberately bends "fail
-- loud, never silently" so that a clean checkout, and every gate, still runs
-- without a compiled native dependency. The loud one-time log is the
-- compromise: silent absence would be the outcome the non-negotiables call the
-- worst one, so `available()` is queryable and the warning names the reason.
--
-- The engine never calls this. It is presentation-only, reached through
-- animation_player, exactly like the LOVE ParticleSystem path it complements.
local effekseer = {}

local ok_ffi, ffi = pcall(require, "ffi")

local lib = nil
local initialised = false
local failed = false
local warned = false
local suppressed = false
-- engine.json effekseer.magnification; 1.0 until init(loader) supplies it.
local globalMagnification = 1.0
local effectCache = {}   -- path|magnification -> effect id
local liveHandles = {}

-- Effekseer positions effects in the coordinates the projection defines. Under
-- the screen-space orthographic camera below that is CANVAS PIXELS, which is
-- why play() takes the same numbers battler_geometry.anchor() returns.
local GAME_W, GAME_H = 256, 240

local function warnOnce(reason)
    if warned then return end
    warned = true
    print("[effekseer] effects disabled: " .. tostring(reason))
    print("[effekseer] build the shim per tools/effekseer/README.md to enable them")
end

local CDEF = [[
int  efk_init(int instanceMax, int squareMaxCount);
void efk_shutdown(void);
int  efk_load_effect(const char* utf8Path, float magnification);
void efk_release_effect(int effectId);
int  efk_play(int effectId, float x, float y, float z);
void efk_stop(int handle);
void efk_stop_all(void);
int  efk_exists(int handle);
void efk_set_location(int handle, float x, float y, float z);
int  efk_instance_count(void);
void efk_update(float deltaFrame);
void efk_set_time(float seconds);
void efk_draw(const float* view16, const float* proj16);
const char* efk_last_error(void);
]]

local viewBuf, projBuf

-- Identity view; the orthographic projection does all the work.
local IDENTITY = { 1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1 }

-- Effekseer's OrthographicRH, patched so the origin is top-left and one unit
-- is one canvas pixel -- matching LOVE's coordinate system. Recipe adapted
-- from gittup/EffekseerForLove (roadmap 6.5.1c).
--
-- NOTE THE Y SIGN. EffekseerForLove needs an explicit y negation to get a
-- top-left origin because it draws to the BACKBUFFER. This game always renders
-- into a Canvas, and an OpenGL FBO's origin is bottom-left, so that flip is
-- already applied for us -- negating again puts effects at (x, 240 - y).
-- Verified against the battle scene: an effect anchored to an enemy's centre
-- landed at y=153 instead of y=78. A centred test effect cannot reveal this,
-- which is exactly how it survived the standalone spike (roadmap 6.5.1e).
local function orthoScreen(w, h, zn, zf)
    local m = {
        2 / w, 0, 0, 0,
        0, 2 / h, 0, 0,
        0, 0, 1 / (zn - zf), 0,
        0, 0, zn / (zn - zf), 1,
    }
    m[13] = -1        -- Values[3][0]
    m[14] = -1        -- Values[3][1]
    return m
end

local function toBuf(buf, m)
    for i = 1, 16 do buf[i - 1] = m[i] end
end

local function dllPath()
    -- Next to the game, not inside the .love archive: FFI needs a real file on
    -- disk, which love.filesystem paths inside an archive are not.
    return (love.filesystem.getSourceBaseDirectory() or ".") .. "/effekseer_shim.dll"
end

-- Loads the DLL and initialises the runtime. Safe to call repeatedly; only the
-- first call does work. Requires a live GL context, so call it after the
-- window exists, never at require time.
--
-- `loader` supplies engine.json's `effekseer.magnification`: ONE constant
-- normalising the effect library's authoring scale to canvas pixels, rather
-- than the same number repeated on every track. Effekseer's units are
-- arbitrary, so this is purely a property of how the effects were authored --
-- exactly the kind of number that belongs in the registry and the Engine
-- editor, not scattered through animations.json.
function effekseer.init(loader)
    if loader and loader.engine and loader.engine.effekseer
        and type(loader.engine.effekseer.magnification) == "number" then
        globalMagnification = loader.engine.effekseer.magnification
    end
    if initialised or failed then return initialised end
    if not ok_ffi then failed = true warnOnce("LuaJIT FFI unavailable") return false end

    local okDef = pcall(ffi.cdef, CDEF)
    if not okDef then failed = true warnOnce("cdef failed") return false end

    local okLoad, loaded = pcall(ffi.load, dllPath())
    if not okLoad then
        okLoad, loaded = pcall(ffi.load, "effekseer_shim")   -- fall back to PATH
    end
    if not okLoad then failed = true warnOnce("effekseer_shim.dll not found") return false end
    lib = loaded

    if lib.efk_init(2000, 2000) == 0 then
        failed = true
        warnOnce("efk_init failed: " .. ffi.string(lib.efk_last_error()))
        return false
    end

    viewBuf = ffi.new("float[16]")
    projBuf = ffi.new("float[16]")
    toBuf(viewBuf, IDENTITY)
    toBuf(projBuf, orthoScreen(GAME_W, GAME_H, -512, 512))

    initialised = true
    return true
end

function effekseer.available()
    return initialised and not failed
end

-- Loads (and caches) an effect.
--
-- Effective scale is the GLOBAL constant (engine.json `effekseer.magnification`
-- -- the library's authoring convention) MULTIPLIED by the track's own optional
-- magnification (an artistic tweak for one effect). A track that wants the
-- house scale simply omits it.
--
-- Effekseer's units are arbitrary, and the screen-space camera makes one unit
-- one canvas pixel, so this constant is what puts a source texel on a canvas
-- pixel. Off it in either direction costs sharpness: below, the texture is
-- minified; above, interpolated and soft (roadmap 6.5.1d).
function effekseer.loadEffect(path, magnification)
    if not effekseer.available() then return nil end
    magnification = globalMagnification * (magnification or 1.0)
    local key = path .. "|" .. tostring(magnification)
    if effectCache[key] ~= nil then
        return effectCache[key] or nil
    end
    local id = lib.efk_load_effect(path, magnification)
    if id < 0 then
        print("[effekseer] failed to load '" .. tostring(path) .. "': "
            .. ffi.string(lib.efk_last_error()))
        effectCache[key] = false
        return nil
    end
    effectCache[key] = id
    return id
end

-- x, y are CANVAS PIXELS (256x240 space) -- the same coordinates
-- battler_geometry.anchor() produces.
function effekseer.play(path, x, y, magnification)
    if not effekseer.available() then return nil end
    local id = effekseer.loadEffect(path, magnification)
    if not id then return nil end
    local handle = lib.efk_play(id, x, y, 0)
    if handle >= 0 then liveHandles[handle] = true end
    return handle
end

function effekseer.stop(handle)
    if not effekseer.available() or not handle then return end
    lib.efk_stop(handle)
    liveHandles[handle] = nil
end

function effekseer.stopAll()
    if not effekseer.available() then return end
    lib.efk_stop_all()
    liveHandles = {}
end

function effekseer.setLocation(handle, x, y)
    if not effekseer.available() or not handle then return end
    lib.efk_set_location(handle, x, y, 0)
end

function effekseer.instanceCount()
    if not effekseer.available() then return 0 end
    return lib.efk_instance_count()
end

-- dt is SECONDS; Effekseer counts in 60fps frames. Driven by the caller's dt
-- rather than any clock of Effekseer's own, so the screenshot gate and the
-- editor's preview-anim filmstrip can step it deterministically (roadmap 3.1).
function effekseer.update(dt)
    if not effekseer.available() or suppressed then return end
    lib.efk_update(dt * 60.0)
end

-- Freezes effect time without stopping effects.
--
-- The screenshot harness settles animations by advancing a whole second in one
-- step, which is right for panels and gauges but fatal for effects: anything
-- shorter than 1s is over before the frame is captured, so G5 -- the only gate
-- that can see effects -- would be blind to every short one. The harness
-- suppresses during the settle, then advances effects by a small fixed amount,
-- capturing them mid-life and deterministically.
function effekseer.setSuppressed(value)
    suppressed = value and true or false
end

function effekseer.setTime(seconds)
    if not effekseer.available() then return end
    lib.efk_set_time(seconds)
end

-- Draws every live effect. MUST be preceded by love.graphics.flushBatch():
-- LOVE batches draws, and without a flush the effects render behind everything
-- LOVE queued this frame (roadmap 6.5.1c -- this was a real bug, see
-- tools/effekseer/spike/spike-zorder-bug.png).
function effekseer.draw()
    if not effekseer.available() then return end
    love.graphics.flushBatch()
    lib.efk_draw(viewBuf, projBuf)
end

-- Spawns any due `effekseer` tracks for `target`, anchored against its rect.
--
-- This bridge lives HERE rather than in animation_player because that module
-- keeps a deliberate invariant of knowing nothing about screen geometry, and
-- rather than in battler_geometry because that is the bottom of the dependency
-- stack (ui + battle_layout only). This module may know both, so the two
-- drawers that hold a rect -- renderer.lua for enemies, small_battlers.lua for
-- party members -- each get one call instead of duplicating the resolution.
function effekseer.spawnFor(target, rect)
    if not effekseer.available() or not rect then return end
    local animation_player = require("presentation.animation_player")
    local due = animation_player.consumeEffekseerSpawns(target)
    if not due then return end
    local battler_geometry = require("presentation.battler_geometry")
    for _, spawn in ipairs(due) do
        if spawn.effect then
            local x, y = battler_geometry.anchor(rect, spawn.anchor)
            if x then effekseer.play(spawn.effect, x, y, spawn.magnification) end
        end
    end
end

function effekseer.reset()
    effekseer.stopAll()
end

return effekseer
