# libgit2-prebuilt

Precompiled static Git dependencies for Rust applications. Build native code once in this
repository; consume the resulting libraries without running the native Cargo build scripts.

The first package targets **Windows x64 / MSVC / static CRT (`/MT`)**. It preserves HTTPS and
SSH support and does not require a system Git executable. Other platforms are not yet published.

## Package contract

| Component | Version | Configuration |
| --- | --- | --- |
| libgit2 | 1.8.6 | Static, WinHTTP HTTPS, libssh2 SSH, built-in regex |
| libssh2 | 1.11.1 | Static, Windows CNG crypto, zlib compression |
| zlib | 1.3.2 | Static |

All components use optimized native Release objects with a static CRT and no native LTO.
The same native package can serve Rust dev and release profiles with matching target/CRT/features.
It contains ordinary native objects, not Rust `.rlib` files tied to a Rust compiler version.

Currently tested with `git2 = "=0.19.0"` / `libgit2-sys = 0.17.0+1.8.1`. The libgit2 1.8.6
patch release is in that binding's supported `>=1.8.1, <1.9.0` range. Do not use the bundle with
bindings for a different libgit2 minor version. The package is built with Visual Studio 2022;
use a compatible MSVC linker and Windows SDK. Compiler details are recorded in build evidence.

No upstream functionality is patched out. A small build-only patch removes libgit2's hardcoded
MSVC `/GL` flags, which otherwise override the no-LTO CMake setting and defer native code
generation to the consumer linker. The patch is included with the source release assets.
Commits and source archive SHA-256 values are pinned
in [sources.lock.json](sources.lock.json). This is a source/configuration-reproducible build recipe;
byte-identical output across changing hosted-runner compiler/SDK versions is not promised.

## Consume from Rust

1. Download `libgit2-prebuilt-1.8.6-1-x86_64-pc-windows-msvc-mt.zip` and `SHA256SUMS` from
   [release v1.8.6-1](https://github.com/iXab3r/libgit2-prebuilt/releases/tag/v1.8.6-1).
2. Verify the archive SHA-256. For automated consumers, pin the expected archive hash in your
   own dependency lock/configuration; do not resolve `latest` during application builds.
3. Extract it into a persistent dependency directory, then run the included configuration script:

```powershell
# Example paths; use absolute paths appropriate to your checkout.
pwsh ./Configure-Cargo.ps1 `
    -Package C:/deps/libgit2-prebuilt/1.8.6-1 `
    -Output C:/my-app/native-git.toml

cargo --config C:/my-app/native-git.toml build --target x86_64-pc-windows-msvc
```

The script checks the package's file manifest and generates Cargo overrides for **git2, ssh2,
and z**. Cargo neither compiles nor runs those three native build scripts. Rust FFI/wrapper
crates and the application still compile normally; the native archives are linked into the result.
The generated config enables `+crt-static` for this target. Regenerate it after relocating the
package. Treat it as a local generated file because its library paths are absolute.

These are Cargo's official [native build-script overrides](https://doc.rust-lang.org/cargo/reference/build-scripts.html#overriding-build-scripts).
No fork of git2-rs is needed. All configurations must agree with this package: do not enable
`zlib-ng-compat`, `openssl-on-win32`, or substitute different native backends. Cargo overrides are
workspace-wide for their `links` key, so every consumer of these native libraries must be compatible.
An externally supplied `RUSTFLAGS` can override the configured CRT setting; keep it consistent.

Downloads and extraction belong in dependency setup, not `build.rs`. Once installed, the native
package is usable offline. Missing files fail verification/linking; the configuration does not
fall back to compiling bundled C sources.

## Release layout

Tags use `v<libgit2-version>-<packaging-revision>`, starting with `v1.8.6-1`.
Changing any source, build option, archive contents, or integration script requires a new revision.

```text
libgit2-prebuilt-1.8.6-1-x86_64-pc-windows-msvc-mt.zip
  lib/git2.lib
  lib/libssh2.lib
  lib/zs.lib
  include/...
  licenses/...
  manifest.json
  sources.lock.json
  Configure-Cargo.ps1

libgit2-1.8.6-source.zip
libssh2-1.11.1-source.zip
zlib-1.3.2-source.zip
build-evidence.json
SHA256SUMS
```

`manifest.json` records target, CRT, native features, pinned sources, and file hashes. The release
also supplies exact corresponding upstream source archives. Library names are native archives,
not import libraries; the bundle contains no DLLs.

## Build and verify

Requires PowerShell 7, Visual Studio 2022 with C++ x64 tools and a Windows SDK, native Windows
CMake 3.24 or newer, and Rust/Cargo for the consumer check. Use native CMake, not Cygwin CMake.

```powershell
./scripts/Build.ps1 -CMake 'C:/Program Files/CMake/bin/cmake.exe'

Expand-Archive `
    dist/libgit2-prebuilt-1.8.6-1-x86_64-pc-windows-msvc-mt.zip `
    'build/relocated package'
./scripts/Test.ps1 -Package 'build/relocated package'
```

`Build.ps1` verifies downloads against the source lock, builds and installs the three native
libraries, and packages them. It requires a fresh package staging directory for each publication;
use a fresh checkout for a release. GitHub CI follows this path without a native compilation cache.

`Test.ps1` builds an actual Rust consumer with the default git2 features and all three overrides,
rejects Git-stack native build-script execution, and runs init/commit/status/local clone/fetch/
hard-reset, Unicode path and tracked-deletion checks, plus a public HTTPS clone. It checks that
SSH support is compiled in; authenticated SSH access is not exercised. The HTTPS check requires
network access. Testing after extraction to a path containing spaces verifies relocation.

Consumer first-build/warm-build timings and native producer timings are saved as CI evidence.
The expected performance property is **zero Git-stack native compilations in the consumer**.
Whole-application speedup depends on the critical path and other dependencies; this repository
does not claim that native unit durations can simply be subtracted from total application time.

## Publish

Update the source lock, smoke-test ABI expectation, README, and release notes together. Push
`main`, verify CI, then create and push the matching release tag. The tag workflow checks the
tag against `packageVersion`, builds and tests the package, verifies checksums, and publishes
GitHub Release assets. The workflow uses pinned action commits and grants publication permission
only to the release job.

## Licenses

Original build scripts and tests are MIT licensed. Third-party libraries retain their upstream
licenses, including libgit2's GPLv2 with linking exception. Notices are included in the binary
archive; exact corresponding sources are distributed alongside it. See [LICENSE](LICENSE).
