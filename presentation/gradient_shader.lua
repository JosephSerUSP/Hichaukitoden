-- Shared gradient-map shader.
-- Remap sprite luminance to a low→high color ramp, mixed with the original
-- by `intensity`. Alpha is preserved so transparent pixels stay transparent.
-- This matches the shader used in main.lua's animation preview exactly.

local gradient_shader = {}

local _shader = nil

function gradient_shader.get()
    if not _shader then
        _shader = love.graphics.newShader([[
            extern vec3 lowColor;
            extern vec3 highColor;
            extern number intensity;
            vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
                vec4 px = Texel(tex, tc);
                number lum = dot(px.rgb, vec3(0.299, 0.587, 0.114));
                vec3 mapped = mix(lowColor, highColor, lum);
                vec3 outc = mix(px.rgb, mapped, intensity);
                return vec4(outc, px.a) * color;
            }
        ]])
    end
    return _shader
end

-- Draw fn: apply gradient map if active, otherwise draw normally.
-- `target`     – animation_player key (battler object)
-- `drawFn`     – function() that issues the actual love.graphics.draw call
-- `animation_player` – the module (passed to avoid a circular require)
function gradient_shader.drawWithGradient(target, drawFn, anim_player)
    local gm = anim_player.getGradientMap(target)
    if gm then
        local sh = gradient_shader.get()
        sh:send("lowColor",  { gm.low[1],  gm.low[2],  gm.low[3]  })
        sh:send("highColor", { gm.high[1], gm.high[2], gm.high[3] })
        sh:send("intensity", gm.intensity)
        love.graphics.setShader(sh)
        drawFn()
        love.graphics.setShader()
    else
        drawFn()
    end
end

return gradient_shader
