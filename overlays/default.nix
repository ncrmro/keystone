# Overlay that provides keystone packages.
# Receives flake inputs as arguments so that paths and flake references resolve
# correctly when a consumer flake applies the overlay.
{
  self,
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
}:
let
  # Paths must be captured in `let` BEFORE the overlay function, otherwise they
  # get evaluated in the wrong context when the overlay is applied by a consumer flake
  zesh-src = ../packages/zesh;
  agent-coding-agent-src = ../packages/agent-coding-agent;
  agent-mail-src = ../packages/agent-mail;
  fetch-email-source-src = ../packages/fetch-email-source;
  fetch-forgejo-sources-src = ../packages/fetch-forgejo-sources;
  forgejo-project-src = ../packages/forgejo-project;
  fetch-github-sources-src = ../packages/fetch-github-sources;
  repo-sync-src = ../packages/repo-sync;
  podman-agent-src = ../packages/podman-agent;
  cfait-src = ../packages/cfait;
  ks-src = ../packages/ks;
  pz-src = ../packages/pz;
  chrome-devtools-mcp-src = ../packages/chrome-devtools-mcp;
  grafana-mcp-pkg-src = ../packages/grafana-mcp;
  deepwork-library-jobs-src = ../packages/deepwork-library-jobs;
  keystone-deepwork-jobs-src = ../packages/keystone-deepwork-jobs;
  keystone-conventions-src = ../packages/keystone-conventions;
  himalaya-flake = himalaya;
  calendula-flake = calendula;
  cardamum-flake = cardamum;
  comodoro-flake = comodoro;
  llm-agents-flake = llm-agents;
  browser-previews-flake = browser-previews;
  ghostty-flake = ghostty;
  yazi-flake = yazi;
  agenix-flake = agenix;
  deepwork-flake = deepwork;
in
final: prev: {
  keystone = {
    zesh = final.callPackage zesh-src { };
    agent-coding-agent = final.callPackage agent-coding-agent-src { };
    agent-mail = final.callPackage agent-mail-src { himalaya = final.keystone.himalaya; };
    fetch-email-source = final.callPackage fetch-email-source-src {
      himalaya = final.keystone.himalaya;
    };
    fetch-forgejo-sources = final.callPackage fetch-forgejo-sources-src { };
    forgejo-project = final.callPackage forgejo-project-src { };
    fetch-github-sources = final.callPackage fetch-github-sources-src { };
    repo-sync = final.callPackage repo-sync-src { };
    podman-agent = final.callPackage podman-agent-src { };
    ks = final.callPackage ks-src { };
    pz = final.callPackage pz-src { };
    cfait = final.callPackage cfait-src { };
    himalaya = himalaya-flake.packages.${final.system}.default;
    calendula = calendula-flake.packages.${final.system}.default;
    cardamum = cardamum-flake.packages.${final.system}.default;
    # Comodoro upstream flake is missing dbus from buildInputs/nativeBuildInputs.
    # The postInstall phase runs the binary (to generate completions) before
    # fixup patches RPATH, so we also set LD_LIBRARY_PATH during install.
    comodoro = comodoro-flake.packages.${final.system}.default.overrideAttrs (
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
    # AI coding agents from llm-agents.nix
    claude-code = llm-agents-flake.packages.${final.system}.claude-code;
    gemini-cli = llm-agents-flake.packages.${final.system}.gemini-cli;
    codex = llm-agents-flake.packages.${final.system}.codex;
    opencode = llm-agents-flake.packages.${final.system}.opencode;
    # Browsers from browser-previews
    google-chrome = browser-previews-flake.packages.${final.system}.google-chrome;
    # Desktop tools from flake inputs
    ghostty = ghostty-flake.packages.${final.system}.default;
    yazi = yazi-flake.packages.${final.system}.default;
    agenix = agenix-flake.packages.${final.stdenv.hostPlatform.system}.default;
    deepwork = deepwork-flake.packages.${final.system}.default;
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
  };
  # Top-level overrides so programs.ghostty/yazi use flake versions
  ghostty = ghostty-flake.packages.${final.system}.default;
  yazi = yazi-flake.packages.${final.system}.default;
}
