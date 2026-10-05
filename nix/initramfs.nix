# Base initramfs. Without `init`: busybox, the shell PID 1 and the net feature. With `init`: that
# binary alone. Debug adds the full busybox, dropbear, a passwd entry for root and
# the authorized_keys file passed to mkImage.
{ pkgs, lib }:
{ debug ? false, authorizedKeys ? null, init ? null }:
let
  busybox = if debug then pkgs.pkgsStatic.busybox else import ./busybox.nix { inherit pkgs lib; };
  dropbear = pkgs.pkgsStatic.dropbear;
  name = "snpbase-initramfs" + lib.optionalString (init != null) "-init" + lib.optionalString debug "-debug";
in
pkgs.runCommand name { nativeBuildInputs = [ pkgs.cpio pkgs.zstd ]; } ''
  mkdir -p root/{etc,proc,sys,dev,tmp,run,app}
  ${if init == null then ''
    mkdir -p root/bin root/init.d
    cp ${busybox}/bin/busybox root/bin/busybox
    for a in $(root/bin/busybox --list); do ln -sf busybox root/bin/$a; done
    install -m0755 ${../init/init.sh} root/init
    install -m0755 ${../init/features/net.sh} root/init.d/net.sh
  '' else ''
    install -m0755 ${init} root/init
    ${lib.optionalString debug ''
      mkdir -p root/bin
      cp ${busybox}/bin/busybox root/bin/busybox
      for a in $(root/bin/busybox --list); do ln -sf busybox root/bin/$a; done
    ''}
  ''}
  ${lib.optionalString debug ''
    # dropbear needs a passwd entry with a shell, a writable /etc/dropbear for its host key, and devpts (mounted by init).
    cp ${dropbear}/bin/dropbear root/bin/dropbear
    mkdir -p root/etc/dropbear root/root/.ssh root/var/log
    : > root/var/log/lastlog
    echo 'root:x:0:0:root:/root:/bin/sh' > root/etc/passwd
    echo 'root:x:0:' > root/etc/group
    ${lib.optionalString (authorizedKeys != null) "install -m0600 ${authorizedKeys} root/root/.ssh/authorized_keys"}
  ''}
  find root -mindepth 1 -exec touch -h -d '@1' {} +
  (cd root && find . -mindepth 1 -print0 | LC_ALL=C sort -z | cpio -o -H newc -0 --reproducible --owner +0:+0 --quiet) | zstd -19 -q -o $out
''
