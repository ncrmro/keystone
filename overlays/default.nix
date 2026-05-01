# Overlay that provides keystone packages.
# Receives flake inputs as arguments so that paths and flake references resolve
# correctly when a consumer flake applies the overlay.
{
  self,
  crane,
  himalaya,
  calendula,
  cardamum,
  comodoro,
  llm-agents,
  browser-previews,
  ghostty,
  yazi,
  agenix,
  deepwork,
  grafana-mcp-src,
  lfs-s3-src,
}:
let
  # Paths must be captured in `let` BEFORE the overlay function, otherwise they
  # get evaluated in the wrong context when the overlay is applied by a consumer flake
  zesh-src = ../packages/zesh;
  agent-coding-agent-src = ../packages/agent-coding-agent;
  agent-mail-src = ../packages/agent-mail;
  fetch-email-source-src = ../packages/fetch-email-source;
  fetch-forgejo-sources-src = ../packages/fetch-forgejo-sources;
  forgejo-cli-ex-src = ../packages/forgejo-cli-ex;
  forgejo-project-src = ../packages/forgejo-project;
  fetch-github-sources-src = ../packages/fetch-github-sources;
  repo-sync-src = ../packages/repo-sync;
  podman-agent-src = ../packages/podman-agent;
  cfait-src = ../packages/cfait;
  zellij-tab-name-src = ../packages/zellij-tab-name;
  hyprpolkitagent-src = ../packages/hyprpolkitagent;
  agents-e2e-src = ../packages/agents-e2e;
  ks-src = ../packages/ks;
  ks-legacy-src = ../packages/ks-legacy;
  pz-src = ../packages/pz;
  chrome-devtools-mcp-src = ../packages/chrome-devtools-mcp;
  grafana-mcp-pkg-src = ../packages/grafana-mcp;
  lfs-s3-pkg-src = ../packages/lfs-s3;
  deepwork-library-jobs-src = ../packages/deepwork-library-jobs;
  keystone-deepwork-jobs-src = ../packages/keystone-deepwork-jobs;
  keystone-conventions-src = ../packages/keystone-conventions;
  slidev-src = ../packages/slidev;
  himalaya-flake = himalaya;
  calendula-flake = calendula;
  cardamum-flake = cardamum;
  comodoro-flake = comodoro;
  llm-agents-src = llm-agents;
  browser-previews-flake = browser-previews;
  ghostty-flake = ghostty;
  yazi-flake = yazi;
  agenix-flake = agenix;
  deepwork-flake = deepwork;
in
final: prev:
let
  system = final.stdenv.hostPlatform.system;
  llmAgentsPkgs = import prev.path {
    inherit system;
    config.allowUnfree = true;
  };
  llmAgentsWrapBuddy =
    llmAgentsPkgs.callPackage "${llm-agents-src}/packages/wrapBuddy/package.nix"
      { };
  llmAgentsVersionCheckHomeHook =
    llmAgentsPkgs.callPackage "${llm-agents-src}/packages/versionCheckHomeHook/default.nix"
      { };
  # Required since llm-agents.nix commit 4049025 (2026-04-26): packages like
  # gemini-cli `inherit (perSystem.self) buildNpmPackage`. Upstream wraps
  # nixpkgs' buildNpmPackage with an eval-time guard that requires
  # fetchNpmDeps to support `fetcherVersion = 2`. The guard's failure message
  # tells you to bump nixpkgs (>= 203662a570c4, 2026-02-15) or switch to
  # overlays.default / the flake packages directly. Without this attr, the
  # inherit fails with "attribute 'buildNpmPackage' missing" and blocks every
  # host build.
  llmAgentsBuildNpmPackage =
    llmAgentsPkgs.callPackage "${llm-agents-src}/packages/buildNpmPackage/default.nix"
      { };
  llmAgentsPerSystem = {
    self = {
      wrapBuddy = llmAgentsWrapBuddy;
      versionCheckHomeHook = llmAgentsVersionCheckHomeHook;
      buildNpmPackage = llmAgentsBuildNpmPackage;
    };
  };
