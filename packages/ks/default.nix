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
  keystonePhotos,
  pandoc,
  polkit,
  cups,
  sudo,
  systemd,
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
    keystonePhotos
    pandoc
    polkit
    cups
    sudo
    systemd
    python3Packages.weasyprint
  ];
  text =
    builtins.replaceStrings
      [ "@KS_PRINT_CSS@" "@KS_AGENTS_E2E@" ]
      [ "${./print.css}" "${./agents-e2e.sh}" ]
      (builtins.readFile ./ks.sh);
  meta = with lib; {
    description = "Keystone infrastructure CLI — build and deploy NixOS configurations";
    license = licenses.mit;
    mainProgram = "ks";
  };
}
