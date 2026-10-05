# Custom PID 1

`mkImage { init = <static binary>; }` installs the binary as `/init`, PID 1 of the image; the
shell init is not included. The production initramfs then contains that binary and `/app/` only.
This document is the contract such a binary implements. [snpshim](https://github.com/lsd-cat/snpshim)
is one implementation.

## Provided by the base

Kernel, per profile: `/dev/sev-guest`, virtio-net as `eth0`, tmpfs, devtmpfs, proc, sysfs, IPv4
and IPv6, unix sockets, seccomp. `sandbox` adds namespaces, seccomp filtering and SysV IPC; `disk`
adds the block layer, virtio-blk, dm-crypt, dm-verity and erofs.

Before PID 1 runs: IPv4 DHCP when `ip=dhcp` is on the command line, with the lease's resolvers in
`/proc/net/pnp`; IPv6 SLAAC once `accept_ra` is set on the interface. The initrd may consist of
several concatenated cpio segments, all unpacked by the kernel before `/init` starts.

Initramfs:

```
/init             the binary
/app/init         the application entry point
/app/manifest     application metadata; the shell init reads feature names from it, a custom init defines its own use
/app/cmdline      text mkImage appended to the measured command line
/bin/             debug images only: full busybox and dropbear
/etc/passwd, /etc/dropbear/, /root/.ssh/authorized_keys   debug images only
```

Measured command line: `panic=-1 rootfstype=ramfs rdinit=/init`, console settings in debug
images, `ip=dhcp` when the app manifest names `net`, then the app part.

The Reference Values in `reference-values.json` include the hash of the binary under `init` (the string
`shell` when the shell init is used), next to the kernel, base-initramfs and app hashes.

## Required of the binary

Mount `/proc`, `/sys`, `/dev`, `/tmp`, `/run`, `/dev/shm`. Start `/app/init`, restart it when it
exits, reap children, never exit. In debug images, recognised by the presence of `/bin/dropbear`:
mount `/dev/pts`, start `/bin/dropbear -R -E -p 22`, and run a shell on `/dev/tty0` and
`/dev/ttyS0`. Depend on nothing in `/bin`; production images have no `/bin`.
