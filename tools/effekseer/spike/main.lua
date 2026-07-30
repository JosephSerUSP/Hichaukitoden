-- Effekseer spike harness: does the shim load and initialise against LOVE's
-- own GL context, render an effect, and leave LOVE's rendering intact?
-- The last question is the one that matters -- see roadmap 6.5.2.
local ffi = require("ffi")

ffi.cdef [[
int  efk_init(int instanceMax, int squareMaxCount);
void efk_shutdown(void);
int  efk_load_effect(const char* utf8Path);
int  efk_play(int effectId, float x, float y, float z);
void efk_stop(int handle);
int  efk_exists(int handle);
void efk_update(float deltaFrame);
void efk_set_time(float seconds);
void efk_draw(const float* view16, const float* proj16);
int  efk_instance_count(void);
const char* efk_last_error(void);
]]

local efk, lib
local effectId, handle = -1, -1
local log = {}
local t = 0

local function say(fmt, ...)
    local line = string.format(fmt, ...)
    table.insert(log, line)
    print(line)
end

-- Right-handed look-at and perspective, matching what the example builds via
-- Matrix44::LookAtRH / PerspectiveFovRH. Row-major, which is how the shim
-- copies into Effekseer::Matrix44::Values[r][c].
local function lookAtRH(ex, ey, ez, tx, ty, tz)
    local zx, zy, zz = ex - tx, ey - ty, ez - tz
    local zl = math.sqrt(zx * zx + zy * zy + zz * zz)
    zx, zy, zz = zx / zl, zy / zl, zz / zl
    local xx, xy, xz = -zz, 0, zx           -- up = (0,1,0) cross z
    local xl = math.sqrt(xx * xx + xy * xy + xz * xz)
    xx, xy, xz = xx / xl, xy / xl, xz / xl
    local yx = zy * xz - zz * xy
    local yy = zz * xx - zx * xz
    local yz = zx * xy - zy * xx
    return {
        xx, yx, zx, 0,
        xy, yy, zy, 0,
        xz, yz, zz, 0,
        -(xx * ex + xy * ey + xz * ez),
        -(yx * ex + yy * ey + yz * ez),
        -(zx * ex + zy * ey + zz * ez), 1,
    }
end

local function perspectiveRH(fovy, aspect, znear, zfar)
    local f = 1.0 / math.tan(fovy / 2)
    return {
        f / aspect, 0, 0, 0,
        0, f, 0, 0,
        0, 0, zfar / (znear - zfar), -1,
        0, 0, (znear * zfar) / (znear - zfar), 0,
    }
end

local viewBuf = ffi.new("float[16]")
local projBuf = ffi.new("float[16]")

local function toBuf(buf, m)
    for i = 1, 16 do buf[i - 1] = m[i] end
end

local tintShader, probeCanvas

function love.load()
    tintShader = love.graphics.newShader([[
        vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
            return vec4(0.15, 0.05, 0.35, 1.0) * color;
        }
    ]])
    probeCanvas = love.graphics.newCanvas(160, 64)

    local ok, err = pcall(function()
        lib = ffi.load("D:/efk2/shim/effekseer_shim.dll")
    end)
    if not ok then
        say("FFI LOAD FAILED: %s", tostring(err))
        return
    end
    efk = lib
    say("FFI load: OK")

    local r = efk.efk_init(2000, 2000)
    if r == 0 then
        say("efk_init FAILED: %s", ffi.string(efk.efk_last_error()))
        return
    end
    say("efk_init: OK (against LOVE's GL context)")

    effectId = efk.efk_load_effect("D:/efk2/Dev/Cpp/Test/Resource/Laser01.efk")
    if effectId < 0 then
        say("efk_load_effect FAILED: %s", ffi.string(efk.efk_last_error()))
        return
    end
    say("efk_load_effect: OK (id=%d)", effectId)

    handle = efk.efk_play(effectId, 0, 0, 0)
    say("efk_play: handle=%d", handle)
end

local frame = 0

function love.update(dt)
    t = t + dt
    frame = frame + 1
    -- Auto-capture then exit, so the spike proves itself with an image
    -- instead of a window nobody is watching.
    if frame == 45 then
        love.graphics.captureScreenshot("spike.png")
    elseif frame == 50 then
        if efk then efk.efk_shutdown() end
        say("clean shutdown")
        love.event.quit()
    end
    if efk and effectId >= 0 then
        -- Driven by an explicit step, not a wall clock: the same property the
        -- screenshot gate and the editor's preview-anim filmstrip need.
        efk.efk_update(dt * 60.0)
        if t > 2.0 and handle >= 0 and efk.efk_exists(handle) == 0 then
            handle = efk.efk_play(effectId, 0, 0, 0)
            t = 0
        end
    end
end

function love.draw()
    -- LOVE content BEFORE the effect.
    love.graphics.setColor(0.2, 0.4, 0.9, 1)
    love.graphics.rectangle("fill", 20, 20, 120, 60)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print("LOVE before Effekseer", 20, 90)

    if efk and effectId >= 0 then
        toBuf(viewBuf, lookAtRH(10, 5, 20, 0, 0, 0))
        toBuf(projBuf, perspectiveRH(90 / 180 * math.pi, 800 / 600, 1.0, 500.0))
        efk.efk_draw(viewBuf, projBuf)
    end

    -- LOVE content AFTER the effect. If the GL state guard in the shim is
    -- wrong, THIS is what breaks -- wrong colour, missing text, or nothing.
    love.graphics.setColor(0.9, 0.3, 0.2, 1)
    love.graphics.rectangle("fill", 20, 120, 120, 60)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print("LOVE after Effekseer", 20, 190)
    love.graphics.print("instances: " .. (efk and efk.efk_instance_count() or 0), 20, 210)

    -- Harder state test: a custom shader, a scissor and a non-default blend
    -- mode active across the effect draw. Simple shapes surviving proves very
    -- little; these are the states LOVE actually caches.
    love.graphics.setScissor(400, 380, 380, 200)
    love.graphics.setBlendMode("add")
    love.graphics.setShader(tintShader)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.rectangle("fill", 400, 380, 380, 200)
    love.graphics.setShader()
    love.graphics.setBlendMode("alpha")
    love.graphics.setScissor()
    love.graphics.print("shader+scissor+add AFTER effect", 400, 590)

    -- And the canvas path: render to a canvas, then draw it.
    love.graphics.setCanvas(probeCanvas)
    love.graphics.clear(0, 0, 0, 0)
    love.graphics.setColor(0.3, 0.9, 0.4, 1)
    love.graphics.rectangle("fill", 0, 0, 100, 40)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print("canvas OK", 4, 44)
    love.graphics.setCanvas()
    love.graphics.draw(probeCanvas, 620, 20)

    for i, line in ipairs(log) do
        love.graphics.print(line, 20, 250 + i * 16)
    end
end

function love.keypressed(k)
    if k == "escape" then
        if efk then efk.efk_shutdown() end
        love.event.quit()
    end
end
