# Issue #418: verify: unrelated spec dirty scenario bats test promotion

## Overview

Issue #399 の verify retrospective で提起された改善提案。`/verify` Step 1 の "unrelated spec ファイルが dirty な場合に stash して継続する" ロジックをスクリプトとして抽出し、bats テストで自動検証できるようにする。あわせて Issue #399 の opportunistic post-merge 条件を auto 検証に昇格させる。

具体的には以下を実施する:
- `scripts/check-verify-dirty.sh` を作成し、dirty ファイルを分類するロジックをカプセル化する
- `tests/verify-dirty-detection.bats` でそのスクリプトを網羅的にテストする
- `skills/verify/SKILL.md` Step 1 のインライン dirty 検知ロジックをスクリプト呼び出しに置き換える
- Issue #399 の post-merge 条件に verify command を追加し `verify-type: auto` に昇格させる

## Changed Files

- `scripts/check-verify-dirty.sh`: 新規作成 — dirty ファイル分類スクリプト (bash 3.2+ 互換)
- `tests/verify-dirty-detection.bats`: 新規作成 — `check-verify-dirty.sh` の bats テスト (6 シナリオ)
- `skills/verify/SKILL.md`: Step 1 のインライン dirty 検知ロジックを `check-verify-dirty.sh` 呼び出しに置き換え; `allowed-tools` に `${CLAUDE_PLUGIN_ROOT}/scripts/check-verify-dirty.sh:*` を追加
- `docs/structure.md`: tests カウント 55 → 56 に更新; Scripts Key Files > Project utilities に `check-verify-dirty.sh` エントリを追加
- `docs/ja/structure.md`: `docs/structure.md` の変更を日本語で反映 (translation sync)
- Issue #399 body: post-merge 条件に `<!-- verify: command "bats tests/verify-dirty-detection.bats" -->` を追加し `verify-type: opportunistic` → `verify-type: auto` に変更

## Implementation Steps

1. `scripts/check-verify-dirty.sh` を作成 — 引数: issue 番号; `git status --short` で dirty ファイルを取得し分類; 終了コード: 0=clean, 2=全ファイルが unrelated spec (bash 3.2+ 互換の regex `[[ "$file" =~ $regex ]]` と `BASH_REMATCH` を使用); exit 1=other dirty ファイルあり; unrelated ファイルの場合は stdout にパスを出力 (→ 受入条件 A3)

2. `tests/verify-dirty-detection.bats` を作成 — `setup()` で `BATS_TEST_TMPDIR` に `git init`、初期コミット作成; 以下 6 シナリオをカバー (after Step 1) (→ 受入条件 A1, A2, A3):
   - clean: exit 0
   - unrelated spec dirty (issue 999, NUMBER=123): exit 2
   - related spec dirty (issue 123, NUMBER=123): exit 1
   - 非 spec dirty ファイル: exit 1
   - 複数 unrelated spec dirty: exit 2
   - unrelated + 非 spec mixed: exit 1

3. `skills/verify/SKILL.md` を更新 — Step 1 のインライン dirty 検知ロジックを `bash ${CLAUDE_PLUGIN_ROOT}/scripts/check-verify-dirty.sh $NUMBER` 呼び出しに置き換え; 終了コード 0/1/2 に基づく分岐に書き直す; `allowed-tools` に `${CLAUDE_PLUGIN_ROOT}/scripts/check-verify-dirty.sh:*` を追加 (after Step 1) (→ 受入条件 A3)

4. `docs/structure.md` と `docs/ja/structure.md` を更新 — tests カウント 55 → 56; Key Files > Scripts > Project utilities セクションに `scripts/check-verify-dirty.sh — dirty ファイルを unrelated spec または other に分類する /verify Step 1 ヘルパー` を追加 (parallel with 1, 2, 3)

5. Issue #399 body を `scripts/gh-issue-edit.sh` で更新 — post-merge 条件の行を: `- [ ] <!-- verify: command "bats tests/verify-dirty-detection.bats" --> Issue #393 と同様のシナリオ（verify 対象と無関係な Spec ファイルが dirty）で、verify が hard-error せず stash 提案 or 自動継続を選択できることを確認 <!-- verify-type: auto -->` に変更 (parallel with 4) (→ 受入条件 A4)

## Verification

### Pre-merge

