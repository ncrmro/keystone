{
  buildNpmPackage,
  fetchurl,
  lib,
}:

buildNpmPackage rec {
  pname = "pi-mcp-extension";
  version = "1.5.0";

  src = fetchurl {
    url = "https://registry.npmjs.org/pi-mcp-extension/-/pi-mcp-extension-${version}.tgz";
    hash = "sha256-TKGvTaly8ailXh5vInV90N5qzcB18VXmuclLXEKPaO0=";
  };

  postPatch = ''
    cp ${./package-lock.json} package-lock.json
  '';

  npmDepsHash = "sha256-ygYAD6eAQ8F8d3d34NVoa5pAqvCF09Q/tW80003/2TA=";

  dontNpmBuild = true;

  meta = {
    description = "MCP client extension for the Pi coding agent";
    homepage = "https://github.com/irahardianto/pi-mcp-extension";
    downloadPage = "https://www.npmjs.com/package/pi-mcp-extension";
    license = lib.licenses.mit;
  };
}
