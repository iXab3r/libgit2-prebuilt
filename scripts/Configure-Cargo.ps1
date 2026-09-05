#requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Package,
    [Parameter(Mandatory)][string]$Output
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$Package = (Resolve-Path -LiteralPath $Package).Path
$Manifest = Get-Content -LiteralPath "$Package/manifest.json" -Raw | ConvertFrom-Json
if ($Manifest.schema -ne 1 -or $Manifest.target -ne 'x86_64-pc-windows-msvc' -or $Manifest.crt -ne 'static') {
    throw 'Unsupported package schema, target, or CRT.'
}
foreach ($File in $Manifest.files) {
    $Path = [IO.Path]::GetFullPath((Join-Path $Package $File.path))
    if (-not $Path.StartsWith($Package + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Manifest path escapes package: $($File.path)"
    }
    if ((Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash -ne $File.sha256) {
        throw "Package checksum mismatch: $($File.path)"
    }
}
foreach ($Library in @('git2.lib', 'libssh2.lib', 'zs.lib')) {
    if (-not ($Manifest.files.path -contains "lib/$Library")) { throw "Missing library in manifest: $Library" }
}
# JSON basic string escaping is also valid for these TOML strings.
$Lib = ConvertTo-Json "$Package/lib" -Compress
$Root = ConvertTo-Json $Package -Compress
$Include = ConvertTo-Json "$Package/include" -Compress
$Config = @"
# Generated from libgit2-prebuilt $($Manifest.packageVersion). Regenerate after moving the package.
[target.x86_64-pc-windows-msvc]
rustflags = ["-C", "target-feature=+crt-static"]

[target.x86_64-pc-windows-msvc.git2]
rustc-link-lib = ["static=git2", "winhttp", "rpcrt4", "ole32", "crypt32", "secur32", "advapi32"]
rustc-link-search = [$Lib]
root = $Root

[target.x86_64-pc-windows-msvc.ssh2]
rustc-link-lib = ["static=libssh2", "ws2_32", "crypt32", "bcrypt", "user32"]
rustc-link-search = [$Lib]
root = $Root
include = $Include

[target.x86_64-pc-windows-msvc.z]
rustc-link-lib = ["static=zs"]
rustc-link-search = [$Lib]
root = $Root
include = $Include
"@
$Output = [IO.Path]::GetFullPath($Output)
New-Item -ItemType Directory -Force (Split-Path $Output) | Out-Null
$Config | Set-Content -LiteralPath $Output -Encoding utf8NoBOM
Write-Host "Verified $($Manifest.files.Count) files; Cargo configuration: $Output"
