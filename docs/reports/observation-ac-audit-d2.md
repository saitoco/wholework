# observation AC 実査記録: D2 (#1164 由来, #1275)

親 Issue #1270 の sub-issue #1275 の実査記録。#1164 が区分 D2 (実行シナリオ型) として `verify-type: manual` から `verify-type: observation event=auto-run` へ再型付けした **12 AC 行 / 11 Issue** (#1109 #1106 #1101 #1097 #1031 #954 #529 #515 #511 #486 #446) を対象に、親 #1270 の判定基準 (A/B/C/D/E) に従い 1 行ずつ「どの event が発火したとき何を根拠に PASS 判定できるか」を実査した。

## 分類サマリ

| 分類 | 件数 | 対象 Issue |
|---|---|---|
| A (判定可能・維持) | 5 | #1109 #1106 #1101 #1097 #529 |
| B (条件文の書き換え) | 0 | — |
| C (event の差し替え) | 0 | — |
| D (判定不能・retire) | 0 | — |
| E (`manual` へ差し戻し) | 7 | #1031 #954 #515 #511 #486 #446×2 |
| **合計** | **12** | — |

D が 0 件のため、#1166 方式の retire コメント投稿・`phase/done` 遷移は本 Issue では発生しない。E はすべて「今すぐ `/verify` (manual) で判定できる」区分であり、capability 待ち (`capability=<key>`) に該当するものはない — 7 件とも装備不足ではなく、(a) `/auto` 非対話モードでの構造的制約 (Step 12a fan-out の無条件 skip)、(b) 統計的・定性的トレンド判断で単発 event 発火では信号を持たない、(c) 特定内容の Issue/PR が発生しない限り観測窓が開かない、のいずれかが理由である。

## 分類基準 (親 #1270 より継承)

