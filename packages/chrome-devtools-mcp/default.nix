{
  lib,
  buildNpmPackage,
  fetchzip,
}:
buildNpmPackage (finalAttrs: {
  pname = "chrome-devtools-mcp";
  version = "0.20.0";

  src = fetchzip {
    url = "https://registry.npmjs.org/chrome-devtools-mcp/-/chrome-devtools-mcp-${finalAttrs.version}.tgz";
    hash = "";
  };

  npmDepsHash = "";

  postPatch = ''
    cp ${./package-lock.json} package-lock.json
  '';

  dontNpmBuild = true;

  meta = {
    description = "Chrome DevTools MCP server for browser automation";
    homepage = "https://github.com/nicolo-ribaudo/chrome-devtools-mcp";
    downloadPage = "https://www.npmjs.com/package/chrome-devtools-mcp";
    license = lib.licenses.asl20;
    mainProgram = "chrome-devtools-mcp";
  };
})
