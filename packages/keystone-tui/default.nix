{
  lib,
  rustPlatform,
  pkg-config,
  openssl,
  zlib,
  cmake,
}:
rustPlatform.buildRustPackage {
  pname = "keystone-tui";
  version = "0.1.0";

  src = ./.;

  cargoLock.lockFile = ./Cargo.lock;

  nativeBuildInputs = [pkg-config cmake];
  buildInputs = [
    openssl
    zlib
  ];

  # Let libgit2-sys vendor its own libgit2 to avoid version mismatches

  meta = with lib; {
    description = "TUI for Keystone NixOS infrastructure configuration and management";
    homepage = "https://github.com/ncrmro/keystone";
    license = licenses.mit;
    maintainers = [];
    mainProgram = "keystone-tui";
  };
}
