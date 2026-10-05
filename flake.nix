{
  description = "Base images for AMD SEV-SNP guests: kernel profiles, a base initramfs, and an app contract";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/ac62194c3917d5f474c1a844b6fd6da2db95077d";

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
      lib = pkgs.lib;
      kernel = import ./nix/kernel.nix { inherit pkgs lib; };
      initramfs = import ./nix/initramfs.nix { inherit pkgs lib; };
      mkImage = import ./nix/uki.nix { inherit pkgs lib kernel initramfs; };
    in
    {
      lib = { inherit mkImage; };

      packages.${system} = {
        kernel-minimal = kernel { profile = "minimal"; };
        kernel-sandbox = kernel { profile = "sandbox"; };
        kernel-disk = kernel { profile = "disk"; };
        kernel-minimal-debug = kernel { profile = "minimal"; debug = true; };
        busybox = import ./nix/busybox.nix { inherit pkgs lib; };
        initramfs-prod = initramfs { debug = false; };
        initramfs-debug = initramfs { debug = true; };
        # Example image: the minimal profile with an app that serves its status over HTTP.
        example-minimal = mkImage { profile = "minimal"; app = ./examples/minimal/app; };
        # Same image with the debug switch. It carries no ssh key; scripts/build-debug.sh KEYFILE adds one.
        example-minimal-debug = mkImage { profile = "minimal"; debug = true; app = ./examples/minimal/app; };
        default = self.packages.${system}.example-minimal;
      };

      devShells.${system}.default = pkgs.mkShell {
        packages = with pkgs; [ qemu_kvm sev-snp-measure zstd cpio jq ];
        OVMF_CODE = "${pkgs.OVMF.fd}/FV/OVMF_CODE.fd";   # firmware for the QEMU scripts
      };
    };
}
