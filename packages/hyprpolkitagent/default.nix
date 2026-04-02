{
  hyprpolkitagent,
  stdenv,
}:
hyprpolkitagent.overrideAttrs (old: {
  postPatch = (old.postPatch or "") + ''
    sed -i '/setContextProperty("hpa", authState.qmlIntegration);/a\    authState.qmlEngine->rootContext()->setContextProperty("keystoneThemePath", qEnvironmentVariable("KEYSTONE_POLKIT_THEME"));' src/core/Agent.cpp

    cp ${./main.qml} qml/main.qml
  '';

  postInstall = (old.postInstall or "") + ''
    mv "$out/libexec/hyprpolkitagent" "$out/libexec/.hyprpolkitagent-keystone"
    cat > "$out/libexec/hyprpolkitagent" <<EOF
    #!${stdenv.shell}
    export KEYSTONE_POLKIT_THEME="''${KEYSTONE_POLKIT_THEME:-$HOME/.config/keystone/current/polkit.json}"
    exec "$out/libexec/.hyprpolkitagent-keystone" "\$@"
    EOF
    chmod +x "$out/libexec/hyprpolkitagent"
  '';
})
