{
  lib,
  craneLib,
  fetchFromGitHub,
}:
let
  pname = "zesh";
  version = "0.3.0";

  src = fetchFromGitHub {
    owner = "roberte777";
    repo = "zesh";
    rev = "zesh-v${version}";
    hash = "sha256-10zKOsNEcHb/bNcGC/TJLA738G0cKeMg1vt+PZpiEUI=";
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
  };

  cargoArtifacts = craneLib.buildDepsOnly (commonArgs // { inherit dummySrc; });
in
craneLib.buildPackage (
  commonArgs
  // {
    inherit cargoArtifacts;

    meta = with lib; {
      description = "A zellij session manager with zoxide integration";
      homepage = "https://github.com/roberte777/zesh";
      license = licenses.mit;
      maintainers = [ ];
      mainProgram = "zesh";
    };
  }
)
