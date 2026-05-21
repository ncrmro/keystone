# Portable per-user devbox container image.
#
# Wraps a home-manager `activationPackage` in a layered OCI image that runs
# the activation script JIT at container start, then launches sshd + ttyd →
# zellij. The image is fully self-contained: no host /nix/store mount, no
# nix-build-on-first-start, no GitHub fetcher round-trip.
#
# Pair with `mkSystemFlake { portableUsers = { … }; }` in lib/templates.nix,
# which produces the activationPackage with `terminalMinimal = true` via
# specialArgs — mirroring the installer-ISO build at lib/templates.nix:481-494.
{
  lib,
  runCommand,
  dockerTools,
  writeShellScript,
  bashInteractive,
  coreutils,
  openssh,
  cacert,
  iana-etc,
  tzdata,
  ttyd,
  zellij,
  nix,
  git,
  gh,
  direnv,
  gnused,
  gnugrep,
  gawk,
  procps,
  findutils,
  which,
  less,
  curl,
  shadow,

  # Caller-supplied via mkSystemFlake.portableUsers.<user>:
  homeActivationPackage,
  ks ? null,
  imageName ? "devbox",
  imageTag ? "latest",
  extraContents ? [ ],
}:
let
  runtimeBins = [
    bashInteractive
    coreutils
    openssh
    cacert
    iana-etc
    tzdata
    ttyd
    zellij
    nix
    git
    gh
    direnv
    gnused
    gnugrep
    gawk
    procps
    findutils
    which
    less
    curl
    shadow
  ]
  ++ lib.optional (ks != null) ks
  ++ extraContents;

  runtimePath = lib.makeBinPath runtimeBins;

  # Minimal /etc skeleton + writable dirs. The spike's container had to repair
  # dangling /etc/passwd symlinks at runtime; here we own the rootfs from the
  # start so the entrypoint never has to.
  staticTree = runCommand "devbox-static-tree" { } ''
    mkdir -p $out/etc/ssh $out/etc/profile.d $out/root/.ssh $out/var/empty
    mkdir -p $out/work $out/tmp

    cat > $out/etc/passwd <<EOF
    root:x:0:0:root:/root:${bashInteractive}/bin/bash
    nobody:x:65534:65534:nobody:/var/empty:/bin/false
    sshd:x:74:74:sshd:/var/empty:/bin/false
    EOF

    cat > $out/etc/group <<'EOF'
    root:x:0:
    nogroup:x:65534:
    sshd:x:74:
    EOF

    cat > $out/etc/nsswitch.conf <<'EOF'
    passwd:    files
    group:     files
    hosts:     files dns
    networks:  files dns
    EOF

    cat > $out/etc/ssh/sshd_config <<'EOF'
    Port 22
    PermitRootLogin prohibit-password
    PasswordAuthentication no
    ChallengeResponseAuthentication no
    UsePAM no
    AcceptEnv DEV_PORT_* DEVBOX_* GITHUB_TOKEN GH_TOKEN
    PrintMotd no
    EOF

    chmod 1777 $out/tmp
    chmod 0700 $out/root
  '';

  entrypoint = writeShellScript "devbox-init" ''
    #!${bashInteractive}/bin/bash
    set -u

    export PATH="${runtimePath}"
    export HOME=/root
    export USER=root

    # Normalize commas → spaces in DEV_PORTS (Quadlet emits comma-separated
    # so the systemd Environment= parser doesn't split on whitespace).
    if [ -n "''${DEV_PORTS:-}" ]; then
      DEV_PORTS=$(printf '%s' "$DEV_PORTS" | tr ',' ' ')
      export DEV_PORTS
    fi

    # 1. Idempotent home-manager activation. Closure is fully in the image —
    # `activate` only writes/symlinks files; no network, no nix build.
    if ! ${homeActivationPackage}/activate 2>&1; then
      echo "devbox: home-manager activation reported errors; continuing" >&2
    fi

    # 2. ssh host keys — /etc/ssh is volume-mounted by the launcher.
    if [ ! -f /etc/ssh/ssh_host_ed25519_key ]; then
      ${openssh}/bin/ssh-keygen -A
    fi

    # 3. authorized_keys from a launcher mount.
    if [ -f /run/authorized_keys ]; then
      cp /run/authorized_keys /root/.ssh/authorized_keys
      chmod 600 /root/.ssh/authorized_keys
    fi

    # 4. GitHub PAT from podman secret (mounted by the launcher per-instance).
    cat > /etc/profile.d/devbox-github.sh <<'EOSH'
    if [ -f /run/secrets/github-pat ]; then
      GITHUB_TOKEN="$(tr -d '\n' < /run/secrets/github-pat)"
      export GITHUB_TOKEN
      export GH_TOKEN="$GITHUB_TOKEN"
      export GITHUB_TOKEN_FILE=/run/secrets/github-pat
    fi
    EOSH

    cat > /etc/profile.d/devbox-ports.sh <<EOSH
    export DEV_PORT_BASE="''${DEV_PORT_BASE:-}"
    export DEV_PORT_SPAN="''${DEV_PORT_SPAN:-}"
    export DEV_PORT_WEB="''${DEV_PORT_WEB:-}"
    export DEV_PORT_SSH="''${DEV_PORT_SSH:-}"
    export DEV_PORTS="''${DEV_PORTS:-}"
    export DEVBOX_OWNER="''${DEVBOX_OWNER:-}"
    export DEVBOX_REPO="''${DEVBOX_REPO:-}"
    EOSH

    SESSION="''${DEVBOX_REPO:-devbox}"

    # 5. sshd is best-effort; if it fails, ttyd is still up for debugging.
    ${openssh}/bin/sshd -D &

    exec ${ttyd}/bin/ttyd -W -p 7681 \
      -t fontSize=14 \
      -t 'theme={"background":"#1d1f21"}' \
      ${bashInteractive}/bin/bash -lc "cd /work && ${zellij}/bin/zellij attach -c '$SESSION'"
  '';

in
dockerTools.buildLayeredImage {
  name = imageName;
  tag = imageTag;
  # 100 is the dockerTools default; documented here so changes to layer
  # strategy are explicit. Higher = better dedup, slower podman pull.
  maxLayers = 100;

  contents = runtimeBins ++ [ staticTree ];

  config = {
    Cmd = [ entrypoint ];
    WorkingDir = "/work";
    Env = [
      "PATH=${runtimePath}"
      "HOME=/root"
      "USER=root"
      "TERM=xterm-256color"
      "LANG=C.UTF-8"
      "SSL_CERT_FILE=${cacert}/etc/ssl/certs/ca-bundle.crt"
      "NIX_SSL_CERT_FILE=${cacert}/etc/ssl/certs/ca-bundle.crt"
      "TZDIR=${tzdata}/share/zoneinfo"
    ];
    ExposedPorts = {
      "7681/tcp" = { };
      "22/tcp" = { };
    };
    Labels = {
      "org.opencontainers.image.title" = "Keystone devbox";
      "org.opencontainers.image.description" =
        "Portable per-user terminal sandbox built from a keystone home-manager profile";
      "org.opencontainers.image.source" = "https://github.com/ncrmro/keystone";
    };
  };

  meta = {
    description = "Portable Keystone devbox container image";
    platforms = lib.platforms.linux;
  };
}
