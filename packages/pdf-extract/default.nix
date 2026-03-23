{
  lib,
  stdenv,
  makeWrapper,
  python3Packages,
  jq,
  findutils,
  coreutils,
}:
stdenv.mkDerivation {
  pname = "pdf-extract";
  version = "0.2.0";

  src = ./bin;

  nativeBuildInputs = [ makeWrapper ];

  dontUnpack = true;

  installPhase = ''
    mkdir -p $out/bin
    cp $src/pdf-extract $out/bin/
    chmod +x $out/bin/*

    wrapProgram $out/bin/pdf-extract \
      --prefix PATH : ${
        lib.makeBinPath [
          python3Packages.docling
          jq
          findutils
          coreutils
        ]
      }
  '';

  meta = with lib; {
    description = "Convert PDF to markdown with element-level bounding box citations via Docling";
    mainProgram = "pdf-extract";
  };
}
