{
  lib,
  writeShellApplication,
  curl,
  nix,
  git,
  jq,
  openssh,
  hostname,
  pandoc,
  python3Packages,
}:
writeShellApplication {
  name = "ks";
  runtimeInputs = [
    curl
    nix
    git
    jq
    openssh
    hostname
    pandoc
    python3Packages.weasyprint
  ];
  text = builtins.readFile ./ks.sh;
  meta = with lib; {
    description = "Keystone infrastructure CLI — build and deploy NixOS configurations";
    license = licenses.mit;
    mainProgram = "ks";
  };
}
