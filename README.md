# snpbase

Builds measured boot images for AMD SEV-SNP confidential VMs. An image is a Unified Kernel Image
(UKI) made of a kernel built from a profile, a base initramfs, an application directory supplied
by the consumer, and a command line. The firmware measures all four at launch. The build also
emits `reference-values.json`, the Reference Values for that image.

## Attestation roles

Terms follow the RATS architecture (RFC 9334).

| Role or artifact | In a SEV-SNP guest built from this repository |
|---|---|
| Attester | the guest |
| Attesting Environment | the AMD secure processor and its firmware |
| Target Environment | the OVMF firmware and the UKI: kernel, initramfs, app, command line |
| Evidence | the `ATTESTATION_REPORT` the guest obtains through `/dev/sev-guest`; its `MEASUREMENT` field is the launch measurement |
| Endorsements | the VCEK or VLEK certificate chain from AMD |
| Reference Values | `reference-values.json`: the launch measurement per vCPU count and CPU type, and the hash of each layer |
| Reference Value Provider | whoever publishes a `reference-values.json` after reviewing it: the consumer, or an auditor |
| Verifier | software that appraises Evidence against Reference Values and Endorsements, such as [snpverify](https://github.com/lsd-cat/snpverify) |
| Relying Party | the client that acts on the Attestation Result |

## Layers

| Layer | Source | Contents |
|---|---|---|
| kernel | this repository, one per profile | Linux 6.18.55 from `allnoconfig` plus `kernel/base.config` plus the profile fragment; no modules |
| base initramfs | this repository | the shell PID 1 with the `net` feature and a 22-applet static busybox, or the binary given as `init` |
| app | the consumer | a directory packed under `/app/`; `/app/init` is the application |
| command line | base defaults, `/app/cmdline`, the `cmdline` argument | measured parameters such as `net.ip4=` |

The app directory is packed under `/app/` by the build, so an application cannot replace a base
file. A Reference Value Provider that has reviewed a release of this repository compares the
kernel and base-initramfs hashes in a consumer's `reference-values.json` with that release, then reads
the app directory and the app part of the command line.

## Kernel profiles

| Profile | Beyond the base | For |
|---|---|---|
| `minimal` | nothing: SEV guest driver, virtio-net, tmpfs, IPv4 with kernel DHCP, IPv6 | services without a disk |
| `sandbox` | namespaces, seccomp filter, cross-memory attach, fhandle, SysV IPC | in-guest sandboxes such as gVisor |
| `disk` | block layer, virtio-blk, dm-crypt, dm-verity, erofs | a verity-protected root on a disk, or an encrypted local volume |

The base has no block layer, module loading, USB, input, sound, graphics or console drivers, no
BPF, io_uring, kexec, `/dev/mem` or perf interface, and every x86 speculative-execution
mitigation that applies to a guest. Sizes: `minimal` kernel 3.7 MB, base initramfs 0.2 MB,
`example-minimal` image 4.0 MB.

`debug = true` adds console drivers, early printk, symbol names in panic traces,
`/proc/config.gz`, printk timestamps, the EFI runtime map, the full busybox, a shell on each
console, and dropbear on port 22 accepting the keys in the `authorizedKeys` file. A debug image
has different Reference Values from the production image; an Appraisal Policy for Evidence for a
production service does not include them.

## App contract

```
/app/init       executable; PID 1 starts it after the features and restarts it when it exits
/app/manifest   words, one per feature to run before /app/init; the only feature is net
/app/cmdline    text appended to the measured command line
```

The shell init provides, as `/bin/busybox` and as names in `/bin`: `sh` (also `ash`), `awk`, `cat`, `cp`,
`dmesg`, `echo`, `grep`, `httpd`, `ip`, `ls`, `mkdir`, `mount`, `poweroff`, `printf`, `ps`, `rm`,
`setsid`, `sleep`, `test`, `tr`, `uname`. An application that needs anything else ships it.

PID 1 starts `/app/init` with its standard streams on `/dev/null`. An application that writes to
`/dev/tty0` or `/dev/ttyS0` must tolerate a failed write; a `ttyS0` node exists whether or not the
VM has a serial port.

Network parameters on the measured command line:

```
net.ip4=dhcp | static:ADDR/PREFIX,GW | off     default dhcp; the kernel performs it (ip=dhcp is added)
net.ip6=slaac | static:ADDR/PREFIX,GW | off    default slaac
net.dns=ADDR[,ADDR]                            resolvers; override those from DHCP
```

The network choice is fixed when the image is built, because the command line is measured.

With `init` set, the initramfs contains that binary and `/app/` only; the binary is PID 1 and is
responsible for everything the shell init does. `docs/init.md` states what the base provides to it
and requires of it; any static binary that meets that contract can be used.
[snpshim](https://github.com/lsd-cat/snpshim) is one implementation. The shell init exists for the
example image and for bring-up.

## Use from another flake

```nix
inputs.snpbase.url = "github:lsd-cat/snpbase";

packages.image = snpbase.lib.mkImage {
  profile = "minimal";              # minimal | sandbox | disk
  debug = false;
  app = ./app;                      # directory with init, manifest, cmdline
  init = null;                      # a static binary used as PID 1; null selects the shell init
  cmdline = "";                     # further measured parameters
  ovmf = ./OVMF.fd;                 # the firmware the provider boots; measurements need it
  vcpus = [ 2 4 ];                  # measurement matrix
  vcpuTypes = [ "EPYC-Genoa" ];
  authorizedKeys = null;            # a public-key file; debug images only
};
```

The output directory contains `image.efi` and `reference-values.json`: profile, variant, kernel version,
the hash of each layer, both command-line parts, the UKI hash, and, when `ovmf` is given, its hash
and the launch measurement for each vCPU count and CPU type. A Verifier compares the measurement
with the `MEASUREMENT` field of the Evidence. The measurement depends on the firmware the
provider boots, so the provider's OVMF file is the input, not one from this repository.

## Example and tests

`examples/minimal/app` declares `net` and serves three lines over HTTP on port 8080: a greeting,
whether `/dev/sev-guest` exists, and the kernel version. `example-minimal` is this app on the
`minimal` profile; `example-minimal-debug` adds the debug switch. Both boot on SEV-SNP hardware
(tested 2026-10-05).

```sh
nix build .#example-minimal              # result/image.efi, result/reference-values.json
scripts/build-debug.sh ~/.ssh/id.pub     # debug image accepting that key -> result-debug/; arguments: KEY [APP] [PROFILE] [OVMF]
scripts/qemu-http.sh result              # boots without SEV, prints the app's HTTP lines
scripts/qemu-boot.sh result-debug        # boots a debug image, waits for the console line
nix build .#kernel-minimal --rebuild     # rebuilds; fails if the bytes differ
```

Builds need an x86_64-linux machine; the QEMU scripts need KVM and an OVMF file
(`/usr/share/OVMF/OVMF_CODE_4M.fd` by default). CI builds the kernels and both images, rebuilds
four artifacts and compares the bytes, boots both images under QEMU, and uploads UKIs, Reference Values,
kernels and `SHA256SUMS`; a `v*` tag attaches them to a release. CI Reference Values carry layer
hashes but no launch measurements, because those depend on the provider's firmware. Every kernel fragment line is
checked against the final configuration. The pinned `sev-snp-measure` accepts `EPYC-Milan` and
`EPYC-Genoa`; `EPYC-Turin` needs a newer release.

## Layout

```
flake.nix           mkImage, packages
kernel/             base.config, profile-sandbox.config, profile-disk.config, debug.config
nix/                kernel.nix, busybox.nix, initramfs.nix, uki.nix
init/               init.sh (PID 1), features/net.sh
examples/minimal/   the example app
scripts/            build-debug.sh, qemu-http.sh, qemu-boot.sh
docs/init.md        what a custom PID 1 binary gets from the base and must do
```
