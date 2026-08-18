# Issue #1369: auto: run-spec.sh に silent no-op 検知後の auto-retry-on-fail を実装 (spec phase, #1329 follow-up)

## Overview

Issue #1329 で低リスクと評価された、spec phase への `auto-retry-on-fail` 拡張を実装する。`scripts/run-code.sh` (#1320) の実装 (tier ゲート付き exec self-restart、record-before-exec の recovery 記録、stash preflight、bats カバレッジ) を `scripts/run-spec.sh` に移植する。`run-spec.sh` は既に `reconcile-phase-state.sh spec --check-completion` による silent no-op 検知と `EXIT_CODE=1` 設定を持つが (現物確認済み: `scripts/run-spec.sh` 202-212行目)、retry-vs-fail の分岐自体が存在しない。

## Changed Files

- `scripts/run-spec.sh`: `_TRAILING_ARGS` 保持、`AUTONOMY_TIER`/`AUTO_RETRY_ENABLED`/`AUTO_RETRY_MAX_ITERATIONS`/`SPEC_RETRY_COUNT` 変数ブロック、`_push_with_retry`/`_write_spec_retry_recovery` ヘルパー関数、および retry-vs-fail 分岐の追加 (bash 3.2+ compatible)
- `modules/orchestration-fallbacks.md`: `## auto-retry-on-fail (code_retry_fire)` セクションを spec phase 対応に更新 (Applicable Phases / Phase Scope Decision / Symptom / Fallback Steps / Rationale)
- `tests/run-spec.bats`: auto-retry-on-fail の新規カバレッジ (5 ケース) を追加
- `docs/tech.md`: [Steering Docs sync candidate] 132行目付近の「code-side auto-retry (silent no-op)」記述が `run-code.sh` 限定の記述になっている。spec phase 対応の追記は `/code` の裁量とする (Pre-merge AC 対象外)

## Implementation Steps

1. `scripts/run-spec.sh` に auto-retry-on-fail のコア機構を移植する (→ 受入基準 1, 2)
   - `ISSUE_NUMBER=...` 代入直後の `shift` の直後、`# Parse options` コメントの手前に `_TRAILING_ARGS=("$@")` を追加する (exec 再起動時に元の引数を渡すため)
   - `PERMISSION_MODE`/`PERMISSION_FLAG` の if/else ブロック直後、`echo "=== run-spec.sh: Starting..."` の手前に、`run-code.sh` と同型の変数ブロックを追加する: `AUTONOMY_TIER` は `"$SCRIPT_DIR/get-config-value.sh" autonomy L1` で取得。`AUTO_RETRY_ENABLED`/`AUTO_RETRY_MAX_ITERATIONS` は `.wholework.yml` の `auto-retry-on-fail:` ブロックを awk で解析 (`run-code.sh` と同一パターンを踏襲し、`max_iterations:` と legacy キー `threshold:` の両方を許容する — 本リポジトリの `.wholework.yml` 自体が `threshold: 3` を使用しているため、この許容を落とすと動作が `run-code.sh` と乖離する)。`SPEC_RETRY_COUNT=${SPEC_RETRY_COUNT:-0}; export SPEC_RETRY_COUNT` も同ブロックに追加する
   - 同じ位置に、ヘルパー関数を2つ追加する: `_push_with_retry()` は `run-code.sh` の実装をそのまま移植 (fetch+rebase retry の汎用ロジック、phase 非依存)。`_write_spec_retry_recovery(issue, iteration)` は `_write_code_retry_recovery` を踏襲し、`docs/reports/orchestration-recoveries.md` に見出し `## {date}: spec-retry-fire` のエントリを追記する (Context 行は `Issue #{issue}, phase: spec` / `Source: run-spec.sh auto-retry-on-fail` / `Wrapper: run-spec.sh, iteration: {iteration}/{AUTO_RETRY_MAX_ITERATIONS}`、Recovery Applied 行は `modules/orchestration-fallbacks.md#auto-retry-on-fail-code_retry_fire` を参照 — 同一パターンの拡張として同じ anchor を指す、詳細は Notes 参照)。ファイル不在時は無処理で 0 を返す (既存の `_write_code_retry_recovery` と同じ skip-if-absent 規約)。関数呼び出し直前に `# See modules/orchestration-fallbacks.md#auto-retry-on-fail-code_retry_fire` のポインタコメントを置く
   - 既存の post-claude completion-check ブロック内、`elif echo "$_reconcile_out" | grep -q '"matches_expected":false'; then` の分岐 (現状は警告ログと `EXIT_CODE=1` の設定のみ) を拡張する: 既存の警告ログ出力は維持したうえで、`AUTONOMY_TIER` が `L2`/`L3` かつ `AUTO_RETRY_ENABLED == true` かつ `SPEC_RETRY_COUNT < AUTO_RETRY_MAX_ITERATIONS` の場合 — `SPEC_RETRY_COUNT` をインクリメント・export、`auto-retry: spec phase silent no-op, retry N/M` をログ出力、`AUTO_EVENTS_LOG` が設定されていれば `spec_retry_fire` イベント (`iteration=`, `trigger_reason=silent_no_op`) を emit、stash preflight (`git ls-files --others --exclude-standard -- ':!docs/sessions/**'` で検出した stray untracked file を `git stash push --include-untracked` — `run-code.sh` と同一パターン)、`_write_spec_retry_recovery "$ISSUE_NUMBER" "$SPEC_RETRY_COUNT"` を呼び出し、`exec bash "$0" "$ISSUE_NUMBER" "${_TRAILING_ARGS[@]}"` で自己再起動する。条件を満たさない場合は、tier/flag が条件を満たすが count が上限に達している場合のみ `auto-retry: max iterations reached (...). Manual intervention required.` を追加ログ出力し、いずれの非リトライ経路でも `EXIT_CODE=1` を設定する

