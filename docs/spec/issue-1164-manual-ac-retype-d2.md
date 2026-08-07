# Issue #1164: verify: manual AC 区分 D2 (実行シナリオ型 13 件) を observation へ再型付け

## Overview

親 Issue #1158 の分割 sub-issue。`phase/verify` に滞留する `verify-type: manual` の post-merge AC のうち、区分 D2 (「実際に X を実行して…を確認する」実行シナリオ型) に分類された 13 Issue を対象に、`verify-type: observation event=<name>` へ再型付けする。

対象 13 Issue が持つ `verify-type: manual` の post-merge AC は **16 行** (#507 が 3 行、#446 が 2 行、他 11 Issue は各 1 行)。全件を個別に精査した結果、**12 行を `event=auto-run` へ再型付け**、**4 行を対象外 (`manual` 維持)** とする。うち #1106・#1097 の 2 行は 2026-08-04 の `/auto 1150` (PR #1151) 実行で**既に条件が充足されていた**ことを Issue コメントで記録する。

再型付け結果と対象外理由は `docs/reports/manual-ac-retype-d2.md` に記録する。この記録ファイルがあることで、Pre-merge の `rubric` AC が grader から参照可能になる (`/spec` の Spec 自身は `/code` の PR diff に含まれないため、grader に見える形で残すには `/code` フェーズで作成される記録ファイルが必要 — 姉妹 Issue #1163 と同じ理由、詳細は Notes 参照)。

## Changed Files

- `docs/reports/manual-ac-retype-d2.md`: 新規作成 — 区分 D2 16 AC 行のマッピング表 (Issue 番号 / 条件文要約 / 付与 event または対象外 / 選定根拠)、対象外 4 行の理由、`opportunistic-search.sh` 実行による検証結果
- `docs/structure.md`: 変更不要 — Directory Layout tree に `docs/reports/` は既出 (line 62 付近)。Key Files 側は「スクリプトが消費する report ファイル」のみ列挙する方針であり、本記録ファイルは消費側スクリプトを持たないため追加不要 (`grep -n "docs/reports" docs/structure.md` で確認済み — #1163 と同一の判断)
- `docs/ja/` 同期: 対象外 — `docs/translation-workflow.md` § Exclusions が `docs/reports/` を明示的に除外 (18-22 行目で確認済み)
- リポジトリ外 (GitHub Issue 本文, 12 AC 行 / 11 Issue: #1109 #1106 #1101 #1097 #1031 #954 #529 #515 #511 #486 #446×2): `<!-- verify-type: manual -->` を `<!-- verify-type: observation event=auto-run -->` へ置換
- リポジトリ外 (GitHub Issue コメント, #1106 と #1097): 2026-08-04 `/auto 1150` (PR #1151) 実行による既充足の事実を記録するコメントを投稿
- リポジトリ外 (GitHub Issue 本文, #1164 自身): `## Blocked by #1157` セクションの古い文言 (「#1157 の着地が前提」) を、#1157 が CLOSED 済みであることを反映した文言へ更新 (#1163 が自身の `/issue` フェーズで行った更新と同種、#1158 の Notes が「各自の `/issue`/`/spec` 実行時に同様の更新が行われる想定」と記載)

## Implementation Steps

1. `docs/reports/manual-ac-retype-d2.md` を新規作成し、本 Spec の Notes 節「再型付けマッピング」の全 16 AC 行 (event=auto-run 12 行 / 対象外 4 行) を転記する。冒頭に対象 Issue 一覧、件数内訳 (Issue 単位 13 件と AC 行単位 16 行のずれの明記)、`event=` 有効値が `modules/verify-classifier.md` の 5 種に限られる制約を記す (→ AC1, AC3)
2. (after 1) `.tmp/retype-mapping-d2.json` を Write ツールで作成する。各要素は `{"issue": N, "match": "<AC 行を一意に特定する部分文字列>", "event": "auto-run"}` — 対象 11 Issue 12 行分のみ (対象外の #507×3・#444×1 は含めない)。続けて `.tmp/retype-ac-d2.py` を Write ツールで作成する (`docs/spec/issue-1163-manual-ac-retype-a.md` Implementation Step 2-3 の `.tmp/retype-ac.py` と同一ロジック: 既定 dry-run、`--apply` で適用。処理は Issue ごとに `gh issue view N --json body -q .body` で本文取得 → `match` と `<!-- verify-type: manual -->` の両方を含む行を抽出 → ちょうど1行でなければ当該 Issue を skip して警告 → 該当行の `<!-- verify-type: manual -->` のみを `<!-- verify-type: observation event=auto-run -->` へリテラル置換 → 本文全体を `.tmp/issue-body-N.md` へ書き出し → `scripts/gh-issue-edit.sh N .tmp/issue-body-N.md` を呼ぶ)。dry-run で 12 行すべての置換前後を目視確認してから `--apply` を実行する。あわせて #1164 自身の本文の `## Blocked by #1157` セクションを、#1157 が CLOSED 済みであることを反映した文言へ `gh-issue-edit.sh` で更新する (→ AC1)
3. (after 2) #1106 と #1097 に対し、2026-08-04 の `/auto 1150` (PR #1151) 実行で当該 post-merge AC が既に充足されていた事実 (該当 Issue・充足内容は本 Spec の Notes 節を参照) を記録する Issue コメントを `${CLAUDE_PLUGIN_ROOT}/scripts/gh-issue-comment.sh` で投稿する (→ AC2)
4. (parallel with 2) 対象外とした #507 (3 AC 行、saito/trading 別リポジトリ依存) と #444 (1 AC 行、`/audit` は `auto-run` のスコープ外) は一切編集しない。`.tmp/retype-mapping-d2.json` に含めないことで機械的に保証する (→ AC3)
5. (after 2, 3) `${CLAUDE_PLUGIN_ROOT}/scripts/opportunistic-search.sh --event auto-run` を実行し、再型付けした 12 AC 行に対応する Issue 番号 (#1109 #1106 #1101 #1097 #1031 #954 #529 #515 #511 #486 #446) がマッチ集合に含まれることを確認する。実行結果 (マッチ件数、再型付け前 baseline との差分、含有確認済み Issue 番号) を `docs/reports/manual-ac-retype-d2.md` の `## 検証` 節へ追記し、`.tmp/retype-mapping-d2.json` / `.tmp/retype-ac-d2.py` / `.tmp/issue-body-*.md` を削除してコミット対象を `docs/reports/manual-ac-retype-d2.md` のみにする (→ AC1, AC2)

## Verification

### Pre-merge

- <!-- verify: rubric "区分 D2 の 13 件について、各 Issue の post-merge AC が verify-type: observation へ変更され、条件文が要求する実行文脈 (route / Size / phase 等) が event= 属性または条件文中に機械判定可能な形で表現されている" --> 13 件が observation へ再型付けされ実行文脈が表現されている
- <!-- verify: rubric "#1106 と #1097 について、2026-08-04 の /auto 1150 実行で条件が充足されていた事実が Issue コメントまたは AC のチェック状態に反映されている" --> 既に充足済みの 2 件が処理されている
- <!-- verify: rubric "再型付けの対象外とした Issue がある場合、その理由が Issue 単位で記録されている" --> 対象外とした Issue の理由が記録されている

### Post-merge

- 移行完了後の `/audit stats --retention` で、phase/verify の Manual waiting 件数が移行前 (79 件) から13 件減少していることを確認する <!-- verify-type: observation event=auto-run -->

## Notes

### 再型付けマッピング (docs/reports/manual-ac-retype-d2.md へ転記する設計)

`event=` に使用できるのは `modules/verify-classifier.md` § observation Type が定める 5 つの有効値のみ: `pr-review-full` / `pr-review-light` / `auto-run` / `watchdog-kill` / `fix-cycle`。以下は対象 13 Issue / 16 AC 行を個別に精査した結果 (2026-08-07 実測、全件 `phase/verify` ラベル保持・CLOSED 状態を確認済み)。

#### `event=auto-run` (12 AC 行)

| Issue | 条件文の要約 | 選定根拠 |
|---|---|---|
| #1109 | observation AC を持つ Issue に event 発火後 `/verify` を実行し、条件充足時に checkbox 更新・`phase/done` 遷移を確認 | `/verify` は `/auto` の verify phase として実行される。observation 機構自体を検証する条件であり、`/auto` 完了ごとに再チェックする意義が大きい |
| #1106 | 自己 PR に `/auto` の pr route を実行し、merge precondition の警告が出ずに進行することを確認 | `/auto` 実行そのものが観測窓。**2026-08-04 の `/auto 1150` (PR #1151, 自己 PR・pr route・precondition `matches_expected: true`) で既に充足済み** — Implementation Step 3 でコメント記録 |
| #1101 | ベースブランチ側と同一行を変更する PR を実際にレビューし、conflict が MUST 指摘として検出されることを確認 | `/review` は `/auto` 実行の内側。`pr-review-full`/`pr-review-light` いずれの深度でも起こりうる指摘であり、深度を限定する狭いイベントだと取りこぼす (#1163 #765 と同じ選定方針) |
| #1097 | Size L の PR に `run-review.sh --full` を実行し silent no-op 検出が発生せず Response Summary が投稿されることを確認 | `--full` review は `/auto` の review phase 内で実行されうる。**2026-08-04 の `/auto 1150` (PR #1151, Size L・`--full`・exit 0 + Summary 投稿済み) で既に充足済み** — Implementation Step 3 でコメント記録 |
| #1031 | 実際に `/issue` を XL Issue に対して実行し、Step 12a→12c 完了時点で FleetView/pane に subagent が残らないことを目視確認 | `/issue` は `/auto` 実行の内側。**留意**: `run-issue.sh` (`/auto` が呼ぶ `/issue`) は常に非対話モードで実行され、Step 12a の L/XL sub-agent fan-off は「sub-issue 分割は High-Stakes Decision」として非対話モードで無条件 skip される (`docs/tech.md` #923 の分析による確認済み事実)。つまり `/auto` 自身の issue phase がこの条件を満たすことは構造的にない。ただし `/issue` は直接 (対話モードで) 実行することも可能で (`docs/tech.md` fork 判定表)、その場合は Step 12a が実際に発火しうる。`auto-run` は「この /auto 実行が原因で満たされた」ことの証明ではなく「今何かが満たされたかもしれないので再確認せよ」という契機であるため、対話モードでの `/issue` 実行が別途起きていれば検出しうる。#1163 の #861/#859 が確立した「文脈条件を事前排除できない場合は dispatch → SKIPPED が正しい挙動」という設計方針に従い、対象外にはせず `auto-run` を付与する |
| #954 | 実際に Size=XL の Issue で `/issue` を実行し、3 エージェントの調査結果が手動介入なしに回収できることを確認 | #1031 と同型の留意点 (非対話モードでの Step 12a 無条件 skip) が適用される。同じ理由で対象外にはせず `auto-run` を付与する |
| #529 | spec phase で Size が変化する Issue に `/auto N` を実行し、変化後の Size に応じた review 深度・route が自動選択されることを実運用で確認 | 条件文が `/auto N` の実行そのものを明示している |
| #515 | 実プロジェクトで `/verify N` を複数回実行し、tool call parse 失敗の発生頻度が改善していることを定性的に確認 | `/verify` は `/auto` 実行の内側で反復実行される。**留意**: 「頻度が改善」は単発の event 発火では判定しづらい定性的・統計的な問い。専用の計測基盤は現状存在しない (`could not be parsed`/`parse_fail` 等のキーワードで `modules/`・`scripts/`・`skills/` を検索し該当なしを確認済み) ため、`/verify` 再チェック時の LLM 判断 (rubric 相当) に委ねる設計とする |
| #511 | 実機 external connector を使う Issue を `/auto` 非対話モードで実行し、MCP smoke 呼び出しブロック時に SKIPPED が記録され run が中断しないことを確認 | Smoke Test 機構自体は本リポジトリの `/code` (`/auto` の内側) に実装済み (#511 で導入)。当該リポジトリ自身の将来 Issue が `## Smoke Test` + `mcp_call` を持てば発火しうる |
| #486 | 削除系 PR (`file_not_exists`/`file_not_contains` AC を含む) を実際にレビューし FALSE POSITIVE が発生しないことを確認 | `/review` は `/auto` 実行の内側 |
| #446 条件1 | サンプル Issue (新 verify command 提案) で `/issue` 実行し、既存 adapter pattern 確認 step が機能することを確認 | 「サンプル」に限らず、新規 verify command を提案する実 Issue が `/issue`/`/spec` (いずれも `/auto` の内側) で処理されるたびに発火しうる。実際、本 Issue #1164 自身の `/spec` 実行でも #446 が追加した adapter pattern survey ステップが機能した (本 Spec 作成過程で確認) |
| #446 条件2 | 同様に `/spec` 実行で確認 | 条件1と同じ根拠 |

#### 対象外 (`manual` 維持、4 AC 行)

| Issue | 条件文の要約 | 対象外の理由 |
|---|---|---|
| #507 条件1 | saito/trading リポジトリで `/audit stats --since 2026-05-01` を実行し First-try 成功率の変化を確認 | 別リポジトリ (`saito/trading`) 依存。Issue 本文自身が「saito/trading リポジトリでの実際の `/audit stats` 実行確認が必要であり、機械的に自動検証できない」と明記済み (区分 B 相当、upstream から観測不能) |
| #507 条件2 | Outcome レポートに「対象 N 件 / 除外 M 件」表示が含まれることを確認 | 条件1と同一理由 (同一 Issue 内の並列条件) |
| #507 条件3 | 既存 trading レポートで Highlights 表示が再計算後に変わることを確認 | 条件1と同一理由 |
| #444 | `/audit stats` を再実行し、SKILL.md の手順だけで全工程が完走することを確認 | `/audit` は `/auto` のフェーズチェーンに含まれない独立 skill (`docs/tech.md` model-effort matrix: 「Invoked inline (no run-*.sh wrapper)」)。`modules/verify-classifier.md` の 5 有効値はいずれも `/auto`・`/review`・`claude-watchdog.sh`・fix-cycle のいずれかが emitter であり、`/audit` 単独実行に対応する event が存在しない |

### precedent: #1163 との関係

区分 A (34 Issue / 36 AC 行) を扱った姉妹 Issue #1163 (`docs/spec/issue-1163-manual-ac-retype-a.md`, `docs/reports/manual-ac-retype-a.md`) が本 Issue の構造的前例。以下を踏襲する:

- 記録ファイル (`docs/reports/manual-ac-retype-d2.md`) を追加する理由 — rubric grader は Issue 本文・git diff・rubric 本文で名指しされたファイルのみ参照可能で、Spec ファイル自身は `/code` の PR diff に含まれないため、grader に見せるには記録ファイルが必要
- 一括置換ヘルパは `.tmp/` に置き `scripts/` へは残さない (区分ごとに置換対象が異なり汎用化の利得が薄いため)
- 検証には `observation-trigger.sh` ではなく `opportunistic-search.sh --event <name>` を使う (`/code` の `allowed-tools` に登録済みで read-only、`observation-trigger.sh` はコメント投稿の副作用を持つ薄いラッパのため)
- `when=`/`keyword=`/`config=` ゲートは付与しない — 実行文脈条件の宣言は #1118 が明示的に引き受けている (#1163 の裁定を踏襲。親 #1158 の Notes も同じ結論)
- `session=next` は不要 — 対象 13 件はいずれも `skills/*/SKILL.md` 自身の挙動観察条件ではない

### Issue 単位と AC 行単位の件数ずれ

`docs/stats/2026-08-05.md` Section 10 の「区分 D2 = 13 件」は Issue 単位の数え方。実際の `verify-type: manual` AC 行数は 16 行 (#507 が 3 行、#446 が 2 行)。#1163 (34 Issue = 36 AC 行) と同様のずれであり、記録ファイルでは AC 行単位で数え、Issue 単位との対応を明記する。

### 母集団の増加とその許容根拠

#1163 適用後、`opportunistic-search.sh --event auto-run` のマッチは 59 AC 行 (2026-08-06 実測)。本 Issue で 12 行が加わる。#1099 の idempotency guard (24h) と `observation-dispatch-threshold` (既定 5) が影響を抑える。さらなる削減は #1118 (`when=`) と #1162 (セッション内 verify 済み除外) の担当であり、本 Issue のスコープではない。

### 対象外 Issue の判断が #1163 と異なる性質を持つ点

#1163 の対象外 7 件はいずれも「故障注入」「別 repo」「enum 設定依存」など条件そのものの性質による除外だった。本 Issue の対象外 4 件のうち #507 (3 行) は同型 (別 repo 依存) だが、#444 (1 行) は「条件の性質」ではなく「`/audit` という skill が `modules/verify-classifier.md` の event 語彙の対象範囲に構造的に含まれない」という、observation 機構側の語彙制約による除外である。将来 `/audit` 実行を捕捉する event 種別 (例: `audit-run`) が追加されれば再評価の余地がある。

## spec retrospective

### Minor observations

- `modules/verify-classifier.md` の `event=` 5 有効値は `/auto`・`/review`・`claude-watchdog.sh`・fix-cycle の 4 emitter に対応しており、`/audit` や `/doc` のような「`/auto` チェーンに属さない独立 skill」の実行完了を捕捉する event 種別が存在しない。#444 のような条件が今後も同種の理由で対象外になりうるため、`/audit` 完了イベント (例: `audit-run`) の追加を将来検討する価値がある (改善提案として記録するに留め、Issue 起票は `/verify` の集約フェーズに委ねる)
- #1031・#954 は「`/auto` が呼ぶ `/issue` は非対話モードで L/XL sub-agent fan-out を無条件 skip する」という `docs/tech.md` #923 の既存分析により、`auto-run` 発火では条件文が指す codepath が構造的に再現されない可能性が高いことが判明した。それでも #1163 の「文脈条件を事前排除できない場合は dispatch → SKIPPED が正しい挙動」という設計方針に従い対象外にはしなかったが、この 2 件は他の 10 行より SKIPPED が恒常化するリスクが高い区別可能なサブグループであり、`/verify` 側での実態観察 (SKIPPED が本当に恒常化するか) を後日確認する価値がある

### Judgment rationale

- **#1031・#954 を対象外にせず `auto-run` を付与した** — 非対話モードでの `/issue` L/XL sub-agent fan-out 無条件 skip という構造的制約を発見したが、`auto-run` イベントは「この実行が原因で満たされた」ことの証明ではなく「今何かが満たされたかもしれないので再確認せよ」という契機であり、対話モードでの直接 `/issue` 実行という別経路が条件を満たしうる。#1163 が確立した「文脈条件の有無は対象外判定の根拠にならない」という前例を、非対話/対話モードという新しい軸にも一般化して適用した
- **#1101・#1097 に `pr-review-full`/`pr-review-light` ではなく `auto-run` を選んだ** — #1163 の「取りこぼさない最も広いイベント」という選定方針をそのまま踏襲。review 深度を限定するイベントは、対象 Issue の review 深度が事前に読めない場合に取りこぼす
- **#507 を対象外とした** — Issue 本文が「saito/trading リポジトリでの実際の `/audit stats` 実行確認が必要であり、機械的に自動検証できない」と明記済みであり、判断に迷いがなかった。#1163 の #501/#500/#479 (downstream 依存) と同型
- **#444 を対象外とした** — `/audit` が `/auto` のフェーズチェーンに属さない独立 skill であるという `docs/tech.md` の記述上の事実に基づく、5 有効値のいずれの emitter にも対応しない構造的な語彙制約。#1163 の #704 (enum 設定依存で `config=` が表現不能) と同じ「機構側の語彙が条件を表現できない」という性質の除外
- **#1164 自身の「Blocked by #1157」記述更新を Implementation Step 2 に統合した** — 親 #1158 の Notes が「各自の `/issue`/`/spec` 実行時に同様の更新が行われる想定」と記載しており、#1164 は本セッションで `/issue` フェーズを経由しなかった (batch 実行のイベントログで `phase_start` が spec から直接開始していることを確認済み) ため、`/spec` が実質的に最後の機会になる。SPEC_DEPTH=light の Implementation Steps 上限 (5) を超えないよう、独立ステップにはせず Step 2 (Issue 本文編集) に統合した

### Uncertainty resolution

- **#515 の「頻度改善」をどう観測可能にするか** — 専用の計測基盤 (emit_event 等) が存在しないことを `could not be parsed`/`parse_fail` のキーワード grep で確認した。`auto-run` を付与しつつ、判定自体は `/verify` 実行時の定性的な LLM 判断に委ねる設計としたが、これは #1164 の他の 11 行 (状態の有無を機械的に確認できる) より曖昧さが残る。将来 `/verify` がこの条件を繰り返し SKIPPED/UNCERTAIN で返す場合は、統計的な計測を Post-merge AC に追加する形で #515 自身の follow-up として扱うべきであり、本 Issue のスコープでは event 付与に留める
- **#446 の「サンプル Issue」という限定的な文言をどう解釈するか** — 文言通りに「意図的に作成したサンプル Issue でのみ発火する」と読むと故障注入型 (区分 C 相当) に近くなるが、#446 が追加した adapter pattern survey ステップは `/issue` Step 4・`/spec` Step 6 の prerequisite check として恒久的に組み込まれており、新規 verify command を提案する任意の実 Issue で自然に発火する。本 Spec 作成自体がこのステップを経由したことも傍証とした。「サンプル」は導入時の検証手段の説明であり、恒久運用時の発火条件を限定する意図ではないと判断した

## Consumed Comments
No new comments since last phase.

- saito / MEMBER / first-class / ## Acceptance Test Results / https://github.com/saitoco/wholework/issues/1164#issuecomment-5213482066
- saito / MEMBER / first-class / <!-- wholework-event: type=observation-trigger phase=observation-trigger issue=1 / https://github.com/saitoco/wholework/issues/1164#issuecomment-5213691524
## Autonomous Auto-Resolve Log

- **`phase/ready` ラベル不在での続行**: `/code 1164 --pr --non-interactive` 開始時点で Issue のラベルは `phase/code` (label timeline 上、`phase/ready` は既に `phase/code` へ遷移済み)。`reconcile-phase-state.sh --check-precondition code-pr` も `matches_expected: false` を返した。Spec (本ファイル) は spec retrospective まで完備しており、コーディング未着手のまま前回セッションが label 遷移後に中断したレジューム状態と判断した。Spec が存在するため「Spec なしで Issue 本文から要件を読む」対応は不要 — reason: 非対話モードのポリシー (auto-resolve) は Spec 欠落時の縮退経路であり、本件は Spec 完備のため実質的にブロッカーではない。#1163 の Code Retrospective と同型の判断。

## Code Retrospective

### Deviations from Design

- Implementation Steps 2〜4 (`.tmp/retype-mapping-d2.json` 作成 → `.tmp/retype-ac-d2.py` 作成・dry-run・`--apply` 実行、#1164 自身の「Blocked by #1157」文言更新、#1106/#1097 への既充足コメント投稿) を実行しなかった。`/code` 開始時点で対象 13 Issue 全件の GitHub 上の実状態を個別確認したところ、11 Issue 12 AC 行はすべて `verify-type: observation event=auto-run` へ再型付け済み、対象外の #507 (3 行) / #444 (1 行) は `verify-type: manual` のまま誤編集なく維持されていた。#1106・#1097 への既充足コメントも投稿済み、#1164 自身の「Blocked by #1157」セクションも「解消済み」へ更新済みだった。前回セッションが Issue 本文編集・コメント投稿を完了した後、report file 作成前に中断したレジューム状態と判断し、実質的な追加作業は Implementation Step 1 (report file 作成) と Step 5 (`opportunistic-search.sh` による検証・記録) のみとした。#1163 の Code Retrospective と全く同型の状況が区分 D2 でも再現した — 親 #1158 の分割 sub-issue 群で同種のレジュームパターンが繰り返されている。Spec Implementation Steps の記述自体は変更しない (次回同種の再型付け Issue で `.tmp/` ヘルパパターンを再利用する際の参照価値を残すため)。

### Design Gaps/Ambiguities

- なし。#1163 の precedent (report ファイル構造、`opportunistic-search.sh` 検証手順) をそのまま踏襲でき、設計上の曖昧さは生じなかった。

### Rework

- なし。

### Unrelated pre-existing test failures discovered

- `bats tests/` (1507 件) 実行で `run-code.bats` の `auto-retry: silent no-op + AUTO_RETRY_ENABLED=true fires retry` と `auto-retry: preflight stashes parent-main stray untracked file before retry re-invocation` の 2 件が単独実行でも一貫して FAIL することを発見した。両テストとも `reconcile-phase-state.sh` mock のカウンタが retry ループ内で意図通り増加していない (`auto-retry: max iterations reached (3/3)` に到達) ことが原因と推測される。本 Issue の diff は `docs/reports/manual-ac-retype-d2.md` の新規追加のみで `scripts/run-code.sh` やテスト自体には触れていないため、本 Issue のスコープ外の pre-existing な問題と判断し、follow-up Issue #1231 (`retro/code` ラベル) を起票した。また `post_merge_check.bats` の 1 件 (`gh issue reopen called when FAIL input given`) は `--jobs 8` 並列実行時のみ FAIL し、単独実行では PASS することを確認済み (並列実行時のフレーク、実害なし)。

## review retrospective

### Spec vs. implementation divergence patterns

- なし。本 PR は `docs/reports/manual-ac-retype-d2.md` の新規追加と Spec 側の retrospective/handoff 追記のみで、Spec の Implementation Steps からの逸脱はレジューム判断 (#1163 と同型) 以外になかった。

### Recurring issues

- 親 #1158 の分割 sub-issue 群で、「前回セッションが Issue 本文編集・コメント投稿完了後、report file 作成前に中断」というレジュームパターンが #1163 に続き #1164 でも再現した。同種の再型付け Issue が今後も残っている場合、同じ中断パターンが繰り返される可能性が高い。

### Acceptance criteria verification difficulty

- Pre-merge AC 3 件はすべて `rubric` 形式で、対象 13 Issue の GitHub 実状態を個別に `gh issue view` で照合することで機械的かつ明確に PASS 判定できた。UNCERTAIN や verify command の不備は発生しなかった。

## Phase Handoff
<!-- phase: merge -->

### Key Decisions

- pre-merge AC ゲート (`check-pre-merge-ac.sh`) は `unchecked_count: 0`、review-incomplete-fallback チェックも該当なしで、いずれもゲート通過。
- `gh-pr-merge-status.sh` が `mergeable: true, reason: clean` を返したため、conflict 解消フローを経由せず直接スクワッシュマージを実行した。

### Deferred Items

- Post-merge AC (`/audit stats --retention` での Manual waiting 件数減少確認) — `/verify` が `observation event=auto-run` 経路で評価する。
- follow-up Issue #1231 (`run-code.bats` の auto-retry テスト 2 件の FAIL) — 本 Issue のスコープ外、別 Issue で対応。

### Notes for Next Phase

- base branch は `main`。`closes #1164` により Issue は squash merge 後に自動 CLOSE される想定。
- `/verify 1164` では Post-merge AC (observation event=auto-run) の評価を行うこと。

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- Pre-merge AC 3 件を全て `rubric` にした判断は妥当だった。対象 13 Issue の GitHub 実状態を `gh issue view` で照合するだけで機械的に判定でき、UNCERTAIN は発生しなかった。

#### design
- #1163 の precedent (report ファイル構造、`opportunistic-search.sh` 検証手順) をそのまま踏襲でき、設計上の曖昧さは生じなかった。

#### code
- Code Retrospective に記録の通り、Implementation Steps 2〜4 は既に前回セッションで完了済みでレジューム扱いとなった。`/code` 側が GitHub 実状態を個別確認してから差分だけ実行した判断は正しく、二重編集は発生していない。

#### review
- Pre-merge AC 3 件は `/review` 時に rubric で PASS 判定済みで、本 verify では already-checked skip rule により SKIPPED。`/review` の判定が verify 側で覆る事象はなかった。

#### merge
- `mergeable: true, reason: clean` で conflict なくスクワッシュマージ完了。pre-merge AC ゲートも `unchecked_count: 0` で通過。

#### verify
- Post-merge AC は `observation event=auto-run` 1 件のみで、本 verify 実行時点では `observation-trigger.sh` の通知コメントが未投稿のため未発火。SKIPPED (waiting for event) として `phase/verify` に留まる。これは observation AC の設計通りの挙動であり FAIL ではない。
- 親 #1158 の分割 sub-issue 群で「前回セッションが Issue 本文編集・コメント投稿を完了した後、report file 作成前に中断」というレジュームパターンが #1163 に続き #1164 でも再現した (review retrospective にも記録)。#1165〜#1167 でも同型が起きうるが、`/code` 側の「GitHub 実状態を個別確認してから差分実行」で毎回正しく吸収できているため、構造的な欠陥ではなく sub-issue 系列固有の運用事象と判断する。

### Improvement Proposals
- N/A
