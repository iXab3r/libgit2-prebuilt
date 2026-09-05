Precompiled static Git dependencies for `x86_64-pc-windows-msvc`, static CRT (`/MT`).

- libgit2 1.8.6: HTTPS through WinHTTP, SSH through libssh2.
- libssh2 1.11.1: Windows CNG crypto and zlib compression.
- zlib 1.3.2.
- Optimized native Release objects, native LTO disabled.
- Rust consumer smoke test uses git2 0.19.0 and Cargo overrides for all three native build scripts.

Download the `libgit2-prebuilt-...-mt.zip` binary package and verify it against `SHA256SUMS`.
The package includes headers, static libraries, licenses, a file manifest, and `Configure-Cargo.ps1`.
Exact corresponding upstream sources are supplied in the `*-source.zip` assets.
See the repository README for supported Rust versions/features and integration instructions.

SSH capability is verified; authenticated SSH connections are not exercised by the public smoke test.
