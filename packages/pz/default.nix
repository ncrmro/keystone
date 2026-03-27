{
  curl,
  jq,
  lib,
  writeShellApplication,
  zk,
  zellij,
}:
writeShellApplication {
  name = "pz";
  runtimeInputs = [
    curl
    jq
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
