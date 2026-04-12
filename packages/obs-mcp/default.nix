{
  lib,
  fetchzip,
  makeWrapper,
  nodejs,
  stdenvNoCC,
}:
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "obs-mcp";
  version = "1.1.0";

  src = fetchzip {
    url = "https://registry.npmjs.org/obs-mcp/-/obs-mcp-${finalAttrs.version}.tgz";
    hash = "sha256-yOAordY9GeIKvsqDajPMrw9sr54DghrxapFuJf6FSDE=";
  };

  nativeBuildInputs = [ makeWrapper ];

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    pkgDir="$out/lib/node_modules/obs-mcp"
    mkdir -p "$pkgDir" "$out/bin"

    cp -r --no-preserve=mode,ownership LICENSE README.md build package.json "$pkgDir"/

    makeWrapper ${nodejs}/bin/node "$out/bin/obs-mcp" \
      --add-flags "$pkgDir/build/index.js"

    runHook postInstall
  '';

  meta = {
    description = "MCP server for OBS Studio WebSocket control";
    homepage = "https://github.com/royshil/obs-mcp";
    downloadPage = "https://www.npmjs.com/package/obs-mcp";
    license = lib.licenses.mit;
    mainProgram = "obs-mcp";
  };
})
