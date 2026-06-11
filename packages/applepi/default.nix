# applepi — profile-oriented wrapper for launching pi/claude agent CLIs.
#
# Source comes from the `applepi-src` flake input (the Unsupervisedcom/bridl
# repo, renamed upstream to ApplePi). When applepi is published to a fetchable
# URL, swap the input in flake.nix and update `npmDepsHash` below.
{
  lib,
  buildNpmPackage,
  applepi-src,
}:
buildNpmPackage {
  pname = "applepi";
  version = "0-unstable";

  src = applepi-src;

  npmDepsHash = "sha256-yC+2UdB29auGoBRnNztDICJnfo2Wp25svDLwrQMU9Q8=";
  npmDepsFetcherVersion = 2;

  # ApplePi's `prepare` script invokes `npm run build` which runs tsc + schemas
  # copy + chmod +x dist/cli.js. That's exactly what we want for installation,
  # so let the default build phase drive it.
  meta = {
    description = "Profile-oriented wrapper for launching pi, Claude Code, and future agent CLIs";
    homepage = "https://github.com/Unsupervisedcom/bridl";
    license = lib.licenses.bsl11;
    mainProgram = "applepi";
  };
}
