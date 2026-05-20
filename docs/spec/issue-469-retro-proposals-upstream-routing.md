# Issue #469: retro-proposals: Skill infrastructure 分類提案を upstream リポジトリへ自動 routing + サニタイズ機能を追加

## Overview

`modules/retro-proposals.md` を拡張し、`domain-classifier` が **Skill infrastructure improvement** と分類した提案を、`.wholework.yml` で設定した upstream リポジトリへ起票する。下流リポジトリ側では起票をスキップ (upstream のみ起票) し、下流ユーザーが手動で行っていた「サニタイズ → upstream 起票 → 下流 close」3 ステップを不要化する。

新規 `.wholework.yml` marker `retro-proposals-upstream: owner/repo` を追加 (未設定時は現行通り downstream 起票を維持し後方互換)。upstream 起票直前に regex (絶対パス・下流固有 Issue 番号) + LLM (ビジネス文脈) のハイブリッドサニタイズを実施する。

## Changed Files

- `modules/detect-config-markers.md`: Marker Definition Table に `retro-proposals-upstream` 行を追加 (string, デフォルト `""`); Output Format に `RETRO_PROPOSALS_UPSTREAM` を追加
- `modules/retro-proposals.md`: Input に `RETRO_PROPOSALS_UPSTREAM` を追加; Step 7.3 の `domain: specific` 分岐に upstream routing 判定 + サニタイズ前処理 + `gh issue create --repo $RETRO_PROPOSALS_UPSTREAM` + 下流起票スキップを追記; Step 10 に "Skip downstream creation when upstream routed" を追記
- `docs/guide/customization.md`: Available Keys SSoT テーブルに `retro-proposals-upstream` 行を追加 (Type string, Default `""`)
- `docs/ja/guide/customization.md`: 日本語ミラー同期 — 同行を追加
- `tests/retro-proposals.bats`: 新規作成 (bash 3.2+ 互換)。fixture とサニタイズ regex 単体テストを含む。upstream marker 設定/未設定 × Skill-infra/Code 分類の組み合わせと、絶対パス・Issue 番号サニタイズ regex の挙動を検証

## Implementation Steps

1. `modules/detect-config-markers.md` の Marker Definition Table に `retro-proposals-upstream` (string, default `""`, "Upstream リポジトリ (owner/repo 形式) — Skill infrastructure improvement 提案の起票先") 行を追加し、Output Format ブロックに `RETRO_PROPOSALS_UPSTREAM: ...` 行を追加 (→ AC4)
2. `modules/retro-proposals.md` の Input に `RETRO_PROPOSALS_UPSTREAM` を追加。Step 7.3 の `domain: specific` (rewrite 後) と Step 10 (`gh issue create`) の間に **Step 7.4「Upstream Routing + Sanitization」** を挿入: (a) `RETRO_PROPOSALS_UPSTREAM` 非空かつ Skill infrastructure 分類のとき upstream routing を発火、(b) サニタイズハイブリッド処理 (regex で絶対パス `/Users/[^[:space:]]*` と downstream 固有 Issue 番号 `#[0-9]+` をプレースホルダ置換 → LLM 呼び出しで残存業務固有名詞を除去) を Issue body に適用、(c) `gh issue create --repo "$RETRO_PROPOSALS_UPSTREAM"` で upstream 起票、(d) 下流側起票はスキップしターミナルへ `"Routed to upstream {owner/repo}#{N}; skipping downstream creation"` を出力。`RETRO_PROPOSALS_UPSTREAM` 未設定 or Code improvement 分類のときは従来パスで downstream 起票 (fallback) (→ AC1, AC2, AC3, AC6)
3. `docs/guide/customization.md` の Available Keys テーブルに `| \`retro-proposals-upstream\` | string | \`""\` | Upstream リポジトリ (owner/repo) — Skill infrastructure improvement 分類提案の起票先。未設定時は現リポジトリへ起票 (後方互換) |` 行を追加 (→ AC5)
4. `docs/ja/guide/customization.md` の同等位置に同行を日本語訳で追加 (description: "Upstream リポジトリ (owner/repo) — Skill infrastructure improvement 分類提案の起票先。未設定時は現リポジトリへ起票 (後方互換)")
5. `tests/retro-proposals.bats` を新規作成 (bash 3.2+ 互換)。`@test "sanitize: absolute paths to placeholder"`, `@test "sanitize: downstream issue numbers to placeholder"`, `@test "routing: upstream unset falls back to downstream"`, `@test "routing: upstream set + skill-infra classification → upstream"`, `@test "routing: upstream set + code classification → downstream"` を含む。CI 上で `tests/*.bats` の glob により自動実行される (→ AC7, AC8)

