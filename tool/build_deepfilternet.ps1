param(
  [string]$SourcePath = ".tools/DeepFilterNet"
)

# Builds DeepFilterNet's C API (libDF, MIT) as df.dll and copies it, the
# DeepFilterNet3 ONNX model and the licence into windows/third_party/deepfilternet.
# Needs a Rust toolchain (x86_64-pc-windows-msvc) and the MSVC build tools.

$ErrorActionPreference = "Stop"
$commit = "d375b2d8309e0935d165700c91da9de862a99c31"
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$resolvedSource = [System.IO.Path]::GetFullPath(
  (Join-Path $repositoryRoot $SourcePath)
)
$outputPath = Join-Path $repositoryRoot "windows/third_party/deepfilternet"

if (-not (Test-Path -LiteralPath $resolvedSource)) {
  git clone https://github.com/Rikorose/DeepFilterNet.git $resolvedSource
}

git -C $resolvedSource fetch origin $commit
git -C $resolvedSource checkout --detach $commit

# Upstream's `capi` feature drags in `default-model`, which embeds an 8 MB copy
# of the model that the C API never reads (df_create always takes a path).
# The model ships as its own file, so the embedded copy is dropped here.
$cargoToml = Join-Path $resolvedSource "libDF/Cargo.toml"
(Get-Content $cargoToml) -replace 'capi = \["tract", "default-model", ', 'capi = ["tract", ' |
  Set-Content $cargoToml
if (-not (Select-String -Path $cargoToml -Pattern 'capi = \["tract", "dep:ndarray"' -Quiet)) {
  throw "Could not drop default-model from the capi feature in $cargoToml"
}

# Static CRT, like libdave: the DLL must not depend on a redistributable the
# machine may lack.
$env:RUSTFLAGS = "-C target-feature=+crt-static"
# Whole-program optimisation and no symbols: the bundle carries this DLL, and
# the default release profile is more than twice the size for no speed.
cargo build --release `
  --manifest-path (Join-Path $resolvedSource "libDF/Cargo.toml") `
  --no-default-features --features capi `
  --config "profile.release.lto='fat'" `
  --config "profile.release.codegen-units=1" `
  --config "profile.release.strip=true"
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

New-Item -ItemType Directory -Force -Path $outputPath | Out-Null
Copy-Item -Force (Join-Path $resolvedSource "target/release/df.dll") $outputPath
Copy-Item -Force (Join-Path $resolvedSource "models/DeepFilterNet3_onnx.tar.gz") $outputPath
Copy-Item -Force (Join-Path $resolvedSource "LICENSE-MIT") (Join-Path $outputPath "LICENSE")

$binary = Join-Path $outputPath "df.dll"
$hash = (Get-FileHash -Algorithm SHA256 $binary).Hash
Write-Host "Built $binary"
Write-Host "SHA-256: $hash"
