# Issue #161: run-code.sh に既存 PR 検出ガードを追加（watchdog retry による PR 重複を防止）

## Overview

`/auto` の watchdog retry によって `run-code.sh` が重複実行され、同一 Issue に複数の PR が作成される問題（#154 で発生）を防ぐ。

`run-code.sh` の pr route 実行時に、対象 Issue の open PR が既存であれば `claude -p` を起動せず exit 0 で終了する冪等性ガードを追加する。これにより watchdog retry や多重起動時の PR 重複を構造的に防止する。

## Changed Files

- `scripts/run-code.sh`: pr route 実行時の既存 PR 照会ガードを追加（stale worktree cleanup の前に挿入）
- `tests/run-code.bats`: 既存 PR 検出ガードに関する 4 つのテストケースを追加

## Implementation Steps

1. `scripts/run-code.sh` の stale worktree cleanup（`# Cleanup stale worktrees/branches from previous failed runs` コメント行）の**前**に、`ROUTE_FLAG == "--pr"` 時のみ動作する PR 存在チェックブロックを追加する。（→ 受入条件 1, 2, 3）

   ```bash
   # Idempotency guard: skip if open PR already exists for this issue
   if [[ "$ROUTE_FLAG" == "--pr" ]]; then
     EXISTING_PR=$(gh pr list --head "*issue-${ISSUE_NUMBER}-*" --state open --json number -q '.[0].number' 2>/dev/null || true)
     if [[ -n "$EXISTING_PR" ]]; then
       echo "=== run-code.sh: Existing PR #${EXISTING_PR} detected for issue #${ISSUE_NUMBER}, skipping /code ==="
       echo "PR: $(gh pr view ${EXISTING_PR} --json url -q '.url')"
       print_end_banner "issue" "$ISSUE_NUMBER" "code"
       echo "Next actions:"
       echo "  - /review ${EXISTING_PR}"
       echo "  - /auto ${ISSUE_NUMBER}"
       exit 0
     fi
   fi
   ```

2. `tests/run-code.bats` に既存 PR 検出ガードのテストケースを追加する。（→ 受入条件 5）

   **gh モック拡張:** `setup()` の `gh` モックに `gh pr list --state open` への応答を追加。デフォルト（既存モック）は空レスポンス（PR なし）。PR 検出テストでは各テスト関数内でモックを上書きして PR 番号を返すよう切り替える。

   **追加テストケース:**
   - `--pr` 指定 + 既存 PR なし → claude が呼ばれる（従来通り）
   - `--pr` 指定 + 既存 PR あり → claude が呼ばれず exit 0、"Existing PR #N detected" が出力される
   - `--patch` 指定 + 既存 PR あり → ガードが作動せず claude が呼ばれる
   - ROUTE_FLAG 未指定 + 既存 PR あり → ガードが作動せず claude が呼ばれる

## Verification

### Pre-merge

- <!-- verify: file_contains "scripts/run-code.sh" "gh pr list --head" --> `run-code.sh` に既存 PR 照会ロジックが追加されている
- <!-- verify: file_contains "scripts/run-code.sh" "Existing PR" --> 既存 PR 検出時の出力メッセージが実装されている
- <!-- verify: file_contains "scripts/run-code.sh" "skipping /code" --> スキップ動作の出力メッセージが実装されている
- <!-- verify: file_exists "tests/run-code.bats" --> `tests/run-code.bats` が存在する（既存）
- <!-- verify: file_contains "tests/run-code.bats" "Existing PR" --> bats テストに既存 PR 検出のテストケースが追加されている
- <!-- verify: github_check "gh run list --workflow=test.yml --limit=1 --json conclusion --jq '.[0].conclusion'" "success" --> bats テスト CI が PASS する

### Post-merge

- 手動で既存 PR を作成した状態で `/auto N --pr` を実行し、claude -p が起動せず "Existing PR #M detected" が出力されることを確認
- `/auto 154` のような正常ケース（PR 未作成）でガードが誤作動せず通常通り PR が作成される
- watchdog retry シナリオで重複 PR が発生しなくなる（#162 効果測定の入力として観測）

