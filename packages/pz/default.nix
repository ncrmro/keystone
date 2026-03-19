{
  lib,
  writeShellApplication,
  zellij,
}:
writeShellApplication {
  name = "pz";
  runtimeInputs = [
    zellij
  ];
  text = builtins.readFile ./pz.sh;
  meta = with lib; {
    description = "Projctl Zellij session manager — create and attach to project sessions";
    license = licenses.mit;
    mainProgram = "pz";
  };
}
