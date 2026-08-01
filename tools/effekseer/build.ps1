<#
.SYNOPSIS
    Builds effekseer_shim.dll from tools/effekseer/efk_shim.cpp.

.DESCRIPTION
    The DLL is a 6.4MB build artifact and is deliberately NOT committed (see
    .gitignore). That policy only works if rebuilding is one command, so this
    script is the executable form of the recipe in README.md and roadmap
    section 6.5.1a -- which existed only as prose, and prose that has to be
    hand-transcribed is how a checkout ends up running a stale shim.

    It clones and configures Effekseer if needed, builds the two static
    libraries, links the shim, and writes effekseer_shim.dll to the repo root.

    Requires MinGW-w64 (MSYS2), NOT MSVC:
        winget install MSYS2.MSYS2
        pacman -S mingw-w64-x86_64-gcc mingw-w64-x86_64-cmake mingw-w64-x86_64-make

.PARAMETER EffekseerRoot
    Where the Effekseer source lives (cloned here if absent). Keep it SHORT --
    a deep path blows CMAKE_OBJECT_PATH_MAX (250 chars) during try-compile.

.PARAMETER MinGWBin
    The MSYS2 mingw64 bin directory holding g++/cmake/ninja.

.EXAMPLE
    .\tools\effekseer\build.ps1
    .\tools\effekseer\build.ps1 -EffekseerRoot D:\efk2
#>
[CmdletBinding()]
param(
    [string]$EffekseerRoot = "D:\efk2",
    [string]$MinGWBin      = "C:\msys64\mingw64\bin"
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path))

if (-not (Test-Path (Join-Path $MinGWBin "g++.exe"))) {
    throw "No g++ at $MinGWBin. Install MSYS2 + mingw-w64-x86_64-gcc, or pass -MinGWBin."
}
$env:PATH = "$MinGWBin;$env:PATH"

# --- Source -----------------------------------------------------------------
if (-not (Test-Path (Join-Path $EffekseerRoot "Dev\Cpp\Effekseer"))) {
    Write-Host "Cloning Effekseer into $EffekseerRoot ..."
    # core.longpaths is required: the checkout otherwise dies on MAX_PATH inside
    # Dev/Editor/.../mqoToEffekseerModelConverter. And do NOT sparse-checkout
    # only Dev/Cpp -- the root cmake/ directory defines filterfolder(), which
    # every library's CMakeLists.txt calls.
    git -c core.longpaths=true clone --depth 1 https://github.com/effekseer/Effekseer.git $EffekseerRoot
    if ($LASTEXITCODE -ne 0) { throw "clone failed" }
}

# --- Configure --------------------------------------------------------------
$buildDir = Join-Path $EffekseerRoot "build"
if (-not (Test-Path (Join-Path $buildDir "CMakeCache.txt"))) {
    Write-Host "Configuring ..."
    # Every flag here is load-bearing. The sound flags especially: USE_OPENAL
    # defaults ON, and without OpenAL present Dev/Cpp/CMakeLists.txt sets a
    # property on an EffekseerSoundAL target that was never created and
    # configure fails. LOVE owns sound anyway.
    & cmake -S $EffekseerRoot -B $buildDir -G Ninja -DCMAKE_BUILD_TYPE=Release `
        -DBUILD_EXAMPLES=OFF -DBUILD_TOOLS=OFF -DBUILD_VIEWER=OFF `
        -DBUILD_EDITOR=OFF -DBUILD_TEST=OFF `
        -DBUILD_GL=ON -DBUILD_DX9=OFF -DBUILD_DX11=OFF -DBUILD_DX12=OFF `
        -DNETWORK_ENABLED=OFF `
        -DUSE_OPENAL=OFF -DUSE_DSOUND=OFF -DUSE_XAUDIO2=OFF -DUSE_OSM=OFF
    if ($LASTEXITCODE -ne 0) { throw "cmake configure failed" }
}

Write-Host "Building runtime libraries ..."
& cmake --build $buildDir --target Effekseer EffekseerRendererGL
if ($LASTEXITCODE -ne 0) { throw "cmake build failed" }

# --- Link the shim ----------------------------------------------------------
$cpp = Join-Path $repoRoot "tools\effekseer\efk_shim.cpp"
$out = Join-Path $repoRoot "effekseer_shim.dll"
$dev = Join-Path $EffekseerRoot "Dev\Cpp"
$bld = Join-Path $buildDir "Dev\Cpp"

Write-Host "Linking $out ..."
# -static matters: without it the DLL pulls in libwinpthread-1.dll and stops
# being a single self-contained file. As built it depends only on KERNEL32,
# msvcrt and OPENGL32.
& g++ -shared -O2 -o $out $cpp `
    "-I$dev\Effekseer" "-I$dev\EffekseerRendererGL" "-I$dev\EffekseerRendererCommon" `
    "-L$bld\Effekseer" "-L$bld\EffekseerRendererGL" "-L$bld\EffekseerRendererCommon" `
    -lEffekseerRendererGL -lEffekseerRendererCommon -lEffekseer -lopengl32 -lgdi32 `
    -static -static-libgcc -static-libstdc++ "-Wl,--exclude-all-symbols"
if ($LASTEXITCODE -ne 0) { throw "shim link failed" }

# presentation/effekseer.lua resolves every symbol CDEF declares at init and
# refuses a DLL missing any of them, so a partial build degrades loudly rather
# than dying mid-draw. Check here too, where the fix is one rebuild away.
$exports = & (Join-Path $MinGWBin "nm.exe") --defined-only $out 2>$null |
    Select-String -Pattern "\befk_\w+" -AllMatches |
    ForEach-Object { $_.Matches.Value } | Sort-Object -Unique
$declared = Select-String -Path (Join-Path $repoRoot "presentation\effekseer.lua") `
    -Pattern "(efk_\w+)\s*\(" -AllMatches |
    ForEach-Object { $_.Matches } | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique
$missing = $declared | Where-Object { $exports -notcontains $_ }
if ($missing) {
    throw "Built DLL is missing exports the engine declares: $($missing -join ', ')"
}

Write-Host ""
Write-Host "OK: $out ($([math]::Round((Get-Item $out).Length / 1MB, 1)) MB), $($exports.Count) efk_* exports."
