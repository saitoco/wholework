# Issue #1139: review: Step 9 の CI Blocking から pre-existing 失敗を除外

## Overview

`skills/review/SKILL.md` Step 9 の CI Blocking ルールには例外が一切なく、CI ジョブが FAILURE なら無条件に `severity: MUST` / `path: null` のエントリを注入する。`scripts/check-forbidden-expressions.sh` はリポジトリ全体を無条件に走査するため、`main` に禁止表現の違反が 1 件でも存在すると、その違反と無関係な全 PR がブロックされる。

本 Issue は、`/merge` で既に使われている baseline 分類器 `scripts/pre-merge-check.sh` (#719 で追加) を `/review` Step 9 からも再利用し、CI FAILURE を「この PR が導入した違反 (NEW_FAILURE)」と「base ブランチから継承しただけの違反 (PRE_EXISTING)」に帰属判定したうえで、前者のみをブロッキングとする。

## Reproduction Steps

1. `main` に禁止表現の違反を含むファイルが存在する状態にする (実例: `docs/spec/issue-1135-external-kill-root-cause.md` の旧称残存)
2. 当該ファイルを一切変更しない PR を作成する (実例: PR #1138 — diff は `tests/*.bats` 3 件と自身の Spec のみ)
3. CI の `Forbidden Expressions check` ジョブが FAILURE になる
4. `/review <PR番号>` を実行する
5. Step 9 が当該 FAILURE を無条件に MUST 化し、Step 12.2 が「Fix all MUST issues」に従って無関係な他 Issue の成果物を inline 修正する

`git diff main -- docs/spec/issue-1135-external-kill-root-cause.md` が空である (= PR が当該ファイルを触っていない) にもかかわらずブロックされる点が、本 Issue の核心。

## Root Cause

Step 9 の「Blocking by default」段落が、CI FAILURE の**帰属** (この PR が壊したのか、base から継承しただけなのか) を判定する手段を一切持たないこと。現行テキストは「No built-in exception exists for known-flaky or unrelated-job failures; every FAILURE job blocks until a follow-up Issue defines an allowlist.」と明示的に例外なしを宣言している。

一方、同じ帰属判定を行うスクリプト `scripts/pre-merge-check.sh` は #719 で既に存在し、base ref / head ref それぞれを ephemeral worktree 上で実行して `NEW_FAILURE` (exit 2) / `PRE_EXISTING` / `FIXED` / `CLEAN` (いずれも exit 0) / env エラー (exit 1) に分類する。check の dispatch table に `forbidden-expressions` が登録済みだが、呼び出し元は `scripts/run-merge.sh` の pre-screen のみで、`/review` からは未使用だった。#719 のスコープが起点インシデント #702 (merge phase) に限定されていただけで、review phase を意図的に除外した設計判断ではない。

修正方針の妥当性: 新規に diff スコープ限定モードを実装するのではなく既存スクリプトを再利用することで、帰属判定の基準が 1 系統に保たれる。`tests/pre-merge-check.bats` が 4 分類すべてを既にカバーしているため、分類器自体の追加テストも不要。

## Consumed Comments

- saito / MEMBER / first-class / Issue Retrospective — 起票時原案から既存 `pre-merge-check.sh` 再利用への方針転換、AC 全面差し替え、タイトル更新の記録 (本 Spec の Overview・Root Cause に反映済み) / https://github.com/saitoco/wholework/issues/1139#issuecomment-5374156795
- saito / MEMBER / first-class / Triage AC audit 警告 — AC2 の `section_contains` 第2引数に見出し記号を含めており恒久的 UNCERTAIN になるとの指摘。修復案どおり `"## Step 9"` を `"Step 9"` に修正して Issue body に反映済み / https://github.com/saitoco/wholework/issues/1139#issuecomment-5374190752

## Changed Files

- `skills/review/SKILL.md`: (1) frontmatter `allowed-tools` の `Bash(...)` パターンに `${CLAUDE_PLUGIN_ROOT}/scripts/pre-merge-check.sh:*` を追加 (2) Step 9「Blocking by default」段落の最終文を差し替え (3) Step 9 に `### Pre-existing failure exception (baseline attribution)` サブセクションを新設 (4) Step 12.2 Fix Work に out-of-scope エントリの修正禁止を 1 文追加
- `tests/review.bats`: `step12_2_section()` ヘルパー追加 + 新規テストケース 5 件追加 (Step 9 サブセクション 4 件 + Step 12.2 1 件)
- `modules/orchestration-fallbacks.md`: `## baseline-failure` の `### Rationale` に 1 行追加 — `/review` Step 9 も `pre-merge-check.sh` を呼ぶが、本エントリが扱う症状は merge phase の `run-merge.sh` abort に限定される旨を明記
- `.claude/settings.json.template`: **変更不要** (grep 確認済み) — 個別スクリプトは列挙されておらず、`Bash(${WHOLEWORK_ROOT}/scripts/*.sh *)` と plugin cache のワイルドカードが `pre-merge-check.sh` を包含する。先行事例として `wait-ci-checks.sh` も個別列挙なしで `/review` から使用中 (`grep -c "wait-ci-checks.sh" .claude/settings.json.template` = 0)
- `docs/structure.md` / `docs/ja/structure.md`: **変更不要** (grep 確認済み) — `scripts/pre-merge-check.sh` の記述は分類ロジックと終了コードのみで呼び出し元を列挙していないため、呼び出し元追加による陳腐化が発生しない
- `docs/workflow.md`: **変更不要** (grep 確認済み) — `### 4. /review` セクションは CI Blocking の挙動を一切記述しておらず (`grep -n "CI\b" docs/workflow.md` の 3 ヒットはいずれも Size routing / pr-preview / Review PENDING retry に関するもの)、詳細を `skills/review/SKILL.md` に委譲している
- `skills/review/skill-dev-recheck.md`: **変更不要** — Step 9 からの outbound pointer 先だが、`## Step 8: Additional Suggestions on CI Failure` は `validate-skill-syntax` ジョブ固有の修正提案のみを列挙しており、`Forbidden Expressions check` の帰属判定ロジックとは重複も矛盾もしない。ここに分類ロジックを二重記載すると SSoT が分岐するため意図的に除外する
- `docs/ja/` 翻訳同期: **対象外** — `docs/translation-workflow.md` の同期義務はトップレベル `docs/*.md` に対するもので、本 Issue の Changed Files に該当ファイルはない
- [Steering Docs sync candidate] keyword `review` skipped: matched 1056 files (no discriminating power)
- [Steering Docs sync candidate] keyword `pre-merge-check.sh` skipped: matched 18 files (no discriminating power)
- [Steering Docs sync candidate] keyword `orchestration-fallbacks` skipped: matched 139 files (no discriminating power)

## Implementation Steps

1. `skills/review/SKILL.md` frontmatter の `allowed-tools` にある `Bash(...)` パターン内に `${CLAUDE_PLUGIN_ROOT}/scripts/pre-merge-check.sh:*` を追加する。挿入位置は `${CLAUDE_PLUGIN_ROOT}/scripts/wait-ci-checks.sh:*,` の直後。ワイルドカード (`scripts/*.sh`) では `scripts/validate-skill-syntax.py` の突合を通過しないため、リテラルで追加すること (→ acceptance criteria 8)

2. `skills/review/SKILL.md` Step 9 の「Blocking by default」段落について、最終文「No built-in exception exists for known-flaky or unrelated-job failures; every FAILURE job blocks until a follow-up Issue defines an allowlist.」を、直後に新設するサブセクションを唯一の例外として参照する文へ差し替える。known-flaky allowlist が存在しないことと、それ以外の FAILURE ジョブが無条件にブロックすることは維持する (parallel with 1) (→ acceptance criteria 1)

3. `skills/review/SKILL.md` Step 9 の「Blocking by default」段落の直後に `### Pre-existing failure exception (baseline attribution)` サブセクションを新設する (after 2) (→ acceptance criteria 1, 2, 3)。記載必須の内容:
   - 背景 1〜2 文 (リポジトリ全体走査型 check は base に違反が 1 件あるだけで全 PR を落とす / inline 修正が PR の diff スコープを汚染する / 実例 #1136・PR #1138)
   - **適用範囲 (exhaustive)**: `Forbidden Expressions check` ジョブのみ。`scripts/pre-merge-check.sh` の check dispatch table に登録された唯一のエントリ `forbidden-expressions` に対応する。他の FAILURE ジョブは無条件ブロックを維持する。`push` と `pull_request` の両トリガーが同名ジョブの rollup エントリを生成しうるため、いずれか 1 つでも FAILURE なら分類器を 1 回実行する
   - 実行コマンド (bash コードフェンス): `${CLAUDE_PLUGIN_ROOT}/scripts/pre-merge-check.sh "$NUMBER" forbidden-expressions` — `$NUMBER` は Step 1 で解決済みの PR 番号。前景 (foreground) で実行する
   - 終了コード別の判定表 (exhaustive マーカー付き、4 行): exit 2 / 出力接頭辞 `NEW_FAILURE:` → **Blocking** (従来どおり MUST エントリを注入) ・ exit 0 / `PRE_EXISTING:` → **Non-blocking** ・ exit 0 / `FIXED:` または `CLEAN:` → **Non-blocking** ・ exit 1 (引数不足・ref 解決失敗・fetch 失敗・worktree 追加失敗を含む) → **Blocking** (分類器が実行できなかった旨を MUST エントリ本文に記載)
   - exit 1 を fail-closed とする根拠: `run-merge.sh` の fail-open と方向が逆に見えるが、両者とも「分類器が判定を出せないときは分類器導入前の挙動に戻す」という同一原則の適用結果である (merge では分類器はゲートを追加するだけなので戻す = 通す、review では既存ゲートを緩めるだけなので戻す = 止める)
   - Non-blocking 時の処理: CI Status テーブルの当該ジョブ行の Notes 欄に分類名 (`PRE_EXISTING` / `FIXED` / `CLEAN`) を記録し、`"severity": "CONSIDER"` / `"path": null` エントリを 1 件追加する。エントリ本文には「base ブランチから継承した違反であり **out of scope for this PR** である」ことを明記する。既存の open なフォローアップ Issue を `gh issue list --state open --search "check-forbidden-expressions in:title,body" --limit 10` で検索し、見つかれば番号を引用する。この Step からは Issue を起票せず、この PR 内で違反を修正しない旨も明記する

4. `skills/review/SKILL.md` Step 12.2 Fix Work の冒頭文「Fix all MUST issues. Claude decides whether to fix SHOULD/CONSIDER issues.」に、**out of scope for this PR** と明記されたエントリは修正せず 12.4 の Skipped Issues に記録する旨の 1 文を追加する。inline 修正こそが #1136 の実害だったため、Step 9 側の記述だけでは閉じない (after 3) (→ acceptance criteria 6)

5. `tests/review.bats` に `step12_2_section()` ヘルパー (`### 12.2. Fix Work` から `### 12.3` の直前までを awk で抽出、既存の `step12_3_section()` と同じパターン) を追加し、新規テストケースを 5 件追加する (after 3, 4) (→ acceptance criteria 5, 6)。テスト名は AC の `file_contains` パターンと一致させること:
   - `@test "Step 9: pre-existing CI failure exception invokes pre-merge-check.sh"`
   - `@test "Step 9: pre-existing CI failure exception enumerates all four classifications"`
   - `@test "Step 9: pre-existing CI failure exception is fail-closed on classifier env error"`
   - `@test "Step 9: pre-existing CI failure exception is scoped to the Forbidden Expressions check job"`
   - `@test "Step 12.2: out-of-scope entries are excluded from fix work"`

6. `modules/orchestration-fallbacks.md` の `## baseline-failure` セクション内 `### Rationale` の末尾に 1 行追加する。内容: #1139 以降 `/review` Step 9 も `pre-merge-check.sh` を呼ぶが、本エントリが扱う症状は merge phase の `run-merge.sh` abort に限定され、`/review` での NEW_FAILURE は MUST レビュー指摘として Step 12 が処理するため本 fallback の手順は適用しない (parallel with 1〜5) (対応する acceptance criteria なし — SHOULD レベルのドキュメント整合)

7. `bats tests/review.bats` と `bats tests/pre-merge-check.bats` をローカルで前景実行し PASS を確認する。あわせて `python3 scripts/validate-skill-syntax.py skills/` と `bash scripts/check-forbidden-expressions.sh` を実行し、allowed-tools 突合と禁止表現の両方が通ることを確認してからコミットする (after 5, 6) (→ acceptance criteria 4, 7)

## Verification

### Pre-merge

- <!-- verify: rubric "skills/review/SKILL.md Step 9 の CI Blocking ルールが、'Forbidden Expressions check' ジョブが FAILURE の場合に既存の scripts/pre-merge-check.sh <PR番号> forbidden-expressions を実行して pre-existing failure かどうかを判定し、終了コード 2 (NEW_FAILURE) の場合のみ MUST 化、それ以外 (PRE_EXISTING/CLEAN/FIXED、exit 0) は非ブロッキングとしフォローアップ Issue に委ねる判定が明記されている" --> `skills/review/SKILL.md` Step 9 に `pre-merge-check.sh` を用いた pre-existing 失敗の除外ロジックが明記されている
- <!-- verify: section_contains "skills/review/SKILL.md" "Step 9" "pre-merge-check.sh" --> Step 9 セクション本文に `pre-merge-check.sh` への言及がある
- <!-- verify: section_contains "skills/review/SKILL.md" "Step 9" "NEW_FAILURE" --> Step 9 セクション本文に終了コード 2 の分類名 `NEW_FAILURE` が明記されている
- <!-- verify: command "bats tests/pre-merge-check.bats" --> 既存の `tests/pre-merge-check.bats` が regression なく PASS する
- <!-- verify: file_contains "tests/review.bats" "Step 9: pre-existing CI failure exception" --> `tests/review.bats` に Step 9 の pre-existing 除外ロジックを検証する新規テストケースが追加されている
- <!-- verify: file_contains "tests/review.bats" "Step 12.2: out-of-scope entries" --> `tests/review.bats` に Step 12.2 の out-of-scope エントリ除外を検証する新規テストケースが追加されている
- <!-- verify: command "bats tests/review.bats" --> `tests/review.bats` がフルスイートで PASS する
- <!-- verify: file_contains "skills/review/SKILL.md" "scripts/pre-merge-check.sh:*" --> `skills/review/SKILL.md` の `allowed-tools` に `pre-merge-check.sh` が登録されている

### Post-merge

- 次回 `main` に pre-existing な禁止表現違反が存在する状態で無関係な PR の `/review` を実行した際、当該違反が MUST 化されないことを観察する <!-- verify-type: observation event=auto-run session=next -->

## Tool Dependencies

### Bash Command Patterns

- `${CLAUDE_PLUGIN_ROOT}/scripts/pre-merge-check.sh:*`: **`skills/review/SKILL.md` の `allowed-tools` に未登録のため追加が必要** (実装ステップ 1)。Step 9 の新サブセクションから baseline 分類器を呼び出す
- `gh issue list:*`: 既存フォローアップ Issue の検索。`skills/review/SKILL.md` の `allowed-tools` に登録済みのため追加不要

### Built-in Tools

- `Read` / `Edit`: いずれも `skills/review/SKILL.md` の `allowed-tools` に登録済みのため追加不要

### MCP Tools

- なし

## Uncertainty

- **`/review` の worktree 内から `pre-merge-check.sh` を実行した際の `git worktree add` の可否**: `/review` は Step 2 で `.claude/worktrees/review+pr-N` に入り PR head ブランチを checkout した状態で Step 9 に到達する。`pre-merge-check.sh` は `mktemp -d` 配下に `git worktree add --detach` で ephemeral worktree を追加する。
  - **検証方法**: リポジトリの PreToolUse フックが Bash を対象にしていないことの確認 (`hooks/hooks.json`)
  - **検証結果 (解決済み)**: `hooks/hooks.json` の PreToolUse matcher は `Edit|Write|NotebookEdit|Read` のみで Bash を含まないため `hook-worktree-path-guard.sh` は発火しない。また linked worktree からの `git worktree add` は common dir (`.git/worktrees`) に登録されるため動作する
  - **影響範囲**: 実装ステップ 3

- **CI が評価する ref と分類器が評価する ref の乖離**: `.github/workflows/test.yml` は `on: push` と `on: pull_request` の両方をトリガーとし、`pull_request` では `actions/checkout@v4` が merge ref を checkout する。一方 `pre-merge-check.sh` は `origin/<base>` と `origin/<head>` を個別に評価する。
  - **検証方法**: 4 分類それぞれについて帰属判定として正しい結論に至るかの机上検証
  - **検証結果 (解決済み)**: base が違反を持ち head も継承 → 両方 FAIL → `PRE_EXISTING` → 非ブロッキング (正しい)。PR 分岐後に base が違反を獲得 → base FAIL / head PASS → `FIXED` → 非ブロッキング (正しい。merge ref では CI が落ちるが PR は違反を導入していない)。base クリーンで head が違反を導入 → `NEW_FAILURE` → ブロッキング (正しい)。本 Issue が必要とするのは帰属判定であり、CI の判定対象 ref と一致させる必要はない
  - **影響範囲**: 実装ステップ 3

- **`allowed-tools` 追加漏れが CI で検出されるか**: 本文中の `${CLAUDE_PLUGIN_ROOT}/scripts/*.sh` 参照と `allowed-tools` の突合が自動化されているか。
  - **検証方法**: `scripts/validate-skill-syntax.py` の該当ロジック確認
  - **検証結果 (解決済み)**: 同スクリプト内で本文の `${CLAUDE_PLUGIN_ROOT}/scripts/*.sh` パターンを抽出し、`allowed-tools` の `Bash(...)` に含まれなければ「本文中に参照されたスクリプトが `allowed-tools` の Bash(...) パターンに含まれていません」というエラーを出す実装が存在する。CI の "Validate skill syntax" ジョブで実行されるため、実装ステップ 1 の漏れは PR 段階で検出される
  - **影響範囲**: 実装ステップ 1

## Notes

### fail-safe critical 判定

本 Issue の実装対象は `modules/skill-dev-checks.md` 由来の判定基準 (a)「ある操作をブロック/許可するゲート」に該当するため fail-safe critical と判定した。エッジケースの期待挙動:

- **入力が空**: `$NUMBER` が空の場合、`pre-merge-check.sh` は usage を出力して exit 1 → fail-closed (MUST 化を維持)。`/review` では Step 1 で PR 番号が解決済みのため実際には発生しないが、判定表の exit 1 行がこのケースを包含する
- **特殊文字を含む入力**: `$NUMBER` は Step 1 で解決した PR 番号のみ。実行コマンドでは必ずダブルクォートで囲む
- **依存コマンドの失敗時**: `pre-merge-check.sh` は `set -euo pipefail` 配下で、ref 解決失敗・`git fetch` 失敗・`git worktree add` 失敗・check スクリプト不在のいずれでも exit 1 を返す。すべて **fail-closed** (従来どおりブロック) として扱う。根拠は上記「分類器導入前の挙動に戻す」原則
- **巨大入力**: 該当なし (引数は PR 番号と check 名のみ)

### audit/investigation-type Issue 判定

**該当しない**。本 Issue は既存項目の調査・分類ではなく `/review` の挙動変更であり、判定根拠を永続成果物に記録する性質のものでもない。したがって「引数に書く識別子の存在検証を必須化する」実装ステップの追加は不要。

### 新規分岐ロジックに対する新規テストケース

実装ステップ 3・4 が `skills/review/SKILL.md` に新規分岐 (CI FAILURE ジョブ名による分岐と終了コードによる 4 分類、および fix work の out-of-scope 分岐) を追加するため、`command "bats tests/review.bats"` の AC は既存スイートの PASS だけでは足りない。実装ステップ 5 で新規テストケース 5 件 (Step 9 用 4 件・Step 12.2 用 1 件) を追加したうえでスイートが PASS することを要求する。`tests/pre-merge-check.bats` 側は分類器自体に変更がないため regression 確認のみ。

### 共有モジュール抽出の判断

Step 9 の新サブセクションのロジックは `/review` のみが使用するため、`modules/` への抽出は行わず SKILL.md に直接記述する (`modules/skill-dev-checks.md` の判断基準「単一利用なら SKILL.md への直接記述で可、2 箇所以上で使うなら modules/ へ抽出」に従う)。将来 `/merge` 以外の phase が同じ帰属判定を必要とした時点で抽出を再検討する。

### SKILL.md validation 制約

`scripts/validate-skill-syntax.py` の既知制約のうち、本 Issue の追記テキストが抵触しうるのは「本文中の半角感嘆符禁止」と「本文中の 3 連バッククォート禁止」。新サブセクションでは半角感嘆符を使わず、コードフェンスは通常どおり使用する (プレーンな本文中に 3 連バッククォートを地の文として書かない)。

### 列挙マーカー

新サブセクションの「適用範囲」と「終了コード別の判定表」はいずれも網羅列挙であるため、`modules/skill-dev-checks.md` の規約に従い **(exhaustive)** マーカーを付与する。

### `ci-failure-classifier.md` との関係

`modules/ci-failure-classifier.md` は CI プラットフォーム自体の障害 (`ci-infra`) を判定するモジュールで、消費者は `/auto` と `/verify` のみ。本 Issue の帰属判定 (pre-existing か否か) は直交する軸であり、Step 9 から `ci-failure-classifier.md` を読む必要はない。両者を混同しないよう、新サブセクションでは `ci-infra` に言及しない。

### `pre-merge-check.sh` の既存消費者

`grep -rl "pre-merge-check.sh" docs/ tests/ scripts/ modules/` の 18 ヒットのうち、履歴記録 (`docs/spec/` 10 件・`docs/reports/` 3 件) を除いた稼働中の消費者は `scripts/run-merge.sh` / `modules/orchestration-fallbacks.md` / `docs/structure.md` / `docs/ja/structure.md` / `tests/pre-merge-check.bats` / `tests/run-merge.bats` の 6 件。それぞれ本 Issue の変更で前提が崩れないか確認した結果、更新が必要なのは `modules/orchestration-fallbacks.md` のみ (Changed Files に記載)。`scripts/run-merge.sh` の pre-screen は本 Issue で変更しないため、`/review` と `/merge` で同じ分類器が独立に 2 回走ることになるが、`pre-merge-check.sh` は副作用を持たない読み取り専用の分類器であり冪等なため問題にならない。

### Uncertainty セクションと Implementation Steps の整合

Uncertainty の 3 項目はいずれも Spec 作成時に解決済みで、解決内容が新たな実装作業を生むのは 3 件目 (`allowed-tools` 追加) のみ。これは実装ステップ 1 として明示的に転記済みで、転記漏れはない。1 件目・2 件目は「現行設計のままで問題ない」ことの確認であり、対応する実装ステップは存在しない (方向 (b): Uncertainty 側の記述を実際の実装スコープに一致させた)。
