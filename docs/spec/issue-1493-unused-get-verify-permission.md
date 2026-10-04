# Issue #1493: scripts: 未使用の get-verify-permission.sh を verify-executor から利用するか削除する

## Issue Retrospective

### Autonomous Auto-Resolve Log

- **スクリプトを削除する (verify-executor から利用する案は採らない)** — reason: `modules/verify-executor.md` § Permission Semantics が「Permission に基づく実行時 enforcement は out of scope、table は意図の記録のみ」と明記しており、スクリプト化しても消費先がない。LLM が直接読む既存実装を維持するのが最小変更で、AC も削除方針でのみ決定的に判定できる
  - Other candidates: `modules/verify-executor.md` のカスタムハンドラー読み取り手順からスクリプトを呼ぶ形に変更して残す

### Acceptance Criteria の変更理由

- 元の AC は「呼び出し元がある、またはスクリプトが削除されている」という二択の disjunction だった。方針を削除に確定したため、決定的に判定できる `file_not_exists` x2 と `file_not_contains` に分解した
- 元の rubric は両方針を含む条件文だったため、削除後の参照取り残しがないこと、および verify-executor の Permission 読み取り手順が維持されていることを確認する形に絞った
- `docs/ja/structure.md` は `/doc translate` の自動生成物のため AC 対象外とした (`docs/spec/issue-276-*.md` は過去 Spec のため同様に対象外)

### Title

方針確定により scope が狭まったため、タイトルを「…を verify-executor から利用するか削除する」から「…を削除する」へ更新した。

### Background の事実確認

「呼び出し元が `docs/structure.md` と `tests/get-verify-permission.bats` だけ」という記述は `grep -rl` で確認済み (ほかに過去 Spec `docs/spec/issue-276-verify-executor-permission.md` と翻訳出力 `docs/ja/structure.md` のみ)。

### Consumed Comments

No new comments since last phase.

## Consumed Comments
No new comments since last phase.
