{
  lib,
  craneLib,
  fetchFromGitHub,
}:
let
  pname = "cfait";
  version = "0.5.5";

  src = fetchFromGitHub {
    owner = "trougnouf";
    repo = "cfait";
    rev = "v${version}";
    hash = "sha256-N5OjvYXAgDcaYklgbjZxZv0eS6toIZ/Gd0E+CynFLOU=";
  };

  cargoMetadata = ./cargo-metadata;
  cargoLock = ./Cargo.lock;
  cargoToml = "${cargoMetadata}/Cargo.toml";
  cargoVendorDir = craneLib.vendorCargoDeps { inherit cargoLock; };
  dummySrc = craneLib.mkDummySrc {
    src = cargoMetadata;
    inherit cargoLock;
  };

  commonArgs = {
    inherit
      cargoLock
      cargoToml
      cargoVendorDir
      pname
      src
      version
      ;

    # Only build the TUI binary (default feature), skip GUI and mobile
    cargoExtraArgs = "--no-default-features --features tui";
  };

  cargoArtifacts = craneLib.buildDepsOnly (commonArgs // { inherit dummySrc; });
in
craneLib.buildPackage (
  commonArgs
  // {
    inherit cargoArtifacts;

    # Tests require system TLS certificates unavailable in the Nix sandbox
    doCheck = false;

    meta = with lib; {
      description = "Powerful, fast and elegant CalDAV task/TODO manager (TUI)";
      homepage = "https://github.com/trougnouf/cfait";
      license = licenses.gpl3Only;
      maintainers = [ ];
      mainProgram = "cfait";
    };
  }
)
