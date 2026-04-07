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
  systemd,
  python3Packages,
  agents-e2e,
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
    systemd
    python3Packages.weasyprint
  ];
  text =
    builtins.replaceStrings
      [ "@KS_PRINT_CSS@" "@KS_AGENTS_E2E@" ]
      [ "${./print.css}" "${agents-e2e}/bin/agents-e2e" ]
      (builtins.readFile ./ks.sh);
  meta = with lib; {
    description = "Keystone infrastructure CLI — build and deploy NixOS configurations";
    license = licenses.mit;
    mainProgram = "ks";
  };
}
