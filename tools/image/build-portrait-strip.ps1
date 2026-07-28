param(
    [Parameter(Mandatory = $true)][string]$InputPath,
    [Parameter(Mandatory = $true)][string]$OutputPath,
    [int]$Frames = 5,
    [int]$FrameWidth = 128,
    [int]$FrameHeight = 192
)

$ErrorActionPreference = "Stop"

if (-not (Get-Command magick -ErrorAction SilentlyContinue)) {
    throw "ImageMagick 'magick' is required."
}

$source = (Resolve-Path -LiteralPath $InputPath).Path
$outputDirectory = Split-Path -Parent $OutputPath
if (-not $outputDirectory) {
    $outputDirectory = (Get-Location).Path
}
New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null
$output = Join-Path (Resolve-Path -LiteralPath $outputDirectory).Path (Split-Path -Leaf $OutputPath)

$geometry = (& magick identify -format "%w %h" $source).Split(" ")
$sourceWidth = [int]$geometry[0]
$sourceHeight = [int]$geometry[1]
$cellWidth = [math]::Floor($sourceWidth / $Frames)
$temporary = Join-Path ([System.IO.Path]::GetTempPath()) ("second-rite-portrait-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $temporary | Out-Null

try {
    $framePaths = @()
    for ($index = 0; $index -lt $Frames; $index++) {
        $x = $index * $cellWidth
        $width = if ($index -eq $Frames - 1) { $sourceWidth - $x } else { $cellWidth }
        $framePath = Join-Path $temporary ("frame-{0:D2}.png" -f $index)

        # Flood-filling from a one-pixel black border removes only the connected
        # source backdrop. Enclosed dark ink and marker shadows remain intact.
        & magick $source `
            -crop "${width}x${sourceHeight}+${x}+0" +repage `
            -bordercolor black -border 1 -alpha on -fuzz "7%" `
            -fill none -draw "color 0,0 floodfill" `
            -shave 1x1 -trim +repage `
            -resize "$($FrameWidth - 6)x$($FrameHeight - 6)>" `
            -gravity south -background none -extent "${FrameWidth}x${FrameHeight}" `
            $framePath
        if ($LASTEXITCODE -ne 0) { throw "ImageMagick failed while building frame $index." }
        $framePaths += $framePath
    }

    & magick @framePaths +append -strip -colors 128 PNG8:$output
    if ($LASTEXITCODE -ne 0) { throw "ImageMagick failed while assembling the strip." }
}
finally {
    Remove-Item -LiteralPath $temporary -Recurse -Force
}

Write-Output "Built portrait strip: $output"
