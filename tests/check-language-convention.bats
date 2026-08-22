#!/usr/bin/env bats

SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/scripts/check-language-convention.py"

@test "true positive: plain prose CJK outside fence exits 1" {
  run bash -c "printf '+++ b/modules/example.md\n@@ -1,0 +1,1 @@\n+転記した内容の rationale をそのまま英語ドキュメントに追加する。\n' | python3 '$SCRIPT'"
  [ "$status" -eq 1 ]
  [[ "$output" == *"modules/example.md:"* ]]
}

@test "false positive: CJK inside fenced code block exits 0" {
  run bash -c "printf '+++ b/skills/verify/SKILL.md\n@@ -1,0 +1,3 @@\n+\`\`\`\n+転記した内容の rationale をそのまま英語ドキュメントに追加する。\n+\`\`\`\n' | python3 '$SCRIPT'"
  [ "$status" -eq 0 ]
}

@test "false positive: CJK inside inline code span exits 0" {
  run bash -c "printf '+++ b/skills/audit/SKILL.md\n@@ -1,0 +1,1 @@\n+| \`デザイン\` | design domain keyword |\n' | python3 '$SCRIPT'"
  [ "$status" -eq 0 ]
}

@test "false positive: CJK inside double-quoted string literal exits 0" {
  run bash -c "printf '+++ b/skills/verify/SKILL.md\n@@ -1,0 +1,1 @@\n+Print: \"検証が完了しました\"\n' | python3 '$SCRIPT'"
  [ "$status" -eq 0 ]
}

@test "no violations: diff with no CJK exits 0" {
  run bash -c "printf '+++ b/scripts/example.sh\n@@ -1,0 +1,1 @@\n+echo \"hello world\"\n' | python3 '$SCRIPT'"
  [ "$status" -eq 0 ]
}

@test "removed lines (-) are not scanned" {
  run bash -c "printf -- '+++ b/modules/example.md\n@@ -1,1 +0,0 @@\n-転記した内容の rationale をそのまま英語ドキュメントに追加する。\n' | python3 '$SCRIPT'"
  [ "$status" -eq 0 ]
}

@test "false positive: edit inside a pre-existing fenced block (fence markers unchanged) exits 0" {
  run bash -c "printf '+++ b/skills/verify/SKILL.md\n@@ -10,7 +10,7 @@\n \`\`\`\n existing english line\n-old english line\n+新しい日本語の行\n \`\`\`\n other line\n' | python3 '$SCRIPT'"
  [ "$status" -eq 0 ]
}

@test "true positive: CJK after a double-backtick span with an odd embedded backtick is not swallowed" {
  run bash -c "printf '+++ b/modules/example.md\n@@ -1,0 +1,1 @@\n+\`\`he said\` hello\`\`日本語プローズ\`end\`\n' | python3 '$SCRIPT'"
  [ "$status" -eq 1 ]
  [[ "$output" == *"modules/example.md:"* ]]
}

@test "false positive: CJK inside single-quoted string literal exits 0" {
  run bash -c "printf '+++ b/scripts/example.sh\n@@ -1,0 +1,1 @@\n+printf '\''検証が完了しました'\''\n' | python3 '$SCRIPT'"
  [ "$status" -eq 0 ]
}

@test "true positive: apostrophes in English contractions/possessives do not pair up and swallow CJK" {
  run bash -c "printf '+++ b/modules/example.md\n@@ -1,0 +1,1 @@\n+isn'\''t sure 検証 that'\''s fine\n' | python3 '$SCRIPT'"
  [ "$status" -eq 1 ]
  [[ "$output" == *"modules/example.md:"* ]]
}