## Verification

### Pre-merge

- <!-- verify: file_contains "modules/retro-proposals.md" "retro-proposals-upstream" --> `modules/retro-proposals.md` に新 marker `retro-proposals-upstream` を参照する起票先切替ロジックが追加されている
- <!-- verify: rubric "modules/retro-proposals.md に、Skill infrastructure improvement と分類された提案を upstream リポジトリへ起票し、下流リポジトリ側では起票をスキップする (upstream のみ起票) 設計が明示されている" --> 下流スキップ方針 (upstream-only) が明文化されている
- <!-- verify: rubric "modules/retro-proposals.md に、`retro-proposals-upstream` marker が未設定の場合は現状通り downstream リポジトリへ起票する fallback 動作が明示されている (後方互換性)" --> marker 未設定時の fallback 動作が明示されている
- <!-- verify: file_contains "modules/detect-config-markers.md" "retro-proposals-upstream" --> `.wholework.yml` の新 marker `retro-proposals-upstream` (値: GitHub `owner/repo` 形式) が `detect-config-markers.md` の marker definition table に追加されている
- <!-- verify: file_contains "docs/guide/customization.md" "retro-proposals-upstream" --> `docs/guide/customization.md` Available Keys テーブル (SSoT) に `retro-proposals-upstream` キーが追加されている
- <!-- verify: rubric "modules/retro-proposals.md に、Skill infrastructure 提案を upstream に起票する前のサニタイズ処理 (機械的 regex で絶対パスと下流固有 Issue 番号を除去、LLM ベースで業務固有名詞などのビジネス文脈を除去するハイブリッド方式) が追加されている" --> サニタイズ処理が hybrid 方式 (regex + LLM) で記述されている
- <!-- verify: file_exists "tests/retro-proposals.bats" --> `tests/retro-proposals.bats` が新規作成され、upstream routing/サニタイズ/fallback の各分岐をカバーするテストケースを含む
- <!-- verify: github_check "gh pr checks --json name,conclusion --jq '[.[] | select(.name | test(\"bats\"; \"i\")) | .conclusion] | unique | join(\",\")'" "success" --> bats テスト CI ジョブが PR で success

### Post-merge

- 下流プロジェクトで `/verify` を実行し、Skill infrastructure 分類提案が upstream リポジトリへサニタイズ済みで起票され、下流側には起票されないことを実機で確認

## Notes

- **bash 3.2+ 互換**: `tests/retro-proposals.bats` は macOS システム bash (3.2) でも動作する記法を使用 (`mapfile` 等の bash 4+ 機能を避ける)
- **Auto-resolved 設計判断 (Issue body 参照)**: A1 下流スキップ / A2 hybrid サニタイズ / A3 marker 未設定時 downstream fallback。Spec はこの 3 決定を前提に Step 2 の挿入位置と分岐ロジックを設計
- **サニタイズ regex 設計**:
  - 絶対パス: `s|/Users/[^[:space:]]*|<absolute-path>|g` (downstream env 由来パスをマスク)
  - 下流固有 Issue 番号: `s/#[0-9]+/#<downstream-issue>/g` (本文 / リンクの両方をプレースホルダ化)
  - LLM サニタイズは regex 後の本文を入力に取り、社名・銘柄名・金額等を `[redacted]` 化
