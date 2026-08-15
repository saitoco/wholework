# Issue #1325: skill-dev-verify-audit: 検出力ゼロのテストを証明する AC を Pattern 2 で検出し #1130 の回帰テストを是正

## Consumed Comments

No new comments since last phase.

## Overview

`/verify 1130` の実測で、AC が「新規テストが追加されている」ことを正しく確認して PASS したにもかかわらず、追加されたテスト自体に検出力がなく回帰を捕まえられないケースが確認された。既存の `skills/triage/skill-dev-verify-audit.md` Pattern 2 のサブパターンはいずれもこれを被覆していない。

具体的には、#1130 で `scripts/validate-skill-syntax.py` の `INLINE_CODE_PATTERN` を単一バッククォート前提から後方参照パターンへ修正した際に追加された回帰テスト (`tests/validate-skill-syntax.bats`) が、修正前のコードに対しても PASS してしまう (検出力ゼロ) 状態のまま着地していた。本 Issue は (1) この回帰テスト自体を是正し、(2) 同種の欠陥を将来のAC監査 (`/triage` Step 7、`/issue` Step 15) で検出できるよう `skill-dev-verify-audit.md` の Pattern 2 に新規サブパターンを追加する。

## Reproduction Steps

1. `tests/validate-skill-syntax.bats` の `@test "success: double-backtick inline code with nested single backtick does not swallow surrounding content"` は、フィクスチャの verify コマンドに既知コマンド (`file_exists`) を使用している。このため、`INLINE_CODE_PATTERN` が単一バッククォート前提だった #1130 修正前のコミット (`10dc158d^`) に対して実行しても `0 error` で PASS してしまう。
2. 同じフィクスチャの verify コマンドを未知のコマンド名 (`totally_unknown_command`) に変えて #1130 修正前後で実行すると、修正前は `0 error`/`exit 0`、修正後は `1 error`/`exit 1` に分かれ、初めて検出力を持つ。Issue 本文の実測テーブルに加え、本 Spec 作成時に現行 (修正後) の `validate-skill-syntax.py` に対して同フィクスチャを実行し `exit 1` / `未知の verify コマンド 'totally_unknown_command'` を確認済み。

## Root Cause

`tests/validate-skill-syntax.bats` の回帰テストのフィクスチャが既知の verify コマンド (`file_exists`) を使用していたため、`validate_verify_commands()` が二重バッククォート span 直後の `<!-- verify: ... -->` コメントを検査対象として認識できているかどうかに関わらず、同じ `0 error` という出力に収束していた — コメントが誤って消失した場合は「検査対象なし → 0 error」、正しく残存した場合は「検証され有効なコマンドと判定 → 0 error」で、両者が区別できない。加えて `skills/triage/skill-dev-verify-audit.md` の Pattern 2 (常時 PASS サブパターン集) に、この「成果物は存在するが検出力を持たない」形の欠陥を捕捉するサブパターンが存在しなかったため、`/triage` Step 7 / `/issue` Step 15 の AC 監査でもこの種の AC を起票時点で指摘できなかった。

## Changed Files

- `tests/validate-skill-syntax.bats`: 二重バッククォート回帰テストのフィクスチャの verify コマンドを未知のコマンド名へ変更し、assert を反転 (`status -eq 1` + エラーメッセージ照合)。テスト名も新しい assertion 方向に合わせて変更
- `skills/triage/skill-dev-verify-audit.md`: Pattern 2 に「検出力ゼロの成果物を証明する AC」サブパターンを追加 (既存の「既存テストファイルの実行に起因する常時 PASS」サブパターンの直後、`section_contains`/`section_not_contains` 型サブパターンの直前に挿入)

## Implementation Steps

