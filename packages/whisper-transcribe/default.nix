{
  lib,
  stdenv,
  makeWrapper,
  whisper-cpp,
  ffmpeg,
  curl,
  coreutils,
  defaultLanguage ? "en",
  defaultModel ? "large-v3",
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
      --prefix PATH : ${lib.makeBinPath [
        whisper-cpp
        ffmpeg
        curl
        coreutils
      ]} \
      --set WHISPER_DEFAULT_LANGUAGE "${defaultLanguage}" \
      --set WHISPER_DEFAULT_MODEL "${defaultModel}"
  '';

  meta = with lib; {
    description = "Local audio transcription via whisper.cpp with auto model download";
    mainProgram = "whisper-transcribe";
  };
}
