{
  lib,
  stdenv,
  makeWrapper,
  whisper-cpp,
  ffmpeg,
  curl,
  coreutils,
}:
stdenv.mkDerivation {
  pname = "whisper-transcribe";
  version = "0.1.0";

  src = ./bin;

  nativeBuildInputs = [ makeWrapper ];

  dontUnpack = true;

  installPhase = ''
    mkdir -p $out/bin
    cp $src/whisper-transcribe $out/bin/
    chmod +x $out/bin/*

    wrapProgram $out/bin/whisper-transcribe \
      --prefix PATH : ${
        lib.makeBinPath [
          whisper-cpp
          ffmpeg
          curl
          coreutils
        ]
      }
  '';

  meta = with lib; {
    description = "Local audio transcription via whisper.cpp with auto model download";
    mainProgram = "whisper-transcribe";
  };
}
