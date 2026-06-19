{
  lib,
  craneLib,
  fetchCrate,
  openssl,
  pkg-config,
}:
let
  pname = "forgejo-cli-ex";
  version = "0.1.9";

  src = fetchCrate {
    inherit pname version;
    hash = "sha256-tyf3LHor7q/XfYR110dL6mMUvuiKL6hPnHO9ompqYg8=";
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

    nativeBuildInputs = [ pkg-config ];
    buildInputs = [ openssl ];
  };

  cargoArtifacts = craneLib.buildDepsOnly (commonArgs // { inherit dummySrc; });
in
craneLib.buildPackage (
  commonArgs
  // {
    inherit cargoArtifacts;

    # Upstream integration tests expect Docker and network access.
    doCheck = false;

    meta = with lib; {
      description = "Forgejo CLI extension using UI endpoints for Actions operations";
      homepage = "https://github.com/JKamsker/forgejo-cli-ex";
      license = licenses.lgpl3Plus;
      maintainers = [ ];
      mainProgram = "fj-ex";
    };
  }
)
