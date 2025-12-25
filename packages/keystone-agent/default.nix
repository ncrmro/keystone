{
  lib,
  python3Packages,
  makeWrapper,
  nix,
}:
python3Packages.buildPythonApplication {
  pname = "keystone-agent";
  version = "0.1.0";

  src = ./.;

  format = "other";

  nativeBuildInputs = [makeWrapper];

  # No Python dependencies yet, but ready for adding them
  propagatedBuildInputs = [];

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin
    cp agent.py $out/bin/keystone-agent
    chmod +x $out/bin/keystone-agent

    # Wrap to ensure python3 is available
    wrapProgram $out/bin/keystone-agent \
      --prefix PATH : ${lib.makeBinPath [nix]}

    runHook postInstall
  '';

  meta = with lib; {
    description = "Keystone Agent Sandbox Manager - CLI for managing isolated MicroVM environments for AI coding agents";
    homepage = "https://github.com/ncrmro/keystone";
    license = licenses.mit;
    maintainers = [];
    mainProgram = "keystone-agent";
  };
}
