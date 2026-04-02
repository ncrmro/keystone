{
  lib,
  rustPlatform,
  fetchCrate,
  openssl,
  pkg-config,
}:
rustPlatform.buildRustPackage rec {
  pname = "forgejo-cli-ex";
  version = "0.1.9";

  src = fetchCrate {
    inherit pname version;
    hash = "sha256-tyf3LHor7q/XfYR110dL6mMUvuiKL6hPnHO9ompqYg8=";
  };

  cargoHash = "sha256-RTas3uNDBOHekStw9rezqGyhUwKMOyl6ZkFePfS6N0Y=";

  nativeBuildInputs = [ pkg-config ];
  buildInputs = [ openssl ];

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
