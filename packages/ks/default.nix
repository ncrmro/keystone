{
  lib,
  writeShellApplication,
  nix,
  git,
  jq,
  openssh,
  hostname,
}:
writeShellApplication {
  name = "ks";
  runtimeInputs = [
    nix
    git
    jq
    openssh
    hostname
  ];
  text = builtins.readFile ./ks.sh;
  meta = with lib; {
    description = "Keystone infrastructure CLI — build and deploy NixOS configurations";
    license = licenses.mit;
    mainProgram = "ks";
  };
}