- <!-- verify: file_exists "tests/verify-dirty-detection.bats" --> `tests/verify-dirty-detection.bats` が作成されている
- <!-- verify: grep "unrelated" "tests/verify-dirty-detection.bats" --> `tests/verify-dirty-detection.bats` に unrelated spec dirty シナリオをカバーするテストケースが含まれている
- <!-- verify: command "bats tests/verify-dirty-detection.bats" --> 追加した bats テストが PASS する

### Post-merge

- <!-- verify: command "gh issue view 399 --json body --jq '.body' | grep -q 'verify-dirty-detection'" --> Issue #399 の post-merge 条件に `verify-dirty-detection.bats` を参照する verify command が追加されている

## Code Retrospective

### Deviations from Design

- N/A: implementation steps followed the Spec exactly. The only adaptation was adding `touch docs/spec/.gitkeep && git add && git commit` in bats `setup()` to track the `docs/spec/` directory, ensuring `git status --short` shows individual file paths rather than the directory root. This matches the real-world state (where `docs/spec/` is already tracked) and the Spec Note requiring an initial commit for `git stash` compatibility.

### Design Gaps/Ambiguities

- The Spec's Note about requiring an initial commit for `git stash` was correct, but a further subtlety emerged: `git status --short` shows untracked directories as a single entry (e.g., `?? docs/`) rather than individual files unless the parent directory is already tracked. The test setup needed a `.gitkeep` commit to match the real-world behavior.

### Rework

- Test cases 2 and 5 initially failed because the test repo had an untracked `docs/` directory. Fixed by adding `touch docs/spec/.gitkeep` + initial commit in `setup()`.

## Notes

- `check-verify-dirty.sh` は `git status --short` のみ使用し、シブリングスクリプト呼び出しを行わない。既存 bats テストの `WHOLEWORK_SCRIPT_DIR` MOCK_DIR に mock の追加は不要
- scripts カウント: `docs/structure.md` の既記載 "(47 files)" と実ファイル数 46 の差異は既存 drift。`check-verify-dirty.sh` 追加後に 47 で一致するため scripts カウント変更は不要
- tests カウント: 現在 55、`verify-dirty-detection.bats` 追加後 56 → structure.md の "(55 files)" → "(56 files)" に更新が必要
- bats テストが `git stash` を含む git 操作を前提とするため、`setup()` では初期コミット作成が必須 (`git stash` は HEAD が存在しないと失敗する)
- `scripts/check-verify-dirty.sh` の スクリプト本体は `${CLAUDE_PLUGIN_ROOT}/scripts/check-verify-dirty.sh:*` として SKILL.md `allowed-tools` に記載するが、スクリプト自身の `SCRIPT_DIR` 変数は不要 (シブリング呼び出しなし)

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- Issue body の Auto-Resolved Ambiguity Points (A1–A3) がファイル名・テスト対象・昇格操作の曖昧さをすべて事前解消しており、実装中の判断ブレがなかった。
- Spec に `## Verification` セクション（verify command を明示）が含まれており、条件と検証手段の整合性が高い。

#### design
- Implementation Steps が Spec の設計通りに実装された（Code Retrospective: "N/A: implementation steps followed the Spec exactly"）。
- `git status --short` の挙動（untracked ディレクトリが個別ファイルではなくディレクトリ名で表示される）という細かい実装上の落とし穴が設計フェーズでは予見されていなかった。ただし修正は軽微だった。

#### code
- テストケース 2・5 が初回失敗（docs/ 未追跡の問題）。`setup()` に `.gitkeep` 初期コミットを追加して修正（小規模リワーク）。
- 最終的に 6/6 テストケースが PASS し、全受入条件を満たした。
- パッチルート（main 直コミット）で実装。PR レビューなし（スコープが小さく適切な判断）。

#### review
- PR を作成せず main 直コミットを採用。スコープが小さく（新規スクリプト＋bats テスト）、レビュー省略は妥当。
- ただし Issue #399 body の更新（verify-type 昇格操作）は副作用を伴うため、将来的に同種の変更は PR 経由が望ましい可能性がある。

#### merge
- 3 コミット（design / feat / code-retrospective）が main に直接マージ。コンフリクトや CI 失敗なし。

#### verify
- 全4条件が初回実行で PASS。FAIL/UNCERTAIN/PENDING ゼロ。
- Post-merge 条件（パイプを含む `command` ヒント）が non-interactive full モードで正常実行できた。
- `check-verify-dirty.sh` の抽出により SKILL.md のインライン dirty 検知が bats テスト可能な構造になり、CI で継続的に検証できるようになった。

### Improvement Proposals
- N/A
