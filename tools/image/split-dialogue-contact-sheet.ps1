param(
    [Parameter(Mandatory = $true)][string]$InputPath,
    [Parameter(Mandatory = $true)][string]$OutputDirectory,
    [Parameter(Mandatory = $true)][string[]]$Names,
    [int]$Columns = 2,
    [int]$Rows = 3,
    [int]$StartX = 0,
    [int]$StartY = 0,
    [int]$CellWidth = 0,
    [int]$CellHeight = 0,
    [int]$GutterX = 0,
    [int]$GutterY = 0,
    [int]$CanvasWidth = 256,
    [int]$CanvasHeight = 240,
    [int]$VisibleHeight = 144
)

$ErrorActionPreference = "Stop"
if (-not (Get-Command magick -ErrorAction SilentlyContinue)) {
    throw "ImageMagick 'magick' is required."
}
if ($Names.Count -ne ($Columns * $Rows)) {
    throw "Names must contain exactly Columns * Rows entries."
}

$inputItem = Get-Item -LiteralPath $InputPath
$dimensions = (& magick identify -format "%w %h" $inputItem.FullName).Split(" ")
$imageWidth, $imageHeight = [int]$dimensions[0], [int]$dimensions[1]
if ($CellWidth -le 0) {
    $CellWidth = [math]::Floor(($imageWidth - $StartX - (($Columns - 1) * $GutterX)) / $Columns)
}
if ($CellHeight -le 0) {
    $CellHeight = [math]::Floor(($imageHeight - $StartY - (($Rows - 1) * $GutterY)) / $Rows)
}

$visibleAspect = $CanvasWidth / $VisibleHeight
$cellAspect = $CellWidth / $CellHeight
if ($cellAspect -gt $visibleAspect) {
    $cropWidth, $cropHeight = [math]::Floor($CellHeight * $visibleAspect), $CellHeight
} else {
    $cropWidth, $cropHeight = $CellWidth, [math]::Floor($CellWidth / $visibleAspect)
}

New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
for ($i = 0; $i -lt $Names.Count; $i++) {
    $column = $i % $Columns
    $row = [math]::Floor($i / $Columns)
    $x = $StartX + ($column * ($CellWidth + $GutterX))
    $y = $StartY + ($row * ($CellHeight + $GutterY))
    $native = Join-Path $OutputDirectory ($Names[$i] + ".png")

    & magick $inputItem.FullName `
        -crop "$($CellWidth)x$($CellHeight)+$x+$y" +repage `
        -gravity center -crop "$($cropWidth)x$($cropHeight)+0+0" +repage `
        -filter Lanczos -resize "$($CanvasWidth)x$($VisibleHeight)!" `
        -background black -gravity north -extent "$($CanvasWidth)x$($CanvasHeight)" `
        -colors 128 PNG8:$native
    if ($LASTEXITCODE -ne 0) { throw "Failed to build dialogue plate '$($Names[$i])'." }
}

Write-Output "Split $($Names.Count) dialogue plates into '$OutputDirectory'."
