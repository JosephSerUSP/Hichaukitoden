$ErrorActionPreference = "Stop"
$env:LOVE_PATH = if ($env:LOVE_PATH) { $env:LOVE_PATH } else { "C:\Program Files\LOVE\lovec.exe" }
$output = & $env:LOVE_PATH . validate golden
$capture = $false
$result = @()
foreach ($line in $output) {
    if ($line -eq "GOLDEN END") { $capture = $false }
    if ($capture) { $result += $line }
    if ($line -eq "GOLDEN BEGIN") { $capture = $true }
}
$result | Out-File -Encoding UTF8 "tools\golden\battle.log"