## Notes

- **CI verify コマンド修正**: Issue body 受入条件 6 の verify command は `github_check "gh pr checks" "Run bats tests"` だが、Size S は patch route（PR なし）のため `gh run list` 形式に修正した。`github_check "gh pr checks"` はパッチルートでは UNCERTAIN になる（`verify-classifier.md` 参照）。
- **bats テスト input data format**: `setup()` 内の `gh` モックを `case` 文パターンで拡張し、`gh pr list --state open` 呼び出し時に PR 番号（例: `"456"`）または空文字を返すよう切り替える。各テスト関数内でモックファイルを再定義してパターンを差し替える方式（既存の stale branch テストと同じパターン）。
- **複数 open PR 存在時の挙動**: 先頭 1 件を採用、警告なし。Issue body の方針通り。
- **closed PR は検出対象外**: `--state open` を明示することで、ユーザーが意図的にクローズした PR の再利用を防ぐ。
- **run-auto-sub.sh は変更不要**: XL sub-issue 経由でも `run-code.sh` を呼び出すため、本修正が自動で効く。

## Spec Retrospective

(スペック側のレトロスペクティブはなし)

## Code Retrospective

### Deviations from Design
- N/A（スペックの実装コード例をそのまま適用した）

### Design Gaps/Ambiguities
- `gh` モックの拡張方法について Spec では「case 文パターンで拡張」と記載があったが、実際には if/elif チェーンで実装した。既存テストが if/elif パターンを使っており、それとの一貫性を優先した。機能的には同等。

### Rework
- Issue body の受入条件 6 の verify command（`gh pr checks` → `gh run list`）を patch route に適合する形に更新した。Spec では既に修正済みだったが、Issue body との同期が必要だったため修正と変更追跡コメントを実施した。

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- Spec は実装コードを正確に記述しており設計の乖離なし。verify command の patch route 非互換問題を Spec 側で正しく検出・修正済みだったが、Issue body への同期が遅延した（Code phase で対処）。

#### design
- N/A（本 Issue には design phase なし）

#### code
- 実装はスペック通りで、設計逸脱なし。`gh` モックの if/elif vs case 差異は機能的に等価。Issue body sync の rework が 1 件発生したが軽微。

#### review
- patch route のため PR なし、review は実施されなかった。

#### merge
- `d36a2af` として main に直接コミット（patch route）。コンフリクトなし。

#### verify
- 第 1 回 verify: 条件 1〜5 は PASS。条件 6（CI PASS）は UNCERTAIN（retrospective commit プッシュ直後の in_progress 状態で判定不能）。
- 第 2 回 verify（2026-04-14）: 全 6 条件 PASS を確認。条件 6 は CI run `b2b0329`（2026-04-14T04:50:12Z）が success として完了したため PASS。第 1 回 UNCERTAIN は一時的な in_progress 状態が原因であり、実装上の問題ではなかったことが確認された。
- 第 3 回 verify（2026-04-15）: 全 6 条件 PASS を再確認。実装に問題なし。Issue は OPEN 状態（パッチルート + auto-close disabled）。残存 opportunistic/manual 条件（#7, #8, #9）未チェックのため `phase/verify` を付与。

### Improvement Proposals
- verify 実行時に CI が in_progress の場合、UNCERTAIN として Issue を reopen するのではなく「pending」扱いにして、CI 完了後に再 verify を促すフローを検討すること。現在の設計では CI が単に実行中の状態でも reopen + fix-cycle ラベルが付与されてしまい、誤ったシグナルになる。
- `/spec` または `/code` フェーズで verify command の route 互換性（`gh pr checks` vs `gh run list`）を自動チェックし、patch route の Issue には patch route 互換の verify command を強制するバリデーションを追加することを検討。Issue body と Spec の間で verify command の不整合が発生しやすいため。
