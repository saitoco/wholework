# Issue #861: scripts: 各 phase 開始時 (run-*.sh 冒頭) に session isolation check を追加

## Overview

並列セッション環境で複数の `/auto` セッションが parent repo を共有している場合、各 phase 開始時に他セッションの作業ファイルが parent main に残置されていても検出できなかった。本 Issue では `run-spec.sh` / `run-code.sh` / `run-review.sh` / `run-merge.sh` / `run-auto-sub.sh` の冒頭で `check-verify-dirty.sh` を呼び出す session isolation check を追加し、early detection を実現する。

- **parent main の重大 dirty** (tracked file 未 commit): `exit 1` で abort
- **他 worktree / 他 session 由来の dirty**: `exit 2` → warning 出力のみ、処理続行 (best-effort)
- **自 worktree 由来の dirty**: `exit 0` として無視
- **check 自体が失敗** (スクリプト不存在等): `[[ -x ... ]]` guard で skip → block しない

## Changed Files

- `scripts/run-spec.sh`: SCRIPT_DIR 設定直後に session isolation check block を追加 — bash 3.2+ compatible
- `scripts/run-code.sh`: SCRIPT_DIR 設定直後に session isolation check block を追加 — bash 3.2+ compatible
- `scripts/run-review.sh`: SCRIPT_DIR 設定直後に session isolation check block を追加 (引数は `$PR_NUMBER`) — bash 3.2+ compatible
- `scripts/run-merge.sh`: SCRIPT_DIR 設定直後に session isolation check block を追加 (引数は `$PR_NUMBER`) — bash 3.2+ compatible
- `scripts/run-auto-sub.sh`: SCRIPT_DIR 設定直後に session isolation check block を追加 (引数は `$SUB_NUMBER`) — bash 3.2+ compatible
- `tests/run-spec.bats`: setup に `check-verify-dirty.sh` mock (exit 0) 追加、exit 1 / exit 2 の新規 test case 追加
- `tests/run-code.bats`: setup に `check-verify-dirty.sh` mock (exit 0) 追加、exit 1 / exit 2 の新規 test case 追加
- `tests/run-review.bats`: setup に `check-verify-dirty.sh` mock (exit 0) 追加、exit 1 / exit 2 の新規 test case 追加
- `tests/run-merge.bats`: setup に `check-verify-dirty.sh` mock (exit 0) 追加、exit 1 / exit 2 の新規 test case 追加
- `tests/run-auto-sub.bats`: setup に `check-verify-dirty.sh` mock (exit 0) 追加、exit 1 / exit 2 の新規 test case 追加

## Implementation Steps

1. **run-spec.sh / run-code.sh への dirty check 追加**: `SCRIPT_DIR` 設定直後 (`AUTO_EVENTS_LOG` 設定前) に次の block を挿入。`$ISSUE_NUMBER` を引数に渡す。
   ```bash
   # Session isolation check: detect other-session dirty files (best-effort)
   if [[ -x "${SCRIPT_DIR}/check-verify-dirty.sh" ]]; then
     _dirty_exit=0
     bash "${SCRIPT_DIR}/check-verify-dirty.sh" "${ISSUE_NUMBER}" || _dirty_exit=$?
     case "${_dirty_exit}" in
       0) ;;
       1)
         echo "Error: parent main has uncommitted changes. Resolve before proceeding." >&2
         exit 1
         ;;
       2)
         echo "Warning: detected other-session dirty files. Proceeding (best-effort)." >&2
         ;;
     esac
   fi
   ```
   (→ AC1, AC2)

2. **run-review.sh / run-merge.sh への dirty check 追加**: `SCRIPT_DIR` 設定直後 (`AUTO_EVENTS_LOG` 設定前) に同 block を挿入。引数には `$PR_NUMBER` を渡す (review/merge は issue number を持たないため、best-effort proxy として PR number を使用; self-worktree 分類は機能しないが重大 dirty 検出は正常動作する)。
   (→ AC1, AC2)

