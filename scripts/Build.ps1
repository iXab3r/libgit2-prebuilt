#requires -Version 7.0
[CmdletBinding()]
param([string]$CMake = 'cmake', [int]$Jobs = [Environment]::ProcessorCount)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if (-not $IsWindows) { throw 'The first package supports Windows x64/MSVC only.' }
$Repo = Split-Path $PSScriptRoot
$Lock = Get-Content (Join-Path $Repo 'sources.lock.json') -Raw | ConvertFrom-Json
$Asset = "libgit2-prebuilt-$($Lock.packageVersion)-$($Lock.target)-mt"
$Build = Join-Path $Repo 'build'
$Install = (Join-Path $Build "install/$($Lock.packageVersion)").Replace('\', '/')
$Package = Join-Path $Build "packages/$Asset"
$Dist = Join-Path $Repo 'dist'
$Cache = Join-Path $Repo 'cache'
New-Item -ItemType Directory -Force $Build, $Install, $Dist, $Cache | Out-Null
if (Test-Path $Package) { throw "Package staging already exists: $Package. Use a fresh checkout/build directory for publication." }

function Invoke-CMake([string[]]$Arguments) {
    & $CMake @Arguments
    if ($LASTEXITCODE -ne 0) { throw "CMake failed ($LASTEXITCODE): $Arguments" }
}

$Watch = [Diagnostics.Stopwatch]::StartNew()
$Sources = @{}
$Timings = @()
foreach ($Source in $Lock.sources) {
    $Archive = Join-Path $Cache "$($Source.name).zip"
    if (-not (Test-Path $Archive)) {
        Invoke-WebRequest "https://codeload.github.com/$($Source.repository)/zip/$($Source.commit)" -OutFile $Archive
    }
    if ((Get-FileHash $Archive -Algorithm SHA256).Hash -ne $Source.sha256) {
        throw "Source checksum mismatch: $Archive"
    }
    $SourceDir = Join-Path $Build "sources/$($Source.name)-$($Source.commit)"
    if (-not (Test-Path $SourceDir)) {
        Expand-Archive -LiteralPath $Archive -DestinationPath (Join-Path $Build 'sources')
    }
    $Sources[$Source.name] = $SourceDir
    if ($Source.name -eq 'libgit2') { & "$PSScriptRoot/Disable-Libgit2Lto.ps1" -Source $SourceDir }
    $NativeBuild = Join-Path $Build "$($Source.name)-$($Source.commit)"
    $Options = @(
        '--fresh', '-S', $SourceDir, '-B', $NativeBuild, '-G', 'Visual Studio 17 2022', '-A', 'x64',
        '-DCMAKE_POLICY_DEFAULT_CMP0091=NEW', '-DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreaded',
        '-DCMAKE_INTERPROCEDURAL_OPTIMIZATION=OFF', '-DCMAKE_C_FLAGS_RELEASE=/O2 /Ob2 /DNDEBUG',
        "-DCMAKE_INSTALL_PREFIX=$Install", '-DCMAKE_INSTALL_LIBDIR=lib',
        "-DCMAKE_PREFIX_PATH=$Install", '-DBUILD_SHARED_LIBS=OFF'
    )
    switch ($Source.name) {
        'zlib' {
            $Options += @('-DZLIB_BUILD_SHARED=OFF', '-DZLIB_BUILD_STATIC=ON', '-DZLIB_BUILD_TESTING=OFF')
        }
        'libssh2' {
            $Options += @('-DBUILD_STATIC_LIBS=ON', '-DBUILD_EXAMPLES=OFF', '-DBUILD_TESTING=OFF',
                '-DCRYPTO_BACKEND=WinCNG', '-DENABLE_ZLIB_COMPRESSION=ON',
                "-DZLIB_LIBRARY=$Install/lib/zs.lib", "-DZLIB_INCLUDE_DIR=$Install/include")
        }
        'libgit2' {
            $Options += @('-DBUILD_TESTS=OFF', '-DBUILD_CLI=OFF', '-DBUILD_EXAMPLES=OFF',
                '-DBUILD_FUZZERS=OFF', '-DSTATIC_CRT=ON', '-DUSE_SSH=libssh2', '-DUSE_HTTPS=WinHTTP',
                '-DUSE_BUNDLED_ZLIB=OFF', '-DREGEX_BACKEND=builtin', '-DUSE_GSSAPI=OFF',
                "-DZLIB_LIBRARY=$Install/lib/zs.lib", "-DZLIB_INCLUDE_DIR=$Install/include",
                "-DLIBSSH2_LIBRARY=$Install/lib/libssh2.lib", "-DLIBSSH2_INCLUDE_DIR=$Install/include",
                '-DPKG_CONFIG_EXECUTABLE:FILEPATH=',
                "-DCMAKE_REQUIRED_LIBRARIES=$Install/lib/zs.lib;ws2_32;crypt32;bcrypt")
        }
    }
    $Step = [Diagnostics.Stopwatch]::StartNew()
    Invoke-CMake $Options
    $LtoSettings = @(Get-ChildItem $NativeBuild -Recurse -Filter '*.vcxproj' |
        Select-String '<WholeProgramOptimization>true|/GL(?!-)')
    if ($LtoSettings.Count) { throw "Native LTO must be disabled: $($Source.name)" }
    Invoke-CMake @('--build', $NativeBuild, '--config', 'Release', '--parallel', "$Jobs")
    Invoke-CMake @('--install', $NativeBuild, '--config', 'Release')
    $Timings += @{ name = $Source.name; seconds = [Math]::Round($Step.Elapsed.TotalSeconds, 3) }
}

New-Item -ItemType Directory -Force "$Package/lib", "$Package/licenses" | Out-Null
foreach ($Library in @('git2.lib', 'libssh2.lib', 'zs.lib')) {
    Copy-Item -LiteralPath "$Install/lib/$Library" -Destination "$Package/lib/$Library"
}
Copy-Item -LiteralPath "$Install/include" -Destination "$Package/include" -Recurse
Copy-Item -LiteralPath "$Repo/sources.lock.json" -Destination $Package
Copy-Item -LiteralPath "$Repo/scripts/Configure-Cargo.ps1" -Destination $Package
Copy-Item -LiteralPath "$Repo/scripts/Disable-Libgit2Lto.ps1" -Destination $Package
Copy-Item -LiteralPath "$Repo/LICENSE" -Destination "$Package/licenses/build-scripts-MIT.txt"
foreach ($Source in $Lock.sources) {
    $License = if ($Source.name -eq 'zlib') { 'LICENSE' } else { 'COPYING' }
    Copy-Item -LiteralPath "$($Sources[$Source.name])/$License" -Destination "$Package/licenses/$($Source.name).txt"
    # Supply exact corresponding sources alongside the binaries in every release.
    Copy-Item -LiteralPath "$Cache/$($Source.name).zip" -Destination "$Dist/$($Source.name)-$($Source.version)-source.zip"
}
Copy-Item -LiteralPath "$Repo/scripts/Disable-Libgit2Lto.ps1" -Destination $Dist
Copy-Item -LiteralPath "$($Sources['libgit2'])/deps/llhttp/LICENSE-MIT" -Destination "$Package/licenses/llhttp.txt"

$Files = @(Get-ChildItem $Package -File -Recurse | Sort-Object FullName | ForEach-Object {
    @{ path = [IO.Path]::GetRelativePath($Package, $_.FullName).Replace('\', '/');
       sha256 = (Get-FileHash $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant(); bytes = $_.Length }
})
$Manifest = [ordered]@{
    schema = 1; packageVersion = $Lock.packageVersion; target = $Lock.target; crt = 'static';
    configuration = 'Release'; nativeLto = $false; https = 'WinHTTP'; ssh = 'libssh2/WinCNG';
    sources = $Lock.sources; files = $Files
}
$Manifest | ConvertTo-Json -Depth 8 | Set-Content "$Package/manifest.json" -Encoding utf8NoBOM
$Timing = @{ nativeBuildSeconds = [Math]::Round($Watch.Elapsed.TotalSeconds, 3); steps = $Timings;
    cmake = (& $CMake --version | Select-Object -First 1);
    compiler = @(Get-ChildItem $Build -Recurse -Filter CMakeCCompiler.cmake | ForEach-Object {
        Get-Content $_.FullName | Select-String '^set\(CMAKE_C_COMPILER_(VERSION|ID) ' | ForEach-Object { $_.Line }
    } | Sort-Object -Unique)
}
$Timing | ConvertTo-Json -Depth 5 | Set-Content "$Dist/build-evidence.json" -Encoding utf8NoBOM
Compress-Archive -Path "$Package/*" -DestinationPath "$Dist/$Asset.zip" -CompressionLevel Optimal -Force
Get-ChildItem $Dist -File | Where-Object Name -ne 'SHA256SUMS' | Sort-Object Name | ForEach-Object {
    "{0}  {1}" -f (Get-FileHash $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant(), $_.Name
} | Set-Content "$Dist/SHA256SUMS" -Encoding utf8NoBOM
Write-Host "Package: $Dist/$Asset.zip"
