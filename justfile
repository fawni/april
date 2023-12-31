set windows-shell := ["pwsh.exe", "-NoLogo", "-Command"]

_default:
    @just --list

# build april in release (ReleaseSafe) mode
@dev:
    zig build
    ./zig-out/bin/april

# build april in release (ReleaseSafe) mode
@build:
    zig build -Drelease

# build and run april
@run: (build)
    ./zig-out/bin/april

# build and test april
@test:
    zig build test -Drelease