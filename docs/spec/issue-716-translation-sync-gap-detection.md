# Issue #716: improvement: docs/ja/ 翻訳同期漏れの自動検出 (繰り返しパターン)

## Overview

`docs/` 配下の英語ファイルを変更した際に、対応する `docs/ja/` ミラーの同期漏れを自動検出する仕組みを実装する。
具体的には `scripts/check-translation-sync.sh` の出力に "Translation sync gap" warning を追加し、`/code` SKILL.md の同期チェックを passive な手順参照から能動的なギャップ検出に強化する。

## Changed Files

- `scripts/check-translation-sync.sh`: OUTDATED/MISSING_JA エントリに "Translation sync gap" warning 行を追加 (summary 行の後、stdout) — bash 3.2+ compatible
- `skills/code/SKILL.md`: Step 9 `docs/ja/` sync check を passive な手順参照から能動的なギャップ検出 + warning 出力 + 同期手順へ置き換え
- `tests/check-translation-sync.bats`: "Translation sync gap" 出力の bats テスト 2 件追加 (OUTDATED / MISSING_JA 各ケース)

## Implementation Steps

1. `scripts/check-translation-sync.sh` を修正し、OUTDATED/MISSING_JA を判定したループ内の `printf` 行の直後に warning 行を stdout に追加する (→ AC2)

   - OUTDATED の場合 (ループ内の `status="OUTDATED"` ブランチの `printf` の直後): `echo "Translation sync gap: $en_file was updated but $ja_file was not"`
   - MISSING_JA の場合 (ループ内の `status="MISSING_JA"` ブランチの `printf` の直後): `echo "Translation sync gap: $ja_file does not exist"`
   - 既存の `$en_file` / `$ja_file` 変数はループスコープ内にあるため、そのまま参照可能
   - bash 3.2+ 互換: `echo` を使用

