# AI artifacts evaluation test
#
# Validates the archetype-aware AI artifact system:
#   1. Artifact tree structure is correct per archetype (REQ-4 through REQ-8)
#   2. Each archetype has per-tool instruction files (REQ-6)
#   3. Skills are archetype-scoped (REQ-10)
#   4. Role agent profiles exist for declared roles (REQ-11)
#
# Build: nix build .#checks.x86_64-linux.ai-artifacts-evaluation
#
{
  pkgs,
  lib,
  self,
}:
let
  artifactsDir = "${self}/ai-artifacts";
  archetypesYaml = "${self}/conventions/archetypes.yaml";
in
pkgs.runCommand "test-ai-artifacts-evaluation"
  {
    nativeBuildInputs = [
      pkgs.yq-go
      pkgs.coreutils
    ];
  }
  ''
    echo "AI artifact evaluation tests"
    echo "============================="
    echo ""

    ARCHETYPES_FILE="${archetypesYaml}"
    ARTIFACTS="${artifactsDir}"

    # Test 1: Every archetype has all four tool instruction files
    echo "Test 1: Every archetype has all tool instruction files..."
    for arch in $(yq -r '.archetypes | keys | .[]' "$ARCHETYPES_FILE"); do
      for check in "claude/CLAUDE.md" "gemini/GEMINI.md" "codex/AGENTS.md" "opencode/AGENTS.md"; do
        if [ ! -f "$ARTIFACTS/archetypes/$arch/$check" ]; then
          echo "  FAIL: missing $ARTIFACTS/archetypes/$arch/$check"
          exit 1
        fi
      done
    done
    echo "  PASS"

    # Test 2: Each archetype has a deepwork skill (always included)
    echo "Test 2: Each archetype has deepwork skill..."
    for arch in $(yq -r '.archetypes | keys | .[]' "$ARCHETYPES_FILE"); do
      if [ ! -f "$ARTIFACTS/archetypes/$arch/skills/deepwork/SKILL.md" ]; then
        echo "  FAIL: missing deepwork skill for $arch"
        exit 1
      fi
    done
    echo "  PASS"

    # Test 3: Archetype-specific skills are present
    echo "Test 3: Archetype-specific skills exist..."
    # Engineer should have sweng-implement, product should not
    if [ ! -f "$ARTIFACTS/archetypes/engineer/skills/sweng-implement/SKILL.md" ]; then
      echo "  FAIL: engineer missing sweng-implement"
      exit 1
    fi
    if [ -f "$ARTIFACTS/archetypes/product/skills/sweng-implement/SKILL.md" ]; then
      echo "  FAIL: product should NOT have sweng-implement"
      exit 1
    fi
    # Product should have portfolio-review, engineer should not
    if [ ! -f "$ARTIFACTS/archetypes/product/skills/portfolio-review/SKILL.md" ]; then
      echo "  FAIL: product missing portfolio-review"
      exit 1
    fi
    if [ -f "$ARTIFACTS/archetypes/engineer/skills/portfolio-review/SKILL.md" ]; then
      echo "  FAIL: engineer should NOT have portfolio-review"
      exit 1
    fi
    echo "  PASS"

    # Test 4: Codex skills have agents/openai.yaml variants
    echo "Test 4: Codex skills have agents/openai.yaml..."
    for arch in $(yq -r '.archetypes | keys | .[]' "$ARCHETYPES_FILE"); do
      skill_count=$(yq ".archetypes.$arch.skills | length" "$ARCHETYPES_FILE" 2>/dev/null || echo "0")
      for ((s = 0; s < skill_count; s++)); do
        cmd_name=$(yq -r ".archetypes.$arch.skills[$s]" "$ARCHETYPES_FILE")
        skill_dir=$(echo "$cmd_name" | tr '.' '-')
        if [ ! -f "$ARTIFACTS/archetypes/$arch/skills/$skill_dir/codex/agents/openai.yaml" ]; then
          echo "  FAIL: missing codex agent yaml for $arch/$skill_dir"
          exit 1
        fi
      done
    done
    echo "  PASS"

    # Test 5: Role agent profiles exist for declared roles
    echo "Test 5: Role agent profiles exist..."
    for arch in $(yq -r '.archetypes | keys | .[]' "$ARCHETYPES_FILE"); do
      role_names=$(yq -r ".archetypes.$arch.roles // {} | keys | .[]" "$ARCHETYPES_FILE" 2>/dev/null || true)
      for role in $role_names; do
        for tool in claude gemini codex opencode; do
          if [ ! -f "$ARTIFACTS/roles/$role/$tool/agent.md" ]; then
            echo "  FAIL: missing role profile $role/$tool/agent.md"
            exit 1
          fi
        done
      done
    done
    echo "  PASS"

    # Test 6: Instruction file content varies by archetype
    echo "Test 6: Instruction files differ across archetypes..."
    engineer_md=$(cat "$ARTIFACTS/archetypes/engineer/claude/CLAUDE.md")
    product_md=$(cat "$ARTIFACTS/archetypes/product/claude/CLAUDE.md")
    if [ "$engineer_md" = "$product_md" ]; then
      echo "  FAIL: engineer and product CLAUDE.md are identical"
      exit 1
    fi
    echo "  PASS"

    # Test 7: keystone-system-host has fewer skills than engineer
    echo "Test 7: Archetype skill scoping is correct..."
    host_skills=$(find "$ARTIFACTS/archetypes/keystone-system-host/skills" -name "SKILL.md" -not -path "*/codex/*" | wc -l)
    eng_skills=$(find "$ARTIFACTS/archetypes/engineer/skills" -name "SKILL.md" -not -path "*/codex/*" | wc -l)
    if [ "$host_skills" -lt "$eng_skills" ]; then
      echo "  PASS: host=$host_skills skills < engineer=$eng_skills skills"
    else
      echo "  FAIL: host=$host_skills should be less than engineer=$eng_skills"
      exit 1
    fi

    echo ""
    echo "All AI artifact evaluation tests passed!"
    touch $out
  ''
