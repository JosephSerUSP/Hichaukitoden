$ErrorActionPreference = "Stop"
$rootDir = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path))
Set-Location $rootDir

# Regenerating golden screenshots is an OWNER-SIGNED action. A red G5 means a
# visual regression until proven otherwise -- never run this to silence a diff
# (AGENTS.md, same rule as G2/G3).
$tempOut = New-TemporaryFile
try {
    & lovec . screenshots | Out-File -FilePath $tempOut.FullName -Encoding utf8
    if ($LASTEXITCODE -ne 0) {
        throw "lovec . screenshots exited with $LASTEXITCODE"
    }
    & python "tools/golden/screens.py" capture --input $tempOut.FullName
    if ($LASTEXITCODE -ne 0) {
        throw "Golden screenshot capture failed"
    }
} finally {
    Remove-Item $tempOut.FullName -ErrorAction SilentlyContinue
}