2. `skills/code/SKILL.md` Step 9 の `docs/ja/` sync check を以下の形に置き換える (→ AC1)

   現在:
   ```
   **`docs/ja/` sync check:** If `docs/translation-workflow.md` exists, read it and follow the sync procedure.
   ```

   変更後:
   ```
   **`docs/ja/` sync check (gap detection + sync):** If `docs/translation-workflow.md` exists:
   1. Identify all `docs/*.md` and `docs/guide/*.md` files changed in this session (excluding `docs/ja/`, `docs/spec/`, `docs/stats/`, `docs/reports/`)
   2. For each changed file, check whether the corresponding `docs/ja/` counterpart was also updated in this session
   3. For any counterpart that was NOT updated: output "Translation sync gap: [en_file] was updated but docs/ja/[en_file_basename] was not" and then follow `docs/translation-workflow.md` sync procedure to update the missing counterpart
   4. After sync, optionally run `bash scripts/check-translation-sync.sh` to confirm IN_SYNC status (runs against committed state — only accurate after commit)
   ```

3. `tests/check-translation-sync.bats` に以下の 2 テストを追加する (→ AC3, regression guard)

   ```bash
   @test "outdated: Translation sync gap warning output for OUTDATED file" {
       # same setup as the existing "outdated" test
       echo "ja content" > docs/ja/en.md
       git add docs/ja/en.md
       GIT_COMMITTER_DATE="2024-01-01T10:00:00" GIT_AUTHOR_DATE="2024-01-01T10:00:00" \
           git commit -q -m "add ja"
       echo "en content" > docs/en.md
       git add docs/en.md
       GIT_COMMITTER_DATE="2024-01-02T10:00:00" GIT_AUTHOR_DATE="2024-01-02T10:00:00" \
           git commit -q -m "add en"
       run bash "$SCRIPT"
       [ "$status" -eq 0 ]
       [[ "$output" == *"Translation sync gap"* ]]
   }

   @test "missing_ja: Translation sync gap warning output for MISSING_JA file" {
       echo "en content" > docs/en.md
       git add docs/en.md
       GIT_COMMITTER_DATE="2024-01-01T10:00:00" GIT_AUTHOR_DATE="2024-01-01T10:00:00" \
           git commit -q -m "add en"
       run bash "$SCRIPT"
       [ "$status" -eq 0 ]
       [[ "$output" == *"Translation sync gap"* ]]
   }
   ```

## Verification

### Pre-merge

- <!-- verify: rubric "docs/ 配下の英語ファイル変更時に翻訳同期状態を自動チェックする機構が実装されている (scripts/, modules/, skills/ のいずれかに提案 1-4 のうち少なくとも一つが実装済み)" --> 上記提案 1-4 のうちいずれかが実装され、`docs/` の英語ファイル変更時に翻訳同期状態が自動チェックされる
- <!-- verify: rubric "翻訳同期漏れ検出時に 'Translation sync gap' または同等の内容を含む明確な warning メッセージが出力される仕組みが実装されている" --> 翻訳同期漏れが検出された際に明確な warning メッセージが出力される (例: "Translation sync gap: docs/X.md was updated but docs/ja/X.md was not")
- <!-- verify: github_check "gh pr checks" "Run bats tests" --> 既存テスト (`bats tests/*.bats`) が green

### Post-merge

- 次回 `docs/` 配下の英語ファイル変更を含む PR で、warning が期待通り発火することを確認 <!-- verify-type: opportunistic -->

## Notes

### Conflict with implementation (Proposal 1)

Issue 本文 Proposal 1 は "scripts/check-translation-sync.sh の新規追加" と記述しているが、このスクリプトは Issue #173 で既に実装済み。

Auto-resolution (non-interactive mode): Proposal 1 は既実装として扱い、Proposal 2 (code フェーズ warning 検出) を主実装とする。合わせてスクリプト自体に "Translation sync gap" 出力形式を追加することで Proposal 1 の不足部分 (warning format) を補完する。

### Auto-Resolve Log

- **Proposal 1 の既実装コンフリクト** — reason: `scripts/check-translation-sync.sh` は Issue #173 で実装済み。Proposal 2 (code フェーズ) + スクリプト warning 出力拡張を実装することで AC1/AC2 を満たす。
- **warning 出力先 (stdout vs stderr)** — reason: stdout に追加 (summary 行の後)。理由: 既存 bats テストが `$output` (stdout) を参照するため。stderr だと新規テストで `$stderr` を使う必要があり、既存テストとの一貫性が低下する。既存の `grep "IN_SYNC"` パイプチェーン (#585 等) への影響なし (warning 行は summary の後、独立行)。

### check-translation-sync.sh の動作特性

- git commit タイムスタンプ比較のため、未コミット変更は検出されない
- そのため `/code` Step 9 の gap detection は「git diff で変更ファイルを特定し counterpart の存在を確認する」という LLM 判断ベースの手法を採用
- `bash scripts/check-translation-sync.sh` によるコミット後確認を Implementation Step 2 の手順 4 として案内 (optional)

## issue retrospective

### Verify Command 追加 (AC 変更)

**変更内容**: pre-merge 受入条件 3 件に verify command を付与し、post-merge の非標準 `verify-type` タグを修正した。

### Auto-Resolve Log

- **`rubric` verify command を AC1・AC2 に付与** — reason: 実装アプローチが提案 1-4 から自由選択であり、対象ファイルパスを事前に特定できない。behavioral verification として `rubric` を選択 (approach-agnostic な検証が可能)。`file_contains`/`grep` は実装後に Spec で付与するのが適切。
  - Other candidates: `file_contains "scripts/check-translation-sync.sh" "Translation sync gap"` (提案 1 を前提とするため事前特定不可)

- **`github_check "gh pr checks" "Run bats tests"` を AC3 に付与** — reason: size 未設定だが、翻訳同期チェック機構の追加は M サイズ相当の改善 Issue と判断し PR ルートの verify command を選択。CI workflow は `test.yml` の "Run bats tests" ジョブが対象。
  - Other candidates: `command "bats tests/"` (CI 連携なし、UNCERTAIN になる可能性)

- **`<!-- verify-type: observation event=pr-review-light -->` → `<!-- verify-type: opportunistic -->`** — reason: `observation event=pr-review-light` は非標準形式 (有効値: `auto`/`opportunistic`/`manual`)。「次回の同種 PR で観察する」という性質は `opportunistic` に相当する。
  - Other candidates: `manual` (次回 PR の結果を人手確認するなら manual も妥当だが、/verify が自動的に観察できる状況なら opportunistic が適切)

## spec retrospective

### Minor observations

- `scripts/check-translation-sync.sh` は Issue #173 で既実装。Issue 本文 Proposal 1 の "新規追加" という記述は古い状態のため、/spec フェーズでのコンフリクト検出が実装上のアプローチ選択に貢献した。

### Judgment rationale

- **warning 出力位置 (ループ内 vs summary 後)**: ループ内で即時出力する方式を採用。変数スコープの自然な流れに沿い、後から収集する配列処理が不要で実装が簡潔。
- **stdout vs stderr**: bats テストが `$output` (stdout) を参照する既存パターンに合わせ stdout を選択。stderr にすると新テストで `$stderr` を使う必要があり不統一。
- **実装方針 (Proposal 2)**: check-translation-sync.sh は git commit タイムスタンプ比較のため未コミット変更を検知できない。/code SKILL.md では LLM 判断による変更ファイル特定 + counterpart チェックの手法が自然なアプローチ。

### Uncertainty resolution

- **check-translation-sync.sh の未コミット変更検知制限**: 設計上の特性として Notes に記録。/code Step 9 の gap detection は git diff ではなく LLM のセッション内変更把握に依存する方式とした。スクリプトによるコミット後確認は optional として案内。

## Phase Handoff
<!-- phase: spec -->

### Key Decisions

- Proposal 2 (code フェーズ gap detection) を主実装として採用。check-translation-sync.sh は既存スクリプトを拡張 (Proposal 1 の既実装コンフリクトを auto-resolve)。
- warning 行はループ内の `printf` 直後に stdout 出力 (stderr や summary 後収集ではない)。
- /code SKILL.md の変更は Step 9 の 1 段落を 4-step の能動的検出フローに置き換えるだけ (最小限)。

### Deferred Items

- `file_contains "scripts/check-translation-sync.sh" "Translation sync gap"` verify command は /code 実装後に Spec に追記可能 (現状は rubric で代替)。
- check-translation-sync.sh に `--filter <file>` オプションを追加する改善は本 Issue スコープ外 (既存の grep フィルタパターン #585 で代替可能)。

### Notes for Next Phase

- check-translation-sync.sh の変更は OUTDATED/MISSING_JA 判定ブランチ内の `printf` の直後に `echo` を追加するだけ。既存変数 `$en_file` / `$ja_file` をそのまま使用できる。
- /code SKILL.md の変更対象は `**\`docs/ja/\` sync check:**` で始まる 1 行を 4-step ブロックに置き換える。
- bats テスト 2 件は既存の outdated/missing_ja テストのセットアップを再利用できる (fixture コードの複製)。

## Consumed Comments

- T-Saito (OWNER) / first-class: Issue Retrospective (pre-cutoff) — rubric verify commands の自動付与、`verify-type: opportunistic` 修正。cutoff (2026-06-20T14:32:43Z) 以降の新規コメントなし。
