# Issue #904: instrumentation: token_usage イベントの model フィールドが常に unknown になる不具合を修正

## Overview

`docs/sessions/*/events.jsonl` に記録される `token_usage` イベントの `model` フィールドが、実データ上すべて `"unknown"` になっている不具合を修正する。原因は `scripts/run-auto-sub.sh` の抽出ロジックが実在しない `.model` トップレベルキーを参照している点にあり、実際の model ID は `modelUsage.<model-id>.*` 形式で格納されている。修正スコープは `run-auto-sub.sh` の抽出ロジックのみに閉じる (書き込み側スクリプトは無関係)。

## Consumed Comments

- login: saito / authorAssociation: MEMBER / trust tier: first-class — `/issue 904 --non-interactive` の Issue Retrospective。triage 自動連鎖 (Type=Bug, Size=S, Value=3)、タイトル正規化、Background 行番号ドリフト修正 (409-415 → 425-435)、および曖昧点3件 (書き込み側修正の要否、複数 model キー時の選択ルール、Reference 行番号) の非対話自動解決ログを含む。内容は既に Issue 本文の Auto-Resolve Log セクションに反映済み。 (https://github.com/saitoco/wholework/issues/904#issuecomment-4883441136)

### code phase (cutoff: 2026-07-04T18:58:04Z)

No new comments since last phase.

## Reproduction Steps

1. 実際にリポジトリへ残存するアーカイブ済みセッションログを確認する: `token_usage` イベントを1件以上含む `docs/sessions/*/events.jsonl` をサンプル走査した5件 (`62650-1782653419-2026-06-28`, `82534-1782700033-2026-06-29`, `89954-1782720565-2026-06-29`, `98315-1782515143-2026-06-27`, `98856-1781977087-2026-06-22`) すべてで、`model` フィールドが例外なく `"unknown"` になっていることを確認した (例: `{"ts":"2026-06-20T18:01:34Z","issue":696,"event":"token_usage",...,"model":"unknown",...}`)。
2. リポジトリに残存する実際の `claude -p --output-format json` 出力サンプル (`.tmp/token-usage-891.json` ほか) を確認すると、トップレベルの `.model` キーは常に `null` であり、実際の model ID は `.modelUsage.<model-id>.*` (例: `.modelUsage.claude-sonnet-5.inputTokens`) 配下に格納されている。
3. 現在の抽出コマンド `jq -r '.model // empty' .tmp/token-usage-891.json` を実データに対して実行すると空文字列を返す。これが `scripts/run-auto-sub.sh:435` の `${_model:-unknown}` フォールバックを常に発火させ、`"unknown"` が記録される。

## Root Cause

`scripts/run-auto-sub.sh:429` の `_model=$(jq -r '.model // empty' "$_token_usage_file" ...)` は、`claude -p --output-format json` の出力に `.model` というトップレベル文字列キーが存在するという誤った前提に基づいている。実際には (`.tmp/token-usage-891.json`, `-884.json` 等、複数の実サンプルで確認済み) このキーは常に `null` であり、jq の `//` 演算子は `null` を偽値として扱うため `empty` にフォールスルーする。結果として `_model` は常に空文字列になり、bash 側の `${_model:-unknown}` フォールバックが常時発火して `model` フィールドが無条件に `"unknown"` になる。この因果関係は上記アーカイブ済みセッションログのサンプル調査でも裏付けられている。

副次的な要因として、既存のリグレッションテスト (`tests/run-auto-sub.bats:585-627`) は `run-code.sh` のモックとしてトップレベルに `"model":"claude-sonnet-4-6"` という文字列を直接持つ架空の fixture を書き込んでおり、これは実際の CLI 出力形状 (`.model` は常に `null`) と乖離している。そのためテストは現状の (バグを含む) `.model` 抽出パスを「成功」として通過させてしまい、fixture と実出力の形状の乖離を検知できていなかった。

また、`modelUsage` に複数の model キーが含まれるケースが実サンプル (`.tmp/token-usage-884.json`: `claude-sonnet-5` と `claude-haiku-4-5-20251001` の2キー — メイン処理と別 model を使った sub-agent の混在) で確認されており、抽出ロジックは単一値の `model` フィールドに詰める代表 model を選択する必要がある。

書き込み側スクリプト (`run-code.sh` / `run-review.sh` / `run-merge.sh`) は `claude -p --output-format json` の標準出力をそのまま `$TOKEN_USAGE_FILE` へリダイレクトしているのみであり、生成ロジック自体に問題はない (Issue フェーズで確認済み、本 Spec 作成時に同一サンプルで再確認)。修正は `run-auto-sub.sh` の抽出ロジックに閉じる。

## Changed Files

- `scripts/run-auto-sub.sh`: L429 の `_model=$(jq -r '.model // empty' ...)` を、`modelUsage` の全キーから入力+出力トークン合計が最大のキーを選択する抽出ロジックに変更する — `_model=$(jq -r '.modelUsage // {} | to_entries | if length == 0 then empty else (max_by(.value.inputTokens + .value.outputTokens) | .key) end' "$_token_usage_file" 2>/dev/null || true)` — bash 3.2+ compatible (jq 式のみの変更で bash 側の構文は不変)
- `tests/run-auto-sub.bats`: L598-606 付近の既存 `token_usage` テストの fixture を実際の CLI 出力形状 (`model: null` + `modelUsage.<model-id>.*`) に合わせて書き換え、アサーションを `token_usage` という文字列の存在チェックのみ (かつ不一致時は `skip` で握り潰す弱いガード) から、`model=<実ID>` の値そのものを検証する形に強化する。あわせて複数 `modelUsage` キー時の主要 model 選択 (トークン合計最大キー) を検証する新規テストケースを追加する — bash 3.2+ compatible
- `docs/reports/event-log-schema.md`: `token_usage` イベント節に、`modelUsage` が複数キーを持つ場合の主要 model 選択ルール (入力+出力トークン合計最大のキーを採用) を1文追記する
- `docs/migration-notes.md`, `docs/structure.md`, `docs/tech.md`, `docs/workflow.md` (および対応する `docs/ja/` 訳): [Steering Docs sync candidate] キーワード `run-auto-sub.sh` で検出。内容をプレビューした限り、いずれも verify フェーズ除去・retry-on-kill・resume probe 等 `token_usage`/`model` フィールドと無関係な記述であり、恐らく変更不要。最終判断は `/code` で確認する

## Implementation Steps

1. `scripts/run-auto-sub.sh` L429 の `_model` 抽出ロジックを、`modelUsage` オブジェクトの全キーを走査し入力+出力トークン合計が最大のキー名を返す jq 式に置き換える (`.model` 参照は完全に削除する) (→ acceptance criteria AC1, AC2, AC3)
2. `tests/run-auto-sub.bats` の既存 `token_usage: emit_event called ...` テスト (L585-627) の fixture JSON を実際の CLI 出力形状に合わせて書き換え (`"model":null` を含み、`modelUsage` に単一キーを持つ形)、アサーションを `grep -q "model=<実ID>"` へ強化する (after 1) (→ acceptance criteria AC1)
3. `tests/run-auto-sub.bats` に、`modelUsage` に2キー (トークン合計が異なる) を持つ fixture を用いた新規テストケースを追加し、トークン合計最大のキーが `model=` として emit されることを検証する (after 1) (→ acceptance criteria AC3)
4. `docs/reports/event-log-schema.md` の `token_usage` イベント節に、複数 `modelUsage` キー時の主要 model 選択ルールを1文追記する (→ ドキュメント整合性、直接対応する AC なし)

## Verification

### Pre-merge

- <!-- verify: rubric "scripts/run-auto-sub.sh の token_usage emit 経路で、.tmp/token-usage-*.json の modelUsage キーから実 model ID を抽出するよう修正されている" --> `run-auto-sub.sh` の token_usage emit で実 model ID が記録されるよう修正されている
- <!-- verify: grep "modelUsage" "scripts/run-auto-sub.sh" --> `run-auto-sub.sh` の抽出ロジックが `modelUsage` を参照している (存在しない `.model` キーへの参照から変更されたことの機械的裏付け)
- <!-- verify: rubric "modelUsage に複数 model キーが含まれる場合、入力+出力トークン合計が最大のキーが phase の主要 model として選択される" --> 複数 model 使用セッションで主要 model が適切に選択される

### Post-merge

- 次回 `/auto` 実行後の `docs/sessions/*/events.jsonl` の `token_usage` イベントで `model` フィールドが `"unknown"` ではなく実 model ID を保持していることを観察 <!-- verify-type: observation event=auto-run -->
  - Expected output structure:
    - `token_usage` イベントの `model` フィールド値が `"unknown"` ではないこと
    - `model` フィールド値が実在する model ID 形式 (`docs/tech.md` の model-effort-matrix に記載された ID、例: `claude-sonnet-5`) に一致すること

## Notes

- 複数 `modelUsage` キーのトークン合計が完全に同点の場合にどちらのキーが選ばれるかは jq `max_by` の実装挙動に依存するが、Issue の受入条件はこの挙動を規定しておらず本 Spec でも追加の規定は行わない (Issue フェーズの Auto-Resolve Log が採用した「最小リスクな解釈」の範囲内)。
- `jq` の `max_by` / `to_entries` / `// empty` の各構文は `scripts/get-auto-session-report.sh:346` で既に `max_by` が使われているなど、本リポジトリの既存パターンと整合している。加えて実サンプルファイル (`.tmp/token-usage-891.json`, `-884.json`) に対して実際に実行し、意図通りの挙動 (単一キー → そのキー、2キー → トークン合計最大のキー) を確認済み。
- `docs/reports/event-log-schema.md` は `modules/doc-checker.md` の Impact Assessment 既定スコープ (`docs/reports/` は除外対象) の対象外だが、Issue 本文の Reference が直接この節を指しており、本修正で `model` フィールドの実質的な意味 (常に `unknown` → 実 ID、かつ新規のタイブレークルール) が変わるため、Changed Files に含めた。

## Auto Retrospective
### Orchestration Anomalies
- **[code-patch-silent-no-op]** Tier 2 fallback applied: phase=`code-patch`, action=run-code.sh-patch-retry, result=recovered.

### Improvement Proposals
- N/A (resolved by Tier 2 fallback catalog)
