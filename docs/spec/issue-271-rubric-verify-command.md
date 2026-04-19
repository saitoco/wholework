# Issue #271: verify-executor: 自然言語ルーブリックコマンド `rubric` を追加

## Overview

`<!-- verify: rubric "..." -->` を新しい verify command として導入する。hard-pattern(`file_contains` / `grep` 等)では判定しきれない意味レベルの条件を、書き手が Issue 作成時点で明示的に意味判定(LLM grader)へ回せる opt-in 経路を提供する。

grader は adversarial スタンスで動き、入力は **Issue 本文と実装成果物(git diff と rubric テキスト内で明示的に言及されたファイル)** のみ。Spec ファイルは入力に含めない(wholework の Issue=WHAT / Spec=HOW 原則を守るため)。戻り値は PASS / FAIL / UNCERTAIN、FAIL 時は gap の自然言語記述を付す。safe mode では UNCERTAIN を返す。

hard-pattern との併用可。既存 Step 3(暗黙 AI judgment フォールバック)とは「明示 opt-in vs 暗黙」で責務を分ける。

## Changed Files

- `modules/verify-executor.md`: Processing Steps 翻訳テーブルに `rubric "text"` 行を追加(Permission 列は既存、`always_allow` を設定)、続いて "### Rubric Command Semantics" サブセクションを新設し、grader 入力範囲(`Spec files are not passed to the grader` の明文化を含む)・adversarial スタンス・戻り値の 3 値と gap 記述・safe mode UNCERTAIN を記述
- `modules/verify-patterns.md`: "### 9. When to Use `rubric` vs hard-pattern" セクションを追加(hard-pattern が構造的に弱い条件カテゴリと rubric の選択基準)
- `skills/issue/SKILL.md`: "Supported commands (exhaustive)" 表に `rubric` 行を追加
- `skills/spec/SKILL.md`: 既存の `verify-patterns.md` 参照ブロック付近に、意味判定が要る条件向けに `rubric` を参照する旨を 1 行追加
- `skills/verify/SKILL.md`: Step 2 に rubric 処理フローの注記を追加、Step 3(AI judgment フォールバック)と rubric の責務境界(暗黙 vs 明示 opt-in)を明示
- `tests/verify-rubric.bats`: 新規作成。rubric の翻訳テーブルディスパッチ、safe-mode UNCERTAIN の返却、syntax エラー系の UNCERTAIN 経路を検証(LLM 応答そのもののテストは範囲外) — bash 3.2+ 互換

## Implementation Steps

1. `modules/verify-executor.md` を編集: Processing Steps 翻訳テーブルに `rubric "text"` 行を追加(処理内容: "Mode-dependent: `safe` → UNCERTAIN. `full` → grader を adversarial system prompt で呼び出し、Issue 本文と git diff + rubric 内で言及されたファイルを入力として PASS / FAIL / UNCERTAIN を判定"、Permission: `always_allow`)。表の直後に新しいサブセクション "### Rubric Command Semantics" を追加し、以下を明記:(a)grader input scope(Issue body、git diff、rubric 内で explicit に参照されたファイルのみ。`Spec files are not passed to the grader` の一文を含める)、(b)adversarial stance、(c)return values PASS / FAIL / UNCERTAIN と FAIL 時の gap 記述、(d)safe mode behavior(`rubric` returns UNCERTAIN in safe mode)、(e)Managed Agents Outcome への将来移植の意図(→ 受け入れ条件 1〜5)

2. `modules/verify-patterns.md` に "### 9. When to Use `rubric` vs hard-pattern" セクションを追加。hard-pattern が構造的に弱いカテゴリ(意味判定、主観評価、半角/全角ゆれ、単一行 grep では拾えない概念的一致)を列挙し、その場合に `rubric` を使う旨と、CI の決定論的判定が必要なケースでは hard-pattern を優先する旨のガイドラインを記述(→ 受け入れ条件 6)

3. `skills/issue/SKILL.md` の "Supported commands (exhaustive)" 表に行追加: `rubric` / `rubric "text"` / "Semantic-level natural-language judgment via LLM grader. Safe mode returns UNCERTAIN; full mode performs adversarial grading. See `modules/verify-patterns.md` §9 for selection criteria."(→ 受け入れ条件 7)

4. `skills/spec/SKILL.md` の `verify-patterns.md` 参照ブロック付近(行 331 付近)に 1 行追加: "意味レベルの条件には `rubric` verify command を検討する(`modules/verify-patterns.md` §9 参照)"。併せて `skills/verify/SKILL.md` の Step 2(Conditions with Verify Commands)セクションに rubric 処理フロー注記を追加(翻訳テーブル経由で adversarial grader を呼ぶ、入力は Issue 本文 + git diff)、Step 3 直前に「Step 3 の AI judgment フォールバックは hint 無し条件への暗黙フォールバック、`rubric` は Issue 作成時点で宣言する明示 opt-in」という責務境界を明記(→ 受け入れ条件 8, 9)

