# Issue #765: check-forbidden-expressions: false positive パターンを修正して CI シグナル品質を改善

## Overview

`scripts/check-forbidden-expressions.sh` が `\bIssue Spec\b` パターンで 3 種類の false positive を検出し CI が exit 1 を返し続けている。根本原因に対処して `bash scripts/check-forbidden-expressions.sh` が exit 0 を返すようにする。

## Consumed Comments

- saito / MEMBER / first-class / Issue Retrospective (root cause 3 パターン特定・verify command 修正・方針決定) / https://github.com/saitoco/wholework/issues/765#issuecomment-4816167963

## Reproduction Steps

1. `bash scripts/check-forbidden-expressions.sh` を実行
2. Exit code 1 が返る (false positive 3 件)
   - `docs/spec/issue-761-*.md`: バッククォートで囲まれた `` `Issue Spec` `` (Pattern 3)
   - `docs/sessions/*/session.md`: auto-generated log が `Issue Spec` をメタ参照 (Pattern 2)
   - `docs/reports/auto-session-*.md`: `per-Issue Spec` 複合語 (Pattern 1 + Pattern 2)

## Root Cause

**Pattern 1**: ERE の `\b` はハイフン (`-`) の後に単語文字が続く場合もマッチする。`per-Issue Spec` の `-I` 間に `\b` がマッチし `Issue Spec` が検出される。

**Pattern 2**: `SCAN_DIRS` に `docs/` が含まれており、自動生成ログ (`docs/sessions/`, `docs/reports/`) が deprecated term をメタ参照しても検出されてしまう。

**Pattern 3**: バッククォート `` ` `` は非単語文字なので `\bIssue Spec\b` がマッチする。`docs/spec/` の retrospective テキストが `` `Issue Spec` `` とバッククォートで言及する場合に検出される。

**Fix approach (組み合わせ)**:
- Pattern 2: `check_term` の grep パイプラインに `grep -v '^docs/sessions/'` と `grep -v '^docs/reports/'` を追加 (auto-generated はスキャン対象外)
- Pattern 1 + 3: `check_term` に 4 番目オプション引数 `extra_grep_v` を追加し、`Issue Spec` ケースに `'[-\`]Issue Spec'` (hyphen または backtick 先行) の追加除外を渡す

## Changed Files

- `scripts/check-forbidden-expressions.sh`: `check_term` に `grep -v '^docs/sessions/'` / `grep -v '^docs/reports/'` を追加; 4 番目引数 `extra_grep_v` (オプション) を追加し `Issue Spec` ケースに `-\`]Issue Spec` 除外を渡す — bash 3.2+ 対応
- `tests/check-forbidden-expressions.bats`: Pattern 1/2/3 の false positive 防止テスト 4 件追加

## Implementation Steps

1. **`scripts/check-forbidden-expressions.sh` の `check_term` 関数を修正** (→ AC1)

   - 4 番目引数 `extra_grep_v="${4:-}"` を追加
   - grep パイプラインに `| grep -v '^docs/sessions/'` と `| grep -v '^docs/reports/'` を追加 (全 term に適用)
   - 関数末尾: `if [ -n "$extra_grep_v" ] && [ -n "$result" ]; then result=$(printf '%s\n' "$result" | grep -v -- "$extra_grep_v" || true); fi` を追加

2. **`Issue Spec` ケースに追加除外を渡す** (→ AC1, AC2)

   `case "$TERM"` の `Issue Spec` ブロックを変更:
   ```
   check_term "$TERM" "-rE" '\bIssue Spec\b' '[-`]Issue Spec'  # 旧称: deprecated term pattern
   ```
   - `[-` `` ` `` `]Issue Spec` (BRE character class) がハイフン先行 (`per-Issue Spec`) とバッククォート先行 (`` `Issue Spec`` ) を除外

3. **`tests/check-forbidden-expressions.bats` にテスト追加** (→ AC3)

   以下 4 件の `@test` を追加 (既存テストの後):
   - `"false positive: Issue Spec in docs/sessions is not flagged"` — `docs/sessions/some-session/session.md` に `Issue Spec` を書いて exit 0 を確認
   - `"false positive: Issue Spec in docs/reports is not flagged"` — `docs/reports/report.md` に `per-Issue Spec` を書いて exit 0 を確認
   - `"false positive: hyphen-preceded Issue Spec in skills is not flagged"` — `skills/note.md` に `per-Issue Spec tracking` を書いて exit 0 を確認
   - `"false positive: backtick-quoted Issue Spec in docs/spec is not flagged"` — `docs/spec/note.md` に `` `Issue Spec` `` を書いて exit 0 を確認

## Verification

### Pre-merge

- <!-- verify: rubric "scripts/check-forbidden-expressions.sh が修正され、per-Issue Spec (ハイフン後に大文字 Issue が続く複合語) が false positive として検出されなくなっている。または docs/sessions/ / docs/reports/ がスキャン対象から除外されている。または類似の対処が行われている" --> false positive の根本原因が修正されている
- <!-- verify: command "bash scripts/check-forbidden-expressions.sh" --> `bash scripts/check-forbidden-expressions.sh` が exit 0 (現在の false positive が全件解消)
- <!-- verify: rubric "tests/check-forbidden-expressions.bats に、per-Issue Spec (ハイフン後の大文字 Issue Spec) または docs/sessions/ / docs/reports/ 除外等の修正内容に対応した false positive 防止テストが追加されている" --> 修正内容に対応した bats テストが追加されている

### Post-merge

- 次回 PR で `per-Issue Spec` 等の正当な記述が commit に含まれた際、Forbidden Expressions check が PASS することを観察

## Notes

- `[-` `` ` `` `]Issue Spec` は BRE character class (旧称: deprecated term exclusion pattern)。クラス先頭の `-` はリテラル (範囲指定なし) 。macOS BSD grep / GNU grep 両対応
- `extra_grep_v` が空の場合 (`[ -n "$extra_grep_v" ]` 判定) は追加 grep -v をスキップし、既存の全 term の動作に影響なし
- `docs/sessions/` と `docs/reports/` 除外は全 DEPRECATED_TERMS に適用される (これらは常に auto-generated のためスキャン不要)
- bats テストの `docs/sessions/` や `docs/reports/` は `setup()` では作られないため、各テスト内で `mkdir -p` が必要
- `tests/check-forbidden-expressions.bats` は `grep -v 'tests/check-forbidden-expressions.bats'` で除外済みのため、テストコード内の `per-Issue Spec` / `` `Issue Spec` `` 文字列リテラルは自己参照を起こさない
