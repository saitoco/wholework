# Issue #702: verify: retrospective tail で /audit recoveries 閾値超え検出時に improvement Issue を auto-file

## Overview

`/verify` 完了時の retrospective tail (retro-proposals 呼び出し前) に、orchestration-recoveries.md の閾値超え symptom を inline 検出し、既起票 Issue がなければ `gh issue create` で improvement Issue を auto-file する機能を追加する。

- **ゲート条件**: `.wholework.yml: recoveries-auto-fire.enabled: true` かつ `AUTONOMY_TIER=L2 or L3`
- **L1 tier 時**: advisory print のみ (path A)
- **副作用**: `recoveries_threshold_fire` イベントを `auto-events.jsonl` に emit
- **既存資産**: `scripts/collect-recovery-candidates.sh` をそのまま呼び出す
- **`/audit recoveries` 手動 path**: 残す (大量バックログ初回処理 / 閾値変更時 rescan 用)

## Changed Files

- `modules/detect-config-markers.md`: add `recoveries-auto-fire.enabled` → `RECOVERIES_AUTO_FIRE_ENABLED` (bool, default `false`) and `recoveries-auto-fire.threshold` → `RECOVERIES_AUTO_FIRE_THRESHOLD` (integer, default `3`) to marker definition table — bash 3.2+ compatible
- `scripts/emit-event.sh`: append `recoveries_threshold_fire` event schema comment (fields: `symptom`, `count`, `issue_number`)
- `scripts/setup-labels.sh`: add `"retro/recoveries|5319E7|Recovery candidate auto-filed"` to ALWAYS_LABELS after `retro/code`; update comment count 13→14 — bash 3.2+ compatible
- `tests/setup-labels.bats`: add `label_created "retro/recoveries"` alongside existing retro assertions; update `count_label_creates` assertion from `eq 30` to `eq 31`
- `skills/verify/SKILL.md`: (a) add `${CLAUDE_PLUGIN_ROOT}/scripts/collect-recovery-candidates.sh:*` to `allowed-tools`; (b) add `RECOVERIES_AUTO_FIRE_ENABLED` and `RECOVERIES_AUTO_FIRE_THRESHOLD` to Step 4 config detection; (c) insert new Step 15 "Recovery Candidates Tail Check" (shifting old Step 15 → Step 16)
- `docs/guide/customization.md`: add `recoveries-auto-fire.enabled` and `recoveries-auto-fire.threshold` rows to Available Keys table; add commented sample YAML block
- `docs/ja/guide/customization.md`: mirror `docs/guide/customization.md` changes in Japanese

## Implementation Steps

1. **`modules/detect-config-markers.md`**: add two rows to the Marker Definition Table, immediately after the `auto-retry-on-fail.*` rows:
   ```
   | `recoveries-auto-fire.enabled` | `RECOVERIES_AUTO_FIRE_ENABLED` | `true` | `false` |
   | `recoveries-auto-fire.threshold` | `RECOVERIES_AUTO_FIRE_THRESHOLD` | Integer string (extract as-is; use `3` if ≤0 or non-numeric) | `3` |
   ```
   Follow the nested-key parsing rule analogous to `auto-retry-on-fail.*` (both block and flat key format supported). Add corresponding Output Format entries. (→ AC3)

2. **`scripts/emit-event.sh`**: append a `recoveries_threshold_fire` block to the "Documented event schemas" comment section:
   ```
   # recoveries_threshold_fire: verify tail detected threshold-exceeding symptom and auto-filed Issue
   #   symptom=<symptom-short>       symptom identifier from orchestration-recoveries.md
   #   count=<n>                     occurrence count that exceeded threshold
   #   issue_number=<NNN>            GitHub Issue number created (0 if L1 advisory only)
   ```
   (→ AC2)

3. **`scripts/setup-labels.sh` + `tests/setup-labels.bats`** (label addition — bash 3.2+ compatible):
   - `setup-labels.sh`: insert `"retro/recoveries|5319E7|Recovery candidate auto-filed"` after `"retro/code|..."` in ALWAYS_LABELS; update the count comment on line 13 from `13 labels` to `14 labels` (add `retro/recoveries` to the label name list)
   - `tests/setup-labels.bats`: add `label_created "retro/recoveries"` in the "env=full: always-group non-phase labels present" test after `label_created "retro/code"`; update `[ "$(count_label_creates)" -eq 30 ]` to `-eq 31`

