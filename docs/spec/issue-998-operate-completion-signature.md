# Issue #998: reconcile-phase-state: operate route の completion signature が closes #N コミットに依存しており誤検知

## Overview

`/auto` の operate route は patch route の phase sequence をそのまま再利用しており、`/code` 実行後に `reconcile-phase-state.sh code-patch $NUMBER --check-completion` が走る。しかし `modules/phase-state.md` が定める `code-patch` の completion signature は「`origin/main` に `closes #N` を含む fresh commit が 1 件以上ある」ことであり、operate route はそもそも実装 diff を生成しない (commit/push/PR ブロックを丸ごとスキップする) ため、成功した operate route 実行が `matches_expected: false` と判定される。

本 Issue は `code-patch` の completion check に **operate route の実際の産出物 (Execution Log / Execution Plan の Issue コメントマーカー) を代替 signature として認識する分岐** を追加し、この false-negative を解消する。

## Reproduction Steps

1. Spec の `## Changed Files` にリポジトリ内ファイルが 1 件も含まれず、`## Implementation Steps` がすべて外部ツール操作である Issue を用意する (operate route の判定条件 — `modules/size-workflow-table.md` § "Diff-less Axis (operate route)")。
2. `.wholework.yml` に `autonomy: L3` と `auto-retry-on-fail.enabled: true` を設定する (本リポジトリの現行設定と同一)。
3. `/auto <N>` を実行する。`/code` は Step 0 で `ROUTE=operate` を検出し、外部操作を実行して `## Execution Log` コメントを Issue に投稿し、`phase/verify` へラベル遷移して正常終了する (`skills/code/SKILL.md` Step 8/11/13)。
4. `scripts/run-code.sh` (line 286-328) が `reconcile-phase-state.sh code-patch $NUMBER --check-completion` を実行する。`closes #N` コミットは存在しないため `commits_found: false` となる。

観測される 3 つの誤動作:

- **(a) fix-cycle での external write 再実行 (最も危険)**: `/verify` FAIL で Issue が reopen された後の operate route 再実行では、`_completion_code_patch()` の reopen_ts 分岐 (`scripts/reconcile-phase-state.sh` line 238-241) がラベル fallback を無条件にスキップするため `matches_expected: false` が確定する。`run-code.sh` は "silent no-op" と判定して `exec bash "$0"` で `/code` を再起動し (line 320)、**同一の外部システム書き込みが再実行される**。operate route は post-hoc review の安全弁を持たないため (これが autonomy tier gating の存在理由)、この再実行は unsafe。
- **(b) L1 advisory の hard failure**: `autonomy: L1` では `/code` は `## Execution Plan` コメントを投稿してラベルを `phase/code` に留めたまま正常完了する。この状態はラベル fallback (`phase/verify|done`) にも該当しないため `matches_expected: false` となり、L1 は auto-retry の tier gate (L2/L3 のみ) を通らないので `EXIT_CODE=1` となる (line 326)。設計どおり成功した advisory 実行が orchestration recovery Tier 2/3 に落ちる。
- **(c) 誤った diagnosis の下流汚染**: 初回 (reopen なし) の L2/L3 実行では、`phase/verify` ラベルによる async-external-commit fallback (line 243-246) が偶然 `matches_expected: true` を返す。ただし diagnosis は "async external commit area" (実態と無関係) となり、`commits_found: false` がそのまま recovery sub-agent の `reconcile_snapshot` に渡る。

## Root Cause

`scripts/reconcile-phase-state.sh` の `_completion_code_patch()` は completion 判定を 2 段構成で行っている:

1. Primary: `git log origin/main [--after=<reopen_ts>] --grep="closes #N"`
2. Fallback: Issue のラベル (`phase/verify` / `phase/done`) または state (`CLOSED`) — ただし reopen_ts が非 null のときはスキップ

operate route の産出物はこのどちらとも一致しない。operate route が実際に生成するのは Issue コメントであり、`skills/code/SKILL.md` Step 11 が先頭行に置く machine-readable マーカー `<!-- wholework-event: type=execution-log phase=code issue=$NUMBER -->` (L2/L3) だけが「operate route の code phase が完了した」ことの決定的な証跡である。L1 advisory の `## Execution Plan` コメントには現状マーカーが付与されていない。

修正方針は **`code-patch` の completion signature に operate-aware な第 3 段を追加する**こと。新規 `code-operate` phase 名を導入しない理由は Notes を参照。