2. `modules/orchestration-fallbacks.md` の `## auto-retry-on-fail (code_retry_fire)` セクションを spec phase 対応に更新する (after 1) (→ 受入基準 3)
   - 既存セクションを in-place で拡張する形をとる (新規 H2 サブセクションは追加しない — 理由は Notes 参照)
   - **Symptom**: `run-code.sh` の既存箇条書きに並べて、`run-spec.sh` が同様に `exec bash "$0" "$ISSUE_NUMBER" "${_TRAILING_ARGS[@]}"` で自己再起動する旨の箇条書きを追加する
   - **Applicable Phases**: 「code phase only (patch and pr routes alike)」を「code phase (patch/pr) and spec phase」相当に書き換え、呼び出し経路非依存の記述は維持する
   - **Phase Scope Decision**: `spec` の箇条書きから「Recommended as a follow-up Issue... not implemented by #1329 itself」を削除し、本 Issue (#1369) で実装済みである旨に更新する (structural shape の説明文自体は現状のまま維持する)
   - **Fallback Steps**: 手順1の記述を `_write_code_retry_recovery`/`_write_spec_retry_recovery` の両方を指す形に一般化する
   - **Rationale**: 末尾の「Issue #1329 is the decision record for scoping this mechanism to the code phase only」を、#1369 で spec phase まで範囲を拡張した旨を反映する形に更新する

