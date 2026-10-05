# mkImage: kernel profile, base initramfs, app directory and command line -> UKI and reference-values.json,
# the Reference Values (RFC 9334) a Verifier compares with the Evidence.
# The app directory is packed under /app/, so it cannot replace a base file. `init`, when given, is
# a static binary installed as PID 1; the shell init is then not included.
{ pkgs, lib, kernel, initramfs }:
{ profile ? "minimal", debug ? false, app, init ? null, cmdline ? "", ovmf ? null, authorizedKeys ? null
# EPYC-Turin as a vcpuType needs a sev-snp-measure newer than the pinned 0.0.11.
, vcpus ? [ 1 2 4 8 ], vcpuTypes ? [ "EPYC-Milan" "EPYC-Genoa" ], name ? "image" }:
let
  k = kernel { inherit profile debug; };
  base = initramfs { inherit debug authorizedKeys init; };
  appCpio = pkgs.runCommand "snp-app" { nativeBuildInputs = [ pkgs.cpio pkgs.zstd ]; } ''
    mkdir -p root/app
    cp -a ${app}/. root/app/
    chmod -R u+w root
    [ -x root/app/init ] || { echo "app: missing executable /app/init" >&2; exit 1; }
    find root -mindepth 1 -exec touch -h -d '@1' {} +
    (cd root && find . -mindepth 1 -print0 | LC_ALL=C sort -z | cpio -o -H newc -0 --reproducible --owner +0:+0 --quiet) | zstd -19 -q -o $out
  '';
  baseCmdline = "panic=-1 rootfstype=ramfs rdinit=/init"
    + lib.optionalString debug " console=ttyS0,115200 console=tty0 loglevel=7 panic=30";
  appCmdline = lib.optionalString (builtins.pathExists (app + "/cmdline")) (lib.fileContents (app + "/cmdline"))
    + lib.optionalString (cmdline != "") " ${cmdline}";
  # The kernel does IPv4 DHCP (CONFIG_IP_PNP) when the app declares net and does not choose static or off.
  manifest = lib.optionalString (builtins.pathExists (app + "/manifest")) (lib.fileContents (app + "/manifest"));
  wantsDhcp = lib.elem "net" (lib.splitString "\n" (lib.replaceStrings [" "] ["\n"] manifest)) && !(lib.hasInfix "net.ip4=" appCmdline);
  netCmdline = lib.optionalString wantsDhcp " ip=dhcp";
  fullCmdline = lib.trim "${baseCmdline}${netCmdline} ${appCmdline}";
  osrel = pkgs.writeText "os-release" ''
    NAME="snpbase"
    ID=snpbase
    VERSION_ID=${profile}${lib.optionalString debug "-debug"}
  '';
  variant = if debug then "debug" else "prod";
in
pkgs.runCommand "snp-${name}-${profile}-${variant}" { nativeBuildInputs = with pkgs; [ systemdUkify sev-snp-measure jq ]; } ''
  mkdir -p $out
  ukify build --linux ${k}/bzImage --initrd ${base} --initrd ${appCpio} \
    --cmdline ${lib.escapeShellArg fullCmdline} --os-release @${osrel} --uname $(cat ${k}/version) \
    --output $out/${name}.efi

  # Launch measurements, the Reference Values for the MEASUREMENT field of the Evidence, need the
  # firmware the provider boots; without `ovmf` the Reference Values have none.
  measurements='{}'
  ${lib.optionalString (ovmf != null) ''
    for n in ${toString vcpus}; do for t in ${toString vcpuTypes}; do
      m=$(sev-snp-measure --mode snp --vcpus $n --vcpu-type $t --ovmf ${ovmf} --kernel $out/${name}.efi --output-format hex)
      measurements=$(echo "$measurements" | jq --arg k "$n/$t" --arg v "$m" '. + {($k): $v}')
    done; done
  ''}

  jq -n \
    --arg profile "${profile}" --arg variant "${variant}" --arg kernelVersion "$(cat ${k}/version)" \
    --arg kernel "$(sha256sum ${k}/bzImage | cut -d' ' -f1)" --arg initramfs "$(sha256sum ${base} | cut -d' ' -f1)" \
    --arg app "$(sha256sum ${appCpio} | cut -d' ' -f1)" --arg init "${if init != null then "$(sha256sum ${init} | cut -d' ' -f1)" else ""}" --arg baseCmdline ${lib.escapeShellArg (baseCmdline + netCmdline)} \
    --arg appCmdline ${lib.escapeShellArg appCmdline} --arg ovmf "${if ovmf != null then "$(sha256sum ${ovmf} | cut -d' ' -f1)" else ""}" \
    --arg uki "$(sha256sum $out/${name}.efi | cut -d' ' -f1)" --argjson measurements "$measurements" \
    '{ base: { profile: $profile, variant: $variant, kernel_version: $kernelVersion, kernel_sha256: $kernel, initramfs_sha256: $initramfs, cmdline: $baseCmdline },
       init: (if $init == "" then "shell" else $init end),
       app: { sha256: $app, cmdline: $appCmdline },
       ovmf_sha256: (if $ovmf == "" then null else $ovmf end), uki_sha256: $uki, measurements: $measurements }' > $out/reference-values.json
''
