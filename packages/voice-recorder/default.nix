{
  lib,
  stdenv,
  makeWrapper,
  pipewire,
  coreutils,
}:
stdenv.mkDerivation {
  pname = "voice-recorder";
  version = "0.1.0";

  src = ./bin;

  nativeBuildInputs = [ makeWrapper ];

  dontUnpack = true;

  installPhase = ''
    mkdir -p $out/bin
    cp $src/voice-recorder $out/bin/
    chmod +x $out/bin/*

    wrapProgram $out/bin/voice-recorder \
      --prefix PATH : ${
        lib.makeBinPath [
          pipewire
          coreutils
        ]
      }
  '';

  meta = with lib; {
    description = "PipeWire microphone capture to timestamped WAV files";
    mainProgram = "voice-recorder";
  };
}
