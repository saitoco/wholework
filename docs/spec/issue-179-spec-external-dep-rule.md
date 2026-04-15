# Issue #179: spec: Standardize External Command Dependency Documentation

## Overview

`/verify` レトロスペクティブ（Issue #177）で発見された問題への対処。`bats --jobs 4` に GNU Parallel が必要だったが、Spec の Implementation Steps にその依存が記載されておらず、実装時に `parallel: command not found` エラーで初めて判明した。

`/spec` SKILL.md のStep 10 SHOULD 制約テーブルに「外部コマンド依存を Implementation Steps に明記する」規約を追加する。あわせて Issue #177 の Spec を遡及更新し、規約適用例として "external package dependencies" を記載する。

## Changed Files

- `skills/spec/SKILL.md`: Step 10 SHOULD 制約テーブルに External command dependencies 行を追加
- `docs/spec/issue-177-ci-bats-speed.md`: Implementation Step 1 に外部パッケージ依存情報を追記（遡及更新）

## Implementation Steps

1. `skills/spec/SKILL.md` の Step 10 SHOULD 制約テーブルの末尾（`| External GitHub Action required inputs |...` 行の直後）に以下の行を追加する（→ 受入基準 A）:

   ```
   | External command dependencies | When Implementation Steps use commands with external dependencies (packages requiring installation: apt packages, brew formulas, npm modules, OS-specific binaries), include install steps for each package explicitly | #179 |
   ```

2. `docs/spec/issue-177-ci-bats-speed.md` の Implementation Step 1 の末尾に外部パッケージ依存情報を追記する（→ 受入基準 B）:

   変更前:
   ```
   1. `.github/workflows/test.yml` の `Install bats` ステップに `parallel` を追加: `sudo apt-get install -y bats` → `sudo apt-get install -y bats parallel`
   ```
   変更後（末尾に追記）:
   ```
   1. `.github/workflows/test.yml` の `Install bats` ステップに `parallel` を追加: `sudo apt-get install -y bats` → `sudo apt-get install -y bats parallel`（external package dependencies: `bats` (bats-core), `parallel` (GNU Parallel)）
   ```

## Verification

### Pre-merge

- <!-- verify: grep "external.*depend\|depend.*package\|install.*step" "skills/spec/SKILL.md" --> `/spec` SKILL.md に外部コマンド依存を Implementation Steps に記載する旨が規約として追加されている
- <!-- verify: grep "package\|dependencies" "docs/spec/issue-177-ci-bats-speed.md" --> 新規 Spec 生成時に依存パッケージが実装ステップに含まれることが期待される

### Post-merge

- `/spec` 実行時に Step 10 SHOULD 制約テーブルに External command dependencies 行が含まれる
- 新規 Spec 作成時、外部コマンドを使用する実装ステップにはパッケージ名とインストールコマンドが記載されることが期待される

## Notes

- SPEC_DEPTH=light のため ambiguity resolution / uncertainty detection はスキップ
- 遡及更新（`docs/spec/issue-177-ci-bats-speed.md`）は規約適用の実例として追加する（Issue #177 は既に完了済みで再実装はしない）
- SHOULD 制約の追加のため `validate-skill-syntax.py` の MUST 違反チェック対象外
