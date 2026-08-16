# Issue #1096: spec/code: 新規ロジック追加時に検証系テストの実効性を担保させる

## Overview

「常時 PASS になる検証を書かない」規律は Issue の AC には適用されているが、実装コードのテスト assert には適用されていない。同じ欠陥クラス (対象ファイルに既存の類似文字列があると常時 PASS してしまう assert) が AC からテストへ場所を変えて再発している (#1061 / PR #1090)。加えて、新規ロジックに対応する回帰テストがそもそも追加されないケースも観測されている (#1109)。

`/spec` と `/code` の両方に、検証系テストの実効性を担保する手順を追加する:

1. `/code`: 新規追加する検証系テストの assert (`grep` / `grep -q` / `file_contains` 相当) について、実装前の状態で FAIL することを確認する手順を追加し、常時 PASS のテストが merge されるのを防ぐ
2. `/spec`: Implementation Steps が既存スクリプト/モジュール/スキルへ新規の分岐ロジックを追加する場合、command 系 AC / Verification 項目で「既存スイートが PASS すること」だけでなく「新規ロジックを検証する新規テストケースを追加したうえでスイートが PASS すること」を明記させる

両者は同じガードの前半 (テストが無い) と後半 (テストがあっても効いていない) にあたるため、本 Issue で一体的に扱う。

## Changed Files

- `skills/code/SKILL.md`: Step 8 (Implement) の `#### Stale Test Assertion Check` サブセクション直後に、新規検証系テストの実装前 FAIL 確認サブセクションを追加
- `tests/code.bats`: 上記追加内容を検証する新規テストケースを追加
- `skills/spec/SKILL.md`: Step 10 (Create Spec) の「Verification conditions vs. Issue body acceptance criteria consistency check」直後、「BRE metacharacter detection in verify commands」の前に、新規ロジック追加時の新規テストケース明記チェックを追加
- `tests/spec.bats`: 上記追加内容を検証する新規テストケースを追加

Steering Docs sync candidate check (grep -rn による横断検索) を実施済み: 「実装前 FAIL」「常時 PASS」「Stale Test Assertion」「回帰テスト」「新規テストケース」等のキーワードで `docs/` `tests/` `scripts/` `modules/` を検索したが、`docs/spec/` 配下の過去 Spec (履歴記録、対象外) 以外に追加の sync candidate は見つからなかった。`skill-dev-doc-impact.md` の Change Type ("Skill addition, change, or deletion") は該当しうるが、既存の類似変更 (Stale Test Assertion Check 自体や Step 10 内の多数のサブチェック追加) が `docs/workflow.md` / `README.md` / `CLAUDE.md` を一切更新していない先例と整合するため、今回もドキュメント同期は不要と判断した。

## Implementation Steps

1. `skills/code/SKILL.md` の Step 8 (`#### Stale Test Assertion Check` サブセクションの直後) に、新しいサブセクション `#### New Verification-Test Pre-implementation FAIL Check` を追加する (→ 検証項目 1, 2)。内容:
   - **対象の識別**: 今回の実装で新規追加したテストのうち、対象ファイルの内容を文字列で検証するもの (`grep` / `grep -q` / `file_contains` 相当の assert) を対象とする。プロセス出力や終了コードを検証する assert は対象外と明記する。
   - **実装前 FAIL の確認**: 対象の assert ごとに、実装対象ファイルを一時的に実装前の状態へ戻し (例: `git stash push -- <実装対象ファイル>`)、新規テストを実行して FAIL することを確認する。確認後は `git stash pop` で復元する。
   - **PASS してしまった場合の対処**: 意図せず PASS した場合は、対象ファイルに既存の類似文字列がありパターンが非固有と判断し、より固有の文字列への変更、またはスコープ限定 (`tests/code.bats` の `step0_section` のような既存の節単位抽出パターンの再利用を含む) へ修正し、再度 FAIL を確認する。
   - **確認結果の記録**: `## Code Retrospective` (Step 12) に「新規テスト N 件について実装前 FAIL を確認済み」の形式で記録する。
2. (after 1) `tests/code.bats` に、Step 1 で追加したサブセクションの内容を検証する新規テストケースを追加する (→ 検証項目 3)。既存の `grep -q 'KEYWORD' "$SKILL_FILE"` 形式に倣い、少なくとも次を検証する: (a) 新セクション見出しの存在、(b) 対象識別 (`file_contains`-equivalent 等) の記述、(c) PASS してしまった場合の対処記述、(d) Code Retrospective への記録形式の記述。
3. (parallel with 1, 2) `skills/spec/SKILL.md` の Step 10、「Verification conditions vs. Issue body acceptance criteria consistency check」直後・「BRE metacharacter detection in verify commands」前に、新しいサブセクション `**New test case requirement for new branch logic (regardless of SPEC_DEPTH):**` を追加する (→ 検証項目 4, 5)。内容:
   - **対象の識別**: `## Implementation Steps` の各項目が、既存スクリプト/モジュール/スキルへ新規の分岐ロジック (条件分岐、新規ケース、新規イベント種別など) を追加するかを識別する。
   - **新規テストケースの明記**: 該当する Implementation Step に対応する command 系 AC / Verification 項目 (例: `command "bats tests/xxx.bats"`) について、「既存スイートが PASS すること」だけでなく「新規ロジックを検証する新規テストケース (tests/xxx.bats に <new-case-name>) を追加したうえでスイートが PASS すること」を Implementation Steps または AC に明記することを求める、という要求文言を含める (この例文の「新規テストケース」という日本語表現によって検証項目 5 の `file_contains` を満たす — SKILL.md 本文中で Notes/条件文の日本語引用例を示す既存パターン (例: skills/code/SKILL.md の出力メッセージ例、skills/spec/SKILL.md の Notes 記載例) と同様の扱い)。
   - **確認結果の記録**: `SPEC_DEPTH=full` の場合は Step 13 の `## spec retrospective` に、要求した新規テストケースの概要を記録する。`SPEC_DEPTH=light` の場合は Step 13 自体がスキップされるため、代わりに Spec の `## Notes` セクションに同じ概要を記録する旨を明記する。
   - **Skip 条件**: Implementation Steps が既存ファイルへ新規の分岐ロジックを追加しない場合 (既存動作の変更のみ、ドキュメントのみの変更など) はこのチェックをスキップする旨を明記する。
   - この新規チェックは「Stale Test Assertion Check」(削除されたリテラル文字列の残存確認) や「Tag/enum semantic extension consumer sweep」(既存 tag/enum の意味論拡張時の consumer 再検証) とは目的が異なる (新規追加テストの要求) ことが分かるよう、書き分ける。
4. (after 3) `tests/spec.bats` に、Step 3 で追加したサブセクションの内容を検証する新規テストケースを追加する (→ 検証項目 6)。既存の `grep -q 'KEYWORD' "$SKILL_FILE"` 形式に倣い、少なくとも次を検証する: (a) 新セクション見出しの存在、(b) SPEC_DEPTH=light 時に Notes セクションへ記録する旨の記述。

## Verification

### Pre-merge

- <!-- verify: rubric "skills/code/SKILL.md に、新規追加する検証系テストの assert が実装前の状態で FAIL することを確認する手順が追加されている。対象となる assert の種類 (文字列マッチ系) が識別できる形で示されている" --> `/code` 側: 実装前 FAIL 確認の手順が追加されている
- <!-- verify: rubric "実装前 FAIL 確認で PASS してしまった場合の対処 (より固有の文字列への変更、節単位へのスコープ限定など) が具体的に示されている" --> `/code` 側: 常時 PASS が判明した場合の対処が示されている
- <!-- verify: command "bats tests/code.bats" --> `tests/code.bats` が PASS する
- <!-- verify: rubric "skills/spec/SKILL.md に、Implementation Steps が既存スクリプト/モジュール/スキルへ新規の分岐ロジックを追加する Issue で、command 系 AC / Verification 項目を書く際、『既存スイートが PASS すること』だけでなく『新規ロジックを検証する新規テストケースを追加したうえでスイートが PASS すること』を明記させる手順が追加されている" --> `/spec` 側: 新規ロジック追加時に新規テストケースの明記を求める手順が追加されている
- <!-- verify: file_contains "skills/spec/SKILL.md" "新規テストケース" --> `/spec` 側の手順に「新規テストケース」の明記要求が含まれている (rubric の補助的機械チェック)
- <!-- verify: command "bats tests/spec.bats" --> `tests/spec.bats` が PASS する

### Post-merge

- 新規ロジックの追加を伴う Issue を `/spec` → `/code` に通し、(a) `/spec` が新規テストケースの追加を Implementation Steps / AC に明記し、(b) `/code` が実装前 FAIL の確認を実施し Code Retrospective に記録することを確認する <!-- verify-type: manual -->

## Notes

- **Simplicity Rule (Pre-merge Verification 件数) の超過について**: Issue 本文の Pre-merge AC は 6 件で、light テンプレートの上限 (5 件) を超過している。SKILL.md の「Verify command sync rule」は Issue 本文の `<!-- verify: ... -->` を verbatim でコピーすることを義務付けており、個々の AC は `/code` 側 3 件 + `/spec` 側 3 件で意味的にも独立しているため統合できない。Verify command sync rule を優先し、6 件のまま維持した (non-interactive mode の auto-resolve 方針に基づく判断)。Implementation Steps は 4 件に収め、Simplicity Rule の light 上限 (5 件) 内に収まっている。
- **Post-merge AC の `verify-type: manual` 維持について**: 「新規ロジック追加を伴う次の Issue が `/spec` → `/code` を通ること」を確認する条件であり、対象 Issue が不定 (将来の任意の Issue) のため `file_exists` / `file_contains` / `http_status` / `rubric` のいずれにも機械的に置き換えられない。`modules/verify-classifier.md` の分類基準に照らし `manual` を維持する。
- **`Stale Test Assertion Check` との違い**: 既存の `skills/code/stale-test-check.md` (Stale Test Assertion Check) は「削除されたリテラル文字列がテストに残存していないか」を確認するもので、目的は本 Issue の「新規追加テストが実装前に FAIL するか」の確認と異なる (削除 vs. 新規追加)。両者を混同しないよう、Implementation Steps では明確に書き分ける。
- **`/issue` 側で自己適用済みの判断**: 本 Issue 自体は「既存スクリプト/モジュール/スキルへ新規の分岐ロジックを追加する」Issue に該当する。したがって、本 Spec 自身も Issue #1096 が要求する新ルールを先取りして適用し、`tests/code.bats` / `tests/spec.bats` への新規テストケース追加を Implementation Steps 2, 4 に明記した (Changed Files に両ファイルを含めた形で Issue Retrospective 時点で既に想定されていた設計との整合)。
- **Domain file 確認**: `skills/spec/*.md` のバンドル Domain file のうち、`skill-dev-constraints.md` (`load_when: spec_depth: full`) は SPEC_DEPTH=light のため非ロード。`visual-diff-guidance.md` / `visual-state-enumeration.md` (`load_when: capability: visual-diff`) は `.wholework.yml` に `capabilities.visual-diff` が未設定のため非ロード。`external-spec.md` / `figma-design-phase.md` は無条件ロード対象だが、本 Issue は外部コマンド仕様確認・UI 要素のいずれにも該当せず、内容の適用はなし。project-local Domain file (`.wholework/domains/spec/`) は存在しない。
- **Auto-Resolve Log (SPEC_DEPTH=light につき Step 7 は本来スキップだが、非対話モード全体方針に基づき記録)**: `/spec` 側の新セクションが要求する「Spec Retrospective への概要記録」は、Issue 本文が SPEC_DEPTH=full の Step 13 を前提に書かれているが、SPEC_DEPTH=light では Step 13 自体がスキップされ `## spec retrospective` セクションを持たない。Implementation Step 3 で「light の場合は Notes セクションで代替する」という分岐を明示することで解決した。
- **コンフリクト検出**: `skills/code/SKILL.md` には既に類似目的に見える `Stale Test Assertion Check` が存在したため精査した。目的が「削除文字列の残存確認」対「新規追加テストの実効性確認」で異なると判断し、別サブセクションとして追加する設計にした (統合は不採用: 対象の識別ロジックとタイミング (削除時 vs. 新規追加時) が異なり、統合すると条件分岐が複雑化するため)。
- **常時 PASS でないことの実行確認**: `grep -c "新規テストケース" skills/spec/SKILL.md`、`grep -c "New Verification-Test Pre-implementation FAIL Check" skills/code/SKILL.md`、`grep -c "New test case requirement for new branch logic" skills/spec/SKILL.md` をいずれも実装前の状態で実行し、0 件であることを確認済み。対応する `tests/code.bats` / `tests/spec.bats` の新規テストケース (Implementation Steps 2, 4) も同じ理由で実装前 FAIL が保証される。
