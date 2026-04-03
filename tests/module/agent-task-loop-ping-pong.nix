{
  pkgs,
  lib,
}:
let
  emailPingFixture = ../fixtures/task-loop/email-ping-source.json;
  calendulaEventsFixture = ../fixtures/task-loop/calendula-events.json;
  emptyProjectIndexFixture = ../fixtures/task-loop/project-index-empty.json;
  defaultsJson = builtins.toJSON {
    profile = "";
    provider = "";
    model = "";
    fallbackModel = "";
    effort = "";
  };
  profilesJson = builtins.toJSON {
    fast = {
      claude = { };
    };
    medium = {
      claude = { };
    };
  };
  projectIndexHelper = pkgs.writeShellScriptBin "keystone-project-index" ''
    cat ${emptyProjectIndexFixture}
  '';
  taskLoopScript = pkgs.replaceVars ../../modules/os/agents/scripts/task-loop.sh {
    notesDir = "/tmp/task-loop-ping-pong-notes";
    maxTasks = "1";
    agentName = "test";
    githubUsername = "";
    forgejoUsername = "";
    defaultsJson = defaultsJson;
    ingestJson = defaultsJson;
    prioritizeJson = defaultsJson;
    executeJson = defaultsJson;
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

    mkdir -p "$HOME" "$TASK_LOOP_TEST_STATE_DIR" "$PWD/stubs" /tmp/task-loop-ping-pong-notes

    printf '%s\n' 'tasks: []' > /tmp/task-loop-ping-pong-notes/TASKS.yaml

    # Stub: systemctl (no-op)
    printf '%s\n' '#!${pkgs.bash}/bin/bash' 'exit 0' > "$PWD/stubs/systemctl"
    chmod +x "$PWD/stubs/systemctl"

    # Stub: git (no-op)
    printf '%s\n' '#!${pkgs.bash}/bin/bash' 'exit 0' > "$PWD/stubs/git"
    chmod +x "$PWD/stubs/git"

    # Stub: hostname
    printf '%s\n' '#!${pkgs.bash}/bin/bash' "printf '%s\\n' \"test-host\"" > "$PWD/stubs/hostname"
    chmod +x "$PWD/stubs/hostname"

    # Stub: himalaya - returns ping email fixture
    printf '%s\n' '#!${pkgs.bash}/bin/bash' "cat ${emailPingFixture}" > "$PWD/stubs/himalaya"
    chmod +x "$PWD/stubs/himalaya"

    # Stub: calendula - returns events fixture
    printf '%s\n' '#!${pkgs.bash}/bin/bash' "cat ${calendulaEventsFixture}" > "$PWD/stubs/calendula"
    chmod +x "$PWD/stubs/calendula"

    # Stub: claude - handles ingest, prioritize, and execute stages
    cat > "$PWD/stubs/claude" <<'STUBEOF'
    #!${pkgs.bash}/bin/bash
    set -euo pipefail

    args="$*"
    state_dir="''${TASK_LOOP_TEST_STATE_DIR:?}"

    if printf '%s' "$args" | grep -q "task_loop ingest"; then
      # Ingest stage: create a pong reply task from the ping email
      printf '%s\n' "1" > "$state_dir/ingest-count"
      cat > TASKS.yaml <<'YAML'
    tasks:
      - name: reply-pong-to-test
        description: "Reply with pong to the ping email from test@ncrmro.com"
        status: pending
        source: email
        source_ref: "email-1-test@ncrmro.com"
    YAML

    elif printf '%s' "$args" | grep -q "task_loop prioritize"; then
      # Prioritize stage: assign model haiku to the pong task
      printf '%s\n' "1" > "$state_dir/prioritize-count"
      yq -i '(.tasks[] | select(.name == "reply-pong-to-test")).model = "haiku"' TASKS.yaml

    else
      # Execute stage: record the task name and exit 0
      # (task-loop.sh marks the task completed on exit 0)
      printf '%s\n' "1" > "$state_dir/execute-count"
      printf '%s\n' "$args" > "$state_dir/execute-args"
    fi

    printf '%s\n' '{"total_tokens":1}'
    STUBEOF
    chmod +x "$PWD/stubs/claude"

    # Run the task loop once
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
      exit 1
    fi
    echo "PASS: execute stage invoked"

    # 4. Execute received the pong task name
    execute_args="$(cat "$TASK_LOOP_TEST_STATE_DIR/execute-args")"
    if ! printf '%s' "$execute_args" | grep -qi "reply-pong-to-test"; then
      echo "FAIL: execute stage did not receive pong task name" >&2
      echo "  execute args: $execute_args" >&2
      exit 1
    fi
    echo "PASS: execute received pong task name"

    # 5. TASKS.yaml has the pong task (status should be completed after execute exit 0)
    pong_status="$(yq '[.tasks[] | select(.name == "reply-pong-to-test")] | .[0].status' /tmp/task-loop-ping-pong-notes/TASKS.yaml)"
    if [[ "$pong_status" != "completed" ]]; then
      echo "FAIL: pong task status is '$pong_status', expected 'completed'" >&2
      echo "  TASKS.yaml contents:" >&2
      cat /tmp/task-loop-ping-pong-notes/TASKS.yaml >&2
      exit 1
    fi
    echo "PASS: pong task completed"

    # 6. Pong task has model haiku assigned
    pong_model="$(yq '[.tasks[] | select(.name == "reply-pong-to-test")] | .[0].model' /tmp/task-loop-ping-pong-notes/TASKS.yaml)"
    if [[ "$pong_model" != "haiku" ]]; then
      echo "FAIL: pong task model is '$pong_model', expected 'haiku'" >&2
      exit 1
    fi
    echo "PASS: pong task model is haiku"

    echo ""
    echo "All ping-pong pipeline assertions passed."
    touch "$out"
  ''
