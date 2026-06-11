# bridl — profile-oriented wrapper for launching pi/claude agent CLIs.
#
# Source comes from the `bridl-src` flake input (currently a local path).
# When bridl is published to a fetchable URL, swap the input in flake.nix
# and update `npmDepsHash` below.
{
  lib,
  buildNpmPackage,
  bridl-src,
}:
buildNpmPackage {
  pname = "bridl";
  version = "0-unstable";

  src = bridl-src;

  npmDepsHash = "sha256-yC+2UdB29auGoBRnNztDICJnfo2Wp25svDLwrQMU9Q8=";
  npmDepsFetcherVersion = 2;

  # Bridl's `prepare` script invokes `npm run build` which runs tsc + schemas
  # copy + chmod +x dist/cli.js. That's exactly what we want for installation,
  # so let the default build phase drive it.
  meta = {
    description = "Profile-oriented wrapper for launching pi, Claude Code, and future agent CLIs";
    homepage = "https://github.com/Unsupervisedcom/bridl";
    license = lib.licenses.bsl11;
    mainProgram = "bridl";
  };
}
