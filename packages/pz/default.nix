{
  curl,
  eternal-terminal,
  jq,
  lib,
  nix,
  openssh,
  writeShellApplication,
  yq-go,
  zk,
  zellij,
}:
writeShellApplication {
  name = "pz";
  runtimeInputs = [
    curl
    eternal-terminal
    jq
    nix
    openssh
    yq-go
    zk
    zellij
  ];
  text = builtins.readFile ./pz.sh;
  meta = with lib; {
    description = "Projctl Zellij session manager — create and attach to project sessions";
    license = licenses.mit;
    mainProgram = "pz";
  };
}
