{
  lib,
  python3,
  makeWrapper,
  openssh,
  git,
  lsof,
}:

python3.pkgs.buildPythonApplication {
  pname = "keystone-agent";
  version = "0.1.0";
  format = "other";

  src = ./.;

  nativeBuildInputs = [ makeWrapper ];

  propagatedBuildInputs = [
    openssh
    git
    lsof
  ];

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin
    cp agent.py $out/bin/keystone-agent
    chmod +x $out/bin/keystone-agent

    wrapProgram $out/bin/keystone-agent \
      --prefix PATH : ${
        lib.makeBinPath [
          openssh
          git
          lsof
        ]
      }

    runHook postInstall
  '';

  meta = with lib; {
    description = "MicroVM sandbox manager for AI coding agents";
    homepage = "https://github.com/ncrmro/keystone";
    license = licenses.mit;
    maintainers = [ ];
    mainProgram = "keystone-agent";
  };
}