1. `tests/validate-skill-syntax.bats` の `# --- inline code (double backtick) validation ---` 見出し直下にある `@test "success: double-backtick inline code with nested single backtick does not swallow surrounding content"` を以下の通り変更する:
   - テスト名を `@test "error: unknown verify command adjacent to double-backtick inline code is not swallowed"` へ変更
   - フィクスチャ内の `<!-- verify: file_exists "path/to/file" -->` を `<!-- verify: totally_unknown_command "path/to/file" -->` へ変更 (二重バッククォート span・末尾の単一バッククォート参照はそのまま維持)
   - assert を `[ "$status" -eq 0 ]` / `[[ "$output" == *"0 error"* ]]` から `[ "$status" -eq 1 ]` / `[[ "$output" == *"未知の verify コマンド"* ]]` へ反転
   (→ acceptance criteria 1)
2. `skills/triage/skill-dev-verify-audit.md` の Pattern 2 内、「既存テストファイルの実行に起因する常時 PASS (`command` 型 AC)」サブパターンの Fix options 直後 (`section_contains`/`section_not_contains` 型サブパターンの直前) に新規サブパターンを挿入する。既存サブパターンと同じ構成 (太字見出し → 説明文 → 例 → Detection approach → Fix options) で以下を含める:
   - 見出し: `**検出力ゼロの成果物を証明する AC (新規テスト追加を主張する AC)**:`
   - 説明文: AC がテスト・回帰保護コードの新規追加を主張しており AC 本文の文言自体は字義通り満たされていても、追加されたテストが検出対象の欠陥に対して修正前後で同じ結果を返すケースがあること。既存テストファイルの実行に起因する常時 PASS」サブパターンとは異なり AC 自体は常時 PASS ではない (新規テストが実在する) 点を明記し、「検出力」という判別語を含める
   - 例: #1130 の `INLINE_CODE_PATTERN` 修正・回帰テストのフィクスチャ (`file_exists` → `totally_unknown_command` で検出力が生まれた実測) を実例として挙げ、#1325 を参照する
   - Detection approach: (a) AC がテスト・回帰保護コードの新規追加のみを主張しているか確認、(b) フィクスチャが欠陥に対して実際に感度を持つか検討 (可能なら修正前状態での FAIL を確認)、(c) 確認できない場合はフィクスチャが常に安全側の結果を返す既知の値のみを使い欠陥固有の分岐を経由していないか確認、(d) 判定が難しい場合は検出せず素通し
   - Fix options: フィクスチャに欠陥を再現する入力 (未知の値・異常系・境界値など) を含める、assert を欠陥固有の挙動への具体的照合へ変更する、の2つ以上
   (parallel with 1) (→ acceptance criteria 2)
3. `bats tests/validate-skill-syntax.bats` を実行し、全テストが PASS することを確認する (after 1) (→ acceptance criteria 3)

## Verification

### Pre-merge

- <!-- verify: rubric "tests/validate-skill-syntax.bats の二重バッククォート回帰テストの fixture が、二重バッククォート span の直後に置いた verify command を validator が実際に検査対象として認識することを assert している (例: 未知の verify コマンドを置きエラーが報告されることを確認する)。単に 0 error であることのみを assert する形になっていない" --> `tests/validate-skill-syntax.bats` の二重バッククォート回帰テストが、修正前の `INLINE_CODE_PATTERN` で実行した場合に FAIL する入力を使っている
- <!-- verify: grep "検出力" "skills/triage/skill-dev-verify-audit.md" --> `skills/triage/skill-dev-verify-audit.md` の Pattern 2 に、検出力ゼロの成果物を証明する AC のサブパターンが追加されている
- <!-- verify: command "bats tests/validate-skill-syntax.bats" --> `bats tests/validate-skill-syntax.bats` が PASS する

### Post-merge

- 以降の `/issue` Step 15 AC 監査で、「新規テストが追加されている」形の AC に対して検出力の確認を促す指摘が出ることを確認する<!-- verify-type: observation event=auto-run -->

## Notes

