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

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- Spec の Implementation Steps をそのまま実装。`resolve_filtered_context()` に2つ目の `sed -E` 式 (`--[A-Za-z0-9-]+=[A-Za-z0-9._-]+`) を追加し、パス様トークン除去と同じキャッシュ済み1回のフィルタリングパスで CLI フラグ構文も除去する構成にした。
- Behavioral Change Detection がヒット (`tests/check-known-events-firing.bats` が `scripts/opportunistic-search.sh` を直接対応テスト外で参照) したため、`bats --jobs 18 tests/` でフルスイート (1654件) を実行し全件 PASS を確認した。

### Deferred Items
- Post-merge AC (`event=pr-review-light session=next` の観測) は本 PR の対象外。次回以降 Issue #476 の `/verify` dispatch 時に自然発火を待つ。

### Notes for Next Phase
- Pre-merge AC 3件は本フェーズ内で verify-executor full mode により PASS 確認済み、Issue #1293 のチェックボックスも更新済み。
- 追加した2件の bats テスト名には `CLI flag token` という一意な部分文字列を含めてあるため、`bats --filter 'CLI flag token' tests/opportunistic-search.bats` が引き続き有効。
