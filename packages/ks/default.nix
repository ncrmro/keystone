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
  pandoc,
  cups,
  python3Packages,
}:
writeShellApplication {
  name = "ks";
  runtimeInputs = [
    curl
    fzf
    nix
    git
    glow
    jq
    openssh
    hostname
    pandoc
    cups
    python3Packages.weasyprint
  ];
  text = builtins.readFile ./ks.sh;
  meta = with lib; {
    description = "Keystone infrastructure CLI — build and deploy NixOS configurations";
    license = licenses.mit;
    mainProgram = "ks";
  };
}
