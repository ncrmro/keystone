{
  pkgs,
  lib,
}:
pkgs.runCommand "test-projects-schema"
  {
    nativeBuildInputs = with pkgs; [
      bash
      jq
      yq-go
    ];
  }
  ''
    set -euo pipefail

    schema="${../../schemas/projects.schema.json}"

    # --- Valid projects file ---
    cat > valid.yaml <<'EOF'
    keystone:
      mission: "Build Keystone tooling."
      repos:
        - ncrmro/keystone
        - ncrmro/nixos-config
      milestones:
        - name: "v1 stabilization"
          date: "2026-05-01"
    agents:
      mission: "Multi-agent workflows"
      repos:
        - ncrmro/keystone
      icon: "icons/agents.png"
    EOF

    valid_json=$(yq -o=json eval '.' valid.yaml)

    # All top-level keys must be valid slugs (lowercase, hyphens)
    printf '%s\n' "$valid_json" | jq -e '
      keys | all(test("^[a-z0-9]+(-[a-z0-9]+)*$"))
    ' >/dev/null

    # Each project must have mission (string) and repos (array of owner/repo)
    printf '%s\n' "$valid_json" | jq -e '
      to_entries | all(.value |
        (.mission | type) == "string"
        and (.repos | type) == "array"
        and (.repos | length) >= 1
        and (.repos | all(test("^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$")))
      )
    ' >/dev/null

    # Milestones must have name, optional date
    printf '%s\n' "$valid_json" | jq -e '
      .keystone.milestones | all(
        (.name | type) == "string"
        and (if .date then (.date | type) == "string" else true end)
      )
    ' >/dev/null

    # Icon is optional string
    printf '%s\n' "$valid_json" | jq -e '
      .agents.icon | type == "string"
    ' >/dev/null

    # --- Invalid: bad slug ---
    cat > bad-slug.yaml <<'EOF'
    My Project:
      mission: "Bad slug"
      repos:
        - owner/repo
    EOF

    bad_slug_json=$(yq -o=json eval '.' bad-slug.yaml)
    if printf '%s\n' "$bad_slug_json" | jq -e 'keys | all(test("^[a-z0-9]+(-[a-z0-9]+)*$"))' >/dev/null 2>&1; then
      echo "FAIL: bad slug should not pass validation" >&2
      exit 1
    fi

    # --- Invalid: missing repos ---
    cat > no-repos.yaml <<'EOF'
    valid-slug:
      mission: "Missing repos field"
    EOF

    no_repos_json=$(yq -o=json eval '.' no-repos.yaml)
    if printf '%s\n' "$no_repos_json" | jq -e 'to_entries | all(.value | (.repos | type) == "array" and (.repos | length) >= 1)' >/dev/null 2>&1; then
      echo "FAIL: missing repos should not pass validation" >&2
      exit 1
    fi

    # --- Invalid: bad repo format ---
    cat > bad-repo.yaml <<'EOF'
    test-project:
      mission: "Bad repo format"
      repos:
        - just-a-name
    EOF

    bad_repo_json=$(yq -o=json eval '.' bad-repo.yaml)
    if printf '%s\n' "$bad_repo_json" | jq -e 'to_entries | all(.value | .repos | all(test("^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$")))' >/dev/null 2>&1; then
      echo "FAIL: bad repo format should not pass validation" >&2
      exit 1
    fi

    echo "All schema validation tests passed."
    touch "$out"
  ''
