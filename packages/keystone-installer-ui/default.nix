{
  lib,
  buildNpmPackage,
  nodejs,
  ...
}:
buildNpmPackage {
  pname = "keystone-installer-ui";
  version = "1.0.0";

  src = ./.;

  # Generate package-lock.json hash
  # To get the correct hash, run: nix build .#keystone-installer-ui
  # The error message will show the expected hash
  npmDepsHash = "sha256-Hge/LwloXaBSPEreeSoQWxdWN9if64PrTd8vTjCUyCM=";

  # Dependencies needed at runtime
  buildInputs = [nodejs];

  # Build script is already defined in package.json
  npmBuildScript = "build";

  # Install phase
  installPhase = ''
        runHook preInstall

        mkdir -p $out/bin $out/lib/keystone-installer

        # Copy all necessary files
        cp -r dist $out/lib/keystone-installer/
        cp -r node_modules $out/lib/keystone-installer/
        cp package.json $out/lib/keystone-installer/

        # Create executable wrapper
        cat > $out/bin/keystone-installer << EOF
    #!${nodejs}/bin/node
    import('$out/lib/keystone-installer/dist/index.js');
    EOF
        chmod +x $out/bin/keystone-installer

        runHook postInstall
  '';

  meta = with lib; {
    description = "Keystone installer TUI using Ink";
    license = licenses.mit;
    platforms = platforms.linux;
    mainProgram = "keystone-installer";
  };
}
