# Busybox with only the applets the shell init, the net feature and the example app use. Reuses the
# nixpkgs static-musl busybox derivation and replaces its configuration with allnoconfig plus this
# list; every requested option is checked in the final .config.
{ pkgs, lib }:
let
  options = [
    "BUSYBOX" "STATIC" "LONG_OPTS" "FEATURE_IPV6" "SH_IS_ASH" "ASH" "ASH_ECHO" "ASH_PRINTF" "ASH_TEST" "FEATURE_SH_MATH"
    "TEST" "ECHO" "PRINTF" "CAT" "CP" "RM" "MKDIR" "LS" "TR" "AWK" "GREP" "SLEEP" "UNAME" "PS" "DMESG" "POWEROFF"
    "MOUNT" "FEATURE_MOUNT_FLAGS" "SETSID"
    "IP" "FEATURE_IP_ADDRESS" "FEATURE_IP_LINK" "FEATURE_IP_ROUTE"
    "HTTPD" "FEATURE_HTTPD_RANGES"
  ];
  base = pkgs.pkgsStatic.busybox;
in
base.overrideAttrs (old: {
  pname = "snpbase-busybox";
  configurePhase = ''
    runHook preConfigure
    make $makeFlags allnoconfig
    for o in ${lib.concatStringsSep " " options}; do
      sed -i "s/^# CONFIG_$o is not set/CONFIG_$o=y/" .config
      grep -q "^CONFIG_$o=y" .config || echo "CONFIG_$o=y" >> .config
    done
    sed -i 's|^CONFIG_CROSS_COMPILER_PREFIX=.*|CONFIG_CROSS_COMPILER_PREFIX="${pkgs.pkgsStatic.stdenv.cc.targetPrefix}"|' .config
    { yes "" 2>/dev/null || true; } | make $makeFlags oldconfig
    missing=0
    for o in ${lib.concatStringsSep " " options}; do
      grep -q "^CONFIG_$o=y" .config || { echo "busybox option not enabled: CONFIG_$o" >&2; missing=1; }
    done
    [ "$missing" = 0 ] || exit 1
    runHook postConfigure
  '';
  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    cp busybox $out/bin/busybox
    ./busybox --list > $out/applets
    runHook postInstall
  '';
})
