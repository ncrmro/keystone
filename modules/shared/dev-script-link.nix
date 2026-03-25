{ lib }:
let
  resolveRepoCheckout =
    config: repoFlakeInput:
    let
      repos = config.keystone.repos or { };
      homeDir = config.home.homeDirectory;
      repoEntry = lib.findFirst (name: (repos.${name}.flakeInput or null) == repoFlakeInput) null (
        lib.attrNames repos
      );
    in
    if (config.keystone.development or false) && repoEntry != null then
      "${homeDir}/.keystone/repos/${repoEntry}"
    else
      null;
in
{
  inherit resolveRepoCheckout;

  mkHomeScriptCommand =
    {
      config,
      commandName,
      relativePath,
      package,
      repoFlakeInput ? "keystone",
    }:
    let
      repoCheckout = resolveRepoCheckout config repoFlakeInput;
    in
    lib.mkMerge [
      (lib.mkIf (repoCheckout == null) {
        home.packages = [ package ];
      })
      (lib.mkIf (repoCheckout != null) {
        home.file.".local/bin/${commandName}".source =
          config.lib.file.mkOutOfStoreSymlink "${repoCheckout}/${relativePath}";
      })
    ];
}