| 分類 | 基準 |
|---|---|
| A | 指定 event の発火時に、条件文が要求する観測対象が実行事実・リポジトリ状態・GitHub 状態のいずれかから判定できる |
| B | 観測対象は存在するが条件文が曖昧/母集団定義を欠く → 書き換え |
| C | 判定可能だが event 選択が誤り → 差し替え |
| D | どの有効 event でも観測窓が開かず、`/verify` 実行時にも判定不能 → retire (#1166 方式) |
| E | event では観測窓が開かないが `/verify` 実行時に Claude が実際に操作・確認すれば判定できる → `manual` へ差し戻し |

## A: 判定可能 (5 行、維持)

いずれも「AC 行は編集せず維持」。以下は各行の判定根拠 (どの情報源を見れば PASS/FAIL/SKIPPED が決まるか)。

### #1109 — observation AC の event 発火後 `/verify` 実行で checkbox 更新・`phase/done` 遷移を確認

- **条件文**: 「observation AC を持つ Issue に対して event 発火後に `/verify` を実行し、条件が満たされている場合に checkbox が更新され `phase/done` へ遷移することを確認する」
- **判定根拠**: この条件は observation dispatch 機構自体の動作確認であり、observation AC を持つ Issue 群 (baseline 母集団 82 Issue) に対して `auto-run` が発火するたびに繰り返し観測機会が生じる。`.tmp/auto-events.jsonl` の `phase=verify` イベント (`session_id` で dispatch と対応付け) と、dispatch 対象 Issue の GitHub 上のラベル/checkbox 状態を突き合わせることで、observation dispatch 起点の `/verify` 実行が実際に checkbox 更新・`phase/done` 遷移まで到達したかを判定できる。#1109 自身の修正 (`/verify` の event 発火済み分岐、`modules/verify-executor.md` の記述更新) が本条件の評価手段そのものを定義しているため、循環参照ではなく自己整合的に判定可能
- **現状**: まだ「observation dispatch 起点の `/verify` 実行が checkbox を更新した」明確な実例は本実査時点で確認できていないため SKIPPED のまま。発火頻度が高いため今後の観測機会は多い

### #1106 — 自己 PR への `/auto` pr route 実行で merge precondition 警告が出ないことを確認

- **条件文**: 「自己 PR に `/auto` の pr route を実行し、merge precondition の警告が出ずに進行することを確認する」
- **判定根拠**: wholework は単一アカウントによる自己ホスト運用が前提であり、pr route を通る `/auto` 実行は**ほぼ全件が自己 PR** に該当する。`scripts/reconcile-phase-state.sh` の merge precondition 診断出力 (`review-summary` marker の有無、`reviewDecision`) が直接の判定材料になる
- **既存実例**: 2026-08-04 の `/auto 1150` (PR #1151、自己 PR・pr route) で `matches_expected: true` を確認済み — `docs/reports/manual-ac-retype-d2.md` に記録あり。頻度・実例とも十分でありA判定が妥当

### #1101 — ベースブランチとの同一行 conflict が MUST 指摘として検出されることを確認

- **条件文**: 「ベースブランチ側と同一行を変更する PR を実際にレビューし、conflict が MUST 指摘として検出されることを確認する」
- **判定根拠**: #1101 の Background に記録の通り、`modules/verify-executor.md` の `html_check` 行だけでも #424/#1056/#1074/#1069 の 4 件が編集しており、SSoT 文書での同一行 conflict は本リポジトリで実際に繰り返し発生している既知パターン。`/review` が投稿する PR コメント (merge-tree conflict の MUST 指摘) を event 発火時点の直近レビュー結果から確認できる
- **現状**: SKIPPED のまま (直近で該当 conflict が発生していない)。再発性が確認されている既知パターンのため今後の観測機会は見込める

### #1097 — Size L PR の `--full` review で silent no-op が発生しないことを確認

- **条件文**: 「Size L の PR に対して `run-review.sh <PR> --full` を実行し、silent no-op 検出が発生せず review 自身の Response Summary が投稿されることを確認する」
- **判定根拠**: Size L の PR は一定頻度で発生し、`--full` review はその都度実行される。`run-review.sh` の exit code と PR コメント (Response Summary の投稿有無) が直接の判定材料
- **既存実例**: 2026-08-04 の `/auto 1150` (PR #1151、Size L・`--full`・exit 0 + Summary 投稿済み) で確認済み — `docs/reports/manual-ac-retype-d2.md` に記録あり

### #529 — spec phase 後の Size 変化で route/review 深度が自動選択されることを確認

- **条件文**: 「spec phase で Size が変化する Issue に `/auto N` を実行し、変化後の Size に応じた review 深度・route が自動選択されることを実運用で確認する」
- **判定根拠**: spec phase での Size 変化 (M→L 等) は稀ではあるが実運用で一定数発生する。`.tmp/auto-events.jsonl` の Step 2 (dispatch 時 Size) と spec phase 後の `--no-cache` 再取得 Size を比較し、それに応じた route/review 深度選択を確認できる
- **既存実例**: 派生元 #501 (`/auto` 実行で spec phase が M→L に Size 再評価し、review 深度の手動切替が必要だった実例) が本条件の直接の動機であり、機構は実装済み

## E: `manual` へ差し戻し (7 行)

いずれも Issue 本文の `<!-- verify-type: observation event=auto-run -->` を `<!-- verify-type: manual -->` に書き換えた (AC 行の条件文自体は変更していない)。

### #1031 — `/issue` Step 12a subagent の pane 残留防止 (目視確認)

- **条件文**: 「実際に `/issue` を XL Issue に対して実行し、Step 12a → 12b → 12c 完了時点で FleetView / pane に subagent が残らないことを目視確認」
- **差し戻し理由**: Step 12a の並列 subagent fan-out は、非対話モードでは "High-Stakes Decision" として無条件 skip される (`modules/ambiguity-detector.md`)。`auto-run` を含む 5 つの有効 event 値はいずれも `/auto`・`/review`・`claude-watchdog.sh`・fix-cycle という**非対話実行由来**の emitter であるため、これら 5 event のいずれが発火しても Step 12a が実際に fan-out する瞬間には到達しない。つまり event 発火では観測窓が原理的に開かない
- **`/verify` 実行時に何をすれば判定できるか**: 対話モードで人間が直接 `/issue` を XL Issue に対して実行し、Step 12a→12c 完了直後に `ListAgents` で subagent の残留 (idle 状態) を確認する、または目視で FleetView / pane を確認する。これは Claude/人間が実際に操作すれば判定できるため D ではなく E とした

### #954 — `/issue` L/XL 並列 subagent の結果配信 (SendMessage/Write フォールバック)

- **条件文**: 「実際に Size=XL の Issue で `/issue` を実行し、3 エージェントの調査結果が手動介入なしに回収できることを確認する」
- **差し戻し理由**: #1031 と同型の構造的制約 — Step 12a の fan-out が非対話モードで無条件 skip されるため、5 つの有効 event 値のいずれでも観測窓が開かない
- **`/verify` 実行時に何をすれば判定できるか**: 対話モードで人間が Size=XL の Issue に対し `/issue` を実行し、3 エージェント (`issue-scope`/`issue-risk`/`issue-precedent`) の調査結果が `SendMessage` 経由 (または `Write` フォールバック経由) で手動介入なしに回収できたかを Spec の記載内容から確認する

### #515 — `/verify` の tool call parse 失敗頻度の定性的改善確認

- **条件文**: 「実プロジェクトで `/verify N` を複数回実行し、`The model's tool call could not be parsed` の発生頻度が改善していることを定性的に確認」
- **差し戻し理由**: `docs/reports/manual-ac-retype-d2.md` が再型付け時点で既に指摘済みの通り、「頻度が改善」は単発の event 発火では判定しづらい定性的・統計的な問いであり、発生頻度を追跡する専用の計測基盤が本リポジトリに存在しない。`auto-run` は「1 回の実行が起きた」という事実しか伝えず、複数回にわたる頻度比較のトレンド情報を持たないため、event 発火では観測窓が開かない
- **`/verify` 実行時に何をすれば判定できるか**: `/verify` 実行時に Claude が直近セッションでの `tool call could not be parsed` エラー遭遇頻度を rubric 相当の定性的判断で確認する。再型付け当初の設計意図 (「`/verify` 再チェック時の LLM 判断に委ねる」) とも整合する

### #511 — MCP smoke test ブロック時の SKIPPED 記録確認

- **条件文**: 「実機 external connector を使う Issue を `/auto` 非対話モードで実行し、MCP smoke 呼び出しがブロックされたケースで SKIPPED が記録され run が中断しないことを確認する」
- **差し戻し理由**: Smoke Test 機構自体は本リポジトリの `/code` に実装済みだが、条件の発火には「将来のある Issue が `## Smoke Test` + `mcp_call` を Spec に持ち、かつ非対話モードで実際にブロックされる」という特定内容の Issue が存在することが前提となる。`auto-run` はこの内容依存の前提と無関係に発火するため、大半の発火で観測窓が開かない (#446/#486 と同型の「特定内容の Issue/PR 依存」パターン)
- **`/verify` 実行時に何をすれば判定できるか**: `## Smoke Test` + `mcp_call` を持つ Issue が実際に `/code` 非対話モードで処理された際、Code Retrospective・completion message に SKIPPED 記録があるかを個別に確認する

### #486 — 削除系 PR レビューでの FALSE POSITIVE 防止確認

- **条件文**: 「削除系 PR (`file_not_exists` / `file_not_contains` AC を含む PR) を実際にレビューし、FALSE POSITIVE が発生しないことを確認する」
- **差し戻し理由**: 親 #1270 が名指しした実例。「該当タイプの PR が発生しない限り観測窓が開かない」(親 Issue 本文より) — `auto-run` は削除系 PR の有無と無関係に発火するため、大半の発火で SKIPPED になる
- **`/verify` 実行時に何をすれば判定できるか**: 削除系 AC (`file_not_exists`/`file_not_contains`) を含む PR が実際にレビューされた際、そのレビュー結果 (PR コメント) を確認して FALSE POSITIVE の有無を判定する

### #446 条件1/条件2 — 新規 verify command 提案 Issue での adapter pattern 確認 step 動作確認 (`/issue` / `/spec`)

- **条件文 (条件1)**: 「サンプル Issue (新 verify command 提案) で `/issue` 実行し、既存 adapter pattern 確認 step が機能することを手動確認」
- **条件文 (条件2)**: 「同様に `/spec` 実行で確認」
- **差し戻し理由**: 親 #1270 が名指しした実例。(1) `/auto` は `/issue` を毎回実行しない (unlabeled Issue の triage 時のみ)、(2) 実行されても「新規 verify command 提案」という Issue 内容の前提が別途必要 (親 Issue 本文より)。加えて、adapter pattern 確認 step が「機能した」ことを示す機械的に検索可能な証跡 (`auto-events.jsonl` 等) が存在しないため、event 発火時点で判定材料を得る手段がない
- **`/verify` 実行時に何をすれば判定できるか**: 新規 verify command を提案する実 Issue が `/issue`/`/spec` で実際に処理された際、そのセッション記録 (Spec の Codebase Investigation セクション、adapter-resolver.md 参照の有無) を確認して既存 adapter pattern 確認 step が機能したかを判定する

## D: 判定不能 (0 行)

該当なし。12 行のうち「event でも `/verify` 実行時でも原理的に判定不能」に該当するものはなかった — E に分類した 7 行はいずれも `/verify` (manual) 実行時に Claude または人間が実際に操作・確認すれば判定可能であり、#1166 方式の retire は発生しない。

## E の内訳: 即判定可能 / 装備待ちの区別

7 行すべてが「今すぐ `/verify` (manual) で判定できる」に該当し、`capability=<key>` を要する装備待ちの行はない。

| Issue | 装備待ちか | 理由 |
|---|---|---|
| #1031 | 否 | `ListAgents` (標準ツール) と対話モードでの直接実行で判定可能 |
| #954 | 否 | Spec 記載内容の確認で判定可能 |
| #515 | 否 | rubric 相当の定性的判断で判定可能 |
| #511 | 否 | Code Retrospective / completion message の確認で判定可能 |
| #486 | 否 | PR コメントの確認で判定可能 |
| #446 条件1/条件2 | 否 | セッション記録の確認で判定可能 |

## #446 / #486 の分類・処理内容 (親 Issue が名指しした実例)

親 #1270 は「D と決め打ちしない」として #446 (条件1・条件2) と #486 を明示的に E 候補として本 sub-issue に配分した。実査の結果、いずれも E (`manual` へ差し戻し) と判定し、Issue 本文の該当行を書き換えた。詳細は上記「E: `manual` へ差し戻し」節の #446/#486 各項を参照。

## D2 対象行以外の Post-merge 構成 (処理への影響確認)

`docs/spec/issue-1275-observation-ac-audit-d2.md` Notes に記録の通り、#529 は D2 対象行以外に `verify-type: auto` の条件が既に `[x]` チェック済み、#511 は D2 対象行以外に `verify-type: opportunistic` の未チェック条件 (`## Smoke Test` セクションに関する条件) が別途残る。いずれも本 Issue では D (retire) が発生しなかったため `phase/done` 遷移判断は不要であり、この構成差異は処理結果に影響しない。

## 検証: opportunistic-search.sh dry-run によるマッチ集合確認

`scripts/opportunistic-search.sh --event auto-run --dry-run` (read-only) を編集前後で実行し、機械的に突合した。

- **編集前**: 85 AC 行がマッチ (baseline と一致)。対象 12 行 (#1109 #1106 #1101 #1097 #1031 #954 #529 #515 #511 #486 #446×2) は全件マッチ集合に含まれることを確認
- **編集後**: A 判定の 5 行 (#1109 #1106 #1101 #1097 #529) は引き続きマッチ集合に含まれることを確認。E 判定の 7 行 (#1031 #954 #515 #511 #486 #446×2) はいずれもマッチ集合から意図通り除外されたことを確認
- **総マッチ数の変化**: 85→75 (10 減)。E 判定 7 行の除外により本来は 7 減の想定だが、差分は 10 だった。個別突合の結果、7 行の除外に加えて #861 / #769 / #859 の 3 行が編集前後で変動していたことを確認した。これらは本 Issue の編集対象外であり、実査期間中に他セッションで行われた並行活動 (別 Issue のチェックボックス更新等) による変動と考えられる。`docs/reports/manual-ac-retype-d2.md` の先例 (「件数差分の厳密一致より目視突合を正とする」) に倣い、対象 12 行それぞれの個別突合結果 (上記) を正としてマッチ集合確認の根拠とする

## 集約レポートへの統合について

本レポートの分類結果 (A 5 / B 0 / C 0 / D 0 / E 7) を `docs/reports/observation-ac-audit-summary.md` の集約テーブルへ統合するのは親 #1270 自身の責務であり、本 Issue のスコープ外。

## Related

- **#1270** — 親 Issue。実査全体の判定基準・実行順序制約の出典
- **#1274 / #1276** — 由来単位で並列実行される他 sub-issue (由来: #1163 区分 A / #1165 区分 D3)
- **#1164** — 区分 D2 として本 12 行を `verify-type: observation event=auto-run` へ再型付けした Issue。`docs/reports/manual-ac-retype-d2.md` が一次資料
- **#1166** — D (retire) 方式の出典 (本 Issue では該当なし)
- **#1278** — E の `capability=<key>` 内訳の引き継ぎ先 (本 Issue では該当なし、7 行とも即判定可能)
