{
  lib,
  rustPlatform,
  pkg-config,
  openssl,
}:
rustPlatform.buildRustPackage {
  pname = "keystone-ha-tui-client";
  version = "0.1.0";

  src = ./.;

  cargoLock.lockFile = ./Cargo.lock;

  nativeBuildInputs = [ pkg-config ];
  buildInputs = [ openssl ];

  meta = with lib; {
    description = "TUI client for Keystone cross-realm resource management";
    homepage = "https://github.com/ncrmro/keystone";
    license = licenses.mit;
    maintainers = [ ];
    mainProgram = "keystone-ha-tui";
  };
}
