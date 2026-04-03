{
  lib,
  rustPlatform,
  fetchFromGitHub,
  openssl,
  pkg-config,
}:
rustPlatform.buildRustPackage rec {
  pname = "immich-analyze";
  version = "0.3.1";

  src = fetchFromGitHub {
    owner = "timasoft";
    repo = "immich-analyze";
    rev = "v${version}";
    hash = "sha256-y0NUpZOfH0m3g/9+MjqbTqPbMXHz/1fP0jp8LwieSeg=";
  };

  cargoHash = "sha256-+7rJpK9T3n730o6AQWLX9OdctZZJc7No2KTHsc/bSNE=";

  buildInputs = [ openssl ];
  nativeBuildInputs = [ pkg-config ];

  # Tests require network access unavailable in the Nix sandbox
  doCheck = false;

  meta = with lib; {
    description = "AI-powered image description generator for Immich photo management system";
    homepage = "https://github.com/timasoft/immich-analyze";
    license = licenses.gpl3Only;
    maintainers = [ ];
    mainProgram = "immich-analyze";
  };
}