## Changed Files

- `modules/phase-state.md`: Phase Table の `code-patch` 行 Success Signature に operate route の代替 signature を追記し、`### Operate Route Completion Signature` サブセクションを新設。JSON Schema (v1) の field contract 表に `actual.operate_signal` 行を追加
- `scripts/reconcile-phase-state.sh`: `_operate_signal_ts()` ヘルパを追加し、`_completion_code_patch()` にラベル fallback より手前で operate signal 分岐を挿入 — bash 3.2+ 互換 (`declare -A` / `mapfile` 不使用)
- `skills/code/SKILL.md`: Step 8 の `L1` advisory 分岐が投稿する `## Execution Plan` コメントに machine-readable マーカー `<!-- wholework-event: type=execution-plan phase=code issue=$NUMBER -->` を追加
- `skills/auto/SKILL.md`: "patch route XS/S (2 phases)" セクション冒頭の "ROUTE=operate reuses this section verbatim" 段落に、`code-patch` completion check が operate route のマーカーを代替 signature として認識する旨を追記
- `modules/orchestration-fallbacks.md`: `## async-external-commit` の "Fallback Steps" を two-stage → three-stage に更新 (operate signal 段を挿入)
- `tests/reconcile-phase-state.bats`: operate route completion の bats テストを追加 (4 ケース)
- `tests/operate-route.bats`: `modules/phase-state.md` に operate route completion signature が記載されていることの shallow test を追加
- `docs/tech.md`: Architecture Decisions の "operate route (diff-less workflow path)" bullet に completion signature を 1 文追記 [Steering Docs sync candidate — 採用]
- `docs/ja/tech.md`: 上記の日本語ミラーを同期 (`docs/translation-workflow.md` の Sync Procedure に従う)

**変更不要と確認したファイル (grep 実施済み)**:

- `modules/l0-surfaces.md`: `wholework-event` の marker type 一覧を持たない (`type=verify-fail` は Example として記載されているのみで、`type=execution-log` も未登録)。新 type の登録先が存在しないため変更不要
- `scripts/apply-fallback.sh` / `scripts/spawn-recovery-subagent.sh` / `scripts/detect-wrapper-anomaly.sh`: いずれも `reconcile-phase-state.sh --check-completion` の JSON 出力を再利用するのみで、signature ロジックを複製していない。修正は自動的に伝播する
- `docs/workflow.md` / `docs/ja/workflow.md`: operate route の記述 (line 54 / line 47) はユーザー向けの route 説明であり、completion signature は内部の orchestration 詳細のため対象外
- `docs/structure.md` / `docs/product.md`: `reconcile-phase-state.sh` への言及は 1 行の役割説明・用語集エントリのみで、内容は変わらない

## Implementation Steps