- **verify command の設計意図** (Issue 本文より転記): AC2 の `grep "検出力"` は実装前時点で `skills/triage/skill-dev-verify-audit.md` に 0 件であることを確認済み (常時 PASS 回避、本 Spec 作成時に再 grep して再確認済み)。AC3 の `command "bats tests/validate-skill-syntax.bats"` は既存グリーンスイートの実行にあたり、Pattern 2 の「既存テストファイルの実行に起因する常時 PASS」サブパターン (#1294) の対象パターンに本来該当するが、ここでは AC1 の rubric が検出力そのものを担保するため、AC3 は「是正後もスイート全体が壊れていないこと」の確認に限定した補助 AC と位置づける (同サブパターンの (d) 「回帰保護のみを主張する AC は検出対象外」という除外条件に合致する)。
- **挿入位置の判断根拠**: 新規サブパターンは「既存テストファイルの実行に起因する常時 PASS」サブパターン (#1294) と「AC がテストの新規追加を主張する」という表層を共有しつつ、常時 PASS ではなく検出力欠如という異なる欠陥層を扱う。Issue 本文の比較表がこの両者の違いを直接対比しているため、直後に隣接配置することで読み手が対比を追いやすくなる。
- **フィクスチャ反転の実測確認**: `.tmp/` にフィクスチャを再現し、現行 (修正後) の `validate-skill-syntax.py` に対して `totally_unknown_command` を用いると `exit 1` / 出力に `未知の verify コマンド 'totally_unknown_command'` を含むことを Spec 作成時に実行確認した (Issue 本文の実測テーブルと一致)。
- **既存の類似テストとの重複なし**: `tests/validate-skill-syntax.bats` には既に `@test "error: unknown verify command name is rejected"` という別テストが存在し、同じ「未知の verify コマンド」文言を単独ケースとして検証している。本 Issue の対象テストは二重バッククォート span との組み合わせ (comment-swallowing 特有の欠陥) を検証する点で目的が異なるため、重複ではない。
- **CI 検証 AC 非搭載**: Issue 本文の Pre-merge に CI ワークフロー確認 AC (`github_check`/`gh run list` 等) が含まれていないため、Verify command sync rule に従い Spec 側でも独自に追加していない。
- **訂正記録 (Issue 本文より転記)**: `/verify 1130` の実行中、本件を誤って `modules/verify-patterns.md` §9 と引用した (同 issue コメントおよび `docs/spec/issue-1130-validate-skill-syntax-backtick.md` の Verify Retrospective)。同ファイル §9 は "When to Use `rubric` vs hard-pattern" であり、常時 PASS の規約はそこには存在しない。正しい SSoT は `skills/triage/skill-dev-verify-audit.md` § Pattern 2 である。
- **Steering Docs sync candidate check**: `skill-dev-verify-audit.md` を参照する全ファイルを `grep -rln` で確認した。消費経路の `skills/triage/SKILL.md` Step 7 / `skills/issue/SKILL.md` Step 15 はいずれも「Read X and follow Processing Steps」形式の参照であり、サブパターン追加によるインターフェース変更は発生しないため変更不要。他に "Pattern 2" を参照するファイル (`skills/spec/codebase-search.md`、`modules/next-action-guide.md`、`skills/doc/SKILL.md`) はいずれも無関係な別概念の "Pattern 2" であることを確認済み。
- **SPEC_DEPTH=light (Size S) のため Step 7 (Ambiguity Resolution) / Step 8 (Uncertainty Identification) はスキップした。**
- **UI Design Phase 非該当**: 本 Issue はテストコード・Domain file の記述変更のみであり、UI 要素を含まない。
- **テストファイル対応**: `tests/validate-skill-syntax.bats` は既存ファイルの変更のみで新規ファイル追加はない。`skill-dev-verify-audit.md` は LLM が読む prose 形式の Domain file であり、対応する bats テストファイルは存在しない。挙動の検証は Post-merge の observation AC (次回 `/triage`/`/issue` 実行時の実観測) が担う。

## Related

- **#1130** — 検出力ゼロの回帰テストが着地した Issue (CLOSED)
- **#1315** — Pattern 2 の被覆表の出典。「充足不能 (定義矛盾)」サブパターン
- **#1294** — 「既存グリーンテスト」サブパターン。本件と層が異なる
- **#1310** — 「常時 UNCERTAIN」サブパターン
