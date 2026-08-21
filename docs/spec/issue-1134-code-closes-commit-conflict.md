# Issue #1134: code: Step 8 の粒度別コミットと Step 11 の closes-commit 要件の衝突を明文化

## Overview

`skills/code/SKILL.md` の Step 8 (粒度別コミット規約) と Step 11 (`closes #N` 付き最終コミット規約) は、patch route で衝突しうる。Step 8 の指示どおり Implementation Steps を都度コミットすると、Step 11 到達時点で working tree がクリーンになり、`closes #N` を付与すべき新規差分が残らない。`closes #N` は GitHub 自動クローズ用キーワードであると同時に `scripts/reconcile-phase-state.sh` の `_completion_code_patch()` が完了判定に使う一級シグナルであり、付与漏れは実装済みの Issue を silent no-op と誤判定させる (#1106, #1226 で実測)。

本 Spec は Issue 本文が提示した 3 案 (A: 最小変更の amend/空コミット運用、B: Step 8 側で最終ステップのコミットを Step 11 に委ねる構造的変更、C: Issue コメント marker 化) のうち、**B (構造的) を主, A (安全弁) を従とするハイブリッド**を採用する:

- **patch route の Step 8** は、最終 Implementation Step の差分をコミットせず Step 11 に持ち越す。これにより Step 11 は原則として常に新規差分を持ち、`closes #N` の付与先を機械的に確保できる (案 B)。
- それでも Step 11 到達時点で working tree がクリーンな残余ケース (`spec-approval-needed` による最終ステップの deferral、再開セッションでの二重コミット等) に備え、Step 11 に **push 前後で挙動を分ける fallback** (未 push なら `--amend`、push 済みなら空コミット) を追加する (案 A)。

**pr route はスコープ外**: pr route の Step 11 は要約コミットを作らず (`git push origin HEAD` → `gh pr create` のみ)、`closes #N` は PR body 側に書かれるためこの衝突は発生しない。Step 8 の「最終ステップのコミットを委ねる」変更を pr route にも適用すると、Step 11 側に受け皿がないため当該差分が未コミットのまま放置される回帰を生む。そのため Step 8 の変更は **patch route 限定**とし、pr route は現行どおり全ステップをその場でコミットする。

案 C (Issue コメント marker 化) は GitHub 自動クローズを失わせる副作用が大きいため不採用。

### Consumed Comments 起因の AC 修正 (適用済み)

`/issue` Step 15 の AC audit コメント (2026-08-21T15:56:15Z) が、Pre-merge AC 3 の rubric テキスト「... `skills/code/SKILL.md` **または** `modules/phase-state.md` に記載されている」に常時 PASS リスクを指摘した: `modules/phase-state.md` の Phase Table `code-patch` 行は本 Issue 着手前から既に `closes #N` を completion signature として明記しており、この事前記述だけで rubric grader が満たされてしまう可能性がある。

対応として、Issue 本文 AC 3 の rubric テキストを「`skills/code/SKILL.md` の Step 8/Step 11 コミット規約に関する記述の中で明記されている」に修正し (`または modules/phase-state.md` の分岐を削除)、要求箇所を本 Issue の実装対象である `skills/code/SKILL.md` 内に限定した。本 Spec の `## Verification > Pre-merge` は修正後のテキストを反映している。`modules/phase-state.md` 自体の記述は現状のままで正確であり、変更は不要と判断した (Changed Files に含めない)。

## Changed Files

- `skills/code/SKILL.md`: Step 8 のコミット粒度規約に patch route 限定の「最終 Implementation Step のコミットを Step 11 に委ねる」例外を追記し、新設の「Step 8/Step 11 Commit Boundary」小節で理由を明文化。Step 11 の patch route コミットブロックに (a) `closes #N` が `reconcile-phase-state.sh` の completion signal である旨の一文、(b) working tree がクリーンな残余ケース向けの push 前後 fallback (`--amend` / 空コミット) を追記。
- `tests/code.bats`: `step8_section()` 抽出ヘルパーを追加 (既存 `step11_section()` に倣う)。Step 8 の patch route 限定 deferral 規約、Step 11 の completion-signal 言及、Step 11 の push 前後 fallback をそれぞれ検証する新規 `@test` を追加。
- [Steering Docs sync candidate] keyword "code" skipped: matched 1178 files (no discriminating power) — 本 Issue が導入する新規 config key/marker/function name は無く、より上位優先度のキーワードも存在しないため、bare skill name "code" 一本の判定で sync candidate 探索を終了した。

## Implementation Steps

1. `skills/code/SKILL.md` Step 8 を編集する (→ 衝突時の closes 付与方法の明文化, closes の役割文書化)。
   - 挿入位置: 箇条書き `- Commit after each step completes` (`- **DCO: always use \`git commit -s\`...**` の直後) を、patch route 限定の例外を明記する記述に置き換える。要旨: 「patch route では最終 Implementation Step の差分はここでコミットせず、Step 11 の必須コミットに持ち越す。pr route は Step 11 に独立した要約コミットが無く `closes #N` は PR body 側に書かれるためこの例外は適用されない (pr route は従来どおり全ステップをここでコミットする)」。
   - 挿入位置: `#### Allowed-tools Pre-commit Check` の直前に、新設小節 `#### Step 8/Step 11 Commit Boundary (patch route)` を追加する。内容: (a) Step 11 の patch route コミットは `closes #N` を必須で持つこと、Step 8 が全ステップを都度コミットすると Step 11 到達時に新規差分が無くなり付与先を失うこと、そのため直前の例外規約が最終ステップの差分を意図的に残していること、(b) それでも Step 11 到達時に working tree がクリーンな残余ケース (`spec-approval-needed` deferral が最終ステップに掛かっていた場合、再開セッションで既にコミット・push 済みだった場合等) があり得ること、対処は Step 11 側の fallback (次のステップで追記) を参照する旨。
2. `skills/code/SKILL.md` Step 11 の "For patch route" ブロックを編集する (after 1) (→ push 前後の安全境界の区別, closes の役割文書化)。
   - 挿入位置: 既存段落 `Include \`closes #N\` only when the base branch is \`main\`... (Issue #996)` の末尾に一文追加する。要旨: 「`closes #N` は `reconcile-phase-state.sh` の `_completion_code_patch()` が phase completion 判定に使う一級シグナルでもある (`modules/phase-state.md` § Phase Table の `code-patch` 行を参照)。付与漏れは実装済みの Issue を silent no-op と誤判定させる (#1106, #1226)」。
   - 挿入位置: 既存の sign-off/subject ガード `bash` ブロック (`git log -1 --format='%B' | grep -q "^Signed-off-by:"...`) の直後、`Push is done in Step 14 Worktree Exit...` の直前に、新設段落 `**Fallback when Step 8 leaves no new diff (residual case):**` を追加する。内容:
     - まず `git log origin/main..HEAD --oneline` で push 状態を確認する。
     - **非空 (未 push)**: 直近コミットを `git commit -s --amend` で改訂し、subject に `(closes #$NUMBER)` を追記する (body/trailer は保持し、subject に既に含まれる場合は追記しない)。例: `git commit -s --amend -m "$(git log -1 --format=%s) (closes #$NUMBER)" -m "$(git log -1 --format=%b)"`。
     - **空 (push 済み)**: amend は行わない (push 済み履歴の書き換えになるため)。代わりに空コミットを作る: `git commit -s --allow-empty -m "{prefix} <summary> (closes #$NUMBER)\n\nCo-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"` (`{prefix} <summary>` は Step 11 通常時と同じ組み立てを再利用する)。
3. `tests/code.bats` にテストを追加する (after 2) (→ 規約がテストで保護されている)。
   - 既存の `step11_section()` (ファイル冒頭付近) に倣い、`### Step 8:` から次の `### ` 見出しまでを抽出する `step8_section()` awk ヘルパーを追加する。
   - 新規 `@test` (最低 3 件): (a) `step8_section` の出力が patch route 限定の最終ステップ deferral 規約と pr route 除外の両方に言及していることを検証、(b) `step11_section` の出力が `reconcile-phase-state.sh`/`_completion_code_patch` への言及と silent no-op のリスクに言及していることを検証、(c) `step11_section` の出力が `--amend` (未 push) と `--allow-empty` (push 済み) の両方の fallback に言及していることを検証。

## Verification

### Pre-merge

- <!-- verify: rubric "skills/code/SKILL.md に、Step 8 の粒度別コミットにより Step 11 で新規差分が残らない場合の closes #N 付与方法が明記されている" --> 衝突時の closes 付与方法が明文化されている
- <!-- verify: rubric "closes #N 付与の回避手段について、push 前と push 後で取るべき手段が区別して記述されている (push 済み履歴を書き換えない)" --> push 前後の安全境界が区別されている
- <!-- verify: rubric "closes #N が reconcile-phase-state.sh の code-patch completion 判定に使われる一級シグナルである旨が、skills/code/SKILL.md の Step 8/Step 11 コミット規約に関する記述の中で明記されている" --> closes の役割が文書化されている
- <!-- verify: rubric "tests/ に、Step 8 と Step 11 の規約整合を検証するケース (SKILL.md の記述確認で可) が追加されている" --> 規約がテストで保護されている

### Post-merge

- Implementation Steps が 2 つ以上に分かれる patch route の Issue で `/code` を実行し、`closes #N` が決定的に付与されることを確認する <!-- verify-type: opportunistic -->

## Notes

- **新規テストケース要件 (Step 10 の light-depth 対応)**: `tests/code.bats` に `step8_section()` ヘルパーおよび最低 3 件の新規 `@test` (patch route 限定 deferral、closes completion-signal 言及、push 前後 fallback) を追加し、既存スイートが PASS することに加えて新規ロジックを検証するテストが追加された状態でスイートが PASS することを Implementation Step 3 の完了条件とする。
- **pr route を Step 8 変更のスコープ外とした理由**: pr route の Step 11 (`skills/code/SKILL.md` "For pr route" ブロック) は `git push origin HEAD` → `gh pr create` のみで独立した要約コミットを作らない。Step 8 の「最終ステップのコミットを委ねる」変更を pr route にも適用すると、その差分を拾うコミットが存在しなくなり、実装差分が未コミットのまま欠落する回帰を生む。この理由により Step 8 の変更は patch route 限定とした。
- **AC 3 rubric 修正 (Consumed Comments 起因)**: Issue 本文 AC 3 の rubric テキストを、`/issue` Step 15 の AC audit コメントの指摘 (常時 PASS リスク) に基づき修正済み。詳細は Overview の「Consumed Comments 起因の AC 修正」を参照。
- **Steering Docs sync candidate check**: 抽出キーワード "code" (bare skill name) は 1178 ファイルにマッチし判別力なしと判定、探索を終了した。より上位優先度のキーワード (新規 config key/marker/function name、`modules/`・`scripts/` の変更) はいずれも本 Issue に存在しない。
- **Outbound pointer sync candidate check**: Implementation Step 2 で `skills/code/SKILL.md` から `modules/phase-state.md` § Phase Table への参照を新設するが、`modules/phase-state.md` 側の記述 (code-patch 行の completion signature) は本 Issue 着手前から既に正確であり、変更を要しない。Changed Files に追加しない。
- **Simplicity Rule**: Implementation Steps 3 件、Pre-merge Verification 4 件、Post-merge Verification 1 件で light 上限 (各 5 件) 以内。

## Consumed Comments

- saito / MEMBER / first-class / `/issue` フェーズの Issue Retrospective (判断根拠・Auto-Resolve Log・Consumed Comments の記録)。#1226 の 2 例目観測により衝突条件が「Implementation Steps 2 つ以上」に広がったことの報告を含む。本 Spec の設計判断に直接の追加アクションは無いが、Background の文脈として活用した / https://github.com/saitoco/wholework/issues/1134#issuecomment-5372147483
- saito / MEMBER / first-class / `/issue` Step 15 の AC audit: Pre-merge AC 3 の rubric テキストに常時 PASS リスク (`modules/phase-state.md` の既存記述だけで満たされてしまう懸念) を指摘。本 Spec で AC 3 の rubric テキストを `skills/code/SKILL.md` 限定に修正し、Issue 本文にも反映済み / https://github.com/saitoco/wholework/issues/1134#issuecomment-5372198272
