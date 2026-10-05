#!/usr/bin/env bash
# Build a debug image whose dropbear accepts the public keys in KEYFILE.
# usage: scripts/build-debug.sh KEYFILE [APP-DIR] [PROFILE] [OVMF.fd]   -> result-debug/
set -euo pipefail
key=$(realpath "$1"); app=$(realpath "${2:-examples/minimal/app}"); profile=${3:-minimal}; ovmf=${4:+$(realpath "$4")}
cd "$(dirname "$0")/.."
nix build --impure --out-link result-debug --expr "
  let f = builtins.getFlake \"$PWD\";
  in f.lib.mkImage { profile = \"$profile\"; debug = true; app = $app; authorizedKeys = $key; ${ovmf:+ovmf = $ovmf;} }"
echo "result-debug/image.efi"
