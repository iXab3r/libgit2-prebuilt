#requires -Version 7.0
param([Parameter(Mandatory)][string]$Source)
$ErrorActionPreference = 'Stop'
# libgit2 1.8.6 overrides CMAKE_C_FLAGS_RELEASE and unconditionally adds /GL.
# Native LTO objects defer C compilation to the consumer linker and couple the
# archive to MSVC's compiler version. Remove only those three build flags.
$Path = Join-Path $Source 'cmake/DefaultCFlags.cmake'
$Original = 'C7E72C2CEED1B40B1B9852F21671C9530ABD7FCE94ACFF83850E6B08B242E863'
$Patched = 'C4F4AFC79D5B8C4E3E7E81EB25C895D41A56AD8F886C765DEB9015F5784A6C98'
$Actual = (Get-FileHash $Path).Hash
if ($Actual -eq $Patched) { return }
if ($Actual -ne $Original) { throw 'Unexpected libgit2 build flags; review the pinned build-only patch.' }
$Text = [IO.File]::ReadAllText($Path)
$Text = $Text.Replace('/Oy /GL /Gy', '/Oy /Gy').Replace('/Oy- /GL /Gy', '/Oy- /Gy')
[IO.File]::WriteAllText($Path, $Text, [Text.UTF8Encoding]::new($false))
if ((Get-FileHash $Path).Hash -ne $Patched) { throw 'Native LTO patch verification failed.' }
