{
  lib,
  stdenvNoCC,
  makeWrapper,
  python3,
  git,
  systemd,
  runCommand,
}:
let
  pythonEnv = python3.withPackages (ps: [ ps.pyyaml ]);
in
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "linux-task-dispatcher";
  version = "0.1.0";

  src = ./.;

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin
    cp bin/linux-task-dispatcher $out/bin/linux-task-dispatcher
    substituteInPlace $out/bin/linux-task-dispatcher \
      --replace-fail '#!/usr/bin/env python3' '#!${pythonEnv}/bin/python'
    chmod +x $out/bin/linux-task-dispatcher
    wrapProgram $out/bin/linux-task-dispatcher \
      --set PYTHONPATH "${pythonEnv}/${pythonEnv.sitePackages}" \
      --prefix PATH : "${
        lib.makeBinPath [
          git
          systemd
        ]
      }"

    runHook postInstall
  '';

  passthru.tests.dispatcher =
    runCommand "linux-task-dispatcher-test" { nativeBuildInputs = [ git ]; }
      ''
                    set -eu

                    export HOME="$TMPDIR/home"
                    mkdir -p "$HOME/repos/ncrmro/example"
                    git -C "$HOME/repos/ncrmro/example" init
                    git -C "$HOME/repos/ncrmro/example" config user.name "Dispatcher Test"
                    git -C "$HOME/repos/ncrmro/example" config user.email "dispatcher-test@example.invalid"
                    printf 'hello\n' > "$HOME/repos/ncrmro/example/README.md"
                    git -C "$HOME/repos/ncrmro/example" add README.md
                    git -C "$HOME/repos/ncrmro/example" commit -m initial

        printf '%s\n' \
          'tasks:' \
          '  - name: missing-branch' \
          '    status: pending' \
          '    repo: ncrmro/example' \
          '    description: Missing required branch.' \
          '  - name: ready' \
          '    status: pending' \
          '    repo: ncrmro/example' \
          '    branch_name: feat/dispatcher-test' \
          '    provider: codex' \
          '    model: gpt-test' \
          '    description: Implement the dispatcher test task.' \
          > "$TMPDIR/TASKS.yaml"

                    dry_json="$(${finalAttrs.finalPackage}/bin/linux-task-dispatcher --tasks-file "$TMPDIR/TASKS.yaml" --home "$HOME" --dry-run)"
                    printf '%s\n' "$dry_json" | ${python3}/bin/python -c 'import json,sys; data=json.load(sys.stdin); assert data["task"] == "ready"; assert data["worktree"].endswith("/repos/ncrmro/worktree/example/feat/dispatcher-test")'
                    ${pythonEnv}/bin/python -c 'import sys,yaml; data=yaml.safe_load(open(sys.argv[1])); assert data["tasks"][1]["status"] == "pending"' "$TMPDIR/TASKS.yaml"

                    test_json="$(${finalAttrs.finalPackage}/bin/linux-task-dispatcher --tasks-file "$TMPDIR/TASKS.yaml" --home "$HOME" --test-mode --claimed-by test-agent)"
                printf '%s\n' "$test_json" | ${python3}/bin/python -c 'import json,sys; data=json.load(sys.stdin); assert data["task"] == "ready"; assert data["command"][:7] == ["agent.coding-agent", "--repo", "ncrmro/example", "--branch", "feat/dispatcher-test", "--provider", "codex"]'
                    test -f "$HOME/repos/ncrmro/worktree/example/feat/dispatcher-test/.git"
                    ${pythonEnv}/bin/python -c 'import sys,yaml; data=yaml.safe_load(open(sys.argv[1])); task=data["tasks"][1]; assert task["status"] == "in_progress"; assert task["claimed_by"] == "test-agent"; assert "started_at" in task' "$TMPDIR/TASKS.yaml"

                    if ${finalAttrs.finalPackage}/bin/linux-task-dispatcher --tasks-file "$TMPDIR/TASKS.yaml" --home "$HOME" --dry-run > "$TMPDIR/idle.json"; then
                      echo "expected idle dispatcher to exit non-zero" >&2
                      exit 1
                    fi
                    printf '%s\n' "$(cat "$TMPDIR/idle.json")" | ${python3}/bin/python -c 'import json,sys; assert json.load(sys.stdin)["status"] == "idle"'

            mkdir -p $out
      '';

  meta = with lib; {
    description = "Minimal Linux-native TASKS.yaml dispatcher prototype";
    license = licenses.mit;
    mainProgram = "linux-task-dispatcher";
  };
})
