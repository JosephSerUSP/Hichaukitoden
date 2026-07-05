function love.conf(t)
    t.identity = "Hichaukitoden"
    t.window.title = "Hichaukitoden"
    t.window.width = 768 -- 256 * 3
    t.window.height = 720 -- 240 * 3
    t.window.resizable = true
    t.window.minwidth = 256
    t.window.minheight = 240
    t.window.vsync = 1
    t.modules.joystick = true
    t.modules.keyboard = true
    t.modules.mouse = true
    t.modules.sound = true
    t.modules.system = true
    t.modules.timer = true
    t.modules.window = true
    t.modules.graphics = true
    t.modules.image = true
    t.modules.audio = true
    t.console = true
end
