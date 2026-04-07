{
  pkgs,
  lib,
}:
let
  emailPingFixture = ../fixtures/task-loop/email-ping-source.json;
  calendulaEventsFixture = ../fixtures/task-loop/calendula-events.json;
  emptyProjectIndexFixture = ../fixtures/task-loop/project-index-empty.json;
  defaultsJson = builtins.toJSON {
    profile = null;
    provider = "claude";
    model = null;
    fallbackModel = null;
    effort = null;
  };
  stageJson = builtins.toJSON {
    profile = null;
    provider = null;
    model = null;
    fallbackModel = null;
    effort = null;
  };
  profilesJson = builtins.toJSON {
    fast = {
      claude = {
        effort = "low";
        fallbackModel = "sonnet";
        model = "haiku";
      };
    };
    medium = {
      claude = {
        effort = "medium";
        fallbackModel = "opus";
        model = "sonnet";
      };
    };
  };
  projectIndexHelper = pkgs.writeShellScriptBin "keystone-project-index" ''
    cat ${emptyProjectIndexFixture}
  '';
  notesDir = "/tmp/task-loop-ping-pong-notes";
  taskLoopScript = pkgs.replaceVars ../../modules/os/agents/scripts/task-loop.sh {
    notesDir = notesDir;
    maxTasks = "1";
    agentName = "test";
    githubUsername = "";
    forgejoUsername = "";
    defaultsJson = defaultsJson;
    ingestJson = stageJson;
    prioritizeJson = stageJson;
    executeJson = stageJson;
    profilesJson = profilesJson;
    projectIndexHelper = projectIndexHelper;
  };
in
pkgs.runCommand "test-agent-task-loop-ping-pong"
  {
    nativeBuildInputs = with pkgs; [
      bash
      coreutils
      findutils
      gawk
      gnugrep
      gnused
      jq
      util-linux
      yq-go
    ];
  }
  ''
    set -euo pipefail

    export HOME="$PWD/home"
    export TASK_LOOP_TEST_STATE_DIR="$PWD/state"
    export PATH="$PWD/stubs:${
      lib.makeBinPath [
        pkgs.bash
        pkgs.coreutils
        pkgs.findutils
        pkgs.gawk
        pkgs.gnugrep
        pkgs.gnused
        pkgs.jq
        pkgs.util-linux
        pkgs.yq-go
      ]
    }"

    mkdir -p "$HOME" "$TASK_LOOP_TEST_STATE_DIR" "$PWD/stubs" ${notesDir}

    printf '%s\n' 'tasks: []' > ${notesDir}/TASKS.yaml
    mkdir -p ${notesDir}/.deepwork

    # Stub: systemctl (no-op)
    printf '%s\n' '#!${pkgs.bash}/bin/bash' 'exit 0' > "$PWD/stubs/systemctl"
    chmod +x "$PWD/stubs/systemctl"

    # Stub: git (no-op)
    printf '%s\n' '#!${pkgs.bash}/bin/bash' 'exit 0' > "$PWD/stubs/git"
    chmod +x "$PWD/stubs/git"

    # Stub: hostname
    printf '%s\n' '#!${pkgs.bash}/bin/bash' "printf '%s\\n' \"test-host\"" > "$PWD/stubs/hostname"
    chmod +x "$PWD/stubs/hostname"

    # Stub: fetch-email-source — returns ping email fixture with body
    printf '%s\n' '#!${pkgs.bash}/bin/bash' "cat ${emailPingFixture}" > "$PWD/stubs/fetch-email-source"
    chmod +x "$PWD/stubs/fetch-email-source"

    # Stub: calendula — returns events fixture
    printf '%s\n' '#!${pkgs.bash}/bin/bash' "cat ${calendulaEventsFixture}" > "$PWD/stubs/calendula"
    chmod +x "$PWD/stubs/calendula"

    # Stub: claude — handles ingest, prioritize, and execute stages
    cat > "$PWD/stubs/claude" <<'STUBEOF'
    #!${pkgs.bash}/bin/bash
    set -euo pipefail

    args="$*"
    state_dir="''${TASK_LOOP_TEST_STATE_DIR:?}"
    notes_dir="${notesDir}"

    if printf '%s' "$args" | grep -q "task_loop ingest"; then
      printf '%s\n' "1" > "$state_dir/ingest-count"
      printf 'tasks:\n  - name: reply-pong-to-test\n    description: "Reply with pong to the ping email from test@ncrmro.com"\n    status: pending\n    source: email\n    source_ref: "email-1-test@ncrmro.com"\n' > "$notes_dir/TASKS.yaml"

    elif printf '%s' "$args" | grep -q "task_loop prioritize"; then
      printf '%s\n' "1" > "$state_dir/prioritize-count"
      yq -i '(.tasks[] | select(.name == "reply-pong-to-test")).model = "haiku"' "$notes_dir/TASKS.yaml"

    else
      # Execute stage: record the task name and exit 0
      printf '%s\n' "1" > "$state_dir/execute-count"
      printf '%s\n' "$args" > "$state_dir/execute-args"
    fi

    printf '%s\n' '{"total_tokens":1}'
    STUBEOF
    chmod +x "$PWD/stubs/claude"

    # Run the task loop
    bash "${taskLoopScript}"

    # === Assertions ===

    # 1. Ingest was invoked
    if [[ ! -f "$TASK_LOOP_TEST_STATE_DIR/ingest-count" ]]; then
      echo "FAIL: ingest stage was not invoked" >&2
      exit 1
    fi
    echo "PASS: ingest stage invoked"

    # 2. Prioritize was invoked
    if [[ ! -f "$TASK_LOOP_TEST_STATE_DIR/prioritize-count" ]]; then
      echo "FAIL: prioritize stage was not invoked" >&2
      exit 1
    fi
    echo "PASS: prioritize stage invoked"

    # 3. Execute was invoked
    if [[ ! -f "$TASK_LOOP_TEST_STATE_DIR/execute-count" ]]; then
      echo "FAIL: execute stage was not invoked" >&2
      cat ${notesDir}/TASKS.yaml >&2
      exit 1
    fi
    echo "PASS: execute stage invoked"

    # 4. Execute received the pong task
    execute_args="$(cat "$TASK_LOOP_TEST_STATE_DIR/execute-args")"
    if ! printf '%s' "$execute_args" | grep -qi "reply-pong-to-test"; then
      echo "FAIL: execute stage did not receive pong task name" >&2
      echo "  execute args: $execute_args" >&2
      exit 1
    fi
    echo "PASS: execute received pong task name"

    # 5. Task marked completed after successful execute
    pong_status="$(yq '[.tasks[] | select(.name == "reply-pong-to-test")] | .[0].status' ${notesDir}/TASKS.yaml)"
    if [[ "$pong_status" != "completed" ]]; then
      echo "FAIL: pong task status is '$pong_status', expected 'completed'" >&2
      cat ${notesDir}/TASKS.yaml >&2
      exit 1
    fi
    echo "PASS: pong task completed"

    echo ""
    echo "All ping-pong pipeline assertions passed."
    touch "$out"
  ''
