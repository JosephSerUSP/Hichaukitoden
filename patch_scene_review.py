with open('engine/scene.lua', 'r') as f:
    code = f.read()

code = code.replace('-- Fire on_enter\n    scene.runHook("on_enter")', '-- Fire on_enter\n    return scene.runHook("on_enter")')
code = code.replace('function scene.update(dt)\n    if not activeScene then return false end\n    return scene.runHook("on_frame")', 'function scene.update(dt)\n    if not activeScene then return false end\n    activeScene.ctx.dt = dt\n    return scene.runHook("on_frame")')

with open('engine/scene.lua', 'w') as f:
    f.write(code)

with open('main.lua', 'r') as f:
    main = f.read()

main = main.replace('scene_host.push({ session = activeSession, loader = loader }, 1)\n                    if initCraftingScene then initCraftingScene() end', 'if not scene_host.push({ session = activeSession, loader = loader }, 1) then\n                        if initCraftingScene then initCraftingScene() end\n                    end')

with open('main.lua', 'w') as f:
    f.write(main)
