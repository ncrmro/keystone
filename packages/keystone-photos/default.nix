{
  lib,
  writeShellApplication,
  bash,
  coreutils,
  curl,
  gnugrep,
  gnused,
  jq,
  util-linux,
}:
writeShellApplication {
  name = "keystone-photos";
  runtimeInputs = [
    bash
    coreutils
    curl
    gnugrep
    gnused
    jq
    util-linux
  ];
  text = builtins.readFile ./keystone-photos.sh;
  meta = with lib; {
    description = "Immich-backed Keystone photo search CLI";
    license = licenses.mit;
    mainProgram = "keystone-photos";
  };
}
