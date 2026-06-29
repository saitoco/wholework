# Issue #841: modules/verify-patterns.md §23 Decision Procedure を git 以外の non-contiguous シンボルへ汎化

## Overview

`modules/verify-patterns.md §23` の Decision Procedure (step 1) が `git commit` / `git push` のみを例示しており、同セクション本文の「任意のフラグ挿入コマンドに汎化する」宣言と矛盾していた。また、ssh の例示に `ssh -i key host` という placeholder 文字列を使っており、「例示には常に実在リテラルを使う」という §23 自身のガイドラインを自己適用できていなかった。

本 Issue では以下の 3 点を修正する:
- **A**: Decision Procedure (step 1) を git 限定から ssh / kubectl / docker compose 等も含む汎化形式へ更新
- **B**: ssh 例示の `ssh -i key host` placeholder を実在リテラル `ssh -i ~/.ssh/key user@host` に置換
- **C**: `tests/verify-heuristics.bats` に regression test を追加

## Consumed Comments

- saito (MEMBER, first-class): Issue Retrospective — AC3 verify command のパッチ経路修正 (`gh pr checks` → `gh run list`)、AC1・AC2 への補助 `file_contains` 追加、Auto-Resolve ログ (セクションタイトル変更スコープ外の判断) を記録
  URL: https://github.com/saitoco/wholework/issues/841#issuecomment-4828212222

## Changed Files

- `modules/verify-patterns.md`: §23 "Generalizes to any command" テーブルに `kubectl` / `docker compose` 行を追加、ssh 行のキーパス placeholder `key` を `~/.ssh/key` に修正 — bash 3.2+ 非該当 (Markdown ファイル)
- `modules/verify-patterns.md`: §23 Decision Procedure step 1 を汎化 — git のみの例示から ssh / kubectl / docker compose 等を含む汎化形式へ、`ssh -i key host` を `ssh -i ~/.ssh/key user@host` に修正 — bash 3.2+ 非該当 (Markdown ファイル)
- `tests/verify-heuristics.bats`: §23 汎化確認の regression test 3 件を追加 — bash 3.2+ compatible

## Implementation Steps

1. `modules/verify-patterns.md §23` の "Generalizes to any command" テーブルを更新する (→ AC1, AC2)
   - ssh 行: `ssh -i key myserver "deploy.sh"` → `ssh -i ~/.ssh/key user@host "deploy.sh"` に修正
   - kubectl 行を追加: `kubectl --context prod apply -f manifest.yaml` → contiguous anchor `apply -f`
   - docker compose 行を追加: `docker compose -f docker-compose.prod.yml up` → contiguous anchor `compose up` or `up --detach`

2. `modules/verify-patterns.md §23` の Decision Procedure step 1 を更新する (→ AC1, AC2)
   - e.g. リストを git 限定から一般化: `"git commit"`, `"git push"`, `"kubectl apply"`, `"docker compose up"`, `"ssh user@host"` を列挙
   - `ssh -i key host` placeholder → `ssh -i ~/.ssh/key user@host` に修正

3. `tests/verify-heuristics.bats` に以下の regression test を追加する (→ AC3)
   - `verify-heuristics: §23 generalization includes kubectl example` — `grep -q "kubectl" "$VERIFY_PATTERNS"`
   - `verify-heuristics: §23 generalization includes docker compose example` — `grep -q "docker compose" "$VERIFY_PATTERNS"`
   - `verify-heuristics: §23 ssh example uses real key path` — `grep -q "~/.ssh/" "$VERIFY_PATTERNS"`

## Verification

### Pre-merge

- <!-- verify: rubric "modules/verify-patterns.md の non-contiguous heuristic セクションの Decision Procedure (step 1) が git commit に限定されず、ssh / kubectl / docker compose 等の例も含めて汎化されている" --> §23 Decision Procedure が git 以外の non-contiguous シンボル (ssh / kubectl / docker compose 等) も含めて汎化されている
  <!-- verify: file_contains "modules/verify-patterns.md" "kubectl" -->
  <!-- verify: file_contains "modules/verify-patterns.md" "docker compose" -->
- <!-- verify: rubric "modules/verify-patterns.md §23 の例示部分に host command 等の placeholder 文字列がなく、実在リテラル (ssh -i ~/.ssh/key user@host 等) に置換されている" --> §23 の例示が placeholder 文字列を含まず実在リテラルに置換されている
  <!-- verify: file_contains "modules/verify-patterns.md" "~/.ssh/" -->
- <!-- verify: github_check "gh run list --workflow=test.yml --limit=1 --json conclusion --jq '.[0].conclusion'" "success" --> `tests/verify-heuristics.bats` に placeholder pattern 検出の regression test が追加されており CI が通過している

### Post-merge

- 次回 verify command 生成時、ssh / kubectl 等の git 以外の non-contiguous シンボルでも heuristic が機能することを観察 (verify-type: observation)

## Notes

- **セクションタイトル変更スコープ外 (auto-resolved)**: §23 のタイトル `Non-Contiguous Git Invocation` は変更しない。既存の regression test (`grep -q "Non-Contiguous Git Invocation"` in `tests/verify-heuristics.bats`) との互換性を維持するため。タイトル変更は別 Issue に委ねる。
- **実装前確認**: `kubectl`, `docker compose`, `~/.ssh/` はいずれも現在 `modules/verify-patterns.md` に存在しないことを確認済み (`grep -c` = 0)。実装後に `file_contains` verify command が通過する。

## Code Retrospective

### Deviations from Design

- 実装コミットのプレフィックスを `chore:` (Type=Task) ではなく `feat:` を使用した。変更内容 (ガイドライン文書の機能追加) が Feature 相当と判断したため。影響なし。

### Design Gaps/Ambiguities

- Spec の Overview では `ssh -i key host` という placeholder 形式を記載していたが、実際の元テキストは `ssh -i key myserver "deploy.sh"` だった。Spec と現実の差異はあったが実装目標 (実在リテラル化) には影響なし。

### Rework

- None

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- `ssh -i key myserver "deploy.sh"` → `ssh -i ~/.ssh/key user@host "deploy.sh"` に修正 (ホスト名 placeholder `myserver` も実在形式の `user@host` に置換)
- Decision Procedure step 1 の e.g. リストに `"kubectl apply"`, `"docker compose up"`, `"ssh user@host"` を追加し、挿入フラグ例に `kubectl --context prod`, `docker compose -f` を明示
- 既存 regression test との互換性保持のため §23 タイトル (`Non-Contiguous Git Invocation`) は変更しない

### Deferred Items
- §23 タイトルを "Non-Contiguous Symbol Invocation" に変更する件は別 Issue に委ねた
- AC3 `github_check` は push 後に CI が実行されてから確認 (patch route 特性)

### Notes for Next Phase
- All file_contains verify commands (kubectl, docker compose, ~/.ssh/) PASS 済み。rubric PASS。CI (AC3) のみ push 後に確認
- bats tests 全件 PASS (exit code 0、558 tests)
- forbidden expressions check PASS (exit code 0)
