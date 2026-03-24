{
  lib,
  writeShellApplication,
  nix,
  git,
  jq,
  openssh,
  hostname,
  nix-fast-build,
}:
writeShellApplication {
  name = "ks";
  runtimeInputs = [
    nix
    git
    jq
    openssh
    hostname
    nix-fast-build
  ];
  text = builtins.readFile ./ks.sh;
  meta = with lib; {
    description = "Keystone infrastructure CLI — build and deploy NixOS configurations";
    license = licenses.mit;
    mainProgram = "ks";
  };
}
