{
  lib,
  stdenvNoCC,
  makeWrapper,
  python3,
  curl,
  gh,
  systemd,
  bash,
  runCommand,
}:
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "pi-task-runner";
  version = "0.1.0";

  src = ./.;

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin
    cp bin/pi-task-runner $out/bin/pi-task-runner
    substituteInPlace $out/bin/pi-task-runner \
      --replace-fail '#!/usr/bin/env python3' '#!${python3}/bin/python'
    chmod +x $out/bin/pi-task-runner
    wrapProgram $out/bin/pi-task-runner \
      --prefix PATH : "${
        lib.makeBinPath [
          curl
          gh
          systemd
        ]
      }"

    runHook postInstall
  '';

  passthru.tests.runner = runCommand "pi-task-runner-test" { nativeBuildInputs = [ python3 ]; } ''
                set -eu

        bin="${finalAttrs.finalPackage}/bin/pi-task-runner"
        home="$TMPDIR/home"
        state="$TMPDIR/state"
        mock_bin="$PWD/mock-bin"
        worktree="$home/repos/tmp/worktree/agent-ping-pong/feat/ping-pong"
        mkdir -p "$worktree/.git" "$mock_bin" "$home/.config/keystone" "$home/.pi/agent"
        printf '%s\n' '# Pi agent instructions' 'Use local tools promptly.' > "$home/.pi/agent/AGENTS.md"
        printf '%s\n' '# OS agent tools' 'Use himalaya for email.' > "$home/.config/keystone/TOOLS.md"

        {
          printf '%s\n' '#!${bash}/bin/bash'
          printf '%s\n' 'cat <<JSON'
          printf '%s\n' '['
          printf '%s\n' '  {"source":"forgejo","data":['
          printf '%s\n' '    {'
          printf '%s\n' '      "repo":"tmp/agent-ping-pong",'
          printf '%s\n' '      "number":1,'
          printf '%s\n' '      "title":"Ping pong assignment",'
          printf '%s\n' '      "url":"https://git.ncrmro.com/tmp/agent-ping-pong/issues/1",'
          printf '%s\n' '      "type":"Issue",'
          printf '%s\n' "      \"agent_task\":{\"agent\":\"drago\",\"repo\":\"tmp/agent-ping-pong\",\"branch\":\"feat/ping-pong\",\"worktree\":\"$worktree\",\"provider\":\"pi\",\"model\":\"ollama/qwen3:4b\",\"prompt\":\"Reply pong.\"}"
          printf '%s\n' '    }'
          printf '%s\n' '  ]}'
          printf '%s\n' ']'
          printf '%s\n' 'JSON'
        } > "$mock_bin/ks"

        email_worktree="$home/repos/tmp/worktree/mail-agent/feat/email-pong"
        mkdir -p "$email_worktree/.git"
        {
          printf '%s\n' '#!${bash}/bin/bash'
          printf '%s\n' 'cat <<JSON'
          printf '%s\n' '['
          printf '%s\n' '  {"source":"email","data":['
          printf '%s\n' '    {'
          printf '%s\n' '      "id":"mail-1",'
          printf '%s\n' '      "subject":"Please reply pong",'
          printf '%s\n' '      "to":{"addr":"drago@example.com"},'
          printf '%s\n' '      "from":{"addr":"tester@example.com"},'
          printf '%s\n' "      \"agent_task\":{\"agent\":\"drago\",\"repo\":\"tmp/mail-agent\",\"branch\":\"feat/email-pong\",\"worktree\":\"$email_worktree\",\"executor\":\"pi\",\"model\":\"ollama/qwen3:4b\",\"prompt\":\"Use himalaya to reply to tester@example.com with exactly pong.\"}"
          printf '%s\n' '    }'
          printf '%s\n' '  ]}'
          printf '%s\n' ']'
          printf '%s\n' 'JSON'
        } > "$mock_bin/ks-email"

        {
          printf '%s\n' '#!${bash}/bin/bash'
          printf '%s\n' 'printf "%s\n" "$*" > "$TMPDIR/systemd-run.args"'
        } > "$mock_bin/systemd-run"

        chmod +x "$mock_bin/ks" "$mock_bin/ks-email" "$mock_bin/systemd-run"
        export PATH="$mock_bin:$PATH"

        output="$("$bin" --agent drago --home "$home" --state-dir "$state" --ks "$mock_bin/ks" --no-pi-select --systemd-run "$mock_bin/systemd-run")"
                printf '%s\n' "$output" | python -c 'import json,sys; data=json.load(sys.stdin); assert data["status"] == "selected"; assert data["task"]["repo"] == "tmp/agent-ping-pong"; assert "--worktree" in data["command"]'
                python -c 'import json,sys; assert json.load(open(sys.argv[1])) == ["forgejo:tmp/agent-ping-pong#1"]' "$state/seen.json"

        "$bin" --agent drago --home "$home" --state-dir "$state" --ks "$mock_bin/ks" --no-pi-select > "$TMPDIR/idle.json"
        python -c 'import json,sys; assert json.load(open(sys.argv[1]))["status"] == "idle"' "$TMPDIR/idle.json"

        email_state="$TMPDIR/email-state"
        email_output="$("$bin" --agent drago --home "$home" --state-dir "$email_state" --ks "$mock_bin/ks-email" --sources email --no-pi-select --systemd-run "$mock_bin/systemd-run")"
        printf '%s\n' "$email_output" | python -c 'import json,sys; data=json.load(sys.stdin); assert data["status"] == "selected"; assert data["task"]["source_ref"] == "email:mail-1"; assert data["task"]["repo"] == "tmp/mail-agent"; assert data["task"]["prompt"].startswith("Use himalaya")'
        run_script="$(python -c 'import json,sys; data=json.load(sys.stdin); print(data["command"][-1])' <<EOF
    $email_output
    EOF
    )"
        test -x "$run_script"
        grep -F -- '--mode json' "$run_script" >/dev/null
        grep -F -- '--session-dir' "$run_script" >/dev/null
        grep -F -- '--append-system-prompt' "$run_script" >/dev/null
        grep -F 'Pi agent instructions' "$run_script" >/dev/null
        grep -F 'himalaya' "$run_script" >/dev/null
        python -c 'import json,sys; data=json.load(open(sys.argv[1])); assert data["status"] == "launched"; assert data["task"]["source_ref"] == "email:mail-1"; assert data["events"].endswith("/events.jsonl"); assert data["sessions"].endswith("/sessions")' "$(dirname "$run_script")/run.json"

                mkdir -p "$out"
  '';

  meta = with lib; {
    description = "Simple notification-to-Pi OS-agent task runner";
    license = licenses.mit;
    mainProgram = "pi-task-runner";
  };
})
