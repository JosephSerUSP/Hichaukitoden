const fs = require('fs');
let text = fs.readFileSync('main.lua', 'utf8');

const startStr = 'local function makeHarnessSession()';
const endStr = 'print("GOLDEN END")\r\nend\r\n';
const endStr2 = 'print("GOLDEN END")\nend\n';

const startIndex = text.indexOf(startStr);
let endIndex = text.indexOf(endStr);
let finalEndIndex;
if (endIndex !== -1) {
    finalEndIndex = endIndex + endStr.length;
} else {
    endIndex = text.indexOf(endStr2);
    if (endIndex !== -1) {
        finalEndIndex = endIndex + endStr2.length;
    }
}

if (startIndex !== -1 && endIndex !== -1) {
    text = text.substring(0, startIndex) + 'local cli_tools = require("engine.cli_tools")\n' + text.substring(finalEndIndex);
    
    text = text.replace('runPreviewScene(previewSceneId)', 'cli_tools.runPreviewScene(previewSceneId, loader, gameWidth, gameHeight)');
    text = text.replace('runPreviewWindow(previewWindowId, previewWindowMockSpec)', 'cli_tools.runPreviewWindow(previewWindowId, previewWindowMockSpec, loader, gameWidth, gameHeight)');
    text = text.replace('runPreviewFont(previewFontName, tonumber(previewFontSize))', 'cli_tools.runPreviewFont(previewFontName, tonumber(previewFontSize))');
    text = text.replace('runPreviewAnim(previewAnimId, previewAnimJson, previewAnimSprite)', 'cli_tools.runPreviewAnim(previewAnimId, previewAnimJson, previewAnimSprite, loader)');
    text = text.replace('runPreviewMap(previewMapId, previewMapX, previewMapY, previewMapDir)', 'cli_tools.runPreviewMap(previewMapId, previewMapX, previewMapY, previewMapDir, loader)');
    text = text.replace('runPreviewFog(previewFogSpec, previewFogMapId)', 'cli_tools.runPreviewFog(previewFogSpec, previewFogMapId, loader)');
    text = text.replace('ok, err = pcall(runGolden)', 'ok, err = pcall(cli_tools.runGolden, loader)');
    text = text.replace('ok, err = pcall(runGoldenUI)', 'ok, err = pcall(cli_tools.runGoldenUI, loader)');

    fs.writeFileSync('main.lua', text, 'utf8');
    console.log('Successfully updated main.lua');
} else {
    console.log('Failed to find start or end index', startIndex, endIndex);
}
