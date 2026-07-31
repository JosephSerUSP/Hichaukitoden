-- Does Effekseer render INTO a bound LOVE Canvas, in screen-space pixel
-- coordinates, at the game's real 256x240 resolution?
--
-- This is the shape Hichaukitoden actually renders in: everything is drawn to
-- a 256x240 canvas and scaled 3x at the end. If effects cannot land in that
-- canvas, roadmap step 2 does not work regardless of anything proven so far.
--
-- Ortho recipe from gittup/EffekseerForLove (roadmap 6.5.1c): OrthographicRH
-- then patch the translation row so the origin is top-left, matching LOVE.
local ffi = require("ffi")

ffi.cdef [[
int  efk_init(int instanceMax, int squareMaxCount);
void efk_shutdown(void);
int  efk_load_effect(const char* utf8Path, float magnification);
int  efk_play(int effectId, float x, float y, float z);
void efk_update(float deltaFrame);
void efk_draw(const float* view16, const float* proj16);
int  efk_instance_count(void);
const char* efk_last_error(void);
]]

local GAME_W, GAME_H, SCALE = 256, 240, 3

local efk, canvas, effectId
local log = {}
local frame = 0

local function say(f, ...) local s = string.format(f, ...) table.insert(log, s) print(s) end

local viewBuf = ffi.new("float[16]")
local projBuf = ffi.new("float[16]")

-- Identity view; the ortho projection does all the work.
local function identity()
    return { 1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1 }
end

-- Effekseer's OrthographicRH(w,h,zn,zf), then the top-left-origin patch.
local function orthoScreen(w, h, zn, zf)
    local m = {
        2 / w, 0, 0, 0,
        0, 2 / h, 0, 0,
        0, 0, 1 / (zn - zf), 0,
        0, 0, zn / (zn - zf), 1,
    }
    -- NOTE: no y negation. EffekseerForLove negates because it draws to the
    -- BACKBUFFER; we render into a Canvas, whose FBO origin is already
    -- bottom-left, so negating again mirrors everything about the midline.
    -- See roadmap 6.5.1e -- this harness originally had the bug and could not
    -- show it, because it played its effect at the exact canvas centre.
    m[13] = -1            -- Values[3][0]
    m[14] = -1            -- Values[3][1]
    return m
end

local function toBuf(buf, m) for i = 1, 16 do buf[i - 1] = m[i] end end

function love.load()
    love.window.setMode(GAME_W * SCALE, GAME_H * SCALE)
    canvas = love.graphics.newCanvas(GAME_W, GAME_H)
    canvas:setFilter("nearest", "nearest")

    efk = ffi.load("D:/efk2/shim/effekseer_shim.dll")
    if efk.efk_init(2000, 2000) == 0 then
        say("init FAILED: %s", ffi.string(efk.efk_last_error())) return
    end
    effectId = efk.efk_load_effect("D:/efk2/Dev/Cpp/Test/Resource/Laser01.efk", 8.0)
    say("init+load OK (id=%d)", effectId)
    -- Screen-space: play at the centre of the 256x240 canvas.
    efk.efk_play(effectId, 128, 120, 0)
    say("magnification 8x")
end

function love.update(dt)
    frame = frame + 1
    if efk and effectId and effectId >= 0 then efk.efk_update(dt * 60.0) end
    if frame == 40 then love.graphics.captureScreenshot("canvas-test.png")
    elseif frame == 45 then if efk then efk.efk_shutdown() end love.event.quit() end
end

function love.draw()
    -- ---- everything below renders INTO the 256x240 game canvas ----
    love.graphics.setCanvas(canvas)
    love.graphics.clear(0.05, 0.05, 0.08, 1)

    love.graphics.setColor(0.8, 0.7, 0.2, 1)
    love.graphics.print("CANVAS 256x240", 4, 4)
    love.graphics.setColor(0.30, 0.22, 0.10, 1)
    love.graphics.rectangle("fill", 40, 70, 176, 100)   -- last call before the effect

    if efk and effectId and effectId >= 0 then
        love.graphics.flushBatch()                       -- the 6.5.1c fix
        toBuf(viewBuf, identity())
        toBuf(projBuf, orthoScreen(GAME_W, GAME_H, -512, 512))
        efk.efk_draw(viewBuf, projBuf)
    end

    love.graphics.setColor(0.4, 0.9, 1.0, 1)
    love.graphics.print("drawn AFTER effect, in canvas", 4, 220)
    love.graphics.setCanvas()
    -- ---- canvas done; upscale it like the real game does ----

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(canvas, 0, 0, 0, SCALE, SCALE)

    for i, line in ipairs(log) do
        love.graphics.print(line, 8, 8 + i * 16)
    end
    love.graphics.print("instances: " .. (efk and efk.efk_instance_count() or 0), 8, 80)
end
