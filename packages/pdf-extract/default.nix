{
  lib,
  stdenv,
  makeWrapper,
  poppler_utils,
  tesseract,
  jq,
  coreutils,
}:
stdenv.mkDerivation {
  pname = "pdf-extract";
  version = "0.1.0";

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
          poppler_utils
          tesseract
          jq
          coreutils
        ]
      }
  '';

  meta = with lib; {
    description = "Convert PDF to markdown with page-level bounding box citations";
    mainProgram = "pdf-extract";
  };
}