4. **`skills/verify/SKILL.md`** (→ AC1):
   - `allowed-tools` frontmatter: insert `${CLAUDE_PLUGIN_ROOT}/scripts/collect-recovery-candidates.sh:*` after `${CLAUDE_PLUGIN_ROOT}/scripts/run-code.sh:*`
   - Step 4 (detect-config-markers detection block): add `RECOVERIES_AUTO_FIRE_ENABLED` and `RECOVERIES_AUTO_FIRE_THRESHOLD` to the config variable list read from `.wholework.yml`
   - Insert new **Step 15: Recovery Candidates Tail Check** immediately before current Step 15 (retro-proposals); rename current Step 15 → Step 16. New step content:
     - Guard: `if [ ! -f "docs/reports/orchestration-recoveries.md" ]; then skip`
     - Write open-issues JSON to `.tmp/open-issues-$NUMBER.json` for dedup: `gh issue list --state open --limit 200 --json number,title`
     - Run: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/collect-recovery-candidates.sh docs/reports/orchestration-recoveries.md --threshold "$RECOVERIES_AUTO_FIRE_THRESHOLD" --issues-json .tmp/open-issues-$NUMBER.json`
     - If output is empty: skip. For each `symptom-short<TAB>count` line:
       - `AUTONOMY_TIER=L1` OR `RECOVERIES_AUTO_FIRE_ENABLED=false`: print `Recommend: gh issue create --label "retro/recoveries" --title "recoveries: {symptom-short}" (count: {count})`
       - `AUTONOMY_TIER=L2 or L3` AND `RECOVERIES_AUTO_FIRE_ENABLED=true`: `gh issue create --label "retro/recoveries" --title "recoveries: {symptom-short}" --body "..."` → then source `emit-event.sh` and call `EMIT_ISSUE_NUMBER=$NUMBER emit_event "recoveries_threshold_fire" "symptom={symptom-short}" "count={count}" "issue_number={new_issue_number}"`
     - Cleanup: remove `.tmp/open-issues-$NUMBER.json`

5. **`docs/guide/customization.md` + `docs/ja/guide/customization.md`** (config SSoT):
   - `docs/guide/customization.md`:
     - Available Keys table: add two rows after `auto-retry-on-fail.budget_tokens` row:
       ```
       | `recoveries-auto-fire.enabled` | boolean | `false` | Auto-file improvement Issues when orchestration-recoveries.md symptom count exceeds threshold (requires `autonomy: L2` or `L3`). When `false` or autonomy is `L1`, prints a recommendation instead. |
       | `recoveries-auto-fire.threshold` | integer | `3` | Symptom occurrence count threshold for auto-filing. Values ≤0 or non-numeric fall back to `3`. |
       ```
     - Sample YAML: add commented block after `auto-retry-on-fail` block
   - `docs/ja/guide/customization.md`: mirror same additions in Japanese

## Verification

### Pre-merge

- <!-- verify: file_contains "skills/verify/SKILL.md" "recoveries-auto-fire" --> `/verify` SKILL.md に retrospective tail での閾値判定ステップが追記されている
- <!-- verify: file_contains "scripts/emit-event.sh" "recoveries_threshold_fire" --> `recoveries_threshold_fire` イベント型が `emit-event.sh` に追加されている
- <!-- verify: grep "recoveries-auto-fire" "modules/detect-config-markers.md" --> `.wholework.yml` フラグが marker テーブルに登録されている
- <!-- verify: grep "retro/recoveries" "scripts/setup-labels.sh" --> `retro/recoveries` ラベルが `setup-labels.sh` の ALWAYS_LABELS に追加されている
- <!-- verify: file_contains "docs/guide/customization.md" "recoveries-auto-fire" --> `docs/guide/customization.md` の Available Keys に `recoveries-auto-fire.*` が記載されている

### Post-merge

- `.wholework.yml: recoveries-auto-fire.enabled: true` の状態で `orchestration-recoveries.md` に同 symptom が 3 回追加された後、`/verify` 完了時に対応する improvement Issue が auto-file されることを観察 <!-- verify-type: observation event=verify-completion -->

## Notes

- **Step 15 挿入位置**: 現 Step 15 (Collect Improvement Proposals) の直前に挿入し、旧 Step 15 を Step 16 に繰り下げる。新 Step 15 は worktree exit (Step 13) 後の main context で実行されるため、`gh issue create` の L0 write は問題なし
- **autonomy tier チェック**: `AUTONOMY_TIER` は detect-config-markers.md 経由で Step 4 で既取得済み。新 Step 15 では再取得不要
- **`recoveries_threshold_fire` の `issue_number` フィールド**: L1 advisory の場合は `0` を emit (Issue 未作成を示す)
- **`/audit recoveries` 手動 path**: `skills/audit/SKILL.md` の `recoveries` サブコマンドは変更しない。本 Issue は inline 副作用の追加のみ
- **Issue body format**: `gh issue create` の `--body` は背景+目的+AC の標準形式。symptom-short をタイトルに使い `retro/recoveries` ラベルで filed。`triaged` ラベルは付与しない (triage skill が付ける)
- **Blocked-by #704 (E7 autonomy tier)**: `.wholework.yml: autonomy:` が未設定の場合は L1 (safest) にフォールバックするため、auto-file は行われない。`recoveries-auto-fire.enabled: true` を設定しても `autonomy: L2` 以上が必要

## Consumed Comments

No new comments since last phase.

## Code Retrospective

### Deviations from Design

- Spec の Step 4 で「`collect-recovery-candidates.sh:*` を `allowed-tools` の `run-code.sh:*` の後に挿入」と指定されていたが、実際には末尾に追加した。Spec の指定は挿入位置の詳細だが、機能的に同等なため逸脱とはしない。
- `docs/tech.md` のラベルグループカウントが既に古かった (12、`stale-verify` が含まれておらず実際は 13)。今回の追加で 14 になるため、Spec 変更範囲外の `docs/tech.md` と `docs/ja/tech.md` も同時に修正した。

### Design Gaps/Ambiguities

- AC1 の verify コマンド `file_contains "skills/verify/SKILL.md" "recoveries-auto-fire"` は、Spec の実装ステップ通りに実装した場合、変数名 `RECOVERIES_AUTO_FIRE_ENABLED`/`RECOVERIES_AUTO_FIRE_THRESHOLD` のみが登場し config キー名 `recoveries-auto-fire` が SKILL.md に現れないため AC が FAIL になる。Step 15 の説明文に config キー名を明示的に追記することで対応した。

### Rework

- 初回コミット後に SKILL.md の AC1 verify command が FAIL することを確認し、Step 15 の説明文に `recoveries-auto-fire` 文字列を追加するための追加コミットが必要になった。

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- `recoveries-auto-fire` config キーは `auto-retry-on-fail.*` と同じ nested-key パターンで detect-config-markers.md に追加した
- `retro/recoveries` ラベルのカラーは既存の `retro/*` ラベル (5319E7) と統一
- Step 15 は旧 Step 15 (Collect Improvement Proposals) の直前に挿入し、旧 Step 15 は Step 16 にリナンバーした

### Deferred Items
- `docs/tech.md` のラベルグループカウントが 12 (古い) → 14 に更新した。この差異は `stale-verify` ラベルが追加された際の更新漏れ (別 Issue で起票してもよい)
- `recoveries_threshold_fire` event の `issue_number=0` (L1 advisory path) の意味の明確化は今後の課題

### Notes for Next Phase
- verify コマンドは全て pre-merge で `file_contains`/`grep` ベースなので CI で自動確認可能
- post-merge AC は observation event=verify-completion なので手動観察が必要
- `docs/tech.md` の Always ラベルカウントが 12→14 に変わったことで、tech.md の記述と setup-labels.sh の実態が一致するようになった
