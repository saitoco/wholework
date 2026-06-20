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

- saito / MEMBER / first-class / FAIL (iteration 1/3): `code-patch-tier3-recovery` で auto-file した #725 の内容が Issue として成立せず FAIL。クラスタリング・source 引用・verify command なし / https://github.com/saitoco/wholework/issues/702#issuecomment-4759155143
- saito / MEMBER / first-class / FAIL (iteration 2/3): 実装変更なしで再 verify → FAIL 継続。auto-file ロジックの改善が必要 / https://github.com/saitoco/wholework/issues/702#issuecomment-4759163397

## Code Retrospective

### Deviations from Design

- Spec の Step 4 で「`collect-recovery-candidates.sh:*` を `allowed-tools` の `run-code.sh:*` の後に挿入」と指定されていたが、実際には末尾に追加した。Spec の指定は挿入位置の詳細だが、機能的に同等なため逸脱とはしない。
- `docs/tech.md` のラベルグループカウントが既に古かった (12、`stale-verify` が含まれておらず実際は 13)。今回の追加で 14 になるため、Spec 変更範囲外の `docs/tech.md` と `docs/ja/tech.md` も同時に修正した。

### Design Gaps/Ambiguities

- AC1 の verify コマンド `file_contains "skills/verify/SKILL.md" "recoveries-auto-fire"` は、Spec の実装ステップ通りに実装した場合、変数名 `RECOVERIES_AUTO_FIRE_ENABLED`/`RECOVERIES_AUTO_FIRE_THRESHOLD` のみが登場し config キー名 `recoveries-auto-fire` が SKILL.md に現れないため AC が FAIL になる。Step 15 の説明文に config キー名を明示的に追記することで対応した。

### Rework

- 初回コミット後に SKILL.md の AC1 verify command が FAIL することを確認し、Step 15 の説明文に `recoveries-auto-fire` 文字列を追加するための追加コミットが必要になった。

## Code Retrospective (Fix Cycle — verify iteration 2/3)

### Deviations from Design

- N/A

### Design Gaps/Ambiguities

- post-merge AC の意図が「形式上の auto-file」ではなく「実用的な improvement Issue」であることが Spec に明記されていなかった。AC 記述 `improvement Issue が auto-file される` の「実用的」という質的要件は暗黙だった。
- Step 15 の `--body` テンプレートが symptom-short と count のみを含む最小限の形式だったため、3 件の entries が 2 種類の underlying cause (silent no-op / watchdog kill) を持つことを無視した 1 Issue 生成になった。

### Rework

- verify FAIL コメント (iteration 1, 2) を受けて Step 15 の Issue body テンプレートを大幅改修: source entry table・cause clustering・rubric verify command を追加し、ラベル不在時の silent fallback を warning に変更。

## review retrospective

### Spec vs. implementation divergence patterns

Nothing to note. Spec の受け入れ条件 (file_contains / grep ベース) はすべて PASS。コード実装と Spec の整合性は良好。

### Recurring issues

`tests/setup-labels.bats` のテスト名とアサーション値の off-by-one パターンが本 PR 以前から継続していた。今回 SHOULD として指摘し修正済み。ラベル追加の際に「テスト名 = ラベル数 - 1」になるパターンが繰り返しており、Spec のテスト更新ステップに「テスト名とアサーション値を必ず一致させる」旨を明示すると再発防止になる。

### Acceptance criteria verification difficulty

全 pre-merge AC が `file_contains` / `grep` ベースで CI 自動確認可能。UNCERTAIN なし。verify command の品質は高い。post-merge AC が observation event=verify-completion のため手動観察が必要。これは機能の性質上やむを得ない。

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- verify FAIL (iteration 1 & 2) のコメントを受けて Step 15 の Issue body テンプレートを改修: source entry table・cause clustering (exit code/diagnosis ベース)・rubric verify command を追加
- ラベル不在時の silent fallback を廃止し warning + no-fallback に変更
- `--patch` ルートで直接 main にコミット (BASE_BRANCH=main, `closes #702` 付き)

