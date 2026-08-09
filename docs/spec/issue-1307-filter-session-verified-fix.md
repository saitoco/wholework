# Issue #1307: auto: observation scan の session-verified フィルタが並行セッションで誤帰属する問題を解消

## Overview

`scripts/filter-session-verified-issues.sh` は、observation scan の候補 Issue から「本セッションで既に `/verify` を完走した」Issue を除外するフィルタである。セッション解決を `AUTO_SESSION_ID` 環境変数 → `.tmp/auto-session-current` ポインタファイルの順のみで行っており、呼び出し元 (`skills/auto/SKILL.md` の単一 Issue 経路・batch 経路の 2 箇所) は session を明示的に渡していない。`AUTO_SESSION_ID` は Bash tool call をまたいで引き継がれないため実質ポインタファイルのみが解決経路となり、並行 `/auto` セッションが同ファイルを上書きすると誤ったセッションに対して除外判定が行われる (fail-open ではなく silent な誤帰属)。

同一手順内の `scripts/observation-trigger.sh` は既に `--session <literal SESSION_ID>` の in-band hand-off を持つ (#1075)。本 Issue は、Issue 本文の検討候補「案 A」(`--session` オプション追加 + 呼び出し側で明示的に渡す) を採用し、この非対称を解消する。案 A の採用理由: `scripts/collect-run-facts.sh` が既に同じ `--session <id> > AUTO_SESSION_ID env var > .tmp/auto-session-current pointer file` という解決順と `SESSION_ARG` 変数命名パターンを実装済みであり (`scripts/collect-run-facts.sh:72-121`)、既存パターンから一意に導出できる最小変更のため (案 B は呼び出し箇所が増えるたびに同じ間違いが再発しうる、案 C は期待値の入手元が結局 A/B と同じ問題に帰着する)。

## Reproduction Steps

1. 複数の `/auto` セッションを並行実行する (session A, session B)。
2. session A が Issue を `/verify` 完了させ、`.tmp/auto-events.jsonl` に `session_id="A"` の `phase=verify` `phase_start`/`phase_complete` イベントを記録する。
3. session A の end-of-batch observation scan 実行直前に、session B が `.tmp/auto-session-current` を自身の session id (`B`) で上書きする。
4. session A が (session を渡さず) `filter-session-verified-issues.sh` を実行すると、`AUTO_SESSION_ID` は当該 Bash tool call に引き継がれないため `.tmp/auto-session-current` (= B) が解決され、B のイベントに対して除外判定が行われる。
5. 結果: session A で verify 済みの Issue が候補から除外されず残存し、session B で verify 済みの Issue が誤って除外される。警告は出ない (session id 自体の解決には成功しているため fail-open 経路を通らない)。

## Root Cause

`scripts/filter-session-verified-issues.sh:11` のセッション解決順が `AUTO_SESSION_ID` 環境変数 → `.tmp/auto-session-current` ポインタファイルのみで、呼び出し元 (`skills/auto/SKILL.md:755` / `:1249`) が明示的な session 引数を渡していない。ポインタファイルは並行セッション間で共有され最後に書き込んだセッションが勝つ (last-write-wins) ため、並行実行下では「現在のセッション」を正しく指さない。`observation-trigger.sh` は #1075 で `--session` の in-band hand-off を導入済みであり、`filter-session-verified-issues.sh` はこの対処が未適用の残存消費者である。修正方針は `observation-trigger.sh` (および `collect-run-facts.sh`) と対称なインターフェースを追加することで、根本原因である「session 解決をポインタファイルに依存させる構造」自体を、呼び出し側からの明示的な hand-off で置き換える。

## Changed Files

- `scripts/filter-session-verified-issues.sh`: `--session <id>` オプションを追加。セッション解決順を `--session` フラグ → `AUTO_SESSION_ID` 環境変数 → `.tmp/auto-session-current` ポインタファイルに変更する (`scripts/collect-run-facts.sh` の `SESSION_ARG` 変数命名・引数パース・エラーメッセージパターンを踏襲)。ヘッダーコメントの `# Usage:` / `# Session resolution order:` 行を更新。bash 3.2+ 互換 (`mapfile` 不使用、既存コードと同水準)。
- `tests/filter-session-verified-issues.bats`: 並行セッションによる `.tmp/auto-session-current` 上書きを模したテストを追加し、`--session` 明示指定がポインタファイルより優先されることを検証する。
- `skills/auto/SKILL.md`: Event-based observation scan の L2/L3 分岐 2 箇所 (単一 Issue 経路・batch 経路) で、`filter-session-verified-issues.sh` 呼び出しに ` --session <literal SESSION_ID value from step 1>` を追加する (直前行の `observation-trigger.sh --session` 呼び出しと同じ引数形)。

**Steering Docs sync candidate 確認済み (変更不要)**: `docs/structure.md:209` / `docs/ja/structure.md:201` の一行説明 (「`phase=verify` イベント...を除外する (fail-open)」) は解決順の内部実装に踏み込んでおらず、`--session` 追加後も記述として正確なため変更不要と判断した (grep 済み)。`modules/observation-trigger.md:159-170` の「`/auto` session-verified filter (#1162)」節も同様に、フィルタの目的・fail-open 契約を高レベルで記述するのみで解決順の詳細には触れておらず、`--session` 追加はこの記述をより正確にする方向の変更であり矛盾は生じない (grep 済み)。`README.md` / `docs/workflow.md` に本スクリプトへの言及なし (grep 済み、ヒットなし)。

## Implementation Steps

1. `scripts/filter-session-verified-issues.sh` に `--session <id>` オプションを追加する。`scripts/collect-run-facts.sh` の引数パースパターン (`SESSION_ARG` 変数、`while [ $# -gt 0 ]; do case "$1" in --session) ... shift 2 ;; esac; done`、未指定値エラー `"Error: --session requires an argument"` を stderr へ) をそのまま踏襲する。既存の `SESSION_ID="${AUTO_SESSION_ID:-}"` 行 (現在のフォールバック起点) の直前に `SESSION_ID="$SESSION_ARG"` を置き、空なら現行の env var → pointer file フォールバックへ進む形にする。`SESSION_ID` 自体の下流利用箇所 (空判定による fail-open 分岐、`jq --arg sid "$SESSION_ID"` への渡し) は解決順が変わるだけで参照方法は変更不要。ヘッダーコメントの `# Usage:` 行 (`| scripts/filter-session-verified-issues.sh` の末尾に `[--session <id>]` を追加) と `# Session resolution order:` 行 (`--session <id> > AUTO_SESSION_ID env var > .tmp/auto-session-current pointer file` に更新) を修正する。(→ 受入条件 1)
2. `tests/filter-session-verified-issues.bats` に新規 `@test` を追加する (after 1)。既存 `setup()` (`cd "$BATS_TEST_TMPDIR"`; `AUTO_EVENTS_LOG`/`AUTO_SESSION_ID` を export) を再利用。フィクスチャ JSONL に `session_id="session-A"` の Issue (例: 984) と `session_id="session-B-concurrent"` の Issue (例: 995) の `phase=verify` `phase_start` イベントを両方含める。テスト内で `AUTO_SESSION_ID` を unset し、`.tmp/auto-session-current` に `session-B-concurrent` を書き込む (並行セッションによる上書きを模す)。`"$SCRIPT" --session session-A` を実行し、984 (session-A の verify 済み) が出力から除外され、995 (pointer ファイルが指す session-B-concurrent 側の verify 済み) は除外されずに出力に残ることを検証する — 後者が残ることで、`--session` 明示値が pointer ファイルの内容より優先されている (pointer 内容を見ていない) ことを証明する。(→ 受入条件 3)
3. `skills/auto/SKILL.md` の Event-based observation scan L2/L3 分岐を更新する (after 1)。単一 Issue 経路 (`**Event-based observation scan (auto-run event, runs after Completion Report regardless of success/failure):**` 直後の L2/L3 箇条書き) と batch 経路 (`**Event-based observation scan (batch, best-effort):**` 直後の L2/L3 箇条書き) の両方で、`| "${CLAUDE_PLUGIN_ROOT}/scripts/filter-session-verified-issues.sh"` の直後 (閉じバッククォートの前) に ` --session <literal SESSION_ID value from step 1>` を追加する。両箇所とも直前行に同一パターンの `observation-trigger.sh --event auto-run --session <literal SESSION_ID value from step 1>` が既に存在するため、それと同じ引数表記に揃える。(→ 受入条件 2)
4. `bats tests/filter-session-verified-issues.bats` を実行し、既存 4 テスト + 新規テストがすべて PASS することを確認する (after 2, 3)。(→ 受入条件 4)

## Verification

### Pre-merge

- <!-- verify: grep -- "--session" "scripts/filter-session-verified-issues.sh" --> `filter-session-verified-issues.sh` が `--session` オプションで session を明示指定できる
- <!-- verify: rubric "skills/auto/SKILL.md の Event-based observation scan 手順 (単一 Issue 経路と batch 経路の 2 箇所) で、filter-session-verified-issues.sh に対して observation-trigger.sh と同じ literal SESSION_ID が渡される形になっている" --> 呼び出し側 2 箇所が session を渡している
- <!-- verify: rubric "並行セッションが .tmp/auto-session-current を上書きした状況を模した bats テストが追加され、明示指定した session のイベントに対して除外判定が行われることを検証している" --> 誤帰属を防ぐテストが追加されている
- <!-- verify: command "bats tests/filter-session-verified-issues.bats" --> 既存テストが PASS する

### Post-merge

- 次回 `/auto --batch` の end-of-batch observation scan で、当該セッションで verify 済みの Issue が dispatch 候補に残らないことを観察する <!-- verify-type: observation event=auto-run session=next -->
  - Expected output structure:
    - end-of-batch observation scan が `filter-session-verified-issues.sh` を `--session <このセッションの SESSION_ID>` 付きで呼び出しており、フィルタ後の dispatch 候補一覧に本セッション中に `phase=verify` の `phase_start`/`phase_complete` を記録済みの Issue 番号が含まれていない
    - `.tmp/auto-session-current` が並行 `/auto` セッションによって別セッション ID に上書きされていても、上記の除外判定は本セッションの `--session` 明示値に基づいて行われている (pointer ファイルの内容に影響されない)

## Notes

- **案 A を採用**: Issue 本文の検討候補のうち案 A (`--session` オプション追加) を採用した。理由は Overview に記載の通り、`collect-run-facts.sh` が既に同一の解決順・変数命名パターンを実装済みであり「既存パターンから一意に導出できる」ため、非対話モードでの自動解決基準を満たす。案 B/C は不採用 (トレードオフは Issue 本文の検討候補表を参照)。
- **Issue 本文 Post-merge AC に Expected output structure を追加済み**: `modules/verify-classifier.md` の observation 型ガイダンス (Option A: 2-part 構成) と照らし、Issue 本文の Post-merge AC (`event=auto-run session=next`) が "Expected output structure" サブビュレットを欠いていたため、本 `/spec` フェーズ内で Issue 本文・Spec の両方に同一内容を追加した (`gh-issue-edit.sh` で更新済み。前例: `docs/spec/issue-977-run-auto-sub-spec-skip.md`)。観測イベント自体 (次回 batch 完了時に session-verified フィルタが正しく効く) は変更していない。
- Issue 本文 Background の技術的主張 (`filter-session-verified-issues.sh:11` の解決順、`skills/auto/SKILL.md:755`/`:1249` が session を渡していない点、`observation-trigger.sh` の `--session` 対応) はいずれもコードベースと突き合わせて確認済みで (grep/Read 済み)、矛盾は検出しなかった。
- 資格情報・シークレット管理に関わる変更ではないため、credential/security policy alignment check は該当なし。
- UI を伴わないバックエンドスクリプト修正のため、UI Design phase (Figma 連携) は該当なし。
- `scripts/filter-session-verified-issues.sh` は新規スクリプトではなく既存スクリプトの変更のため、allowed-tools impact chain check (Case 1) の対象外 (`skills/auto/SKILL.md` の allowed-tools には `${CLAUDE_PLUGIN_ROOT}/scripts/filter-session-verified-issues.sh:*` が既に登録済みであることを確認済み)。`modules/*.md` の変更を含まないため Case 2 も対象外。

## Consumed Comments

- login: saito / authorAssociation: MEMBER / trust tier: first-class / 内容: `/issue 1307 --non-interactive` (Existing Issue Refinement) の Issue Retrospective。AC1 の verify command を `grep "session" ...` (常時 PASS 欠陥) から `grep -- "--session" ...` (実装後にのみ HIT) へ修正した経緯、Post-merge AC に `session=next` を追加した経緯 (skills/auto/SKILL.md 変更を含むため) を記録。Background の技術的主張は確認済みで修正不要、との申し送りも含む。/ URL: https://github.com/saitoco/wholework/issues/1307#issuecomment-5230556404

## Code Retrospective

### Deviations from Design
- N/A — Implementation Steps 1-4 をそのままの順序・内容で実装した。

### Design Gaps/Ambiguities
- N/A

### Rework
- N/A

## Phase Handoff
<!-- phase: merge -->

### Key Decisions
- pre-merge AC gate (`check-pre-merge-ac.sh`) は unchecked_count=0 で PASS、review-incomplete-fallback チェックも matches_expected=true (organic completion) のため、確認なしでマージを実行した。
- mergeable=true (reason=clean, CI success, review approved) のため conflict resolution (Step 3) はスキップし、直接 squash merge した。

### Deferred Items
- Post-merge AC (`event=auto-run session=next`) は次回 `/auto --batch` 実行時に `/verify` が観測する。merge フェーズでは検証不能 (設計通り継続)。

### Notes for Next Phase
- squash merge 完了、リモートブランチ削除済み。Issue #1307 は `closes #1307` により auto-close 対象 (base=main)。
- `/verify` フェーズでは Post-merge AC の observation イベント (次回 `/auto --batch` end-of-batch scan) の確認を行うこと。

## review retrospective

### Spec vs. implementation divergence patterns
- Nothing to note — Implementation Steps 1-4 通りの実装で、Spec と PR diff の間に構造的な乖離はなかった。

### Recurring issues
- Nothing to note — review-light (4 aspects 統合) で検出された指摘は CONSIDER 1件のみ (fail-open 警告メッセージが `--session` を列挙していない、ドキュメント一貫性の観点)。同種の指摘の繰り返しパターンは見られなかった。

### Acceptance criteria verification difficulty
- Nothing to note — Pre-merge AC 4件はすべて自動判定 (grep 1件 PASS、rubric 2件 PASS、CI 参照フォールバック経由の command 1件 PASS) で UNCERTAIN なく完結した。verify command / rubric 文言のいずれも過不足なく機能した。
