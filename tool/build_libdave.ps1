param(
  [string]$SourcePath = ".tools/libdave"
)

$ErrorActionPreference = "Stop"
$commit = "52cd56dc550f447fb354b3a06c9e2d2e2a4309c6"
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$resolvedSource = [System.IO.Path]::GetFullPath(
  (Join-Path $repositoryRoot $SourcePath)
)
$cppPath = Join-Path $resolvedSource "cpp"
$vcpkgPath = Join-Path $cppPath "vcpkg"
$buildPath = Join-Path $cppPath "build-flucord-shared"
$outputPath = Join-Path $repositoryRoot "windows/third_party/libdave"

if (-not (Test-Path -LiteralPath $resolvedSource)) {
  git clone https://github.com/discord/libdave.git $resolvedSource
}

git -C $resolvedSource fetch origin $commit
git -C $resolvedSource checkout --detach $commit
git -C $resolvedSource submodule update --init --recursive

$bootstrap = Join-Path $vcpkgPath "bootstrap-vcpkg.bat"
& $bootstrap -disableMetrics

$cmake = (where.exe cmake.exe | Select-Object -First 1)
if (-not $cmake) {
  throw "CMake was not found in PATH."
}

& $cmake `
  -S $cppPath `
  -B $buildPath `
  "-DVCPKG_MANIFEST_DIR=$cppPath/vcpkg-alts/openssl_3" `
  "-DCMAKE_TOOLCHAIN_FILE=$vcpkgPath/scripts/buildsystems/vcpkg.cmake" `
  -DVCPKG_TARGET_TRIPLET=x64-windows-static `
  -DBUILD_SHARED_LIBS=ON `
  -DTESTING=OFF `
  -DPERSISTENT_KEYS=OFF `
  -DCMAKE_WINDOWS_EXPORT_ALL_SYMBOLS=ON `
  -DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreaded
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

& $cmake --build $buildPath --config Release --target libdave --parallel
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

New-Item -ItemType Directory -Force -Path $outputPath | Out-Null
Copy-Item -Force (Join-Path $buildPath "Release/libdave.dll") $outputPath
Copy-Item -Force (Join-Path $resolvedSource "LICENSE") $outputPath

$binary = Join-Path $outputPath "libdave.dll"
$hash = (Get-FileHash -Algorithm SHA256 $binary).Hash
Write-Host "Built $binary"
Write-Host "SHA-256: $hash"