### Deferred Items
- `tests/setup-labels.bats` のカウントアサーション不一致 (pre-existing from #706) は未修正のまま — 本 Issue 範囲外
- Step 15 の body template で symptom-short に対応するエントリを自動抽出・クラスタリングする実際の動作は次回 verify で観察が必要

### Notes for Next Phase
- post-merge AC6 は observation event=verify-completion: `.wholework.yml: recoveries-auto-fire.enabled: true` + 同 symptom 3 件蓄積の状態で `/verify` を完走させると Step 15 が走る
- 新テンプレートで生成される Issue body が「実用的な improvement Issue」の質的要件を満たすかは次の観察で確認
- pre-merge AC5 件は変更前後ともに PASS (file_contains/grep ベース)

## Verify Retrospective

### Phase-by-Phase Review

#### issue
- Issue body は L2→L1 経路位置付け (#704 マトリクス) を明記しており、autonomy tier との接続が明確。AC 設計も file_contains/grep の機械検証可能形式で UNCERTAIN=0。

#### spec
- spec phase で Size を S → M にアップグレードした (`Post-spec route demotion/upgrade: S → M`)。spec 段階で必要なファイル数 (5 ファイル: SKILL.md / emit-event.sh / detect-config-markers.md / setup-labels.sh / customization.md 英日) を見積もり直し、S 想定を超えた判断は妥当。
- Spec で `recoveries-auto-fire` config キー名と内部変数名 `RECOVERIES_AUTO_FIRE_*` の対応関係を明記していなかったため、AC1 verify command (config キー名 grep) が初回実装で FAIL する原因になった。Spec の設計-検証 alignment の改善余地。

#### code
- silent no-op anomaly が code-pr で発生 → Tier 2 recovery (run-code 再実行) で復旧 → PR #718 作成成功。auto-retry が機能した。
- AC1 が初回 FAIL したため Step 15 の説明文に `recoveries-auto-fire` 文字列を追加する rework 1 回発生。

#### review
- review-light で適切に MUST/SHOULD を切り分け、`tests/setup-labels.bats` の off-by-one パターンを SHOULD として指摘 → 修正済み。adversarial review が継続的に効いている。

#### merge
- **Forbidden Expressions check が pre-existing FAILURE (`docs/spec/issue-710-blocked-by-workflow.md`)**。`--non-interactive` モードの auto-resolve policy に従いマージ続行。これは本 Issue 範囲外だが、別 Issue として捕捉が必要な orchestration anomaly。
- CI が `ci_failing` でも merge 続行する `--non-interactive` policy の妥当性: ここでは pre-existing FAILURE だったので結果的に正しいが、real FAILURE と pre-existing FAILURE を区別できない判定ロジックは将来の risk。

#### verify
- Pre-merge 5 件すべて idempotent 再検証で PASS。Post-merge 1 件 (observation event=verify-completion) は本セッションでは条件不成立 (recoveries-auto-fire.enabled 未設定 + symptom 3 回蓄積条件未充足) → PENDING で deferred。判断は SSoT (Issue body と Spec) に忠実。

### Improvement Proposals

**1. Spec の config キー名と内部変数名の対応関係明示 (Tier 2 / 規約)**

config フラグ追加時に Spec で `recoveries-auto-fire` (YAML key) ↔ `RECOVERIES_AUTO_FIRE_ENABLED` (env var) のような対応関係を明示する規約を確立する。今回は AC1 が config キー名を grep する設計だったが、Spec 実装ステップでは内部変数名のみ言及していたため initial code が AC1 を FAIL させた。Tier 2 (Spec template の規約として記録、memory entry 候補)。

**2. Forbidden Expressions check の pre-existing FAILURE 区別 (Tier 1 候補)**

merge phase で Forbidden Expressions check が pre-existing FAILURE のため `--non-interactive` auto-resolve でマージ続行した。pre-existing と real FAILURE を機械的に区別できる仕組みが無いと:
- 真に MUST 修正すべき FAILURE を見逃すリスク
- 別 Issue 起票の責務がオペレータに残る

提案: `pre-merge-check.sh` 等で「main ブランチで同 check が FAIL するか」を比較し、pre-existing は warning、新規発生は abort とする policy。あるいは特定 check (Forbidden Expressions 等) に対して「baseline FAILURE 一覧」を管理する。再発性が高く orchestration の boundary に影響するため Tier 1。

別 Issue で `docs/spec/issue-710-blocked-by-workflow.md` の Forbidden Expressions 問題を解消することも別途必要。

**3. `tests/setup-labels.bats` off-by-one パターンの再発防止 (Tier 3 / 既存対処済)**

review で指摘・修正済み。今後ラベル追加時に「テスト名のラベル数 = 現実の ALWAYS_LABELS 数」を一致させる規約を Spec template に明示すれば再発防止になる。Tier 3 (一回限りの修正、規約化は Tier 2 の #2 と統合可能)。
