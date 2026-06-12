# Issue #556: Fable 5 long-turn 対応: watchdog タイムアウト/進捗 echo の spike と再調整

## Overview

`scripts/watchdog-defaults.sh` は `WATCHDOG_TIMEOUT_DEFAULT=1800`（stdout 30 分無出力 → kill）を設定している。Claude Fable 5 は単発リクエストが数分に及ぶ long-turn を生じさせるため、現行の 1800 秒デフォルトで誤 kill が増加するリスクがある。一方で Fable 5 はデフォルトでナレーションが増えるため、そのテキストが `claude -p` の stdout に届けば watchdog をリセットする可能性もある。

本 Issue は Fable 5 下での watchdog 挙動を spike で計測し、誤 kill を防ぐようデフォルト値と進捗 echo を再調整することを目的とする。調整はすべて計測結果に基づいて判断する。

## Changed Files

- `docs/reports/watchdog-recovery-strategy.md`: Fable 5 long-turn の spike 結果・所見を新セクションとして追記（`Fable 5` キーワード・最大 silent window 数値・ナレーション stdout 到達可否・調整方針の根拠）— bash 3.2+ compatible（シェルスクリプト変更なし）
- `scripts/watchdog-defaults.sh`: `WATCHDOG_TIMEOUT_DEFAULT` を spike 結果に基づき引き上げ（条件付き：max silent window > 1800s またはナレーション未到達の場合）— bash 3.2+ compatible
- `tests/watchdog-defaults.bats`: `@test "sourcing sets WATCHDOG_TIMEOUT_DEFAULT=1800"` のテスト名と assertion を新しい値に更新（条件付き：直上と連動）
- `skills/spec/SKILL.md`: Step 10 Spec 作成前に `echo "progress: ..."` を追加（条件付き：spike が long-silent window を検出した場合）
- `skills/review/SKILL.md`: review 統合前（Spec compliance + bug review の結果統合前）に `echo "progress: ..."` を追加（条件付き：spike が long-silent window を検出した場合）

## Implementation Steps

1. **Spike 計測**（→ AC1, AC3）: `run-spec.sh --model claude-fable-5` または `run-code.sh --model claude-fable-5` で実タスクを 1〜2 回実行し、watchdog の heartbeat ログ（stderr: `"watchdog: still waiting, silent for Ns"`）から最大 silent window を記録；ナレーション（中間テキスト）が stdout に届き watchdog をリセットしているか確認する
2. **結果をレポートに追記**（→ AC1, AC3、after 1）: `docs/reports/watchdog-recovery-strategy.md` に `## Fable 5 long-turn findings` セクションを追加し、`Fable 5` キーワード・最大 silent window の計測値・ナレーション stdout 到達可否・`WATCHDOG_TIMEOUT_DEFAULT` 調整方針の根拠を記録（`silent window` という語を含めること）
3. **デフォルト値の調整**（→ AC2、after 1、条件付き）: max silent window > 1800s またはナレーションが stdout に届かない場合、`WATCHDOG_TIMEOUT_DEFAULT=1800` を `WATCHDOG_TIMEOUT_DEFAULT=2700` 等に引き上げ；据え置きの場合はレポートに根拠を記録のみ。値を変更する場合は `tests/watchdog-defaults.bats` の `@test "sourcing sets WATCHDOG_TIMEOUT_DEFAULT=1800"` テスト名と `[ "$output" = "1800" ]` assertion も同値に更新する
4. **progress echo 拡張**（after 1、条件付き）: spike が long-silent window（例: 600 秒超）を示す場合、`skills/spec/SKILL.md` の Step 10 Spec 作成直前と `skills/review/SKILL.md` の review 統合直前に `echo "progress: ..."` を追加
5. **テスト確認**（→ AC4、after 3）: `bats tests/watchdog-defaults.bats` を実行し全テスト green を確認

## Verification

### Pre-merge
- <!-- verify: rubric "Fable 5 spike results (max silent window duration and whether narration reaches stdout) are documented in docs/reports/watchdog-recovery-strategy.md" --> <!-- verify: grep "silent.window" "docs/reports/watchdog-recovery-strategy.md" --> spike の計測結果（Fable 5 下の最大 silent window、ナレーション stdout 到達可否）が `docs/reports/watchdog-recovery-strategy.md` に記録されている
- <!-- verify: grep "WATCHDOG_TIMEOUT_DEFAULT" "scripts/watchdog-defaults.sh" --> <!-- verify: rubric "WATCHDOG_TIMEOUT_DEFAULT in scripts/watchdog-defaults.sh was adjusted based on Fable 5 spike findings, or the value is kept unchanged with a rationale documented in docs/reports/watchdog-recovery-strategy.md" --> `watchdog-defaults.sh` のデフォルト値が計測結果に基づき調整されている（据え置きの場合はその根拠が記録されている）
- <!-- verify: file_contains "docs/reports/watchdog-recovery-strategy.md" "Fable 5" --> watchdog recovery レポートに Fable 5 long-turn の所見が追記されている
- <!-- verify: command "bats tests/watchdog-defaults.bats" --> `.wholework.yml` の `watchdog-timeout-seconds` 上書きが引き続き有効（既存テストが green）

### Post-merge
- Fable 5 を用いた `/auto` 実行で、commits 完了済みなのに watchdog kill → 手動復旧が必要となる事象が再発しないこと（観測）

## Notes

- Step 3・4 は spike 結果によって実施・スキップが分岐する条件付き変更。`WATCHDOG_TIMEOUT_DEFAULT` を変更する場合は必ず `tests/watchdog-defaults.bats` の該当テスト名と assertion を同値に更新すること（未更新だと AC4 が fail する）。
- Spike 計測の代替手法: `WATCHDOG_TIMEOUT=300 bash scripts/claude-watchdog.sh claude -p --model claude-fable-5 "..."` のように小さい WATCHDOG_TIMEOUT で短縮計測も可能。heartbeat ログが最大 silent window の証拠となる。
- `docs/reports/claude-fable-5-impact-strategy.md` の TODO チェックボックス（"Spike `claude-watchdog.sh` stdout cadence under Fable 5..."）は spike 完了後に任意でチェック可能だが、本 Spec の acceptance criteria には含めない（`docs/reports/` は verify 対象外）。
- `grep "silent.window"` は `.` が正規表現ワイルドカードとして動作し "silent window"（スペース）にマッチする。実装で `silent window` という表現を使えば AC1 の grep hint が PASS する。