in
{
  # Expose crane library for Rust package builds — auto-resolved by callPackage
  craneLib = crane.mkLib final;

  keystone = {
    zesh = final.callPackage zesh-src { };
    agent-coding-agent = final.callPackage agent-coding-agent-src { };
    agent-mail = final.callPackage agent-mail-src { himalaya = final.keystone.himalaya; };
    fetch-email-source = final.callPackage fetch-email-source-src {
      himalaya = final.keystone.himalaya;
    };
    fetch-forgejo-sources = final.callPackage fetch-forgejo-sources-src { };
    forgejo-cli-ex = final.callPackage forgejo-cli-ex-src { };
    forgejo-project = final.callPackage forgejo-project-src { };
    fetch-github-sources = final.callPackage fetch-github-sources-src { };
    repo-sync = final.callPackage repo-sync-src { };
    podman-agent = final.callPackage podman-agent-src { };
    agents-e2e = final.callPackage agents-e2e-src { };
    ks-legacy = final.callPackage ks-legacy-src {
      commandName = "ks-legacy";
      ks = final.keystone.ks;
    };
    ks = final.callPackage ks-src { };
    pz = final.callPackage pz-src { };
    cfait = final.callPackage cfait-src { };
    zellij-tab-name = final.callPackage zellij-tab-name-src { };
    hyprpolkitagent = final.callPackage hyprpolkitagent-src { };
    himalaya = himalaya-flake.packages.${system}.default;
    calendula = calendula-flake.packages.${system}.default;
    cardamum = cardamum-flake.packages.${system}.default;
    # Comodoro upstream flake is missing dbus from buildInputs/nativeBuildInputs.
    # The postInstall phase runs the binary (to generate completions) before
    # fixup patches RPATH, so we also set LD_LIBRARY_PATH during install.
    comodoro = comodoro-flake.packages.${system}.default.overrideAttrs (
      old:
      let
        libPath = final.lib.makeLibraryPath [ final.dbus ];
      in
      {
        nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [
          final.pkg-config
          final.makeWrapper
        ];
        buildInputs = (old.buildInputs or [ ]) ++ [ final.dbus ];
        postInstall = ''
          export LD_LIBRARY_PATH="${libPath}''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
        ''
        + (old.postInstall or "")
        + ''
          wrapProgram $out/bin/comodoro --prefix LD_LIBRARY_PATH : "${libPath}"
        '';
      }
    );
    # Import only the four upstream agent packages Keystone exposes. Avoid
    # llm-agents.packages.${system}: unrelated broken upstream packages can make
    # the whole package set fail evaluation during nixos-install.
    claude-code = import "${llm-agents-src}/packages/claude-code/default.nix" {
      pkgs = llmAgentsPkgs;
      perSystem = llmAgentsPerSystem;
    };
    gemini-cli = import "${llm-agents-src}/packages/gemini-cli/default.nix" {
      pkgs = llmAgentsPkgs;
      perSystem = llmAgentsPerSystem;
    };
    codex =
      (import "${llm-agents-src}/packages/codex/default.nix" {
        pkgs = llmAgentsPkgs;
      }).overrideAttrs
        (old: {
          cargoDeps = llmAgentsPkgs.rustPlatform.fetchCargoVendor {
            inherit (old) src;
            name = "codex-${old.version}";
            sourceRoot = "source/codex-rs";
            hash = "sha256-2ZoibDx2LFVdE+dQNei60/eh+qMeDVPVR5DLlK2E+XM=";
            postBuild = ''
              # SECURITY: nixpkgs' vendoring helper recursively probes every
              # Cargo.toml in git dependencies. The rules_rust repo pulled in by
              # Codex's `runfiles` crate contains many intentionally broken test
              # and example workspaces, so keep only the standalone runfiles
              # crate subtree that Codex actually depends on.
              rules_rust_tree="$out/git/b56cbaa8465e74127f1ea216f813cd377295ad81"
              find "$rules_rust_tree" -mindepth 1 -maxdepth 1 ! -name rust -exec rm -rf {} +
              find "$rules_rust_tree/rust" -mindepth 1 -maxdepth 1 ! -name runfiles -exec rm -rf {} +
            '';
          };
        });
    opencode = import "${llm-agents-src}/packages/opencode/default.nix" {
      pkgs = llmAgentsPkgs;
      perSystem = llmAgentsPerSystem;
    };
    # Browsers from browser-previews
    google-chrome = browser-previews-flake.packages.${system}.google-chrome;
    # Desktop tools from flake inputs
    yazi = yazi-flake.packages.${system}.default;
    agenix = agenix-flake.packages.${system}.default;
    deepwork = deepwork-flake.packages.${system}.default;
    deepwork-library-jobs = final.callPackage deepwork-library-jobs-src {
      deepwork-src = deepwork-flake;
    };
    keystone-deepwork-jobs = final.callPackage keystone-deepwork-jobs-src {
      keystone-src = self;
    };
    keystone-conventions = final.callPackage keystone-conventions-src {
      keystone-src = self;
    };
    chrome-devtools-mcp = final.callPackage chrome-devtools-mcp-src { };
    grafana-mcp = final.callPackage grafana-mcp-pkg-src {
      inherit grafana-mcp-src;
    };
    lfs-s3 = final.callPackage lfs-s3-pkg-src {
      inherit lfs-s3-src;
    };
    slidev = final.callPackage slidev-src { };
  }
  // final.lib.optionalAttrs final.stdenv.isLinux {
    # ghostty only has .default for Linux systems
    ghostty = ghostty-flake.packages.${system}.default;
  };
  # Top-level overrides so programs.ghostty/yazi use flake versions
  yazi = yazi-flake.packages.${system}.default;
}
// prev.lib.optionalAttrs prev.stdenv.isLinux {
  ghostty = ghostty-flake.packages.${prev.stdenv.hostPlatform.system}.default;
}
