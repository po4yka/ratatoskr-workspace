#!/usr/bin/env bats

setup() {
  workspace_root=$(cd "$BATS_TEST_DIRNAME/../.." && pwd)
  profile="$workspace_root/integration/compose/knowledge-main-stream.yaml"
  runner="$workspace_root/integration/run-knowledge-main-stream.sh"
}

run_composed_profile_when_enabled() {
  if [[ ${RATATOSKR_RUN_KNO018:-0} != 1 ]]; then
    return 0
  fi

  run "$runner"
  [ "$status" -eq 0 ]
  [[ "$output" == *"KNO-018 composed primary and fault profile: PASS"* ]]
}

@test "all_primary_families_recover_and_publish_terminal_state" {
  test -f "$profile"
  test -x "$runner"

  run env \
    RATATOSKR_TASK_NAMESPACE=kno018-static \
    RATATOSKR_KNOWLEDGE_CONTEXT=/tmp/knowledge \
    RATATOSKR_KNOWLEDGE_REVISION=knowledge \
    RATATOSKR_EXTRACTOR_CONTEXT=/tmp/extractor \
    RATATOSKR_EXTRACTOR_REVISION=extractor \
    RATATOSKR_GITHUB_CONTEXT=/tmp/github \
    RATATOSKR_GITHUB_REVISION=github \
    "$runner" --contract
  [ "$status" -eq 0 ]
  [[ "$output" == *"KNO-018 profile contract: PASS"* ]]

  run_composed_profile_when_enabled
}

@test "replay_poison_tombstone_outbox_and_shutdown_faults_are_safe" {
  test -f "$profile"
  test -x "$runner"

  run env \
    RATATOSKR_TASK_NAMESPACE=kno018-static \
    RATATOSKR_KNOWLEDGE_CONTEXT=/tmp/knowledge \
    RATATOSKR_KNOWLEDGE_REVISION=knowledge \
    RATATOSKR_EXTRACTOR_CONTEXT=/tmp/extractor \
    RATATOSKR_EXTRACTOR_REVISION=extractor \
    RATATOSKR_GITHUB_CONTEXT=/tmp/github \
    RATATOSKR_GITHUB_REVISION=github \
    "$runner" --teardown-plan
  [ "$status" -eq 0 ]
  [[ "$output" == *"--project-name ratatoskr-kno018-static"* ]]
  [[ "$output" == *"down --volumes --remove-orphans"* ]]

  run_composed_profile_when_enabled
}
