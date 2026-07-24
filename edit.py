import re

with open('d:/Antigravity/Hichaukitoden/main.lua', 'r', encoding='utf-8') as f:
    text = f.read()

start_pattern = r'local function makeHarnessSession\(\).*?print\(\"GOLDEN END\"\)\nend\n'
match = re.search(start_pattern, text, re.DOTALL)
if match:
    text = text[:match.start()] + 'local cli_tools = require(\"engine.cli_tools\")\n' + text[match.end():]
    
    text = text.replace('runPreviewScene(previewSceneId)', 'cli_tools.runPreviewScene(previewSceneId, loader, gameWidth, gameHeight)')
    text = text.replace('runPreviewWindow(previewWindowId, previewWindowMockSpec)', 'cli_tools.runPreviewWindow(previewWindowId, previewWindowMockSpec, loader, gameWidth, gameHeight)')
    text = text.replace('runPreviewFont(previewFontName, tonumber(previewFontSize))', 'cli_tools.runPreviewFont(previewFontName, tonumber(previewFontSize))')
    text = text.replace('runPreviewAnim(previewAnimId, previewAnimJson, previewAnimSprite)', 'cli_tools.runPreviewAnim(previewAnimId, previewAnimJson, previewAnimSprite, loader)')
    text = text.replace('runPreviewMap(previewMapId, previewMapX, previewMapY, previewMapDir)', 'cli_tools.runPreviewMap(previewMapId, previewMapX, previewMapY, previewMapDir, loader)')
    text = text.replace('runPreviewFog(previewFogSpec, previewFogMapId)', 'cli_tools.runPreviewFog(previewFogSpec, previewFogMapId, loader)')
    text = text.replace('ok, err = pcall(runGolden)', 'ok, err = pcall(cli_tools.runGolden, loader)')
    text = text.replace('ok, err = pcall(runGoldenUI)', 'ok, err = pcall(cli_tools.runGoldenUI, loader)')

    with open('d:/Antigravity/Hichaukitoden/main.lua', 'w', encoding='utf-8') as f:
        f.write(text)
    print('Replaced')
else:
    print('Pattern not found')
