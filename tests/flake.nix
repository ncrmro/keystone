{
  description = "Keystone test suite and development configurations";

  inputs = {
    # Reference the parent Keystone flake
    keystone.url = "path:..";
    # Follow inputs from parent to ensure consistency
    nixpkgs.follows = "keystone/nixpkgs";
    home-manager.follows = "keystone/home-manager";
    disko.follows = "keystone/disko";
  };

  outputs =
    {
      self,
      keystone,
      nixpkgs,
      home-manager,
      ...
    }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        overlays = [
          (final: prev: {
            keystone = {
              claude-code =
                final.runCommand "mock-claude" { }
                  "mkdir -p $out/bin; touch $out/bin/claude; chmod +x $out/bin/claude";
              gemini-cli =
                final.runCommand "mock-gemini" { }
                  "mkdir -p $out/bin; touch $out/bin/gemini; chmod +x $out/bin/gemini";
              codex =
                final.runCommand "mock-codex" { }
                  "mkdir -p $out/bin; touch $out/bin/codex; chmod +x $out/bin/codex";
              opencode =
                final.runCommand "mock-opencode" { }
                  "mkdir -p $out/bin; touch $out/bin/opencode; chmod +x $out/bin/opencode";
              auto-claude =
                final.runCommand "mock-auto-claude" { }
                  "mkdir -p $out/bin; touch $out/bin/auto-claude; chmod +x $out/bin/auto-claude";
              deepwork =
                final.runCommand "mock-deepwork" { }
                  "mkdir -p $out/bin; touch $out/bin/deepwork; chmod +x $out/bin/deepwork";
              chrome-devtools-mcp = final.runCommand "mock-chrome" { } "mkdir -p $out; touch $out/placeholder";
              slidev =
                final.runCommand "mock-slidev" { }
                  "mkdir -p $out/bin; touch $out/bin/slidev; chmod +x $out/bin/slidev";
              agenix =
                final.runCommand "mock-agenix" { }
                  "mkdir -p $out/bin; touch $out/bin/agenix; chmod +x $out/bin/agenix";
              pz = final.runCommand "mock-pz" { } "mkdir -p $out/bin; touch $out/bin/pz; chmod +x $out/bin/pz";
              calendula =
                final.runCommand "mock-calendula" { }
                  "mkdir -p $out/bin; touch $out/bin/calendula; chmod +x $out/bin/calendula";
              cardamum =
                final.runCommand "mock-cardamum" { }
                  "mkdir -p $out/bin; touch $out/bin/cardamum; chmod +x $out/bin/cardamum";
              keystone-conventions =
                final.runCommand "mock-conventions" { }
                  "mkdir -p $out; touch $out/placeholder";
              fetch-forgejo-sources =
                final.runCommand "mock-fetch-forgejo" { }
                  "mkdir -p $out/bin; touch $out/bin/fetch-forgejo-sources; chmod +x $out/bin/fetch-forgejo-sources";
              fetch-github-sources =
                final.runCommand "mock-fetch-github" { }
                  "mkdir -p $out/bin; touch $out/bin/fetch-github-sources; chmod +x $out/bin/fetch-github-sources";
              fetch-email-source =
                final.runCommand "mock-fetch-email" { }
                  "mkdir -p $out/bin; touch $out/bin/fetch-email-source; chmod +x $out/bin/fetch-email-source";
              ks = final.runCommand "mock-ks" { } "mkdir -p $out/bin; touch $out/bin/ks; chmod +x $out/bin/ks";
              podman-agent =
                final.runCommand "mock-podman-agent" { }
                  "mkdir -p $out/bin; touch $out/bin/podman-agent; chmod +x $out/bin/podman-agent";
              zesh =
                final.runCommand "mock-zesh" { }
                  "mkdir -p $out/bin; touch $out/bin/zesh; chmod +x $out/bin/zesh";
              forgejo-project =
                final.runCommand "mock-forgejo-project" { }
                  "mkdir -p $out/bin; touch $out/bin/forgejo-project; chmod +x $out/bin/forgejo-project";
              agent-mail =
                final.runCommand "mock-agent-mail" { }
                  "mkdir -p $out/bin; touch $out/bin/agent-mail; chmod +x $out/bin/agent-mail";
              agent-coding-agent =
                final.runCommand "mock-agent-coding" { }
                  "mkdir -p $out/bin; touch $out/bin/agent-coding-agent; chmod +x $out/bin/agent-coding-agent";
              keystone-deepwork-jobs = final.runCommand "mock-jobs" { } "mkdir -p $out; touch $out/placeholder";
              himalaya =
                final.runCommand "mock-himalaya" { }
                  "mkdir -p $out/bin; touch $out/bin/himalaya; chmod +x $out/bin/himalaya";
              comodoro =
                final.runCommand "mock-comodoro" { }
                  "mkdir -p $out/bin; touch $out/bin/comodoro; chmod +x $out/bin/comodoro";
              cfait =
                final.runCommand "mock-cfait" { }
                  "mkdir -p $out/bin; touch $out/bin/cfait; chmod +x $out/bin/cfait";
              deepwork-library-jobs =
                final.runCommand "mock-lib-jobs" { }
                  "mkdir -p $out; touch $out/placeholder";
              repo-sync =
                final.runCommand "mock-sync" { }
                  "mkdir -p $out/bin; touch $out/bin/repo-sync; chmod +x $out/bin/repo-sync";
            };
          })
        ];
      };
      lib = pkgs.lib;
    in
    {
      checks.${system} = {
        test-service-account-provisioning = import ./module/service-account-provisioning.nix {
          inherit
            pkgs
            lib
            home-manager
            ;
          self = keystone;
        };

        test-installer = import ./integration/installer.nix {
          inherit pkgs;
          lib = pkgs.lib;
        };

        agent-evaluation = import ./module/agent-evaluation.nix {
          inherit
            pkgs
            lib
            home-manager
            ;
          self = keystone;
          agenix = pkgs.keystone.agenix;
        };
      };

      packages.${system} = self.checks.${system};
    };
}
