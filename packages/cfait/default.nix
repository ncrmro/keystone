{
  lib,
  rustPlatform,
  fetchFromGitHub,
}:
rustPlatform.buildRustPackage rec {
  pname = "cfait";
  version = "0.5.5";

  src = fetchFromGitHub {
    owner = "trougnouf";
    repo = "cfait";
    rev = "v${version}";
    hash = "sha256-N5OjvYXAgDcaYklgbjZxZv0eS6toIZ/Gd0E+CynFLOU=";
  };

  cargoHash = "sha256-34sp31ZmlNn0q9vR7sDRm8eHHiRuOzfYJVX3nB2IqMs=";

  # Only build the TUI binary (default feature), skip GUI and mobile
  buildNoDefaultFeatures = true;
  buildFeatures = [ "tui" ];

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
