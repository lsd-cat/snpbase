#!/usr/bin/env bash
# Boot a debug image under QEMU without SEV and wait for a line on the serial console.
# usage: scripts/qemu-boot.sh RESULT-DIR [EXPECTED-LINE] [OVMF-CODE.fd]   (default firmware: $OVMF_CODE, set by nix develop)
set -euo pipefail
dir=$1; expect=${2:-"hello from /app/init"}; ovmf=${3:-${OVMF_CODE:-/usr/share/OVMF/OVMF_CODE_4M.fd}}
efi=$(ls "$dir"/*.efi | head -1)
log=$(mktemp); qlog=$(mktemp)
# KVM when available, software emulation otherwise (slower; enough for this kernel).
timeout 300 qemu-system-x86_64 -machine q35,accel=kvm:tcg -cpu max -m 1G -smp 2 \
  -drive if=pflash,format=raw,readonly=on,file="$ovmf" \
  -kernel "$efi" -nographic -serial file:"$log" -monitor none -no-reboot \
  -netdev user,id=n0 -device virtio-net-pci,netdev=n0 >"$qlog" 2>&1 &
qemu=$!
until grep -q "$expect" "$log" 2>/dev/null || ! kill -0 $qemu 2>/dev/null; do sleep 1; done
kill $qemu 2>/dev/null || true
if grep -q "$expect" "$log"; then echo "boot ok: $expect"; exit 0; fi
echo "boot failed; qemu output:" >&2; cat "$qlog" >&2; echo "last console lines:" >&2; tail -40 "$log" >&2; exit 1
