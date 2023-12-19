set windows-shell := ["pwsh.exe", "-NoLogo", "-Command"]

address := "0.0.0.0"
port := "6485"

_default:
    @just --list

# build april in release (ReleaseSafe) mode
dev:
    @zig build run -- {{address}} {{port}}

# build april in release (ReleaseSafe) mode
build:
    zig build -Drelease

# build and run april
run: (build)
    ./zig-out/bin/april {{address}} {{port}}

# build and test april
test:
    zig build test -Drelease