#!/bin/busybox sh
# PID 1 of images built without `init`. Mounts the pseudo filesystems, runs the features listed in /app/manifest, then runs
# /app/init as a child with its standard streams on /dev/null and restarts it when it exits.
# PID 1 itself never exits.
export PATH=/bin
bb=/bin/busybox
$bb mount -t proc -o nosuid,nodev,noexec proc /proc
$bb mount -t sysfs -o nosuid,nodev,noexec sysfs /sys
$bb mount -t devtmpfs devtmpfs /dev 2>/dev/null
$bb mount -t tmpfs -o mode=1777,nosuid,nodev tmpfs /tmp
$bb mount -t tmpfs -o mode=0755,nosuid,nodev tmpfs /run
$bb mkdir -p /dev/shm
$bb mount -t tmpfs -o mode=1777,nosuid,nodev tmpfs /dev/shm

# Command-line parameters net.* become variables: net.ip4=dhcp -> net_ip4=dhcp.
for w in $($bb cat /proc/cmdline); do
    case "$w" in *=*) k="${w%%=*}"; case "$k" in net.*) export "$($bb echo "$k" | $bb tr . _)=${w#*=}" ;; esac ;; esac
done

# Write to every console the kernel may have: the framebuffer (hosted VNC) and the serial port.
log() { for c in /dev/console /dev/tty0 /dev/ttyS0; do $bb echo "init: $*" > $c 2>/dev/null; done; }

[ -r /app/manifest ] && for f in $($bb cat /app/manifest); do
    [ -r "/init.d/$f.sh" ] || { log "unknown feature $f"; $bb poweroff -f; }
    . "/init.d/$f.sh"
done

# Debug images: dropbear on port 22 and a shell on each console.
if [ -x /bin/dropbear ]; then
    $bb mkdir -p /dev/pts && $bb mount -t devpts devpts /dev/pts   # devtmpfs hides the initramfs /dev/pts
    /bin/dropbear -R -E -p 22 2>/dev/null &
    log "dropbear on :22 ($([ -s /root/.ssh/authorized_keys ] && echo key installed || echo no key))"
    for con in ttyS0 tty1; do
        [ -e "/dev/$con" ] && ( while :; do $bb setsid -c $bb sh <"/dev/$con" >"/dev/$con" 2>&1; $bb sleep 1; done ) &
    done
fi

( while :; do log "starting /app/init"; /app/init </dev/null >/dev/null 2>&1; log "/app/init exited rc=$?"; $bb sleep 5; done ) &
while :; do wait; $bb sleep 1; done   # the builtin wait reaps children
