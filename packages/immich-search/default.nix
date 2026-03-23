{
  lib,
  stdenv,
  makeWrapper,
  curl,
  jq,
  coreutils,
}:
stdenv.mkDerivation {
  pname = "immich-search";
  version = "0.1.0";

  src = ./bin;

  nativeBuildInputs = [ makeWrapper ];

  dontUnpack = true;

  installPhase = ''
    mkdir -p $out/bin
    cp $src/immich-search $out/bin/
    chmod +x $out/bin/*

    wrapProgram $out/bin/immich-search \
      --prefix PATH : ${
        lib.makeBinPath [
          curl
          jq
          coreutils
        ]
      }
  '';

  meta = with lib; {
    description = "CLI for querying Immich REST API (smart search, person, recent assets)";
    mainProgram = "immich-search";
  };
}
