# Issue #1327: spec: Steering Docs sync candidate check のゲートを締め 96% の空振りを解消

## Consumed Comments

- login: saito / authorAssociation: MEMBER / trust tier: first-class
  intent: `/issue` フェーズの Issue Retrospective コメント。2 件の自動解決 (識別力フィルタ (B) の grep 対象ディレクトリを `docs/ tests/ scripts/` から `docs/ tests/ scripts/ modules/` の 4 ディレクトリに修正、キーワード優先順位 (A) の Medium 段に `modules/{name}.md` を追加) を記録。いずれも Issue 本文の「対応方針 (案)」コードブロックと「## Auto-Resolved Ambiguity Points」に反映済みで、`/spec` 側での追加対応は不要と判断した。
  url: https://github.com/saitoco/wholework/issues/1327#issuecomment-5368249134

## Overview

`skills/spec/SKILL.md` の **Steering Docs sync candidate check** (Step 10) は、発火した Spec 127 本中 122 本 (96%) が「変更不要」判定に着地しており、実質的にゲートとして機能していない。原因は (1) `skills/{name}/SKILL.md` → キーワード `{name}` という抽出規則が `spec`/`code`/`auto` 等の一般語を生み `docs/` 全体に大量ヒットすること、(2) `docs/migration-notes.md` のような履歴記録ファイルが構造的に毎回ヒットし続けることの 2 点。

本 Issue は該当チェックの Steps 1→4 に以下 3 点を追加する:

- **(A)** キーワード抽出の優先順位を明示 (Highest: config key/marker/関数名、Medium: script 名・module 名、Lowest: skill 名)
- **(B)** 新設 Step 2 として「識別力フィルタ」を挿入 — ヒットファイル数が閾値 8 を超えるキーワードは 1 行記録のみでスキップし、個別列挙・評価を行わない。全キーワードがスキップされた場合もより広い検索へのフォールバックは行わない
- **(C)** `docs/migration-notes.md` について、CLI シグネチャ・フラグ・引数順の変更を伴う場合のみ sync candidate として扱うスコープ規則を追加

3 点とも Issue 本文の「対応方針 (案)」に確定済みの書き換え案として記載されており (Auto-Resolved Ambiguity Points 反映済み)、本 Spec はそれを `skills/spec/SKILL.md` の実テキストへ落とし込む。

## Changed Files

- `skills/spec/SKILL.md`: 「Steering Docs sync candidate check」の `Steps:` リスト (現行 Step 1-4、`skills/spec/SKILL.md:320-337` 相当) を書き換え。詳細は Implementation Steps 1-3 を参照。
  - **[Steering Docs sync candidate check 自己適用]**: 本 Changed Files に含まれる `skills/spec/SKILL.md` 自身についてキーワード `spec` (skill 名、本 Issue の新ルールでは Lowest 優先度) を現行アルゴリズムで確認したところ `grep -rl "spec" docs/ tests/ scripts/ modules/ 2>/dev/null | wc -l` は **1184 ファイル**ヒットし、新設フィルタの閾値 8 を大幅に超過する。個別列挙はせず「識別力なし」としてスキップと判断した — 本 Issue が解消しようとしている 96% no-op 問題そのものの実例であり、新フィルタが正しく機能する設計であることの傍証となる。