- **`gh issue create --repo` 前提**: 実行ユーザーの `gh auth` が upstream リポジトリへの write 権限を持つこと (Non-Goals: auth scope 自動化)
- **bats test 入力フォーマット**: サニタイズ regex は単体関数として bats から呼び出し可能な形 (heredoc で input/expected を比較) で実装。upstream routing 分岐は env mock (`RETRO_PROPOSALS_UPSTREAM` を export) で検証
- **bats test 自己参照除外**: 検出対象 (`/Users/...`, `#[0-9]+`) を fixture として含むため、`check-forbidden-expressions.sh` や `/audit drift` の grep 系チェックから `tests/retro-proposals.bats` を除外する必要がある場合は follow-up
- **AC count**: 8 件 (>5; light template の上限超過警告)。Issue body の AC を verbatim sync しているため統合不可。warning を許容
- **Mock 追加**: 既存 bats テストには `gh-graphql.sh` mock が用意されているが、`gh issue create --repo` は直接 `gh` を呼ぶため bats 側で `gh` コマンドの stub を `$BATS_TEST_TMPDIR/bin/gh` に配置し `PATH` を切り替えるパターンを採用 (`tests/get-config-value.bats` の WORK_DIR cd パターンを参考)

## review retrospective

### Spec vs. implementation divergence patterns

Step 7.4.c と Step 10 で upstream 起票失敗時の挙動が矛盾していた。7.4.c は無条件に downstream スキップと記述していたが、Step 10 は "upstream creation succeeded" を条件にしていた。分岐ロジックの条件節を 2 箇所に分けて書くと整合性が崩れやすい。今後は「成功時のみスキップ」という条件を step 7.4 内に一か所集約し、step 10 は cross-reference にとどめる設計を検討する。

### Recurring issues

特になし。

### Acceptance criteria verification difficulty

UNCERTAIN ゼロ — すべて file_contains / rubric / file_exists / github_check で自動検証できた。ただし、呼び出し側スキル (`/verify`, `/auto`) が新 Input 変数 `RETRO_PROPOSALS_UPSTREAM` を明示的に渡していない点は verify command では検出できない設計上のギャップ。モジュール Input セクションだけでなく、呼び出し側スキルの verify command を AC に含めることで次回以降の検出精度が上がる。

## Auto Retrospective

### Orchestration Anomalies
- **[code-completed-no-pr]** Watchdog killed the process in phase `code-pr` (exit code 143) after code-pr completed its commits but before PR creation: `matches_expected:false` and `phase:code-pr` detected in reconcile-phase-state output. The run-code.sh phase exited without creating a PR. Reference: #415.

### Improvement Proposals
- Follow the recovery procedure at `modules/orchestration-fallbacks.md#code-completed-no-pr`: checkout the worktree branch, rebase onto latest main, push the branch, and create the PR with `gh pr create`, then continue with `/review`.

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- Design is well-structured. Notes section details important implementation concerns (bash 3.2+ compatibility, bats test structure, `gh issue create --repo` auth prerequisite).
- The auto-resolved ambiguity points (A1/A2/A3) in the Issue body were referenced in the Spec and correctly guided implementation.

#### design
- Spec divergence in Step 7.4.c / Step 10 (upstream failure handling) was identified at review phase and corrected before merge. This pattern of conditional-skip logic spread across two steps is a structural risk noted in the review retrospective.

#### code
- Single main commit with no fixup/amend patterns. `code-completed-no-pr` Watchdog anomaly occurred but code was correct.

#### review
- Review correctly identified the Step 7.4.c / Step 10 conditional divergence. No conditions were missed that would have caused FAIL in verify.

#### merge
- Clean squash merge (#470 → main). No conflicts.

#### verify
- All 8 pre-merge conditions: PASS.
- Verify command bug detected: condition 8 uses `--json name,conclusion` but `gh pr checks` does not expose a `conclusion` field; the valid field is `state`. The command failed with "Unknown JSON field: conclusion". Alternative verification via `--json name,state` confirmed `SUCCESS`. This bug should be fixed in the Issue template or the verify command pattern for future Issues.
- Post-merge opportunistic condition remains unchecked (requires real downstream test environment).

### Improvement Proposals
- `gh pr checks` verify command pattern: `--json name,conclusion` is invalid; use `--json name,state` and check for `SUCCESS` (not `success`). The existing Issue template or a verify command linter should catch this field name mismatch to prevent silent fallback to alternative verification.