1. `modules/phase-state.md` の Phase Table `code-patch` 行の Success Signature を更新し、`## Output` 配下に `### Operate Route Completion Signature` サブセクション (h3) を新設する。記述内容: operate route は実装 diff を生成しないため `closes #N` コミットを産出しないこと、代替 signature は Issue コメントの machine-readable マーカー `<!-- wholework-event: type=execution-log phase=code issue=N -->` (L2/L3) または `<!-- wholework-event: type=execution-plan phase=code issue=N -->` (L1 advisory) であること、鮮度判定は既存 `closes #N` signature と同一セマンティクス (reopen timestamp が取得できればコメントの `createdAt > reopen_ts` を要求、取得できなければ無制限) であること、判定順序は commit → operate marker → ラベル/state fallback であること (→ 受け入れ基準 1, 2)
2. `modules/phase-state.md` の "JSON Schema (v1)" field contract 表に `actual.operate_signal` (boolean、`code-patch` completion で commit が見つからなかったときに存在、operate route マーカーが検出されたかどうか) の行を追加する (after 1) (→ 受け入れ基準 1)
3. `scripts/reconcile-phase-state.sh` に `_operate_signal_ts()` ヘルパ関数を追加する (既存の `_append_hints_to_actual()` の直後、`_completion_spec()` の手前)。挙動: `gh issue view "$ISSUE_NUMBER" --json comments --jq '<filter>'` で、body に `<!-- wholework-event: type=execution-log phase=code issue=${ISSUE_NUMBER}` または `<!-- wholework-event: type=execution-plan phase=code issue=${ISSUE_NUMBER}` を含むコメントの `createdAt` の最大値を stdout に出力する (該当なし・`gh` 失敗時はいずれも空文字を出力し exit 0)。`ISSUE_NUMBER` は script 冒頭 (line 67) で `^[0-9]+$` 検証済みのため jq フィルタ文字列への直接補間で安全。`gh` 組み込みの `--jq` を使い外部 `jq` へのパイプは行わない (ファイル内の既存スタイルに合わせる) (→ 受け入れ基準 4)
4. `scripts/reconcile-phase-state.sh` の `_completion_code_patch()` に operate signal 分岐を挿入する (after 3)。挿入位置: `mismatch_diag` を設定する if/else ブロックの直後、`# Fallback: check phase labels or issue state` コメント行の直前 (reopen_ts 非 null 時にラベル fallback がスキップされる分岐より手前に置くことで、fix-cycle でも operate signal が効く)。分岐の全挙動:
   - `_operate_signal_ts()` の出力が空または `null` → `operate_signal=false`。`actual_json` の末尾に `,"operate_signal":false` を追記 (`_append_hints_to_actual()` と同じ `${json%\}}` 方式) し、既存のラベル/state fallback へフォールスルー
   - 出力が非空 かつ `reopen_ts` が空または `null` → `operate_signal=true`
   - 出力が非空 かつ `reopen_ts` が非 null かつ マーカーの `createdAt` が `reopen_ts` より後 (bash 3.2 の `[[ "$a" > "$b" ]]` による ISO-8601 UTC 文字列比較。固定長 ASCII のため辞書順比較で正しい) → `operate_signal=true`
   - 出力が非空 かつ `reopen_ts` が非 null かつ マーカーが `reopen_ts` 以前 → `operate_signal=false` (前サイクルの stale marker。ラベル/state fallback へフォールスルー)
   - `operate_signal=true` の場合: `actual_json` に `,"operate_signal":true` を追記し、`_emit_result "true" "operate route completion: execution-log/plan marker comment found (<ts>) for issue #N; no closes #N commit expected" "$actual_json"` を呼んで `return` (exit code 0)
   (→ 受け入れ基準 4)
5. `skills/code/SKILL.md` Step 8 の `#### Operate Route: External Operation Execution` の `L1` 分岐に、`## Execution Plan` コメントの先頭行として `<!-- wholework-event: type=execution-plan phase=code issue=$NUMBER -->` マーカーを置く旨を追記する (`modules/l0-surfaces.md` § "Machine-Readable Event Marker" を参照する形式は Step 11 の Execution Log 記述に合わせる) (parallel with 1-4) (→ 受け入れ基準 6 — Step 9 の shallow test 経由で検証)
6. `skills/auto/SKILL.md` の "patch route XS/S (2 phases)" セクション冒頭にある "ROUTE=operate reuses this section verbatim" 段落に、`code-patch` completion check が operate route の Execution Log / Execution Plan マーカーを代替 success signature として認識するため (`modules/phase-state.md` § "Operate Route Completion Signature")、`closes #N` コミットが無くても成功した operate route 実行は `matches_expected: true` を返す旨を追記する (parallel with 1-5) (→ 受け入れ基準 3)
7. `modules/orchestration-fallbacks.md` の `## async-external-commit` § "Fallback Steps" の "built-in two-stage check" を three-stage に更新し、Primary (git log) と ラベル/state fallback の間に operate marker 段を挿入する (parallel with 1-6) (→ 受け入れ基準 3)
8. `tests/reconcile-phase-state.bats` に operate route completion のテストを追加する (after 4)。既存の `# --- code-patch completion ---` 群と同じ mock 方式 (`$MOCK_DIR` に `gh` / `git` / `gh-graphql.sh` を配置し `WHOLEWORK_SCRIPT_DIR` 経由で差し込む) を用い、`gh` mock は `--json comments` を含む引数のときにマーカーコメントの `createdAt` を echo する。4 ケース: (a) reopen なし + `closes #N` なし + execution-log マーカーあり → `matches_expected:true` かつ `"operate_signal":true`、(b) reopen なし + `closes #N` なし + execution-plan マーカー (L1) あり → `matches_expected:true`、(c) reopen あり + fresh commit なし + reopen より後のマーカーあり → `matches_expected:true` (fix-cycle の再実行防止)、(d) reopen あり + fresh commit なし + reopen より前の stale マーカーのみ → `matches_expected:false` (→ 受け入れ基準 5, 6)
9. `tests/operate-route.bats` にファイル先頭の変数定義として `PHASE_STATE="$PROJECT_ROOT/modules/phase-state.md"` を追加し、shallow test を 2 件追加する (after 1, 5)。既存ファイルの `@test` 命名規約 (`@test "<対象>: <説明>"` — 例 `@test "code skill: operate route execution log is documented"`) に合わせること。(a) `modules/phase-state.md` に operate route の completion signature が記載されている、(b) `skills/code/SKILL.md` に L1 advisory の `execution-plan` マーカーが記載されている (→ 受け入れ基準 6)
10. `docs/tech.md` の Architecture Decisions "operate route (diff-less workflow path)" bullet に、completion signature が `closes #N` コミットではなく Execution Log / Execution Plan コメントマーカーである旨を 1 文追記し、`docs/ja/tech.md` の対応する日本語 bullet を同期する (`docs/translation-workflow.md` の Sync Procedure に従う) (parallel with 1-9) (→ 受け入れ基準 1)

