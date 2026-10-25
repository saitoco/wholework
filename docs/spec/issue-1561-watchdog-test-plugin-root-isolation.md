# Issue #1561: tests: watchdog の kill 分岐のテストが CLAUDE_PLUGIN_ROOT を継承し、本物の observation-trigger.sh を呼んで誤投稿と FAIL を起こす

## Issue Retrospective

### 実施内容

- トリアージ自動連鎖で Type=Bug、Size=XS、Value=2、`theme/observability` を付与した。Size は変更ファイルが `tests/claude-watchdog.bats` 1 件の想定で、原因が明確なバグ修正のため XS (CI 変更を伴わないので CI 依存の最小 M への引き上げは対象外)
- Background の事実主張 (`claude-watchdog.sh` L139-140 の kill 分岐、`run-code.sh` の `CLAUDE_PLUGIN_ROOT` export) をコードで確認した。不一致なし

### 受け入れ条件の変更

- AC1 に `file_contains "tests/claude-watchdog.bats" "CLAUDE_PLUGIN_ROOT"` を併記した。現状 `tests/claude-watchdog.bats` に `CLAUDE_PLUGIN_ROOT` の記述は 0 件なので常時 PASS にはならず、rubric の機械的な補強になる
- 新規 AC として「追加する確認手段が、修正前の挙動に対して FAIL する検出力を持つ」ことを問う rubric を追加した。AC2 は新規テストの追加を主張しうる形で、検出力ゼロのテスト (`CLAUDE_PLUGIN_ROOT` 未設定でしか走らない、など) でも文言上は満たせてしまうため。triage の AC 監査 (Pattern 2 の注意喚起) が実装前に求める対処を、起票時点で AC として織り込んだ
- Background に、現状 `tests/claude-watchdog.bats` が `CLAUDE_PLUGIN_ROOT` を扱っていないという前提を `<!-- premise: ... -->` マーカーで記録した。別の変更で先に解消された場合に `/audit premise` が検出できる

### Auto-Resolve Log

## Autonomous Auto-Resolve Log

- **対処方法 (環境変数を引き継がない / stub に差し替える / CI で設定して実行) の選択は `/code` に委ねる** — reason: AC1・AC2 の文言がどの方法でも成立し、AC の文面に影響しない。`tests/claude-watchdog.bats` の `setup()` は既に `EMIT_*` の `unset` と `AUTO_EVENTS_LOG` の差し替えで隔離しており (#1136)、同じ流儀で `CLAUDE_PLUGIN_ROOT` を扱うのが既存パターンに沿う
  - Other candidates: CI のジョブで `CLAUDE_PLUGIN_ROOT` を設定して実行する
- **既に投稿された誤コメント (#535・#585・#802 ほか) の削除は対象外** — reason: Issue の目的は再発防止で、過去コメントの扱いは AC に含まれていない
  - Other candidates: 誤コメントを併せて削除する (スコープが広がるため別 Issue 向き)

### Consumed Comments

No new comments since last phase.
