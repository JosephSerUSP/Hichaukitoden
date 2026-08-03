$ErrorActionPreference = "Stop"
$rootDir = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path))
Set-Location $rootDir

# Regenerating the golden editor screenshots is an OWNER-SIGNED action. A red G6
# means a visual regression in the editor until proven otherwise -- never run
# this to silence a diff (AGENTS.md, same rule as G2/G3/G5).
& python "tools/golden/editor-screens.py" capture
if ($LASTEXITCODE -ne 0) {
    throw "Golden editor screenshot capture failed"
}