3. **run-auto-sub.sh への dirty check 追加**: `SCRIPT_DIR` 設定直後 (`LOG_PREFIX` 設定前または直後、`AUTO_EVENTS_LOG` 設定前) に同 block を挿入。引数には `$SUB_NUMBER` を渡す。
   (→ AC1, AC2)

4. **bats テストへの mock + test case 追加** (全 5 bats ファイル共通):
   - setup 内の `emit-event.sh` mock 付近に `check-verify-dirty.sh` mock (exit 0) を追加:
     ```bash
     cat > "$MOCK_DIR/check-verify-dirty.sh" <<'MOCK'
     #!/bin/bash
     exit 0
     MOCK
     chmod +x "$MOCK_DIR/check-verify-dirty.sh"
     ```
   - exit 1 (abort) の新規テスト:
     ```bash
     @test "session-isolation: exit 1 causes abort with error" {
         cat > "$MOCK_DIR/check-verify-dirty.sh" <<'MOCK'
     #!/bin/bash
     exit 1
     MOCK
         chmod +x "$MOCK_DIR/check-verify-dirty.sh"
         run bash "$SCRIPT" <number>
         [ "$status" -eq 1 ]
         [[ "$output" == *"parent main has uncommitted changes"* ]]
     }
     ```
   - exit 2 (warning + continue) の新規テスト:
     ```bash
     @test "session-isolation: exit 2 shows warning and continues" {
         cat > "$MOCK_DIR/check-verify-dirty.sh" <<'MOCK'
     #!/bin/bash
     exit 2
     MOCK
         chmod +x "$MOCK_DIR/check-verify-dirty.sh"
         run bash "$SCRIPT" <number>
         [ "$status" -eq 0 ]
         [[ "$output" == *"other-session dirty files"* ]]
     }
     ```
   - `<number>` は各テストファイルの通常引数 (run-spec: `123`, run-code: `123`, run-review: `123`, run-merge: `123`, run-auto-sub: `123` 等)
   (→ AC3, AC4)

5. **`run-auto-sub.bats` の mock 追加注意**: `run-auto-sub.sh` は起動後すぐに `SUB_NUMBER=1` から始まる phase 処理に入るため、`WHOLEWORK_SCRIPT_DIR=$MOCK_DIR` 経由で `check-verify-dirty.sh` mock が呼ばれる。既存の setup で `run-spec.sh` / `run-code.sh` 等をモックしているのと同様に追加する。run-auto-sub.sh のテストでは exit 1 ケースで abort になるため `SCRIPT` は `run-auto-sub.sh` のパス、引数は `SUB_NUMBER` (例: `123`) を使う。
   (→ AC3, AC4)

## Verification

### Pre-merge

- <!-- verify: rubric "scripts/run-spec.sh / run-code.sh / run-review.sh / run-merge.sh / run-auto-sub.sh の冒頭 (Issue 番号確定後、phase 処理開始前) で check-verify-dirty.sh を呼んで dirty state を判定するロジックが追加されている" --> `scripts/run-spec.sh` / `run-code.sh` / `run-review.sh` / `run-merge.sh` / `run-auto-sub.sh` の冒頭で `scripts/check-verify-dirty.sh` を呼ぶロジックが追加されている
- <!-- verify: grep "check-verify-dirty" "scripts/run-code.sh" --> `run-code.sh` が `check-verify-dirty` を参照している (rubric の機械的補完)
- <!-- verify: grep "check-verify-dirty" "scripts/run-spec.sh" --> `run-spec.sh` が `check-verify-dirty` を参照している (rubric の機械的補完)
- <!-- verify: rubric "各 run-*.sh の dirty check ロジックで、parent main の重大 dirty (tracked file 未 commit) の場合のみ非ゼロ exit で abort し、他セッション由来の dirty (他 worktree / 他 session dir) は warning 出力のみで処理続行する best-effort 設計になっている" --> check の結果 parent main の重大 dirty 検出時のみ abort し、他セッション由来の dirty は warning + 処理続行する設計になっている
- <!-- verify: command "bats tests/" --> bats test で「他セッション由来 dirty は warning のみ」「parent main 重大 dirty は abort」両ケースが assert されている

