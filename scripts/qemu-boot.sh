#!/usr/bin/env bash
# Boot a debug image under QEMU without SEV and wait for a line on the serial console.
# usage: scripts/qemu-boot.sh RESULT-DIR [EXPECTED-LINE] [OVMF-CODE.fd]
set -euo pipefail
dir=$1; expect=${2:-"hello from /app/init"}; ovmf=${3:-/usr/share/OVMF/OVMF_CODE_4M.fd}
efi=$(ls "$dir"/*.efi | head -1)
log=$(mktemp)
timeout 180 qemu-system-x86_64 -enable-kvm -machine q35 -cpu host -m 1G -smp 2 \
  -drive if=pflash,format=raw,readonly=on,file="$ovmf" \
  -kernel "$efi" -nographic -serial file:"$log" -monitor none -no-reboot \
  -netdev user,id=n0 -device virtio-net-pci,netdev=n0 >/dev/null 2>&1 &
qemu=$!
until grep -q "$expect" "$log" 2>/dev/null || ! kill -0 $qemu 2>/dev/null; do sleep 1; done
kill $qemu 2>/dev/null || true
if grep -q "$expect" "$log"; then echo "boot ok: $expect"; exit 0; fi
echo "boot failed; last console lines:" >&2; tail -40 "$log" >&2; exit 1
