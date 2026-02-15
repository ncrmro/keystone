{
  lib,
  rustPlatform,
  pkg-config,
  openssl,
  libgit2,
  zlib,
}:
rustPlatform.buildRustPackage {
  pname = "keystone-tui";
  version = "0.1.0";

  src = ./.;

  cargoLock.lockFile = ./Cargo.lock;

  nativeBuildInputs = [pkg-config];
  buildInputs = [
    openssl
    libgit2
    zlib
  ];

  # Use system libgit2 instead of bundled
  LIBGIT2_NO_VENDOR = 1;

  meta = with lib; {
    description = "TUI for Keystone NixOS infrastructure configuration and management";
    homepage = "https://github.com/ncrmro/keystone";
    license = licenses.mit;
    maintainers = [];
    mainProgram = "keystone-tui";
  };
}
