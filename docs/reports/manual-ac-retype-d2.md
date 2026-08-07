# manual AC 区分 D2: observation 再型付けマッピング (#1164)

親 Issue #1158 の分割対応。`phase/verify` に滞留する `verify-type: manual` の post-merge AC のうち、区分 D2 (「実際に X を実行して…を確認する」実行シナリオ型) の 13 Issue / 16 AC 行を対象に、`verify-type: observation event=<name>` への再型付けを行った記録。

## 対象・件数内訳

- 対象 Issue: 13 件 (#1109 #1106 #1101 #1097 #1031 #954 #529 #515 #511 #507 #486 #446 #444)
- 対象 AC 行: 16 行 (#507 が 3 行、#446 が 2 行を持つため、Issue 単位の 13 件と AC 行単位の 16 行にずれがある)
- 再型付け: **12 行** (すべて `event=auto-run`)
- 対象外 (`manual` 維持): **4 行** (#507 が 3 行、#444 が 1 行)

## `event=` 有効値の制約

`event=` に使用できるのは `modules/verify-classifier.md` § observation Type が定める 5 つの有効値のみ: `pr-review-full` / `pr-review-light` / `auto-run` / `watchdog-kill` / `fix-cycle`。区分 D2 の条件文は「実際に X を実行して…を確認する」という実行シナリオ型であり、`/auto` のいずれかのフェーズ (issue / spec / code / review / verify) の内側で発火しうるものが大半のため、`auto-run` (取りこぼさない最も広いイベント) を選定した。5 値のいずれの emitter にも対応しない条件 (#444) は `manual` のまま維持し対象外とした。

## 再型付けマッピング

### `event=auto-run` (12 AC 行)

| Issue | event | 条件文の要約 | 選定根拠 |
|---|---|---|---|
| #1109 | auto-run | observation AC を持つ Issue に event 発火後 `/verify` を実行し、条件充足時に checkbox 更新・`phase/done` 遷移を確認 | `/verify` は `/auto` の verify phase として実行される。observation 機構自体を検証する条件であり、`/auto` 完了ごとに再チェックする意義が大きい |
| #1106 | auto-run | 自己 PR に `/auto` の pr route を実行し、merge precondition の警告が出ずに進行することを確認 | `/auto` 実行そのものが観測窓。**2026-08-04 の `/auto 1150` (PR #1151, 自己 PR・pr route・precondition `matches_expected: true`) で既に充足済み** — Issue コメントで記録済み |
| #1101 | auto-run | ベースブランチ側と同一行を変更する PR を実際にレビューし、conflict が MUST 指摘として検出されることを確認 | `/review` は `/auto` 実行の内側。`pr-review-full`/`pr-review-light` いずれの深度でも起こりうる指摘であり、深度を限定する狭いイベントだと取りこぼす |
| #1097 | auto-run | Size L の PR に `run-review.sh --full` を実行し silent no-op 検出が発生せず Response Summary が投稿されることを確認 | `--full` review は `/auto` の review phase 内で実行されうる。**2026-08-04 の `/auto 1150` (PR #1151, Size L・`--full`・exit 0 + Summary 投稿済み) で既に充足済み** — Issue コメントで記録済み |
| #1031 | auto-run | 実際に `/issue` を XL Issue に対して実行し、Step 12a→12c 完了時点で FleetView/pane に subagent が残らないことを目視確認 | `/issue` は `/auto` 実行の内側。非対話モードでは L/XL sub-agent fan-off が High-Stakes Decision として無条件 skip されるため `/auto` 自身の issue phase がこの条件を満たすことは構造的にないが、対話モードでの直接 `/issue` 実行という別経路が満たしうるため対象外にはせず `auto-run` を付与した |
| #954 | auto-run | 実際に Size=XL の Issue で `/issue` を実行し、3 エージェントの調査結果が手動介入なしに回収できることを確認 | #1031 と同型の留意点 (非対話モードでの Step 12a 無条件 skip) が適用される。同じ理由で対象外にはせず `auto-run` を付与する |
| #529 | auto-run | spec phase で Size が変化する Issue に `/auto N` を実行し、変化後の Size に応じた review 深度・route が自動選択されることを実運用で確認 | 条件文が `/auto N` の実行そのものを明示している |
| #515 | auto-run | 実プロジェクトで `/verify N` を複数回実行し、tool call parse 失敗の発生頻度が改善していることを定性的に確認 | `/verify` は `/auto` 実行の内側で反復実行される。「頻度が改善」は単発の event 発火では判定しづらい定性的・統計的な問いであり、専用の計測基盤は現状存在しないため、`/verify` 再チェック時の LLM 判断 (rubric 相当) に委ねる設計とする |
| #511 | auto-run | 実機 external connector を使う Issue を `/auto` 非対話モードで実行し、MCP smoke 呼び出しブロック時に SKIPPED が記録され run が中断しないことを確認 | Smoke Test 機構自体は本リポジトリの `/code` (`/auto` の内側) に実装済み (#511 で導入)。当該リポジトリ自身の将来 Issue が `## Smoke Test` + `mcp_call` を持てば発火しうる |
| #486 | auto-run | 削除系 PR (`file_not_exists`/`file_not_contains` AC を含む) を実際にレビューし FALSE POSITIVE が発生しないことを確認 | `/review` は `/auto` 実行の内側 |
| #446 条件1 | auto-run | サンプル Issue (新 verify command 提案) で `/issue` 実行し、既存 adapter pattern 確認 step が機能することを確認 | 「サンプル」に限らず、新規 verify command を提案する実 Issue が `/issue`/`/spec` (いずれも `/auto` の内側) で処理されるたびに発火しうる |
| #446 条件2 | auto-run | 同様に `/spec` 実行で確認 | 条件1と同じ根拠 |

### 対象外 (`manual` 維持、4 AC 行)

| Issue | event | 条件文の要約 | 対象外の理由 |
|---|---|---|---|
| #507 条件1 | 対象外 | saito/trading リポジトリで `/audit stats --since 2026-05-01` を実行し First-try 成功率の変化を確認 | 別リポジトリ (`saito/trading`) 依存。Issue 本文自身が「saito/trading リポジトリでの実際の `/audit stats` 実行確認が必要であり、機械的に自動検証できない」と明記済み (downstream から観測不能) |
| #507 条件2 | 対象外 | Outcome レポートに「対象 N 件 / 除外 M 件」表示が含まれることを確認 | 条件1と同一理由 (同一 Issue 内の並列条件) |
| #507 条件3 | 対象外 | 既存 trading レポートで Highlights 表示が再計算後に変わることを確認 | 条件1と同一理由 |
| #444 | 対象外 | `/audit stats` を再実行し、SKILL.md の手順だけで全工程が完走することを確認 | `/audit` は `/auto` のフェーズチェーンに含まれない独立 skill。`modules/verify-classifier.md` の 5 有効値はいずれも `/auto`・`/review`・`claude-watchdog.sh`・fix-cycle のいずれかが emitter であり、`/audit` 単独実行に対応する event が存在しない (機構側の語彙制約による除外) |

## 検証

`${CLAUDE_PLUGIN_ROOT}/scripts/opportunistic-search.sh --event auto-run --dry-run` (read-only。`--dry-run` は `observation-trigger.sh` とのインターフェース互換のために受理される no-op) を実行し、再型付け後の AC がマッチ対象になることを確認した。

- 実行結果: マッチ 85 AC 行 (2026-08-07 実測)
- 再型付け前 baseline (Spec 記載, #1163 適用後 2026-08-06 実測): 59 AC 行
- 本 Issue で再型付けした 12 AC 行 (#1109 #1106 #1101 #1097 #1031 #954 #529 #515 #511 #486 #446×2) は **全件マッチ集合に含まれることを確認済み** (Python で機械的に突合、各 1 回 / #446 のみ 2 回のマッチを確認)
- baseline 59 との単純差分 (+26) は再型付け 12 行と一致しない。同期間に他 sub-issue (#1165〜#1167 等、親 #1158 の並行対応) や `/auto` 実行由来の新規 `observation event=auto-run` AC が母集団に加わった可能性があり、本 Issue の再型付けだけが変動要因ではない。目視突合で対象 12 行の含有を直接確認しているため、件数差分の厳密一致よりもこちらを正とする

### GitHub 上の実状態

- `gh issue view 1109 --json body`: `verify-type: observation event=auto-run` へ再型付け済みを確認
- `gh issue view 1106 --json body`: `verify-type: observation event=auto-run` へ再型付け済みを確認 (既充足コメントも投稿済み)
- `gh issue view 1097 --json body`: `verify-type: observation event=auto-run` へ再型付け済みを確認 (既充足コメントも投稿済み)
- `gh issue view 446 --json body`: 2 条件とも `verify-type: observation event=auto-run` へ再型付け済みを確認
- `gh issue view 507 --json body`: 3 条件とも `verify-type: manual` のまま維持されていることを確認 (対象外)
- `gh issue view 444 --json body`: `verify-type: manual` のまま維持されていることを確認 (対象外)