- `tests/spec.bats`: `Steering Docs sync candidate check` の既存コンテンツアサーションテスト (#1089 で追加した `modules/` ゲート・クロスサーチの 2 件) に続けて、本 Issue が追加する 3 点 (キーワード優先順位・識別力フィルタ・`docs/migration-notes.md` スコープ規則) を保護する新規 `@test` を追加。詳細は Implementation Step 4 を参照。

## Implementation Steps

1. `skills/spec/SKILL.md` の「Steering Docs sync candidate check」`Steps:` リストの現行項目 **1** (`Extract target keywords from each changed file:` で始まる箇所) を、以下のキーワード優先順位付きテキストに置き換える (→ 受入条件 AC3, AC5):

   ```
   1. Extract target keywords from each changed file, in this priority order:
      - **Highest**: any config key, marker name (`type=...`), or function name this Issue
        introduces or changes (e.g., `capabilities.pr-preview`, `type=preview-ac-unverified`)
      - **Medium**: `scripts/{script-name}.sh` → keyword: `{script-name}.sh`;
        `modules/{name}.md` → keyword: `{name}.md`
      - **Lowest**: `skills/{name}/SKILL.md` → keyword: `{name}`

      A bare skill name is the weakest keyword class — it collides with prose usage of the
      same English word throughout `docs/`. When a higher-priority keyword is available for
      the same changed file, use it instead of the skill name.
   ```

2. (after 1) Step 1 で置き換えた項目の直後、現行項目 2 (`For each keyword, run:` で始まる `grep -rn` フルサーチ) の直前に、以下の新項目を挿入する (→ 受入条件 AC1, AC2, AC5):

   ```
   2. **Discriminating-power filter** — before running the full `grep -rn`, count matching files:

      ```bash
      grep -rl "<keyword>" docs/ tests/ scripts/ modules/ 2>/dev/null | wc -l
      ```

      If the count exceeds **8**, the keyword has no discriminating power for this Issue.
      Skip it and record a single line in the Changed Files section:

      `- [Steering Docs sync candidate] keyword "<keyword>" skipped: matched N files (no discriminating power)`

      Do not enumerate or evaluate the individual hits. Bare skill names (`code`, `auto`,
      `spec`, `issue`, `review`, `merge`, `verify`, `doc`) are almost always in this class.

      If **every** extracted keyword is skipped by this filter, record one line stating that
      and end the check — do not fall back to a broader search.
   ```

   挿入後、旧項目 2 (`grep -rn` フルサーチ) は項目 **3** に繰り下がる。その冒頭文を `For each keyword, run:` から `For each keyword that was not skipped by the filter above, run:` に書き換える。ただし直後のコマンド行 `` grep -rn "<keyword>" docs/ tests/ scripts/ modules/ `` は `tests/spec.bats` が一字一句アサートしているため **変更しない** (2>/dev/null を含む完全一致を維持)。

3. (after 2) 旧項目 3 (`For each file found, add a **Steering Docs sync candidate** entry...` で始まるカテゴリ別パターン列挙) は項目 **4** に繰り下がる。その `modules/` 箇条書きの直後に、以下の箇条書きを追加する (→ 受入条件 AC4):

   ```
      - **`docs/migration-notes.md` (scope rule)**: this file records interface changes at the
        private→public migration point. Treat it as a sync candidate **only when this Issue
        changes a CLI signature, flag, or argument order** of a script it lists. Otherwise
        exclude it without inspecting occurrences — a keyword match against a historical
        record is expected and is not drift.
   ```

   旧項目 4 (`The /code phase makes the final include/exclude decision...`) は項目 **5** に繰り下げるのみで文面は変更しない。

4. (after 1, 2, 3) `tests/spec.bats` に、本チェックの既存コンテンツアサーションテスト (31-37 行目、#1089 で追加された `modules/` ゲート・クロスサーチの 2 件) に続けて、本 Issue が追加した 3 点を保護する新規 `@test` を 4 件追加する:

   ```bash
   # Content-assertion tests for the Steering Docs sync candidate check discriminating-power
   # filter, keyword priority ordering, and docs/migration-notes.md scope rule (added for
   # #1327). Guards the tightened Step 10 gate against reverting to the pre-#1327 96% no-op
   # behavior.

   @test "spec skill Steering Docs sync candidate check orders keywords by priority" {
       grep -q 'weakest keyword class' "$SKILL_FILE"
   }

   @test "spec skill Steering Docs sync candidate check applies a discriminating-power filter" {
       grep -q 'Discriminating-power filter' "$SKILL_FILE"
   }

   @test "spec skill Steering Docs sync candidate check does not fall back when all keywords are skipped" {
       grep -q 'do not fall back to a broader search' "$SKILL_FILE"
   }

   @test "spec skill Steering Docs sync candidate check scopes docs/migration-notes.md to CLI signature changes" {
       grep -q 'private→public migration point' "$SKILL_FILE"
   }
   ```

   挿入位置は既存の 2 件のテスト (35-37 行目) の直後、「New test case requirement for new branch logic」用テストのコメントブロック (39 行目) の直前。

## Verification

### Pre-merge

- <!-- verify: rubric "skills/spec/SKILL.md の Steering Docs sync candidate check に、キーワードのヒットファイル数を数えて閾値を超えたら当該キーワードをスキップする識別力フィルタが追加されている。スキップ時は個々のヒットを列挙・評価せず 1 行の記録に留めることが明記されている" --> 識別力フィルタが追加されている
- <!-- verify: grep "discriminating power" "skills/spec/SKILL.md" --> 識別力フィルタの判別語が本文に存在する
- <!-- verify: rubric "skills/spec/SKILL.md に、抽出キーワードの優先順位 (config key / marker / 関数名 > script 名 > skill 名) が明示され、skill 名が最も識別力の弱いクラスであることが記述されている" --> キーワードの優先順位が明示されている
- <!-- verify: rubric "skills/spec/SKILL.md に docs/migration-notes.md のスコープ規則が追加され、CLI シグネチャ・フラグ・引数順の変更を伴う場合のみ sync candidate として扱う旨が明記されている" --> 履歴記録ファイルのスコープ規則が追加されている
- <!-- verify: rubric "抽出した全キーワードが識別力フィルタでスキップされた場合の挙動 (より広い検索へフォールバックしない) が明記されている" --> 全スキップ時のフォールバック禁止が明記されている

### Post-merge

- 本 Issue 着地後に作成された Spec で、Steering Docs sync candidate check の no-op 率が着地前の 96% から低下していることを確認する <!-- verify-type: observation event=auto-run session=next --> <!-- verify: rubric "本 Issue マージ後に作成された Spec のうち Steering Docs sync candidate check に言及したものを対象に、Notes 記載の効果測定コマンドで計測した no-op 判定文言への着地比率、または新設の識別力フィルタによる 1 行スキップ記録 (no discriminating power) での早期終了比率が、着地前の基準値 96% (127 本中 122 本) を明確に下回っている" --> Steering Docs sync candidate check の no-op 率低下を観察

## Notes

### Post-merge AC の強化 (observation AC 構造チェック)

Issue 本文の Post-merge AC は当初 `<!-- verify-type: observation event=auto-run session=next -->` のみで観測構造 (期待される出力) が未記載だった。Step 10「verify-type タグチェック」および `modules/verify-classifier.md` の observation AC 構造チェックに従い、Option B (rubric verify command 付与) で強化し、Issue 本文・本 Spec の両方に反映した。同種の強化は #1017 (`docs/spec/issue-1017-recoveries-symptom-issue-match.md`) に前例がある。rubric の判定基準は Issue 本文 Notes 節「効果測定の方法」に既記載の計測コマンド (127 本中 122 本 = 96%) をそのまま踏襲した。

### 新規テストケース要件 (SPEC_DEPTH=light のため本節に記録)

Implementation Step 1-3 は `skills/spec/SKILL.md` の既存ステップ列挙に新しい分岐 (識別力フィルタによるスキップ/継続の分岐) を追加する。Step 10「New test case requirement for new branch logic」に従い、既存スイートの PASS だけでなく新規ロジックを検証する新規テストケースの追加を要件化し、Implementation Step 4 で `tests/spec.bats` への `@test` 4 件追加として具体化した。SPEC_DEPTH=light のため Step 13 (spec retrospective) は実行されないため、要約をここに記録する。

### doc-checker.md skill-dev supplement の判定

`scripts/validate-skill-syntax.py` が存在するため `modules/skill-dev-doc-impact.md` の Change Type 表を確認した。「Skill addition, change, or deletion」行は `README.md`/`docs/workflow.md`/`CLAUDE.md` の更新を要求するが、影響根拠は「skill list, phase descriptions」(スキル一覧・フェーズ説明) であり、本 Issue は `/spec` の外部インターフェース・フェーズ説明を変えず Step 10 内部の 1 サブ手順のアルゴリズムのみを変更する。`grep -n "sync candidate\|discriminating" README.md docs/workflow.md CLAUDE.md` はヒットなし (未検証のまま「変更不要」と書かない、の pre-verification rule を満たす) であり、3 ファイルとも変更不要と判断した。

### Steering Docs sync candidate check 自己適用の結果

本 Spec の Changed Files に `skills/spec/SKILL.md` 自身が含まれるため、現行 (本 Issue 適用前) の Steering Docs sync candidate check を Step 10 の指示どおり自己適用した。キーワード `spec` (skill 名、本 Issue が定義する優先順位では Lowest) は `docs/ tests/ scripts/ modules/` の 4 ディレクトリで 1184 ファイルにヒットし、新設予定の閾値 8 を大幅に超過する。個別列挙・評価は行わず「識別力なし」としてスキップした。Changed Files 節に記録済み。
