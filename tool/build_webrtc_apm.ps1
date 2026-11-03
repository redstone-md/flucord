param(
  [string]$WorkPath = ".tools/flucord-apm"
)

# Builds flucord_apm.dll: WebRTC Audio Processing (webrtc-audio-processing,
# BSD-3-Clause), the echo and gain stages Discord's own client runs, behind
# the small C API in windows/third_party/webrtc_apm/src. Copies the DLL and
# the licence into windows/third_party/webrtc_apm.
#
# Needs the MSVC build tools and Python with meson and ninja
# (`py -m pip install meson ninja`). meson fetches abseil-cpp through the
# library's own pinned wrap.

$ErrorActionPreference = "Stop"
$commit = "846fe90a289f58b7c9303a635142aa2c7caa93e5"  # v2.1
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$work = [System.IO.Path]::GetFullPath((Join-Path $repositoryRoot $WorkPath))
$shim = Join-Path $repositoryRoot "windows/third_party/webrtc_apm/src"
$outputPath = Join-Path $repositoryRoot "windows/third_party/webrtc_apm"
$library = Join-Path $work "subprojects/webrtc-audio-processing"

New-Item -ItemType Directory -Force -Path (Join-Path $work "subprojects") | Out-Null
Copy-Item -Force (Join-Path $shim "*") $work

if (-not (Test-Path -LiteralPath $library)) {
  git clone https://gitlab.freedesktop.org/pulseaudio/webrtc-audio-processing.git $library
}
git -C $library fetch origin $commit
git -C $library checkout --detach $commit
# A subproject's own wraps are only read from the top-level subprojects
# folder.
Copy-Item -Force (Join-Path $library "subprojects/abseil-cpp.wrap") (Join-Path $work "subprojects")

$build = Join-Path $work "build"
if (Test-Path -LiteralPath $build) { Remove-Item -Recurse -Force $build }
meson setup $build $work --vsenv
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
meson compile -C $build
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

New-Item -ItemType Directory -Force -Path $outputPath | Out-Null
Copy-Item -Force (Join-Path $build "flucord_apm.dll") $outputPath
Copy-Item -Force (Join-Path $library "COPYING") (Join-Path $outputPath "LICENSE")

$binary = Join-Path $outputPath "flucord_apm.dll"
$hash = (Get-FileHash -Algorithm SHA256 $binary).Hash
Write-Host "Built $binary"
Write-Host "SHA-256: $hash"
