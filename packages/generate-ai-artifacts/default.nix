{
  lib,
  stdenv,
  makeWrapper,
  yq-go,
  coreutils,
  gnused,
  gnugrep,
  bash,
  gettext,
}:
stdenv.mkDerivation {
  pname = "generate-ai-artifacts";
  version = "0.1.0";

  src = ./.;

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    mkdir -p $out/bin
    cp generate-ai-artifacts.sh $out/bin/generate-ai-artifacts
    chmod +x $out/bin/generate-ai-artifacts
    wrapProgram $out/bin/generate-ai-artifacts \
      --prefix PATH : ${
        lib.makeBinPath [
          yq-go
          coreutils
          gnused
          gnugrep
          bash
          gettext
        ]
      }
  '';

  meta = {
    description = "Generate archetype-aware AI artifacts from conventions/archetypes.yaml";
    license = lib.licenses.mit;
    mainProgram = "generate-ai-artifacts";
  };
}