5. `tests/verify-rubric.bats` を新規作成。テスト対象は `modules/verify-executor.md` に基づく rubric dispatch 挙動(bats からは `grep -q 'rubric "text"' modules/verify-executor.md` 等のドキュメント存在確認と、safe-mode UNCERTAIN の return path が書かれていることの確認程度の shallow test — LLM 応答自体は mock しない)。加えて existing `grep -q` パターンに揃える形で bash 3.2 互換のシンタックスで書く(→ 受け入れ条件 10, 11)

## Verification

### Pre-merge
- <!-- verify: file_contains "modules/verify-executor.md" "rubric \"text\"" --> `modules/verify-executor.md` の Processing Steps 翻訳テーブルに `rubric "text"` コマンド行が追加されている
- <!-- verify: file_contains "modules/verify-executor.md" "adversarial" --> `modules/verify-executor.md` に grader プロンプトの adversarial スタンス指定が明記されている
- <!-- verify: grep "PASS.*FAIL.*UNCERTAIN\|FAIL.*gap" "modules/verify-executor.md" --> grader の戻り値が PASS / FAIL / UNCERTAIN の 3 値で、FAIL 時は gap の自然言語記述を返す旨が記述されている
- <!-- verify: grep "rubric.*safe.*UNCERTAIN\|safe.*rubric.*UNCERTAIN\|safe mode.*rubric" "modules/verify-executor.md" --> safe mode では `rubric` が UNCERTAIN を返すことが明記されている
- <!-- verify: file_contains "modules/verify-executor.md" "Spec files are not passed to the grader" --> grader の入力範囲が Issue 本文と git diff に限定され、Spec ファイルを含めない旨が明記されている
- <!-- verify: file_contains "modules/verify-patterns.md" "rubric" --> `modules/verify-patterns.md` に rubric の使い所ガイドライン(hard-pattern と rubric の選択基準)が追加されている
- <!-- verify: file_contains "skills/issue/SKILL.md" "rubric" --> `skills/issue/SKILL.md` の verify command 設計ガイドに rubric の選択基準が追加されている
- <!-- verify: file_contains "skills/spec/SKILL.md" "rubric" --> `skills/spec/SKILL.md` の verify command 設計ガイドに rubric の選択基準が追加されている
- <!-- verify: file_contains "skills/verify/SKILL.md" "rubric" --> `skills/verify/SKILL.md` に rubric コマンド処理の記述、および Step 3 の AI judgment フォールバックとの責務境界(暗黙フォールバックと明示 opt-in の違い)が明示されている
- <!-- verify: command "find tests -name '*rubric*.bats' -type f | grep -q ." --> rubric / safe-mode UNCERTAIN を検証する bats テストファイルが追加されている
- <!-- verify: github_check "gh pr checks" "Run bats tests" --> 追加されたテストを含む全 bats テストが CI で PASS する

### Post-merge
- 実 Issue で `rubric` を使った受け入れ条件が `/verify` 経由で期待通り PASS / FAIL / UNCERTAIN を返すことを確認する(verify-type: opportunistic)

## Notes

- **受け入れ条件 5 の hint を spec 作成時に specific 化した**: Issue 元案の `grep "Issue\|issue body" "modules/verify-executor.md"` は既存ファイル内容に多数マッチするため false PASS を出す(緩すぎ)。Spec を source of truth として `file_contains "Spec files are not passed to the grader"` に変更し、対応する Issue 本文 AC 5 も同様に同期する。実装時は `modules/verify-executor.md` の Rubric Command Semantics サブセクション内にこの英語 phrase を必ず含める
- **Permission 列と Rubric の扱い**: `modules/verify-executor.md` には既に `Permission` 列(`always_allow` / `always_ask`)と "Permission Semantics and Managed Agents Mapping" セクションが存在する(別 Issue #276 と重複する事前実装が確認できる)。本 Issue では `rubric` 行に `always_allow` を設定するのみで、列自体の導入・拡張は行わない(スコープ外)
- **grader の実行経路**: LLM 呼び出しは verify-executor 内部の AI judgment と同じ経路(現プロセス内判定)で行う。別 `claude -p` プロセスとして spawn する context 分離は本 Issue のスコープ外(Issue 本文の Out of Scope に明記)
- **bats テストの粒度**: `rubric` は LLM を呼ぶため E2E mock が困難。テストは(a)`modules/verify-executor.md` に必要文言が存在すること、(b)safe-mode の処理経路が書かれていることの shallow 確認に留める。LLM 応答そのものの assertion は行わない
- **既存 Step 3 AI judgment との関係**: `skills/verify/SKILL.md` Step 3 は現状のまま残し、rubric は上位で明示 opt-in される別経路として共存させる。どちらも削除や置換は行わない
