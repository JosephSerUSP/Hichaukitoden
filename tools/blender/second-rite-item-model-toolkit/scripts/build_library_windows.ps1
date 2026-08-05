param(
    [string]$BlenderExe = "",
    [string]$OutputDir = ""
)

$ErrorActionPreference = "Stop"
$ToolkitRoot = Split-Path -Parent $PSScriptRoot

if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $OutputDir = Join-Path $ToolkitRoot "output"
}
$OutputDir = [System.IO.Path]::GetFullPath($OutputDir)

function Find-Blender {
    param([string]$ExplicitPath)

    if (-not [string]::IsNullOrWhiteSpace($ExplicitPath)) {
        if (-not (Test-Path -LiteralPath $ExplicitPath -PathType Leaf)) {
            throw "Blender executable not found: $ExplicitPath"
        }
        return (Resolve-Path -LiteralPath $ExplicitPath).Path
    }

    $command = Get-Command blender.exe -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }

    $roots = @(
        (Join-Path $env:ProgramFiles "Blender Foundation"),
        (Join-Path ${env:ProgramFiles(x86)} "Blender Foundation"),
        (Join-Path $env:LOCALAPPDATA "Programs\Blender Foundation")
    ) | Where-Object { $_ -and (Test-Path $_) }

    foreach ($root in $roots) {
        $candidate = Get-ChildItem -LiteralPath $root -Filter blender.exe -File -Recurse -ErrorAction SilentlyContinue |
            Sort-Object FullName -Descending |
            Select-Object -First 1
        if ($candidate) { return $candidate.FullName }
    }

    throw "Blender was not found. Install Blender 5.0+ or pass -BlenderExe with its full path."
}

$Blender = Find-Blender $BlenderExe
$Generator = Join-Path $ToolkitRoot "build_expanded_item_library.py"
$Exporter = Join-Path $ToolkitRoot "second_rite_item_exporter.py"

if (-not (Test-Path $Generator)) { throw "Missing generator: $Generator" }
if (-not (Test-Path $Exporter)) { throw "Missing exporter: $Exporter" }

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
$env:SECOND_RITE_OUT = $OutputDir

Write-Host "Blender: $Blender"
Write-Host "Output:  $OutputDir"
& $Blender --background --python $Generator
if ($LASTEXITCODE -ne 0) { throw "Blender returned exit code $LASTEXITCODE" }

$Blend = Join-Path $OutputDir "second_rite_item_model_library_expanded.blend"
$Preview = Join-Path $OutputDir "second_rite_item_model_library_expanded_preview.png"
$Manifest = Join-Path $OutputDir "ITEM_MODEL_MANIFEST.md"
$ExportDir = Join-Path $OutputDir "exports"

foreach ($required in @($Blend, $Preview, $Manifest, $ExportDir)) {
    if (-not (Test-Path $required)) { throw "Expected output missing: $required" }
}

$ObjFiles = @(Get-ChildItem -LiteralPath $ExportDir -Filter *.obj -File)
if ($ObjFiles.Count -ne 53) {
    throw "Expected 53 OBJ files, found $($ObjFiles.Count)."
}

$SmallObj = $ObjFiles | Where-Object { $_.Length -le 100 }
if ($SmallObj) {
    throw "One or more OBJ files are unexpectedly small: $($SmallObj.Name -join ', ')"
}

$Package = Join-Path $OutputDir "second-rite-expanded-item-model-library-local.zip"
if (Test-Path $Package) { Remove-Item $Package -Force }
Compress-Archive -Path $Blend, $Preview, $Manifest, $ExportDir, $Generator, $Exporter -DestinationPath $Package -CompressionLevel Optimal

Write-Host "Validated 49 roots / 53 OBJ outputs."
Write-Host "Package: $Package"