## Verification

### Pre-merge

- <!-- verify: rubric "modules/phase-state.md に operate route 用の completion signature (Execution Log コメントマーカーベース、closes #N コミットに依存しない) が定義されている" --> operate route の完了シグネチャが `modules/phase-state.md` に定義されている
- <!-- verify: file_contains "modules/phase-state.md" "operate" --> `modules/phase-state.md` に operate route 向けの記述が含まれている (現状 `modules/phase-state.md` に "operate" の記載なしを確認済み — rubric の補助的な機械チェック)
- <!-- verify: rubric "skills/auto/SKILL.md の operate route フェーズシーケンスが、新しい completion signature (または operate 判定を反映した check) を使用するよう更新されている" --> `/auto` の operate route completion check が更新されている
- <!-- verify: file_contains "scripts/reconcile-phase-state.sh" "execution-log" --> `scripts/reconcile-phase-state.sh` の `_completion_code_patch()` が operate route の Execution Log / Execution Plan コメントマーカーを completion signature として認識する
- <!-- verify: file_contains "tests/reconcile-phase-state.bats" "operate" --> operate route completion の bats テストが `tests/reconcile-phase-state.bats` に追加されている
- <!-- verify: github_check "gh pr checks" "Run bats tests" --> テストスイートが green (PR route)

### Post-merge

- 次回 `/auto` の operate route 実行 (`/code --patch` が operate 判定されるケース) で、`reconcile-phase-state.sh` の completion check が `matches_expected: true` を返し、誤った auto-retry / orchestration recovery が発火しないことを観察

## Tool Dependencies

### Bash Command Patterns

なし (`gh issue view` は `scripts/reconcile-phase-state.sh` 内部の呼び出しであり、SKILL の `allowed-tools` 対象外。新規 `scripts/*.sh` の追加もないため allowed-tools impact chain check は該当なし)

### Built-in Tools

なし (Read / Edit / Write はいずれも `/code` の既存 `allowed-tools` に含まれる)

### MCP Tools

なし

## Uncertainty

