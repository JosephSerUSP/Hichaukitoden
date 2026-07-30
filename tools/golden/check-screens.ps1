$ErrorActionPreference = "Stop"
$rootDir = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path))
Set-Location $rootDir

# The harness prints one very large JSON document (base64 PNGs) between its
# markers. Redirect to a file rather than piping: PowerShell 5.1 re-encodes
# pipeline strings, and a 2.5MB single line is not worth risking that.
$tempOut = New-TemporaryFile
try {
    & lovec . screenshots | Out-File -FilePath $tempOut.FullName -Encoding utf8
    if ($LASTEXITCODE -ne 0) {
        throw "lovec . screenshots exited with $LASTEXITCODE"
    }
    & python "tools/golden/screens.py" check --input $tempOut.FullName
    if ($LASTEXITCODE -ne 0) {
        throw "Golden screenshot mismatch detected"
    }
} finally {
    Remove-Item $tempOut.FullName -ErrorAction SilentlyContinue
}
