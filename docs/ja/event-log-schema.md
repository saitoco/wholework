[English](../event-log-schema.md) | 日本語

# Auto Event Log Schema

このドキュメントは、`/auto` セッション中に出力される構造化イベントログ `.tmp/auto-events.jsonl` のスキーマを定義します。

## 後方互換性の保証

- フィールドは **追加のみ** 行う — 既存のフィールド名を削除したり、型を変更したりしない。
- 利用側は未知のフィールドを許容しなければならない (前方互換な読み取り)。
- `ts`、`issue`、`event` フィールドはすべてのイベントに必ず存在する。

## 既存イベント (#600 で導入)

| イベント種別 | 説明 |
|---|---|
| `sub_start` | sub-issue の処理開始 |
| `phase_start` | フェーズ (spec/code/review/merge) の開始 |
| `wrapper_exit` | フェーズ実行スクリプトの終了 (exit_code 付き) |
| `recovery` | recovery tier の発動 |
| `phase_complete` | フェーズの正常完了 |
| `sub_complete` | sub-issue の処理完了 |
| `anomaly` | フェーズ出力で異常を検出 |
| `size_refresh` | spec フェーズ後に Issue の Size を再評価 |

## 新規イベント (#630 で導入)

### 1. `token_usage`

`AUTO_EVENTS_LOG` が設定されているとき、各フェーズの完了後に `run-auto-sub.sh` が出力する。`run-code.sh` / `run-review.sh` / `run-merge.sh` が書き出す `TOKEN_USAGE_FILE` をパースして生成する。`run-spec.sh` / `run-issue.sh` も自身の `spec` / `issue` フェーズについて直接出力する (#1228)。この場合は、これらのラッパーが自ら書き出すようになった同じ `TOKEN_USAGE_FILE` をパースする。

```json
{
  "ts": "2026-06-14T12:00:00Z",
  "issue": 1023,
  "event": "token_usage",
  "phase": "code",
  "model": "claude-sonnet-4-6",
  "input_tokens": "45000",
  "output_tokens": "12000",
  "cache_read_tokens": "18000"
}
```

| フィールド | 必須 | 説明 |
|---|---|---|
| `ts` | Yes | ISO 8601 UTC タイムスタンプ |
| `issue` | Yes | Issue 番号 |
| `event` | Yes | `"token_usage"` |
| `phase` | Yes | フェーズ名 (`code-patch`、`code-pr`、`review`、`merge`、`spec`、`issue`) |
| `model` | Yes | モデル識別子 (例: `claude-sonnet-4-6`)。`TOKEN_USAGE_FILE` の `modelUsage.<model-id>.*` キーから抽出する (CLI のトップレベル `.model` キーは常に `null` のため使わない) |
| `input_tokens` | Yes | 入力トークン数 (文字列) |
| `output_tokens` | Yes | 出力トークン数 (文字列) |
| `cache_read_tokens` | Yes | キャッシュ読み取りトークン数 (文字列、なければ `0`) |

`modelUsage` に複数のキーが含まれる場合 (例: sub-agent がメインセッションと異なるモデルを使った場合)、`inputTokens + outputTokens` の合計が最大のキーを、そのフェーズの代表 `model` として選ぶ。

**出力箇所**: `code-patch`/`code-pr`/`review`/`merge` は `run-auto-sub.sh` の `run_phase_with_recovery()`、`spec`/`issue` は `run-spec.sh`/`run-issue.sh` が直接出力する (`_EMIT_PHASE_OWNED` で制御)。いずれの場合も、`.tmp/token-usage-{issue}.json` が存在するとき、`wrapper_exit` イベントの直後に出力する。

**対象範囲**: `code-patch`、`code-pr`、`review`、`merge` (`run_phase_with_recovery` 経由で呼ばれる) と、`spec`、`issue` (各ラッパーが直接出力する、#1228)。`run-code.sh` を単独で呼び出した場合は `phase=code` の `phase_start`/`phase_complete` を出力するが、`token_usage` は出力しない。

---

### 2. `watchdog_kill`

ハングしたプロセスを kill する直前に `claude-watchdog.sh` が出力する。

```json
{
  "ts": "2026-06-14T12:00:00Z",
  "issue": 1023,
  "event": "watchdog_kill",
  "phase": "code",
  "pid": "42296",
  "silent_window_sec": "600",
  "timeout_setting": "1800"
}
```

| フィールド | 必須 | 説明 |
|---|---|---|
| `ts` | Yes | ISO 8601 UTC タイムスタンプ |
| `issue` | Yes | Issue 番号 (`EMIT_ISSUE_NUMBER` から取得) |
| `event` | Yes | `"watchdog_kill"` |
| `phase` | Yes | フェーズ名 (`EMIT_PHASE_NAME` から取得、未設定なら `unknown`) |
| `pid` | Yes | kill したプロセスの PID |
| `silent_window_sec` | Yes | kill のきっかけとなった無出力の秒数 |
| `timeout_setting` | Yes | 適用中の `WATCHDOG_TIMEOUT` の値 |

**出力箇所**: `claude-watchdog.sh` の `_auto_emit_watchdog_kill()`。通常モードと `OUTPUT_FORMAT_JSON=1` モードの両方で、`kill "$cmd_pid"` の直前に呼ばれる。

---

### 3. `max_silent_window`

監視対象のプロセスが終了した後 (自然終了でも kill でも)、`claude-watchdog.sh` が出力する。実行中に観測した連続無出力区間の最大値を報告する。

```json
{
  "ts": "2026-06-14T12:00:00Z",
  "issue": 1023,
  "event": "max_silent_window",
  "phase": "code",
  "max_sec": "480"
}
```

| フィールド | 必須 | 説明 |
|---|---|---|
| `ts` | Yes | ISO 8601 UTC タイムスタンプ |
| `issue` | Yes | Issue 番号 (`EMIT_ISSUE_NUMBER` から取得) |
| `event` | Yes | `"max_silent_window"` |
| `phase` | Yes | フェーズ名 (`EMIT_PHASE_NAME` から取得、未設定なら `unknown`) |
| `max_sec` | Yes | 観測した連続無出力の最大秒数 |

**出力箇所**: `claude-watchdog.sh` の `_auto_emit_max_silent()`。`wait "$cmd_pid"` が戻った後に呼ばれる (kill か自然終了かは問わない)。

---

### 4. `concurrent_commit_detected`

フェーズ開始以降に `origin/main` へのコミットを検出したとき、各フェーズの終了時に `run-auto-sub.sh` が出力する。

```json
{
  "ts": "2026-06-14T12:00:00Z",
  "issue": 1023,
  "event": "concurrent_commit_detected",
  "phase": "code",
  "commit_sha": "abc1234",
  "author": "saito",
  "since_phase_start_sec": "150"
}
```

| フィールド | 必須 | 説明 |
|---|---|---|
| `ts` | Yes | ISO 8601 UTC タイムスタンプ |
| `issue` | Yes | Issue 番号 |
| `event` | Yes | `"concurrent_commit_detected"` |
| `phase` | Yes | フェーズ名 |
| `commit_sha` | Yes | 並行コミットの完全な SHA |
| `author` | Yes | コミットの author 名 |
| `since_phase_start_sec` | Yes | フェーズ開始からの経過秒数 |

**出力箇所**: `run-auto-sub.sh` の `run_phase_with_recovery()`、`wrapper_exit` の後。見つかった並行コミット 1 件につき 1 イベントを出力する。定期ポーリングは行わず、オーバーヘッドを抑えるためフェーズ終了時に 1 回だけ確認する。

**除外条件**: 次のコミットはカウントしない。(a) subject がこのフェーズ自身の Issue 番号を参照しているもの (review/merge フェーズでは PR 番号と元の Issue 番号の両方、Issue #895 と #974)、(b) subject が Issue 番号を一切参照していないもの (このフェーズ自身の中間コミットとみなす、Issue #1427)、(c) subject が、このフェーズ内でネストして動いたスキルが扱った Issue を参照しているもの。この Issue は、同じセッション内でこのフェーズの開始後に記録され、`pr` にこのフェーズの PR 番号を持つ `phase_start` イベントから特定する (Issue #1499、`modules/event-emission.md` を参照)。それ以外の Issue 番号を参照するコミットは出力対象となる。

---

### 5. `ci_wait`

CI のポーリング完了後に `wait-ci-checks.sh` が出力する。

```json
{
  "ts": "2026-06-14T12:00:00Z",
  "issue": 1023,
  "event": "ci_wait",
  "phase": "review",
  "wait_sec": "420",
  "checks_passed": "5",
  "checks_failed": "0"
}
```

| フィールド | 必須 | 説明 |
|---|---|---|
| `ts` | Yes | ISO 8601 UTC タイムスタンプ |
| `issue` | Yes | Issue 番号 (`EMIT_ISSUE_NUMBER` から取得) |
| `event` | Yes | `"ci_wait"` |
| `phase` | Yes | フェーズ名 (`EMIT_PHASE_NAME` から取得、未設定なら `review`) |
| `wait_sec` | Yes | CI 待機に費やした合計秒数 |
| `checks_passed` | Yes | `gh pr checks --json bucket` の値が `pass` のチェック数 |
| `checks_failed` | Yes | `gh pr checks --json bucket` の値が `fail` のチェック数 (`ERROR`/`FAILURE`/`TIMED_OUT`/`ACTION_REQUIRED` 状態を含む) |

**出力箇所**: `wait-ci-checks.sh`、最後の完了ログ行の直前。

**補足**: `checks_passed` と `checks_failed` は、`gh pr checks --json name,state,bucket` が返す `bucket` フィールドから `jq` で算出する。生の出力を grep して数えるのではない。

---

### 6. `test_result`

`code` フェーズ中に、フェーズのログファイルで bats のテスト出力を検出したとき `run-auto-sub.sh` が出力する。

```json
{
  "ts": "2026-06-14T12:00:00Z",
  "issue": 1023,
  "event": "test_result",
  "phase": "code",
  "framework": "bats",
  "passed": "17",
  "failed": "0",
  "pattern": "unit"
}
```

| フィールド | 必須 | 説明 |
|---|---|---|
| `ts` | Yes | ISO 8601 UTC タイムスタンプ |
| `issue` | Yes | Issue 番号 |
| `event` | Yes | `"test_result"` |
| `phase` | Yes | 常に `"code"` (code フェーズからのみ出力) |
| `framework` | Yes | テストフレームワーク (`bats`) |
| `passed` | Yes | 成功したテスト数 |
| `failed` | Yes | 失敗したテスト数 |
| `pattern` | Yes | テストパターンのラベル (`unit`) |

**出力箇所**: `run-auto-sub.sh` の `run_phase_with_recovery()`、`wrapper_exit` の後。code フェーズのログファイルに bats の出力パターン (`N tests, N failures`) が見つかったときに出力する。

## 新規イベント (#654 で導入)

### 7. `auto-session-report-published`

**Deprecated** — このイベントは `--narrative-draft` フラグに紐づいていたが、同フラグは #776 で削除された。現在このイベントを出力するコードパスはない。

```json
{
  "ts": "2026-06-15T12:00:00Z",
  "issue": 0,
  "event": "auto-session-report-published",
  "session_id": "abc-999",
  "report_path": "docs/reports/auto-session-abc-999-2026-06-15.md"
}
```

| フィールド | 必須 | 説明 |
|---|---|---|
| `ts` | Yes | ISO 8601 UTC タイムスタンプ |
| `issue` | Yes | 常に `0` (セッション単位のイベントで、特定の Issue に紐づかない) |
| `event` | Yes | `"auto-session-report-published"` |
| `session_id` | Yes | レポート生成対象のセッション ID |
| `report_path` | Yes | 生成されたレポートファイルのパス |

**出力箇所**: 以前は `--narrative-draft` 処理後の `scripts/get-auto-session-report.sh`。`--narrative-draft` 機能は #776 で削除されたため、このイベントは現在出力されない。

**対象範囲**: Deprecated — `--narrative-draft` フラグ使用時にのみ出力されていた。
