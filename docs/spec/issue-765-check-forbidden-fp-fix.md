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

## Code Retrospective

### Deviations from Design
- Spec で示されていなかった問題: Spec ファイル自体 (`docs/spec/issue-765-*.md`) が deprecated term を直接引用していることで CI false positive が追加発生した。Spec の関連行を backtick 化 (extra_grep_v で除外可能な形式) または `旧称:` 追加で対処した。Implementation Steps には記載がなかった作業だが、AC の `bash scripts/check-forbidden-expressions.sh` exit 0 を満たすために必須だった。

### Design Gaps/Ambiguities
- Spec 自身が deprecated term を引用する場合の対処が Spec 設計時に考慮されていなかった。tech.md の "Spec Retrospective: quoting deprecated terms" ガイダンスは retrospective セクションのみを対象としており、Spec 本文の技術的引用については明示的なルールがなかった。
- `extra_grep_v` のフィルタ対象は grep 出力行全体 (`filepath:content`) であるため、行内のどこかに `-Issue Spec` or `` `Issue Spec`` が含まれれば除外される。Spec Notes のある行が `per-Issue Spec` を含むため extra_grep_v で除外されることを確認した (ライン 50 の例)。

### Rework
- Spec ファイル内の 4 箇所を修正: `"Issue Spec"` → `` `Issue Spec` `` への変換 2 件、コードブロック行への `# 旧称` コメント追加 1 件、Notes 行への `(旧称: deprecated term exclusion pattern)` 追記 1 件。実装ステップ自体の変更はなく Spec 本文の cleanup のみ。

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- Pattern 2 (docs/sessions/ / docs/reports/): `check_term` grep パイプラインに固定除外 `grep -v '^docs/sessions/'` / `grep -v '^docs/reports/'` を追加した (全 term に適用)
- Pattern 1 + 3 (hyphen/backtick 先行): `extra_grep_v` 引数 (第 4 引数) を `check_term` に追加し `Issue Spec` ケースのみ `'[-\`]Issue Spec'` を渡す設計を採用した
- Spec ファイルの自己参照問題: backtick 変換 + `旧称` コメント追加で対処した

### Deferred Items
- Pattern 1 (hyphen-preceded) + Pattern 3 (backtick-quoted) の除外は `extra_grep_v` で実装済み。他の deprecated term への `extra_grep_v` 適用は現時点で不要 (false positive は `Issue Spec` のみ確認済み)
- Post-merge で `per-Issue Spec` 等が含む commit が CI PASS することの確認は手動 AC (verify-type: manual) として残す

### Notes for Next Phase
- `/verify` では pre-merge AC 3 件すべて PASS 済み (`bash scripts/check-forbidden-expressions.sh` exit 0 / bats 19 tests OK / rubric 確認済み)
- post-merge AC: 次回 PR で hyphen-preceded `Issue Spec` が含まれた際に CI PASS することを確認する
- 実装はシンプル (スクリプト修正 + テスト追加 + Spec cleanup の 3 ファイルのみ) で副作用リスクは低い

## Verify Retrospective

### Phase-by-Phase Review

#### issue
- `/issue 765` refinement 段階で当初診断 (「単語境界がない」) が誤りであることを確認し、実際の false positive を 3 パターン (per-Issue Spec / docs/sessions/ / docs/reports/) に特定したのが大きい。Background を正しく差し替えたうえで Implementation Steps に進めた。

#### spec
- Root Cause セクションを設けて 3 パターンを明示し、Implementation Steps を結果ベース (exit 0 + テスト追加) に固定したのは設計判断として妥当。
- 「Spec 本文が deprecated term を引用する場合の取り扱い」を考慮しなかった点が gap。本来 Spec 段階で予見すべきだったが、code phase で追加対応が発生した。

#### code
- 想定外の作業: Spec ファイル自体が deprecated term を引用して新たな false positive を生み、これを backtick 化 + `旧称:` コメントで対処。AC2 (`bash scripts/check-forbidden-expressions.sh` exit 0) を満たすために必須だった。
- 1 発で全テスト PASS。`extra_grep_v` (第 4 引数) パターンの導入で他 term への拡張余地も確保。

#### review/merge
- patch route のため review/merge は実行されず (XS/S patch では main 直コミット)。

#### verify
- 3 件すべて PASS、UNCERTAIN ゼロ。AC2 の `command` verify command が full mode で実行され、修正の最終確認として機能した。

### Improvement Proposals

- **tech.md / Spec ガイダンス拡張**: 「Spec 本文 (Implementation Steps、Reproduction Steps 等) で deprecated term を引用する場合は必ずバッククォートで囲む、または `extra_grep_v` 対応の形式 (`旧称:` 付き) を使う」というルールを `tech.md` の Forbidden Expressions セクション、または `skills/spec/SKILL.md` のガイダンスに追加する。
  - 動機: 本 Issue で Spec ファイル自身が CI false positive を新たに生み、code phase で予定外の追加作業 (4 箇所修正) が発生した。同パターンは今後も deprecated term を扱う Issue で再発しうる。
  - Tier 2 (convention): Skill 自体の動作変更ではなく運用ルールの明文化。新規 Issue 起票せず memory として記録するのが妥当。
- **Spec retrospective 自動チェック (将来構想)**: Spec 作成時に `check-forbidden-expressions.sh` を `--include-spec` モードで実行できるようにし、deprecated term 引用の警告を Spec 段階で出す。Tier 3 (one-time memo) — 現時点では起票しない、convention 普及後に再評価。
