{
  lib,
  rustPlatform,
}:
rustPlatform.buildRustPackage {
  pname = "keystone-tui";
  version = "0.1.0";

  src = ./.;

  cargoLock.lockFile = ./Cargo.lock;

  meta = with lib; {
    description = "TUI for Keystone infrastructure management";
    homepage = "https://github.com/ncrmro/keystone";
    license = licenses.mit;
    maintainers = [];
  };
}
