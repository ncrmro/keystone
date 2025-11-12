{
  lib,
  rustPlatform,
  fetchFromGitHub,
}:
rustPlatform.buildRustPackage rec {
  pname = "zesh";
  version = "0.3.0";

  src = fetchFromGitHub {
    owner = "roberte777";
    repo = "zesh";
    rev = "zesh-v${version}";
    hash = "sha256-10zKOsNEcHb/bNcGC/TJLA738G0cKeMg1vt+PZpiEUI=";
  };

  cargoHash = "sha256-N39JD7qeLzro4+6wSP14uAjH8D7kv6sGuhLomcVw600=";

  meta = with lib; {
    description = "A zellij session manager with zoxide integration";
    homepage = "https://github.com/roberte777/zesh";
    license = licenses.mit;
    maintainers = [ ];
    mainProgram = "zesh";
  };
}
