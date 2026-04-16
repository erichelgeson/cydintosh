#!/usr/bin/env bash
# Reproducible CI build for Cydintosh.
# Fetches the Mac Plus v3 ROM from archive.org, applies umac's patches,
# generates Musashi sources, writes a dummy user_config.h, and runs
# `pio run` to produce the ESP32 firmware.
#
# Outputs (relative to repo root):
#   rom_patched.bin                           — patched ROM for flash 0x210000
#   .pio/build/esp32dev/firmware.bin          — main firmware
#   .pio/build/esp32dev/bootloader.bin
#   .pio/build/esp32dev/partitions.bin
set -euo pipefail

# Use the working directory the user invoked us from (important when run via
# `nix run`, where BASH_SOURCE[0] lives in the nix store). Require a .git
# directory so we fail loudly instead of scribbling in random places.
REPO_ROOT="${REPO_ROOT:-$PWD}"
cd "$REPO_ROOT"
if [ ! -e .git ] || [ ! -f platformio.ini ]; then
  echo "ci-build: run from the Cydintosh repo root (missing .git or platformio.ini in $PWD)" >&2
  exit 1
fi

# Mac Plus ROM v3 (128 KiB, first 4 bytes = 0x4D1F8172).
# Override with $MAC_PLUS_ROM_URL if this ever moves.
: "${MAC_PLUS_ROM_URL:=https://raw.githubusercontent.com/sentient06/MacROMan/master/TestImages/128KB%20ROMs/1986-03%20-%204D1F8172%20-%20MacPlus%20v3.ROM}"
: "${ROM_PATH:=$REPO_ROOT/rom.bin}"
: "${ROM_SIZE:=131072}"
: "${ROM_MAGIC:=4d1f8172}"

log() { printf '==> %s\n' "$*"; }

ensure_submodules() {
  if [ ! -f external/umac/Makefile ] || [ ! -f external/umac/external/Musashi/m68kmake.c ]; then
    log "Initializing submodules"
    git submodule update --init --recursive
  fi
}

link_m68kconf() {
  local target=external/umac/external/Musashi/m68kconf.h
  if [ ! -L "$target" ]; then
    log "Linking Musashi m68kconf.h"
    ln -sf ../../../../include/m68kconf.h "$target"
  fi
}

generate_musashi() {
  if [ ! -f external/umac/external/Musashi/m68kops.c ]; then
    log "Generating Musashi m68kops"
    make -C external/umac prepare
  fi
}

ensure_user_config() {
  if [ ! -f include/user_config.h ]; then
    log "Creating placeholder include/user_config.h"
    cp include/user_config.h.tmpl include/user_config.h
  fi
}

fetch_rom() {
  if [ -f "$ROM_PATH" ]; then
    log "Using existing ROM at $ROM_PATH"
  else
    log "Downloading Mac Plus ROM from $MAC_PLUS_ROM_URL"
    curl --fail --location --retry 3 --retry-delay 5 \
      --output "$ROM_PATH" "$MAC_PLUS_ROM_URL"
  fi

  local size
  size=$(stat -c %s "$ROM_PATH" 2>/dev/null || stat -f %z "$ROM_PATH")
  if [ "$size" != "$ROM_SIZE" ]; then
    echo "ROM size $size != expected $ROM_SIZE — aborting" >&2
    exit 1
  fi

  local magic
  magic=$(head -c 4 "$ROM_PATH" | od -An -tx1 | tr -d ' \n')
  if [ "$magic" != "$ROM_MAGIC" ]; then
    echo "ROM magic $magic != expected $ROM_MAGIC — wrong ROM?" >&2
    exit 1
  fi
  log "ROM verified (size=$size magic=$magic)"
}

patch_rom() {
  log "Patching ROM for 240x320"
  python3 tools/generate_patched_rom.py "$ROM_PATH" -o rom_patched.bin
}

build_firmware() {
  export PLATFORMIO_CORE_DIR="${PLATFORMIO_CORE_DIR:-$REPO_ROOT/.pio-core}"
  export PLATFORMIO_WORKSPACE_DIR="${PLATFORMIO_WORKSPACE_DIR:-$REPO_ROOT/.pio}"
  mkdir -p "$PLATFORMIO_CORE_DIR" "$PLATFORMIO_WORKSPACE_DIR"

  log "Building ESP32 firmware (pio run)"
  pio run
}

main() {
  ensure_submodules
  link_m68kconf
  generate_musashi
  ensure_user_config
  fetch_rom
  patch_rom
  build_firmware

  log "Build complete. Artifacts:"
  ls -la rom_patched.bin .pio/build/esp32dev/firmware.bin \
    .pio/build/esp32dev/bootloader.bin \
    .pio/build/esp32dev/partitions.bin 2>/dev/null || true
}

main "$@"
