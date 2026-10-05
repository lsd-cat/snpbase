#!/usr/bin/env bash
# Boot an image under QEMU without SEV, forward a host port to the guest's port 8080, and print
# what the example app serves. Usable for production images, which have no console.
# usage: scripts/qemu-http.sh RESULT-DIR [OVMF-CODE.fd]   (default firmware: $OVMF_CODE, set by nix develop)
set -euo pipefail
dir=$1; ovmf=${2:-${OVMF_CODE:-/usr/share/OVMF/OVMF_CODE_4M.fd}}; port=${PORT:-18080}
efi=$(ls "$dir"/*.efi | head -1); qlog=$(mktemp)
# KVM when available, software emulation otherwise (slower; enough for this kernel).
qemu-system-x86_64 -machine q35,accel=kvm:tcg -cpu max -m 1G -smp 2 \
  -drive if=pflash,format=raw,readonly=on,file="$ovmf" \
  -kernel "$efi" -display none -serial none -monitor none -no-reboot \
  -netdev user,id=n0,hostfwd=tcp:127.0.0.1:$port-:8080 -device virtio-net-pci,netdev=n0 >"$qlog" 2>&1 &
qemu=$!
trap 'kill $qemu 2>/dev/null || true' EXIT
for _ in $(seq 1 240); do
  if out=$(curl -sf --max-time 2 "http://127.0.0.1:$port/" 2>/dev/null); then echo "$out"; exit 0; fi
  kill -0 $qemu 2>/dev/null || { echo "qemu exited before answering:" >&2; cat "$qlog" >&2; exit 1; }
  sleep 1
done
echo "no HTTP answer within 240s" >&2; cat "$qlog" >&2; exit 1
