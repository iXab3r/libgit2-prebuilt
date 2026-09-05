#requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Package,
    [string]$TargetDirectory = (Join-Path (Split-Path $PSScriptRoot) 'smoke/target')
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$Repo = Split-Path $PSScriptRoot
$Config = Join-Path $Repo 'smoke/native.toml'
& "$Package/Configure-Cargo.ps1" -Package $Package -Output $Config
$Log = Join-Path $Repo 'build/rust-consumer.log'
New-Item -ItemType Directory -Force (Split-Path $Log) | Out-Null
$CargoArgs = @('build', '--manifest-path', "$Repo/smoke/Cargo.toml", '--locked', '--release',
    '--target', 'x86_64-pc-windows-msvc', '--target-dir', $TargetDirectory, '--config', $Config, '-vv', '--timings')
$Watch = [Diagnostics.Stopwatch]::StartNew()
& cargo @CargoArgs *> $Log
if ($LASTEXITCODE -ne 0) {
    Get-Content $Log -Tail 60 | Where-Object { $_.Length -lt 1000 } | Write-Host
    throw "Rust consumer build failed. Full log: $Log"
}
$First = $Watch.Elapsed.TotalSeconds
$NativeBuilds = @(Get-Content $Log | Where-Object {
    $_ -match 'Running ' -and $_ -match 'libgit2-sys|libssh2-sys|libz-sys' -and $_ -match 'build_script_build|build-script-build'
})
if ($NativeBuilds.Count) { throw "Unexpected native build-script invocation: $NativeBuilds" }
$Binary = Join-Path $TargetDirectory 'x86_64-pc-windows-msvc/release/libgit2-prebuilt-smoke.exe'
& $Binary
if ($LASTEXITCODE -ne 0) { throw 'Rust behavior smoke test failed.' }
$Watch.Restart()
& cargo @CargoArgs *> (Join-Path $Repo 'build/rust-consumer-warm.log')
if ($LASTEXITCODE -ne 0) { throw 'Warm consumer build failed.' }
$Evidence = @{ firstConsumerBuildSeconds = [Math]::Round($First, 3);
    warmConsumerBuildSeconds = [Math]::Round($Watch.Elapsed.TotalSeconds, 3);
    nativeBuildScriptInvocations = $NativeBuilds.Count; rustc = (& rustc --version);
    profile = 'release'; target = 'x86_64-pc-windows-msvc';
    note = 'First build timing depends on Cargo cache state; no end-to-end application speedup claimed.' }
$Evidence | ConvertTo-Json | Set-Content "$Repo/build/consumer-evidence.json" -Encoding utf8NoBOM
$Evidence | ConvertTo-Json | Write-Host
