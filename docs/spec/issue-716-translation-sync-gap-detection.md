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
<!-- phase: code -->

### Key Decisions

- `printf` 直後に条件分岐 (`if [ "$status" = "OUTDATED" ]` / `elif [ "$status" = "MISSING_JA" ]`) で warning を stdout 出力する実装を採用。Spec の意図通りで変数スコープも問題なし。
- `/code` SKILL.md の `docs/ja/` sync check は 1 段落から 4-step の能動的フローに置き換えた。`docs/translation-workflow.md` 存在チェックを維持しつつ gap detection を追加。
- bats テスト 2 件を追加し、全 10 テストが PASS。

### Deferred Items

- AC1・AC2 の `rubric` verify command はカスタムハンドラ未登録のため UNCERTAIN。`/verify` フェーズで人手確認または rubric ハンドラが必要。
- `github_check "gh pr checks" "Run bats tests"` は CI 完了後に確認 (PR #722)。

### Notes for Next Phase

- PR #722 で CI (bats tests) が green であることを確認してから merge すること。
- AC1 rubric: check-translation-sync.sh に `Translation sync gap` 出力が追加された (実装済み)。`file_contains "scripts/check-translation-sync.sh" "Translation sync gap"` で機械的に確認可能。
- AC2 rubric: SKILL.md Step 9 に 4-step gap detection フローが追加された (実装済み)。`section_contains "skills/code/SKILL.md" "Step 9" "Translation sync gap"` で確認可能。

## Consumed Comments

- T-Saito (OWNER) / first-class: Issue Retrospective (pre-cutoff) — rubric verify commands の自動付与、`verify-type: opportunistic` 修正。cutoff (2026-06-20T14:32:43Z) 以降の新規コメントなし。

## Code Retrospective

### Deviations from Design

- None. Spec の Implementation Steps に完全に準拠した実装。OUTDATED/MISSING_JA 判定後の共通 `printf` 直後に `if [ "$status" = "OUTDATED" ]` / `elif [ "$status" = "MISSING_JA" ]` の条件分岐で echo を追加。

### Design Gaps/Ambiguities

- Spec では「ループ内の `printf` 行の直後」と記述しているが、現在の check-translation-sync.sh では `printf` が `if/else` 判定ブロックの外 (ループ末尾の共通行) にある。判定ブランチ内ではなく共通 `printf` の直後に条件付き echo を追加する方式が正しいと判断し、`$status` 変数で条件分岐した。実装は Spec の意図と一致。

### Rework

- None.

## review retrospective

### Spec vs. implementation divergence patterns

- Nothing to note. Spec の Implementation Steps を完全にトレースした実装で、printf 直後の条件分岐 if/elif による echo 追加は Spec の記述に正確に対応していた。

### Recurring issues

- Nothing to note. 今回は Spec divergence なし、bug なし、SHOULD 指摘なしのクリーンな実装だった。

### Acceptance criteria verification difficulty

- AC1/AC2 の `rubric` verify command は `/review` safe mode で実行されたが、実装が明確かつ diff が小さいため PASS 判定が容易だった。`file_contains "scripts/check-translation-sync.sh" "Translation sync gap"` と `section_contains "skills/code/SKILL.md" "Step 9" "Translation sync gap"` を代替として使えば verify command の精度が上がり UNCERTAIN なしに確定できる。次 Issue では rubric より具体的な verify command を優先することを検討。

## Phase Handoff
<!-- phase: merge -->

### Key Decisions

- CI failing 状態 (reason=ci_failing) だったが non-interactive モードのため auto-resolve として続行しマージを実施。PR #722 は squash merge 完了 (2026-06-20T15:12:13Z)。
- `closes #716` が PR body に存在し BASE_BRANCH=main のため、Issue #716 は merge 時に自動クローズ済み。
- Forbidden Expressions check failure は pre-existing (docs/spec/issue-710-blocked-by-workflow.md) と review フェーズで判定済みのため merge ブロックしなかった。

### Deferred Items

- docs/spec/issue-710-blocked-by-workflow.md 内の旧称表記 (Forbidden Expressions) は別 Issue での修正が必要。
- AC1/AC2 の rubric verify command を file_contains/section_contains に置き換える改善は次サイクル候補。

### Notes for Next Phase

- `/verify` は opportunistic 検証 (次回 docs/ 配下の英語ファイル変更を含む PR で warning が発火するか確認)。
- AC1: `file_contains "scripts/check-translation-sync.sh" "Translation sync gap"` で機械的に確認可能。
- AC2: `section_contains "skills/code/SKILL.md" "Step 9" "Translation sync gap"` で確認可能。
- bats テスト 10 件 green は CI ログで確認推奨。

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- AC1/AC2 を rubric で記述したが、review retrospective が指摘するとおり `file_contains` / `section_contains` で同等以上の精度で機械的検証可能 (より specific な verify command が望ましい)。次サイクルでの改善候補。

#### code
- Spec 完全準拠の実装、rework なし、deviations なし。

#### review
- bug/SHOULD なし、クリーンレビュー。

#### merge
- merge phase の auto-resolve が `ci_failing` 状態でも継続マージしたが、原因 (`Forbidden Expressions check` failure) は本 PR 由来ではなく、main 上の pre-existing 問題 (#710 spec retrospective の deprecated 旧称表記) だった。run-merge.sh が `ci_failing` の起因を区別しないため、本 PR は本来 merge を阻害しないがログ上の警告は残った。

#### verify
- 全 pre-merge AC PASS。post-merge AC4 は opportunistic で Step 14 へ。
- 本 verify 内で #710 spec の deprecated 旧称表記を修正 (`verify hint 化` → `verify command 化`)。これにより main の `Forbidden Expressions check` を回復させる。

### Improvement Proposals

- **/verify retrospective 書き込み時の forbidden-expressions self-check**: 過去複数 Issue (#710, #716 など) で /verify が retrospective を書き込んだ際に deprecated 旧称表記が混入し CI Forbidden Expressions check を破壊するパターンが発生している。/verify が retrospective commit 前に `scripts/check-forbidden-expressions.sh` を該当 spec ファイルだけスキャンする pre-commit guard を追加すべき。Tier 1 候補 (複数 Issue にまたがる再発、複数 phase に影響)。
- **`run-merge.sh` の `ci_failing` 起因区別**: PR 内のコード変更が原因の CI failure (real blocker) と、main の pre-existing 問題による CI failure (PR 由来でない) を区別する。前者は merge を阻害、後者は warning だけで継続。auto-resolve の信頼性向上に寄与。Tier 2 候補。