- **`gh issue view --json comments` の `createdAt` と GraphQL `ReopenedEvent.createdAt` のフォーマット整合**: 辞書順比較を行うには両者が同一フォーマットである必要がある。
  - **検証方法**: 実 Issue (#998) に対して `gh issue view 998 --json comments --jq '.comments[] | .createdAt'` を実行。
  - **検証結果**: `2026-07-13T00:14:10Z` — `gh-graphql.sh --query get-last-reopen` が返す `createdAt` と同じ ISO-8601 UTC 形式 (末尾 `Z`、固定長)。`modules/l0-surfaces.md` の Comment Consumption Procedure も同じ前提で辞書順比較を行っている。**解消済み**。
  - **影響範囲**: Implementation Step 4

- **既存 bats テストへの回帰リスク**: `_completion_code_patch()` に新たな `gh issue view --json comments` 呼び出しを追加するため、既存テストの `gh` mock が新しい引数パターンに応答しない。
  - **検証方法**: 既存 5 ケース (`no matching commit` / `git fetch failure` / `fix-cycle false positive` / `async external commit` / `reopen_ts non-null + phase/verify`) の mock を読み、`--json comments` が未定義パスに落ちて空出力 + exit 0 になることを確認。
  - **検証結果**: いずれの mock も `--json labels` / `--json state` にマッチしない引数では出力なし・exit 0 で終了する。`_operate_signal_ts()` は空出力を「マーカーなし」として扱い、既存の fallback にフォールスルーするため、既存テストの期待値は変わらない。**解消済み** (ただし実装後に `bats tests/reconcile-phase-state.bats` の全ケース green を確認すること)。
  - **影響範囲**: Implementation Step 4, 8

## Notes

### 実装方式の選択根拠 (新規 `code-operate` phase を採用しない理由)

Issue 本文は「新規 `code-operate` phase-state エントリ」と「`code-patch` 内の operate-aware 分岐」の二択を提示していた。**後者を採用**する。

`code-operate` という新しい phase 名を導入すると、その名前を渡す責務が caller 側に生じる。しかし全 caller (`scripts/run-code.sh` line 286-290、`scripts/run-auto-sub.sh` line 654、`skills/auto/SKILL.md` Step 4) は `--patch` / `--pr` フラグから機械的に phase 名を導出しており、`skills/auto/SKILL.md` は "`run-code.sh` itself is unaware of the `operate`/`patch` distinction" と明示している。operate 判定は Spec の `## Implementation Steps` が「すべて外部ツール操作か」という semantic な判断 (`/code` Step 0 で LLM が行う) であり、これを bash 側に再実装することはできない。

一方、実行後に観測可能な証跡 — Execution Log / Execution Plan コメントのマーカー — は completion check の時点で確実に存在し、caller 側の route 知識を一切必要としない。したがって `code-patch` の signature を「commit **または** operate マーカー」に拡張する方式が、既存の caller 契約を壊さずに false-negative を解消できる唯一の設計となる。

### L1 advisory を signature に含める理由

`skills/code/SKILL.md` Step 13 は L1 advisory についても "operate route completes here" と定義しており、L1 は設計上の正常完了である。含めない場合、`scripts/run-code.sh` line 299-327 の silent no-op 判定で `EXIT_CODE=1` となり (L1 は auto-retry の tier gate を通らない)、成功した advisory 実行に対して orchestration recovery が誤発火する。そのため L1 の Execution Plan コメントにも machine-readable マーカーを付与し (Implementation Step 5)、両方を signature として受理する。

### 既知の制約: route 変更を跨いだ stale marker

reopen timestamp が取得できないケースで、同一 Issue の Spec が operate → patch に書き換えられた (かつ reopen されていない) 場合、前サイクルの operate マーカーが真の patch silent no-op を隠蔽しうる。これは既存の `closes #N` signature が持つ「reopen timestamp 不在時は無制限 grep」というフォールバック (diagnosis に "fix-cycle false positive possible" と明記されている) と同じ性質の制約であり、新しい失敗モードのクラスを増やさない。追加の鮮度判定 (`phase/code` ラベル付与時刻を timeline API から取得する等) はコストに見合わないと判断し、`modules/phase-state.md` に制約として記載するに留める。

### #993 との競合注意

#993 も `_completion_code_patch()` (stray PR 検出ギャップ) を変更対象とする。本 Issue の変更は「commit 未検出時のラベル fallback 手前に operate signal 分岐を挿入する」ものであり、#993 の変更点と物理的に近接する可能性が高い。先にマージされた側を base に rebase して conflict を解消すること。

### SKILL.md validator 制約 (skill-dev-constraints.md)

`skills/code/SKILL.md` / `skills/auto/SKILL.md` の本文追記では、`scripts/validate-skill-syntax.py` の MUST 制約に従うこと: 半角 `!` を本文に含めない、Step 番号に小数を使わない、code fence 外に triple backtick を置かない。マーカー文字列 (`<!-- wholework-event: ... -->`) は HTML コメントであり、既存の Step 11 記述と同じくインラインコード (backtick 囲み) で書けば validator の `!` 検出対象外となる。

## Consumed Comments

- saito / MEMBER / first-class / `/issue` フェーズの Issue Retrospective (トリアージ結果 Type=Bug・Size=L・Value=3、タイトル正規化、#993 との重複判定、非対話モードでの自動解決 3 件、Background 記載事実のコードベース突合結果) — https://github.com/saitoco/wholework/issues/998#issuecomment-4953352587
