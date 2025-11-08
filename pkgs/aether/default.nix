{
  lib,
  stdenv,
  fetchFromGitHub,
  makeWrapper,
  gjs,
  gtk4,
  libadwaita,
  libsoup_3,
  imagemagick,
  wrapGAppsHook4,
  gobject-introspection,
}:

stdenv.mkDerivation rec {
  pname = "aether";
  version = "unstable-2024-11-08";

  src = fetchFromGitHub {
    owner = "bjarneo";
    repo = "aether";
    rev = "1ac730453e7a9c3dd6b28ae4d6a1b9e8c5e6f8f9";
    hash = lib.fakeSha256;
  };

  nativeBuildInputs = [
    makeWrapper
    wrapGAppsHook4
    gobject-introspection
  ];

  buildInputs = [
    gjs
    gtk4
    libadwaita
    libsoup_3
    imagemagick
  ];

  dontBuild = true;

  installPhase = ''
    runHook preInstall

    # Create directories
    mkdir -p $out/share/aether
    mkdir -p $out/bin
    mkdir -p $out/share/applications
    mkdir -p $out/share/icons/hicolor/256x256/apps

    # Copy source files
    cp -r src $out/share/aether/
    cp -r templates $out/share/aether/
    cp -r shaders $out/share/aether/

    # Copy icon
    cp icon.png $out/share/icons/hicolor/256x256/apps/aether.png

    # Copy desktop file
    cp li.oever.aether.desktop $out/share/applications/

    # Create wrapper script
    cat > $out/bin/aether <<EOF
#!/bin/bash
cd $out/share/aether
exec ${gjs}/bin/gjs -m src/main.js "\$@"
EOF

    chmod +x $out/bin/aether

    runHook postInstall
  '';

  preFixup = ''
    gappsWrapperArgs+=(
      --prefix PATH : ${lib.makeBinPath [ imagemagick ]}
    )
  '';

  meta = with lib; {
    description = "A visual theming application for Omarchy";
    longDescription = ''
      Aether is a desktop theming application that provides:
      - Intelligent color extraction from wallpapers using ImageMagick
      - Wallhaven.cc wallpaper browsing integration
      - Template-based theme generation for multiple applications
      - Blueprint system for saving and loading themes
      - Support for Hyprland, Waybar, Kitty, and 15+ more applications
    '';
    homepage = "https://github.com/bjarneo/aether";
    license = licenses.unfree; # License not specified in repository
    maintainers = [ ];
    platforms = platforms.linux;
    mainProgram = "aether";
  };
}
