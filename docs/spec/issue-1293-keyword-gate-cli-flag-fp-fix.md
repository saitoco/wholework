# Issue #1293: observation-trigger: keyword= ゲートの非パス様値への部分一致を単語境界マッチに改善

## Overview

`event=pr-review-light keyword=workflow` 等の observation AC が、`opportunistic-search.sh` の `keyword=` ゲートにおける非スラッシュ CLI フラグ構文 (`--workflow=test.yml` 等) への部分一致で誤発火する問題を修正する。Issue #1220 で対応済みのパス様トークン (`/` を含むトークン) 除外に続く、同一失敗モードの残存亜種。単語境界マッチ (`grep -qiw`) は `-` `=` が非単語文字として扱われるため有効でないことを Issue 本文の Auto-Resolved Ambiguity Points で実機確認済み — #1220 と同じ sed ベースのトークン除去アプローチを、CLI フラグ構文にも拡張する。

## Reproduction Steps

1. Issue #476 に `<!-- verify-type: observation event=pr-review-light keyword=workflow -->` の post-merge observation AC が付与されている
2. `/review` が、`github_check "gh run list --workflow=test.yml ..."` という verify command を含む Spec を対象に Opportunistic Verification で `opportunistic-search.sh --event pr-review-light --context-file <Spec>` を呼び出す
3. `resolve_filtered_context()` が Spec 内容から path-like token (`/` を1つ以上含むトークン) のみを `sed -E` で除去するため、`/` を含まない `--workflow=test.yml` はそのまま `FILTERED_CONTEXT` に残る
4. `echo "$FILTERED_CONTEXT" | grep -qi -- "workflow"` が `--workflow=test.yml` 内の部分文字列 `workflow` にマッチし、Issue #476 の観測条件が誤って成立と判定される
5. `/verify 476` が不要に再ディスパッチされる (Issue 本文の記録によれば15回の再実行中、この失敗モードは re-run #14 で観測された)

## Root Cause

`scripts/opportunistic-search.sh` の `resolve_filtered_context()` (line 239-248) は、path-like token (`[A-Za-z0-9._-]+(/[A-Za-z0-9._-]+)+` — `/` を1つ以上含むトークン) のみを `sed -E` で除去する。CLI フラグ構文 `--workflow=test.yml` は `/` を含まないためこの除去の対象外のまま残存し、後続の `grep -qi -- "$KEYWORD"` が部分文字列 `workflow` にマッチしてしまう。

**却下した代替案:**

- **単語境界マッチ (`grep -qiw`)**: Issue 本文の Auto-Resolved Ambiguity Points で実機検証済み — `echo "--workflow=test.yml" | grep -qiw "workflow"` は一致する (`\b` は `/` `.` に加え `-` `=` も非単語文字として扱うため)。#1220 が解決した failure mode と同型で機能しないため却下。
- **構造化マッチ (diff 内の実ファイルパス変更有無ベース)**: `--context-file` は `/review` が渡す Spec ファイルなど、diff 由来でない入力でも使われている。diff ソースを新たに要求する設計変更は既存インターフェースとの非互換が大きく、`modules/observation-trigger.md` が明記する「軽量な pre-filter、意味論的判定は行わない」という設計方針からも逸脱するため、本 Issue のスコープでは採用しない。

**採用した修正方針**: #1220 で確立済みの sed ベーストークン除去パターンを、CLI フラグ構文 (`--flag=value`) にも拡張する。`resolve_filtered_context()` に2つ目の `sed -E` 式を追加し、`--[A-Za-z0-9-]+=[A-Za-z0-9._-]+` パターンのトークンも同じキャッシュ済み1回のフィルタリングパスで除去する。

## Changed Files

- `scripts/opportunistic-search.sh`: `resolve_filtered_context()` に CLI フラグ構文除去用の `sed -E` 式を追加し、関連コメント (Usage ヘッダー・関数直前コメント・マッチループ内のインラインコメント) を更新 — bash 3.2+ 互換維持
- `modules/observation-trigger.md`: § Condition Check Gate (`keyword=`) に「CLI-flag-like token exclusion (Issue #1293)」段落を追加し、Matching specification の該当行を更新
- `tests/opportunistic-search.bats`: 新規 `@test` 2件を追加 (CLI フラグ構文のみの誤マッチ抑制ケース、CLI フラグ構文と正当な文中一致が共存するケース)

## Implementation Steps

1. `scripts/opportunistic-search.sh` の `resolve_filtered_context()` (現状 `sed -E 's#[A-Za-z0-9._-]+(/[A-Za-z0-9._-]+)+##g'` の単一パス) に、2つ目の `sed -E` 式 `'s#--[A-Za-z0-9-]+=[A-Za-z0-9._-]+##g'` を同じ呼び出し内に追加する (`sed -E -e '...' -e '...'` の複数 `-e` 形式)。`keyword=` 比較前に CLI フラグ構文トークン (例: `--workflow=test.yml`) も除去されるようにする。この関数を説明する3箇所のコメント (ファイル冒頭の Usage コメント、`resolve_filtered_context` 直前のコメント、マッチループ内の `KEYWORD` ゲート直前のインラインコメント) を、パス様トークンと CLI フラグ構文トークンの両方に言及する内容へ更新する。bash 3.2+ 互換を維持する (→ acceptance criteria A)
2. (parallel with 1) `modules/observation-trigger.md` § Condition Check Gate (`keyword=`) の「**Path-like token exclusion (Issue #1220)**」段落の直後に「**CLI-flag-like token exclusion (Issue #1293)**」段落を追加する。`--workflow=test.yml` の誤マッチ事例、単語境界マッチが同じ理由 (`-` `=` が非単語文字) で有効でないこと、拡張した除去メカニズムを記述する。「Matching specification」箇条書きの「Path-like token stripping」行を、2つの `sed -E` 式を両方説明する内容に更新する (→ acceptance criteria A, B)
3. (after 1) `tests/opportunistic-search.bats` の既存 `"context gate: keyword found in prose text still includes the issue"` テスト (現状 315行目付近で終了) の直後に、以下2件の `@test` を追加する:
   - `"context gate: keyword found only inside a CLI flag token excludes the issue"` — Mock Issue 508、AC `<!-- verify-type: observation event=pr-review-full keyword=workflow -->`、context file 内容 `gh run list --workflow=test.yml`、期待結果 `[]`
   - `"context gate: keyword found in prose text alongside a CLI flag token still includes the issue"` — Mock Issue 509、同じ AC、context file 内容に CLI フラグ行 (`gh run list --workflow=test.yml`) と正当な文中一致 (`This PR changes the CI workflow configuration.`) を両方含める、期待結果は Issue 509 がマッチに含まれること

   既存テストの `MOCK_ISSUE_LIST` / `MOCK_ISSUE_BODY_N` / `run bash "$SCRIPT" --event ...` パターンに従う (→ acceptance criteria C)

## Verification

### Pre-merge

- <!-- verify: rubric "modules/observation-trigger.md の Condition Check Gate (keyword=) セクションおよび scripts/opportunistic-search.sh の実装が、Issue #1220 のパス様トークン除外に加えて、'--workflow=test.yml' のような非スラッシュ CLI フラグ構文への誤マッチを抑制する仕組みを持っている" -->
- <!-- verify: rubric "Spec に改善方針の比較と選択理由が記載されている" -->
- <!-- verify: command "bats --filter 'CLI flag token' tests/opportunistic-search.bats" -->

### Post-merge

- 次回以降 Issue #476 の `/verify` が dispatch された際、`--workflow=<file>.yml` のような非スラッシュ CLI フラグ構文への誤発火が再現しないことを観察 <!-- verify-type: observation event=pr-review-light session=next -->

## Notes

- **Pre-merge AC3 の verify command 具体化 (Triage AC audit 対応)**: Consumed Comments に記録の通り、triage の AC audit コメントが `command "bats tests/opportunistic-search.bats"` の常時 PASS リスク (スイート全体を無条件実行するため、新規テストを追加しなくても既存56ケースのみで exit 0 になる — Pattern 2 型) を指摘した。Implementation Step 3 で確定した新規テスト名から一意な部分文字列 `CLI flag token` を抽出し、`command "bats --filter 'CLI flag token' tests/opportunistic-search.bats"` へ差し替えた (Issue #1279 と同型のパターン)。同じ内容を Issue #1293 本文の Pre-merge AC3 にも `gh-issue-edit.sh` 経由で反映済み (Spec 作成と同一セッション内)。CI 側の全件実行は別途 `.github/workflows/test.yml` の CI gate が担保する。
- **Issue Retrospective の Auto-Resolve Log は Issue 本文に反映済み**: `/issue 1293 --non-interactive` の Issue Retrospective コメント (Consumed Comments 参照) が記録した「単語境界マッチは #1220 と同型の理由で機能しない」という実機検証結果は、既に Issue 本文の `## Auto-Resolved Ambiguity Points` セクションに反映されている。本 Spec の Root Cause 節で同じ検証結果を引用し、採用方針・却下方針を確定した (→ acceptance criteria B)。
- **allowed-tools impact chain check**: Changed Files に `modules/observation-trigger.md` を含むため Case 2 のゲートを確認した。追加内容が `scripts/opportunistic-search.sh` を参照するため gate は該当したが、`grep -rl "modules/observation-trigger\.md" skills/*/SKILL.md` の結果は空 — 本モジュールを "Read and follow" する SKILL.md が存在しないため、allowed-tools の追加は不要と判断した。
- Domain file: SPEC_DEPTH=light のため `skills/spec/codebase-search.md` / `skill-dev-constraints.md` (いずれも `load_when: spec_depth: full`) は未読み込み。UI 変更を含まないため `figma-design-phase.md` も非該当。プロジェクトローカル Domain file (`.wholework/domains/spec/`) は存在しない。

## Consumed Comments

- saito (MEMBER, first-class) — `/issue 1293 --non-interactive` の Issue Retrospective。Auto-Resolve Log (単語境界マッチが機能しない実機検証結果) を記録。AC 変更なし。https://github.com/saitoco/wholework/issues/1293#issuecomment-5230670606
- saito (MEMBER, first-class) — Triage AC audit: Pre-merge AC3 の verify command `command "bats tests/opportunistic-search.bats"` が新規カバレッジなしでも常時 PASS するリスクを指摘。`bats --filter` への差し替えを推奨 (本 Spec の Notes・Implementation Step 3 で対応済み)。https://github.com/saitoco/wholework/issues/1293#issuecomment-5230697853
- `/code 1293 --non-interactive` (code フェーズ): cutoff (`phase/code` ラベル付与時刻 2026-08-09T09:13:45Z) 以降の新規コメントなし。

## Code Retrospective

### Deviations from Design
- None — Spec の Implementation Steps 1〜3 をそのまま実装した (resolve_filtered_context() への sed -E 式追加とコメント3箇所の更新、observation-trigger.md への段落追加、tests/opportunistic-search.bats への2件のテスト追加)。

### Design Gaps/Ambiguities
- None — Root Cause 節が却下代替案・採用方針を明確に記録していたため、実装方針で迷う点はなかった。

### Rework
- None.

## review retrospective

### Spec vs. implementation divergence patterns
- Nothing to note — review-light (4観点統合) の判定で Spec と PR diff の間に構造的な乖離は見られなかった。Implementation Steps 1〜3 通りの実装。

### Recurring issues
- Nothing to note — MUST/SHOULD/CONSIDER の指摘は0件。同種の指摘の繰り返しパターンは見られなかった。

### Acceptance criteria verification difficulty
- Nothing to note — Pre-merge AC 3件はすべて自動判定 (rubric 2件 PASS、command 1件は CI 参照フォールバック経由で PASS) で UNCERTAIN なく完結した。verify command / rubric 文言のいずれも過不足なく機能した。

## Phase Handoff
<!-- phase: merge -->

### Key Decisions
- pre-merge AC ゲート (`check-pre-merge-ac.sh`) は unchecked_count=0 で通過、review-incomplete-fallback チェックも該当なしのため、コンフリクトなしで直接 squash merge を実行した。
- `gh-pr-merge-status.sh` の mergeable=true (reason=clean, CI success, review approved) を確認済みで、リベース・コンフリクト解決フローは不要だった。

### Deferred Items
- Post-merge AC (`event=pr-review-light session=next`) は引き続き次回以降の Issue #476 `/verify` dispatch 時の自然発火待ち。merge フェーズでは検証不能 (設計通り継続)。

### Notes for Next Phase
- `/verify 1293` で post-merge 観測条件の成立を待つのみ。pre-merge AC 3件は全て PASS 済みでチェックボックス更新は完了している。

## Verify Retrospective

### Phase-by-Phase Review

#### issue

- **Issue タイトルが示唆する方式を実測で反証した**: 起票時のタイトルは「単語境界マッチに改善」だったが、`/issue` フェーズが `echo "--workflow=test.yml" | grep -qiw "workflow"` を実機で実行して一致することを確認し、単語境界マッチでは対象ケースが解消しないことを示した。`-` と `=` がいずれも非単語文字であるため境界条件を満たしてしまうという理由も、#1220 の Spec が既に指摘していた点として引用されている。これを `## Auto-Resolved Ambiguity Points` として Issue 本文に追記し、`/spec` が非解決策を実装するのを未然に防いだ
- **AC1/AC2 が outcome-based (rubric ベース) だったため、方式が変わっても AC の書き換えが不要だった**。#1220 と同じ方針で書かれていたことが効いている。タイトルが特定方式を示唆していても AC が手段を固定していなければ設計の再検討が阻害されない、という事例
- **Step 15 の AC 監査が AC3 の常時 PASS を検出した**: 当初 `command "bats tests/opportunistic-search.bats"` は既存 56 テストのみで常時 PASS だった。指摘は #1279/#1287 を同型例として引用しており、同一 batch で直前に着地した #1294 のサブパターンが機能した結果である

#### spec

- `/issue` の反証を受けて方式 (a) — #1220 のパス様トークン除去を CLI フラグ構文へ拡張 (`sed -E 's#--[A-Za-z0-9-]+=[A-Za-z0-9._-]+##g'`) — を採用。既存の除去パイプラインへの追加で完結しており、#1220 との一貫性が保たれている
- AC3 の常時 PASS 指摘を `bats --filter 'CLI flag token' tests/opportunistic-search.bats` へ絞り込んで解消した。これは #1294 が Pattern 2 の Fix options に記載した手段そのもの

#### code

- `modules/observation-trigger.md` 13 行・`scripts/opportunistic-search.sh` 33 行・`tests/opportunistic-search.bats` 23 行。rework ゼロ
- `modules/*.md` を変更しているが、追加行に含まれる `opportunistic-search.sh` への言及は既存の散文参照であり新規スクリプト呼び出しの追加ではない。したがって #1266 が拡張した allowed-tools impact chain check の Case 2 の前提 (新規呼び出しの追加) は成立せず、#1266 の post-merge 観察対象にも該当しない

#### review

- review-light の 4 観点すべてで指摘 0 件 (MUST: 0 / SHOULD: 0)。MUST 指摘がなかったため `REQUEST_CHANGES` は試行されず、#1256 の自己 PR 422 フォールバックは本 PR では発火していない

#### merge

- PR #1314 を squash merge。コンフリクト・CI 失敗なし

#### verify

- Pre-merge 3 件は既チェックのため skip、post-merge の observation 1 件は `pr-review-light` 未発火で SKIPPED。FAIL・UNCERTAIN ゼロ
- 実体を確認した: `bats --filter 'CLI flag token'` は実テスト 2 件にマッチし両方 PASS。うち 1 件は「CLI フラグと並んで散文にも keyword が出現する場合は除外しない」という偽陰性保護で、除去が効きすぎないことを担保している
- 誤検知の解消を直接検証した: `--workflow=test.yml` を除去処理に通すと keyword `workflow` の出現が 0 になる

### Improvement Proposals

- N/A — 本実行から新たに派生する構造的な改善点は検出されなかった。`/issue` による方式反証・AC 監査の常時 PASS 検出・`/spec` による `--filter` 絞り込みは、いずれも既存の機構 (#1220 の outcome-based AC 方針、#1294 の Pattern 2 サブパターン) が意図どおり機能した結果である
