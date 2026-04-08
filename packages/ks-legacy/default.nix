{
  lib,
  writeShellApplication,
  curl,
  fzf,
  nix,
  git,
  glow,
  jq,
  openssh,
  hostname,
  ks,
  pandoc,
  polkit,
  cups,
  sudo,
  systemd,
  python3Packages,
  commandName ? "ks",
}:
writeShellApplication {
  name = commandName;
  runtimeInputs = [
    curl
    fzf
    nix
    git
    glow
    jq
    openssh
    hostname
    ks
    pandoc
    polkit
    cups
    sudo
    systemd
    python3Packages.weasyprint
  ];
  text = builtins.replaceStrings [ "@KS_PRINT_CSS@" ] [ "${./print.css}" ] (
    builtins.readFile ./ks.sh
  );
  meta = with lib; {
    description = "Legacy Keystone infrastructure CLI compatibility shim";
    license = licenses.mit;
    mainProgram = commandName;
  };
}
