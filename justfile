set windows-shell := ["pwsh.exe", "-NoLogo", "-Command"]

_default:
    @just --list

# build and run april in debug mode
@dev:
    zig build
    ./zig-out/bin/april

# build april in release (ReleaseSafe) mode
@build:
    zig build -Drelease

# build and run april in release mode
@run: (build)
    ./zig-out/bin/april

# build and test april
@test:
    zig build test -Drelease

# build april and install to ~/.local/bin
[unix]
@install: (build) && (install-sh)
    cp -u ./zig-out/bin/april ~/.local/bin

# install april.sh to ~/.local/bin
[unix]
@install-sh:
    cp -u ./bin/april.sh ~/.local/april.sh

push:
    git push
    git push gh
    git push srht
