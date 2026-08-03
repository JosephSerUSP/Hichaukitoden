$ErrorActionPreference = "Stop"
$rootDir = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path))
Set-Location $rootDir

# G6 boots the editor server and a headless Chrome itself, so unlike G2/G3/G5
# there is no engine stdout to marshal through a temp file -- the Python driver
# owns the whole run.
& python "tools/golden/editor-screens.py" check
if ($LASTEXITCODE -ne 0) {
    throw "Golden editor screenshot mismatch detected"
}
