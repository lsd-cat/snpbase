# Kernel for a profile: allnoconfig, then kernel/base.config, the profile fragment, and
# kernel/debug.config when debug is set. Every line of every fragment is checked against the final
# .config; a symbol unknown to this kernel version fails the build.
{ pkgs, lib }:
{ profile ? "minimal", debug ? false }:
let
  version = "6.18.55";
  src = pkgs.fetchurl {
    url = "https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-${version}.tar.xz";
    sha256 = "f410638061a165c12f42ab871d2f3fcd525515359b5faeee80969cff84524df9";
  };
  fragments = [ ../kernel/base.config ]
    ++ lib.optional (profile != "minimal") (../kernel + "/profile-${profile}.config")
    ++ lib.optional debug ../kernel/debug.config;
  name = "snpbase-kernel-${profile}${lib.optionalString debug "-debug"}";
in
pkgs.stdenv.mkDerivation {
  pname = name;
  inherit version src;
  nativeBuildInputs = with pkgs; [ bc bison flex perl python3Minimal openssl elfutils gawk zstd cpio ];
  KBUILD_BUILD_TIMESTAMP = "Thu Jan  1 00:00:00 UTC 1970";
  KBUILD_BUILD_USER = "snpbase";
  KBUILD_BUILD_HOST = "snpbase";
  KBUILD_BUILD_VERSION = "1";
  enableParallelBuilding = true;
  dontStrip = true;
  dontPatchELF = true;
  dontFixup = true;

  configurePhase = ''
    runHook preConfigure
    cat ${lib.concatStringsSep " " fragments} | grep -v '^#' | grep . > fragment
    make ARCH=x86_64 allnoconfig KCONFIG_ALLCONFIG=fragment

    # Assert every fragment line. A later fragment may override an earlier one, so check the last
    # setting of each symbol.
    : > failures
    tac fragment | awk -F= '!seen[$1]++' | while IFS== read -r sym val; do
      short="''${sym#CONFIG_}"
      if ! grep -rqE "^(menu)?config $short$" --include='Kconfig*' .; then
        echo "UNKNOWN SYMBOL: $sym" >> failures; continue
      fi
      case "$val" in
        n) grep -q "^$sym=" .config && echo "EXPECTED OFF: $sym ($(grep "^$sym=" .config))" >> failures ;;
        *) grep -qx "$sym=$val" .config || echo "EXPECTED $sym=$val, got: $(grep "^$sym=" .config || echo unset)" >> failures ;;
      esac
    done
    grep -qx 'CONFIG_MODULES=y' .config && echo "module support enabled" >> failures
    if [ -s failures ]; then cat failures >&2; echo "kernel config assertion failed: $(wc -l < failures) problem(s)" >&2; exit 1; fi
    runHook postConfigure
  '';

  buildPhase = ''
    runHook preBuild
    make ARCH=x86_64 -j"$NIX_BUILD_CORES" bzImage
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out
    cp arch/x86/boot/bzImage $out/bzImage
    cp .config $out/config
    echo "${version}" > $out/version
    runHook postInstall
  '';
}