### Post-merge

- 次回並列セッション環境で各 phase 開始時に他セッション由来 dirty が warning として表示されることを観察 <!-- verify-type: manual -->

## Consumed Comments

- saito / MEMBER / first-class / Issue Retrospective: bats test verify command scope (full suite 採用) および rubric AC への補完 grep 追加の自動解決記録 / https://github.com/saitoco/wholework/issues/861#issuecomment-4839316146

## Notes

- `run-review.sh` と `run-merge.sh` は PR 番号を受け取るため、`check-verify-dirty.sh` に `$PR_NUMBER` を渡す。スクリプト内で worktree 分類の正確な self-worktree 識別はできないが、parent main の重大 dirty 検出 (exit 1 → abort) は正常に機能する。best-effort の制約として Notes に記録。
- Issue body の proposal コード `2>&1 | tee >(cat >&2) || _exit=$?` には PIPESTATUS bug がある (`||` は tee の exit code を捕捉する)。シンプルな `|| _dirty_exit=$?` パターンに変更して実装する。
- `[[ -x "${SCRIPT_DIR}/check-verify-dirty.sh" ]]` guard により、スクリプト不存在時は check 全体を skip → main flow を block しない。
- Issue body で auto-resolve されたあいまいさ: (1) bats test scope → `bats tests/` (full suite) 採用、(2) rubric の補完 grep → `run-code.sh` / `run-spec.sh` の 2 件のみ

## review retrospective

### Spec vs. 実装乖離パターン

特記なし。Spec の実装ステップ (SCRIPT_DIR 直後への block 挿入、引数の選択、case 文パターン) が diff に忠実に反映されており、Spec → 実装の転写は正確だった。`run-review.sh` / `run-merge.sh` が `$PR_NUMBER` を proxy として使用する設計変更も Spec に明示されており、乖離なし。

### 繰り返し発生する Issue

- 特記なし。本 PR は全 5 スクリプトに同一パターンを追加するシンプルな変更のため、繰り返しパターンの課題はなかった。
- CONSIDER 指摘: `case` 文に `*)` catch-all がない (予期しない exit code がサイレント通過)。best-effort 設計として許容範囲だが、同パターンが今後も発生する場合は Spec のテンプレートコードに `*)` を追加することを検討。

### AC 検証難易度

- 全 AC が PASS。`command "bats tests/"` は CI 代替検証 (Run bats tests SUCCESS) で PASS を確認できたため、safe mode でも問題なく処理できた。
- rubric AC の判定は diff の内容から明確に評価でき、UNCERTAIN なし。verify command の品質が高く検証が容易だった。

## Phase Handoff
<!-- phase: review -->

### Key Decisions

- REVIEW_DEPTH=light を適用 (Size M + --light 引数)。Step 10.0 lightweight integrated review を単一エージェントで実行。
- 外部レビューツール (copilot/claude-code-review/coderabbit) が全て無効のため Step 7 をスキップ。
- MUST issues なし。CONSIDER 1 件 (case 文の `*)` catch-all 未実装) のみ。Step 12 フィックスはスキップ。
- `review-light` サブエージェントの代わりにインライン分析を実施 (エージェントファイルがセッション未登録のため)。

### Deferred Items

- `*)` catch-all の追加は CONSIDER 相当のため今回は対応なし。必要であれば別 Issue で扱う。
- Post-merge verification (並列セッション環境での warning 観察) はポスト・マージ手動確認タスク。

### Notes for Next Phase

- MUST issues なし → `/merge 872` を直接実行可能。
- CI 全ジョブ SUCCESS 確認済み。
- PR ブランチ `worktree-code+issue-861` は既存 worktree で使用中のため、merge phase は通常フローで実行すること。