3. `tests/run-spec.bats` に新規テストケースを追加する (after 1) (→ 受入基準 4)
   - `tests/run-code.bats` の対応する5ケース (738-1076行目) を `run-spec.sh` 向けに移植する:
     1. `"auto-retry: silent no-op + AUTO_RETRY_ENABLED=true fires retry (SPEC_RETRY_COUNT increments)"`
     2. `"auto-retry: silent no-op + AUTO_RETRY_ENABLED=false does not retry, exits 1"`
     3. `"auto-retry: SPEC_RETRY_COUNT at max does not retry and exits 1 with advisory"`
     4. `"auto-retry: preflight stashes parent-main stray untracked file before retry re-invocation"`
     5. `"auto-retry: spec_retry_fire records recovery entry before exec re-invocation (Issue #1369)"` (record-before-exec の順序を、2回目の `claude` 呼び出し行より `GIT commit`/`GIT push` 行が前にあることで検証する — `run-code.bats` の Issue #1320 相当テストと同じ検証方法)
   - モックパターンは `tests/run-code.bats` を踏襲する: 各テストローカルで `$MOCK_DIR/get-config-value.sh` を上書きし `autonomy` に `L3` を返すようにする (`setup()` 自体は変更しない — 既存39ケースへの影響を避けるため)。`$BATS_TEST_TMPDIR/.wholework.yml` に `auto-retry-on-fail: enabled: true / max_iterations: 3` を書く。`reconcile-phase-state.sh` モックはカウンタファイルで1回目 `matches_expected:false`、2回目以降 `matches_expected:true` を返す (無限リトライ防止)。`run bash "$SCRIPT" 123` で起動する (`run-spec.sh` の引数形は `<issue-number> [--opus] [--fable] [--max]` であり `--patch`/`--pr` は存在しない)

4. `bats tests/run-spec.bats` を実行し、既存39件 + 新規5件を含むスイート全体が pass することを確認する (after 3) (→ 受入基準 5)

## Verification

### Pre-merge

- <!-- verify: rubric "scripts/run-spec.sh が、claude 呼び出し後の reconcile-phase-state.sh spec --check-completion が matches_expected:false (silent no-op) を返した際、AUTONOMY_TIER が L2 または L3 かつ .wholework.yml の auto-retry-on-fail.enabled: true の条件下で、scripts/run-code.sh の exec bash \"$0\" ... と同型の自己再起動 (exec self-restart) によってリトライを発火する実装になっている" --> silent no-op 検知後の自己リトライが `run-code.sh` と同型で実装されている
- <!-- verify: rubric "scripts/run-spec.sh のリトライ発火時、exec による自己再起動の直前で docs/reports/orchestration-recoveries.md へ spec-retry-fire 相当のエントリを記録する処理が実装されている。run-code.sh の _write_code_retry_recovery と同様に record-before-exec の順序 (exec 後の再起動プロセスは1回目の失敗を観測できないため、記録は exec の前でなければならない) が守られている" --> リトライ前の recovery 記録が record-before-exec の順序で実装されている
- <!-- verify: rubric "modules/orchestration-fallbacks.md の auto-retry-on-fail (code_retry_fire) パターン節が、spec phase でも本パターンが適用されることを反映して更新されている (Applicable Phases への追記、または新規サブセクションの追加のいずれか)。Phase Scope Decision 内の spec に関する記述 (#1329 時点で未実装だった旨) も現状に合わせて更新されている" --> `orchestration-fallbacks.md` が spec phase 対応を反映して更新されている
- <!-- verify: rubric "tests/run-spec.bats に、silent no-op 検知後の auto-retry-on-fail (retry 発火、AUTO_RETRY_ENABLED=false での非発火、max iteration 到達時の非発火、リトライ前の stash preflight、リトライ前の recovery 記録) を検証する新規テストケースが、tests/run-code.bats の対応するテスト群と同水準のカバレッジで追加されている" --> `tests/run-spec.bats` に新規 bats カバレッジが追加されている
- <!-- verify: command "bats tests/run-spec.bats" --> `tests/run-spec.bats` の既存スイートが回帰していない (回帰保護のみを目的とする AC — 新規カバレッジの主張は前項が担う)

### Post-merge

- 実際に spec phase で silent no-op が発生した際、自動リトライが機能することを確認する — 次の `event=auto-run` 発火時、`docs/reports/orchestration-recoveries.md` の spec-retry-fire 相当エントリの有無、または該当セッションの `.tmp/auto-events.jsonl` 内 retry イベントの有無を確認する <!-- verify-type: observation event=auto-run -->

## Notes

- **新規テストケース要件 (Step 13 省略のための記録、SPEC_DEPTH=light)**: Implementation Step 1 は `scripts/run-spec.sh` の既存 completion-check ブロックに新規分岐ロジック (retry-vs-fail 分岐、tier ゲート、stash preflight、recovery 記録) を追加する。Step 3 は `tests/run-spec.bats` に新規5ケース (retry 発火+カウンタ増加、`AUTO_RETRY_ENABLED=false` 非発火、max iteration 非発火、stash preflight、record-before-exec の recovery 記録) を要求しており、これは `tests/run-code.bats` の対応する5ケース (738-1076行目) と同水準のカバレッジである。受入基準4/5で担保されているが、5番目の回帰専用 AC 単体では新規カバレッジの存在を証明しない点に注意。

- **設計判断 — in-place 拡張 vs 新規サブセクション**: `## auto-retry-on-fail (code_retry_fire)` セクションは新規 H2 を追加せず、既存の Applicable Phases / Phase Scope Decision / Symptom / Fallback Steps / Rationale を in-place で拡張する方針とした。理由: Fallback Steps・Escalation・Rationale は code phase と spec phase で構造的に同一 (同じ tier ゲート、同じ record-before-exec の順序、同じ Tier 2/3 への escalation) であり、新規セクションを立てると内容がほぼ丸ごと重複する。受入基準3の rubric は Issue の Auto-Resolved Ambiguity Points により両案とも許容している。

- **命名 — イベント名と recovery 見出し**: recovery ログの見出し `spec-retry-fire` は Issue の Auto-Resolved Ambiguity Points で確定済み (`code-retry-fire` の命名パターンを踏襲)。emit する イベント名 `spec_retry_fire` (アンダースコア区切り) は Issue 本文で明示されていないが、本コードベースの `emit_event` 命名規約 (`phase_start`/`phase_complete`/`wrapper_exit`/`token_usage`/`code_retry_fire` 全てアンダースコア区切り) への一意な拡張であり、low-risk な auto-resolve と判断した。

- **`_write_spec_retry_recovery` の Recovery Applied 参照先**: 記録するエントリの「Recovery Applied」行は `_write_code_retry_recovery` と同じ `modules/orchestration-fallbacks.md#auto-retry-on-fail-code_retry_fire` を参照する (spec 専用の別 anchor は作らない)。上記「in-place 拡張」判断と整合させるため — code/spec のリトライはドキュメント上も単一のパターンとして扱う。

- **allowed-tools impact chain check**: 検討済み。`modules/orchestration-fallbacks.md` への変更 (Step 2) は既存の `scripts/run-spec.sh` の挙動 (同ファイル548行目で既に参照済み) を説明するプローズ更新のみであり、新規スクリプト呼び出しを導入しない。よって読み手である `skills/auto/SKILL.md` / `skills/verify/SKILL.md` の `allowed-tools` に追加は不要。

- **Issue 本文と実装の整合性チェック**: Background の記述 (`run-spec.sh` は既に `reconcile-phase-state.sh spec --check-completion` を呼び `matches_expected:false` で `EXIT_CODE=1` を設定している) を現物の `scripts/run-spec.sh` (202-212行目) で確認済み。齟齬なし。

- **Comment Consumption (triage AC 監査への対応)**: `/spec` 実行開始時に検知した triage コメント (下記 Consumed Comments 参照) の指摘を受け、Pre-merge AC 5件目の文言を Issue 本文側で修正済み (「スイート全体 (既存 + 新規) が pass する」→「既存スイートが回帰していない (回帰保護のみを目的とする AC)」)。本 Spec の Verification はこの修正後の文言を verbatim でコピーしている。

## Consumed Comments

- **saito** (MEMBER, first-class) — Issue Retrospective (Ambiguity Resolution Rationale / Key Policy Decisions を `/issue` フェーズから引き継ぐ内容。SPEC_DEPTH=light のため Spec 側への retrospective 転記は対象外だが、文脈として consume 済み) — https://github.com/saitoco/wholework/issues/1369#issuecomment-5325637030
- **saito** (MEMBER, first-class) — Triage AC 監査: Pre-merge AC 5件目 (`command "bats tests/run-spec.bats"`) が新規カバレッジ主張なしに常時 PASS してしまう問題を指摘し、修正文言を提示。`/spec` 開始時に Issue 本文へ適用済み — https://github.com/saitoco/wholework/issues/1369#issuecomment-5325693052
