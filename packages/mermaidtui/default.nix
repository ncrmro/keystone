{
  lib,
  fetchzip,
  makeWrapper,
  nodejs,
  stdenvNoCC,
}:
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "mermaidtui";
  version = "0.0.5";

  src = fetchzip {
    url = "https://registry.npmjs.org/mermaidtui/-/mermaidtui-${finalAttrs.version}.tgz";
    hash = "sha256-XlyypUb6lopWxUH/ZFcSajiGQezVoYyTzRHLzh5p87Y=";
  };

  nativeBuildInputs = [ makeWrapper ];

  dontConfigure = true;
  dontBuild = true;
  doInstallCheck = true;

  installPhase = ''
    runHook preInstall

    pkgDir="$out/lib/node_modules/mermaidtui"
    mkdir -p "$pkgDir" "$out/bin"

    cp -r --no-preserve=mode,ownership dist package.json "$pkgDir"/

    makeWrapper ${nodejs}/bin/node "$out/bin/mermaidtui" \
      --add-flags "$pkgDir/dist/cli/index.js"

    runHook postInstall
  '';

  installCheckPhase = ''
    runHook preInstallCheck

    echo "graph TD; A-->B;" | $out/bin/mermaidtui >/dev/null

    runHook postInstallCheck
  '';

  meta = {
    description = "Deterministic Unicode and ASCII Mermaid diagram renderer for the terminal";
    homepage = "https://github.com/tariqshams/mermaidtui";
    downloadPage = "https://www.npmjs.com/package/mermaidtui";
    license = lib.licenses.asl20;
    mainProgram = "mermaidtui";
  };
})
