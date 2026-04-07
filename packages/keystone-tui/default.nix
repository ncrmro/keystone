{
  lib,
  craneLib,
  pkg-config,
  openssl,
  zlib,
  cmake,
}:
let
  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./src
      ./tests
      ./Cargo.toml
      ./Cargo.lock
    ];
  };

  commonArgs = {
    inherit src;
    pname = "keystone-tui";
    version = "0.1.0";

    nativeBuildInputs = [
      pkg-config
      cmake
    ];
    buildInputs = [
      openssl
      zlib
    ];
  };

  cargoArtifacts = craneLib.buildDepsOnly commonArgs;
in
craneLib.buildPackage (
  commonArgs
  // {
    inherit cargoArtifacts;

    # Let libgit2-sys vendor its own libgit2 to avoid version mismatches

    meta = with lib; {
      description = "TUI for Keystone NixOS infrastructure configuration and management";
      homepage = "https://github.com/ncrmro/keystone";
      license = licenses.mit;
      maintainers = [ ];
      mainProgram = "keystone-tui";
    };
  }
)
