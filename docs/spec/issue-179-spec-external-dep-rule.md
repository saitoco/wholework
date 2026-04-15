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

## Code Retrospective

### Deviations from Design

- N/A

### Design Gaps/Ambiguities

- N/A

### Rework

- N/A

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- Spec は SPEC_DEPTH=light で作成。受入基準に verify コマンド（`grep`）が付いており、自動検証可能な設計になっている。Issue の発生経緯（#177 レトロスペクティブ）も明確に記載されており、issue → spec 間の追跡性が良好。

#### design
- 変更範囲が2ファイルと小さく、Spec の Implementation Steps が具体的な差分レベルで記述されており、設計の曖昧さが少なかった。

#### code
- コミット構成: `Add design for issue #179` → `chore: add external command dependencies convention to /spec SKILL` → `Add code retrospective for issue #179` の3コミット。fixup/amend パターンなし、リワークなし。patch route で直コミットされており、スムーズな実装だった。

#### review
- PR なし（patch route）。CI 事前検知が働かない。変更内容がドキュメント追記のみ（SKILL.md の SHOULD 制約テーブル行追加と Spec の遡及更新）のため、機能リグレッションリスクは低かった。

#### merge
- 直コミット（patch route）。コンフリクトなし、マージプロセスに問題なし。

#### verify
- 2条件ともに `grep` verify コマンドが付いており、自動 PASS を確認。verify コマンドのパターン（`external.*depend\|depend.*package\|install.*step`）は実際の追加文言と一致しており、verify コマンドの精度は良好だった。

### Improvement Proposals
- N/A
