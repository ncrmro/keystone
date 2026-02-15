{
  description = "Keystone TUI development shell";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    nixpkgs,
    rust-overlay,
    ...
  }: let
    system = "x86_64-linux";
    pkgs = import nixpkgs {
      inherit system;
      overlays = [rust-overlay.overlays.default];
    };
    rust = pkgs.rust-bin.stable.latest.default.override {
      extensions = ["rust-src" "rust-analyzer"];
    };
  in {
    devShells.${system}.default = pkgs.mkShell {
      nativeBuildInputs = with pkgs; [
        rust
        clippy
        pkg-config
      ];

      buildInputs = with pkgs; [
        openssl
        libgit2
        zlib
      ];

      LIBGIT2_NO_VENDOR = 1;
      RUST_SRC_PATH = "${rust}/lib/rustlib/src/rust/library";
    };
  };
}
