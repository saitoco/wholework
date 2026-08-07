# Issue #1158: verify: 滞留中の manual AC 79 件を分類に従って observation へ再型付け・retire

## Overview

`phase/verify` に滞留する `verify-type: manual` の post-merge AC 79 件を、`docs/stats/2026-08-05.md` Section 10 の分類 (A/B/C/D1/D2/D3 の 6 区分) に従って再型付け・retire する取り組み。**2026-08-05 に対応方針 A (分類別 sub-issue 分割) が採用され、GitHub ネイティブの sub-issue 関係で 5 本の sub-issue (#1163〜#1167) へ既に分割済み**であり、実際の 79 件の再型付け・retire 作業はすべて sub-issue 側で行われる。

| sub-issue | 区分 | Issue 数 | 状態 (本 Spec 作成時点、2026-08-07) |
|---|---|---|---|
| #1163 | A (次回…観察型) | 34 | CLOSED — `docs/reports/manual-ac-retype-a.md` として着地済み (29 AC 行を再型付け、7 行対象外) |
| #1164 | D2 (実行シナリオ型) | 13 | OPEN — `phase/issue` 未到達 |
| #1165 | D3 (その他) | 19 | OPEN — `phase/issue` 未到達 |
| #1166 | B (別 repo 依存) | 6 | OPEN — `phase/issue` 未到達 |
| #1167 | C (故障注入 2) + D1 (UI 目視 5) | 7 | OPEN — `phase/issue` 未到達 |

本 Issue (#1158) 自身に残るのは、5 sub-issue すべてが完了した後の**集約クローズアウト作業**のみである。本 Issue の Pre-merge AC 5 件はすべて `rubric` タイプであり、区分 A/B/C/D1/D2/D3 の 6 区分にまたがる集約的な充足条件 (例: 「docs/stats/2026-08-05.md の分類 6 区分と対応が取れている」) を要求している。したがって本 Spec の Implementation Steps は、5 sub-issue が全て `phase/done` (または CLOSED かつ Pre-merge AC 充足) に到達した後に実行可能になる、集約レポート 1 本の作成を定義する。

## Consumed Comments

cutoff: `2026-08-04T20:42:28Z` (`phase/issue` ラベル付与時刻、Issue timeline から取得)

| login | authorAssociation | trust tier | 意図の要約 | URL |
|---|---|---|---|---|
| saito | MEMBER | first-class | #1118 の AC2 を manual → observation に再型付けした具体例を記録。再型付けの判定基準表 (「次回…完走後に」パターンは observation 候補、主観判断・外部環境依存は manual 維持) と、`when=` 属性の付与要否 (現状 #995 のみで実質未展開、本 Issue で 79 件へ付与するかはスコープ判断が必要) を提示 | https://github.com/saitoco/wholework/issues/1158#issuecomment-5199363153 |

Cross-phase marker (`type=verify-fail` / `type=preview-ac-unverified`) の追加スキャン結果: 該当なし。

コメントが提起した「`when=` を 79 件へ併せて付与するか」という論点は、姉妹 sub-issue #1163 が既に裁定済み (`when=` は付与せず #1118 に委ねる。後述 Notes 参照) であり、他の sub-issue もこの前例を踏襲する想定のため、本 Issue で新たに判断し直す必要はない。

### Code phase (cutoff: `2026-08-07T07:26:00Z`, `phase/code` ラベル付与時刻)

No new comments since last phase. Cross-phase marker (`type=verify-fail` / `type=preview-ac-unverified`) の追加スキャン結果: 該当なし。

## Autonomous Auto-Resolve Log

(non-interactive mode; Step 6 の Issue 本文 vs 実装状態の conflict detection、および Step 7 の ambiguity resolution)

- **#1158 自身に Changed Files/Implementation Steps を持たせるか** — Issue 本文冒頭の「本 Issue 自身は...sub-issue の完了を待って close します」は額面通りには「#1158 に固有の実装作業はない」とも読める。しかし Pre-merge AC 5 件が全て `rubric` であり、`modules/verify-executor.md` の定義上 grader が受け取れるのは Issue 本文・git diff・rubric 本文で名指しされたファイルのみ (Issue コメントも Spec ファイルも渡らない) — Issue 本文には 6 区分の対応関係を記録する場所がない。姉妹 sub-issue #1163 が全く同じ制約に直面し、「親 #1158 が想定していた operate route (Issue 本文編集のみ) では成果物が Execution Log コメントにしか残らず rubric が評価不能」という理由で pr route + 記録ファイル 1 本に切り替えた前例がある (`docs/spec/issue-1163-manual-ac-retype-a.md` Notes 「operate route を採らなかった理由」)。同じ論理を親 #1158 自身にも適用し、**5 sub-issue の結果を集約する記録ファイル `docs/reports/manual-ac-retype-summary.md` を 1 本追加する**ことを Changed Files とした
  - 他候補: 「#1158 は Changed Files なしの純粋な追跡 Issue」(棄却 — rubric AC が永久に grade 不能になる) / 「各 sub-issue の記録ファイルへの単純リンク集のみ」(棄却 — AC1 が要求する「6 区分との対応」の集約的な reconciliation が果たせない)
- **Implementation Steps の実行タイミング** — 集約レポートは #1164〜#1167 の成果物 (各 sub-issue 自身の記録ファイル) を引用するため、その 4 件が完了する前には内容を確定できない。Step 1 を明示的な precondition gate として記述し、未充足の場合は後続 Step を実行しないことを明記した
  - 他候補: 「今すぐ空のレポートを作成し後で加筆する」(棄却 — 空ファイルは rubric AC を満たさず、後続セッションが「完了済み」と誤認するリスクがある)
- **Size を XL から縮小するか** — 残存する Changed Files はリポジトリ内 1 ファイルのみで、素の Axis 1 (変更ファイル数) だけを見ると XS/S 相当に見える。しかし `modules/ambiguity-detector.md` の Non-Interactive Mode Handling は「Size downgrade from XL」を明示的に High-Stakes Decision (skip 対象) としている。本 Issue は 79 件・6 区分・5 sub-issue にまたがる取り組み全体を表すラベルとして XL を維持する意味があり (`/audit progress` 等の集計にも影響する)、既に sub-issue 分割という高コストな構造判断も完了済みであるため、**Size は XL を維持し、ダウングレードは実行しない** (Step 18 で再評価はするが適用しない)
  - 他候補: 「Changed Files 数に従って S へ再評価・適用する」(棄却 — High-Stakes Decision の明示的な skip 対象)
- **カテゴリ B の retire/移管判断は本 Issue の対象外** — Issue 本文は「B の retire 判断」を候補として提示するが、sub-issue #1166 自身の Acceptance Criteria が既にこの判断 (Issue 単位で retire/移管を選ぶ) を明示的に所有している。#1158 側で先回りして判断せず、#1166 の結果を集約レポートに転記するに留める

## Changed Files

- `docs/reports/manual-ac-retype-summary.md`: 新規作成 — #1163〜#1167 の 5 sub-issue の結果を集約するクローズアウトレポート。**#1164〜#1167 が全て完了するまで内容を確定できないため、作成は Implementation Steps の precondition gate (Step 1) を満たした後にのみ行う**

## Implementation Steps

1. **Precondition gate**: `gh issue view <N> --json state,labels` を #1164 / #1165 / #1166 / #1167 それぞれに対して実行し、4 件全てが `CLOSED` または `phase/done` ラベルに到達していることを確認する。1 件でも未充足の場合、以降の Step は実行せず、本 Spec は「実行不可 (blocked)」として終了する — 次回 `/code 1158` 実行時に再度この gate から始める (→ AC1〜AC5 の前提)
2. (after 1) `docs/reports/manual-ac-retype-summary.md` を新規作成する。冒頭に `## 対象・件数内訳` として、`docs/stats/2026-08-05.md` Section 10 の 6 区分 (A/B/C/D1/D2/D3) を行に持つ表を書く。列は「区分 / Issue 数 (Issue 本文記載) / 実 AC 行数 / 担当 sub-issue / 状態」。実 AC 行数は各 sub-issue 自身の記録ファイル (`docs/reports/manual-ac-retype-a.md` 等、#1164〜#1167 分のファイル名は各 sub-issue の Spec が定める) から転記し、Issue 単位の件数と AC 行単位の件数が異なる場合 (#1163 で 34 Issue = 36 AC 行だった前例) は両方を明記する。表の合計が `docs/stats/2026-08-05.md` の 79 件と一致することを確認し、差異があれば理由を付記する (→ AC1)
3. (after 2) 同ファイルに `## 区分別処理結果` を追加し、以下 4 小節を各 sub-issue の記録ファイルから転記・要約する:
   - `### A + D2 (observation 再型付け)`: #1163 (34件、着地済み) と #1164 (13件) について、付与された `event=` 値の内訳 (`modules/verify-classifier.md` の 5 有効値のいずれか) と対象外件数を記載 (→ AC2)
   - `### B (retire / 移管)`: #1166 (6件) が Issue 単位で下した retire / downstream 移管の判断とその根拠を転記 (→ AC3)
   - `### D1 (manual 維持)`: #1167 が扱う D1 5件について、manual のまま維持する判断根拠を転記 (→ AC4)
   - `### D3 および対象外 (再型付けしなかった AC)`: #1165 (19件) のうち再型付け/retire しなかった AC、および #1163/#1164/#1167 内の対象外 AC について、Issue 単位の理由を転記 (→ AC5)
4. (parallel with 2, 3) `grep -rn "docs/reports" docs/structure.md` と `docs/translation-workflow.md` の Exclusions 節を確認し、`docs/reports/` 配下の新規ファイルが Key Files 一覧・`docs/ja/` 翻訳同期のいずれも対象外であることを再確認する (前例: `docs/reports/manual-ac-retype-a.md` も両方とも変更不要だった)。変更が不要であることの確認のみで、ファイル編集は行わない (→ Notes 確認事項)

## Verification

### Pre-merge

- <!-- verify: rubric "phase/verify に滞留する manual AC の分類結果 (Issue 番号ごとの移行先) が構造化データまたはドキュメントとして記録されており、docs/stats/2026-08-05.md の分類 6 区分と対応が取れている" --> 分類結果が Issue 番号単位で記録されている
- <!-- verify: rubric "A (次回…観察) および D2 (実行シナリオ) に分類された AC が verify-type: observation へ再型付けされ、適切な event= 属性が付与されている。再型付け後の AC が observation-trigger.sh のマッチ対象になることが確認できる" --> A + D2 が observation へ再型付けされている
- <!-- verify: rubric "B (別 repo) に分類された AC について、retire (条件取り下げ + phase/done 遷移) または downstream への移管のいずれかが実施され、判断根拠が記録されている" --> B の 6 件が retire または移管されている
- <!-- verify: rubric "D1 (UI 目視) に分類された AC が manual のまま維持されており、維持の判断根拠が記録されている" --> D1 が manual 維持され根拠が記録されている
- <!-- verify: rubric "移行対象外とした AC (D3 のうち個別判断で移行しないと決めたもの等) について、その理由が Issue 単位で記録されている" --> 移行しなかった AC の理由が記録されている

### Post-merge

- 移行完了後の `/audit stats --retention` で、phase/verify の Manual waiting 件数が移行前 (79 件) から減少していることを確認する <!-- verify-type: observation event=auto-run -->

## Tool Dependencies

### Bash Command Patterns

- `gh issue view:*`: #1164/#1165/#1166/#1167 の状態確認 (precondition gate) および各 sub-issue の記録ファイル内容の参照 (`/code` の `allowed-tools` に登録済み)

### Built-in Tools

- `Write`: 集約レポートファイルの新規作成
- `Read` / `Grep`: 各 sub-issue の記録ファイル・`docs/stats/2026-08-05.md` の内容確認、`docs/structure.md`/`docs/translation-workflow.md` の対象外確認

### MCP Tools

- なし

## Notes

### なぜ「純粋な追跡 Issue」ではなく Changed Files を持つのか

Issue 本文冒頭の「分割済み」注記は「本 Issue 自身は...sub-issue の完了を待って close します」と述べており、額面通りには実装作業がないように読める。しかし本 Issue の Pre-merge AC 5 件が全て `rubric` である以上、grader が参照できる場所 (Issue 本文・git diff・rubric 本文で名指しされたファイル) のいずれかに集約結果を記録しない限り AC は原理的に評価不能になる。姉妹 Issue #1163 が同型の制約に直面し operate route から pr route + 記録ファイルへ切り替えた前例 (`docs/spec/issue-1163-manual-ac-retype-a.md` Notes) に倣い、本 Issue でも記録ファイル 1 本を Changed Files とした。詳細は `## Autonomous Auto-Resolve Log` を参照。

### Size XL 維持と実際の route の乖離

`modules/size-workflow-table.md` の Size-to-Workflow Mapping Table は XL に対して「split guidance / Verify: —」を割り当てており、Phase-Level Light/Full Mapping 表も patch/pr/operate の 3 列のみで XL 向けの行を持たない。一方 `modules/ambiguity-detector.md` の非対話モードポリシーは「Size downgrade from XL」を High-Stakes Decision として明示的に skip 対象にしている。本 Issue は既に sub-issue 分割という XL 相当の構造判断を完了済みであり、残る作業 (集約レポート 1 本) は実質 S 相当だが、Size ラベルは XL を維持する (Step 18 で再評価はするが適用しない)。このため、将来 `/code 1158` を実行する際は **Size に依存した自動ルーティングではなく明示的な `--pr` フラグ**を使うことを推奨する (`modules/size-workflow-table.md` の Priority order で明示フラグは Size ベースのマッピングより優先される)。集約レポートは 5 sub-issue の rubric AC 充足性を左右する参照先になるため、`--patch` (レビューなし) より `--pr` (軽量レビューあり) が安全側と判断した。

### 未着手の 4 sub-issue に共通する留意点 (先回りメモ)

#1163 の実施を通じて判明した以下の 2 点は、#1164/#1165/#1166/#1167 の `/spec` 実行時にも再発しうるため、集約レポート作成時 (本 Issue の Implementation Step 2) に併せて注記する:

- **Issue 単位の件数と AC 行単位の件数は一致しない**: 区分 A は「34 Issue」だが実際の `verify-type: manual` AC 行は 36 行 (#719 / #708 が各 2 行) だった。`docs/stats/2026-08-05.md` の分類は Issue 単位、`observation-trigger.sh` のマッチ対象は AC 行単位であるため、他区分でも同様のずれが起きうる
- **`observation` への再型付けは `auto-run` イベントのマッチ母集団を実質倍増させる**: #1163 単独で `auto-run` のマッチが 31→59 AC 行に増加した (27 行分の再型付け + 他要因)。D2 (#1164、最大 13 行) がさらに加わる。#1099 の idempotency guard (24h) と `observation-dispatch-threshold` (既定 5) が影響を抑えるが、さらなる削減は #1118 (`when=` ゲート) と #1162 (セッション内 verify 済み除外) の担当であり、本 Issue のスコープではない

### `when=` 属性は付与しない (Consumed Comments の論点への回答)

Consumed Comments で提示された「79 件へ `when=` を併せて付与するか」という論点は、#1163 が既に裁定済み — 「`when=` / `keyword=` / `config=` ゲートは付与しない。実行文脈条件 (`when=`) は #1118 が明示的に引き受けている」(`docs/spec/issue-1163-manual-ac-retype-a.md` Notes)。他の sub-issue もこの前例を踏襲する想定であり、本 Issue の集約レポートもこの方針を追認する形で記録する。

### ドキュメント SSoT の軽微な不整合 (本 Issue のスコープ外)

`modules/verify-classifier.md` の Emitter Lookup Table (41行目付近) は `fix-cycle` イベントを「Not yet implemented」と記載しているが、`skills/verify/SKILL.md` の FAIL → reopen 経路は実際に `observation-trigger.sh --event fix-cycle` を呼んでいる (#1163 の spec retrospective が `modules/observation-trigger.md` 側で同じ不整合を先に指摘済み)。本 Issue の設計判断には影響しないため修正は行わない。

### #1164〜#1167 の Issue 本文に残る古い "Blocked by #1157" 記述

4 件とも本文に `## Blocked by #1157` セクションが残っているが、#1157 は 2026-08-04 に CLOSED (`stateReason: COMPLETED`) 済みで GraphQL 上のブロッキングは解消している (`gh-check-blocking.sh`/`get-blocked-by.sh` で確認済み、exit code は共に「オープンなブロッカーなし」を示す)。#1163 は `/issue --non-interactive` 実行時にこの記述を更新した (issue retrospective 参照)。他 4 件は各自の `/issue`/`/spec` 実行時に同様の更新が行われる想定であり、本 Issue の Spec からは編集しない (他 Issue の本文編集は本 Spec のスコープ外)。

## spec retrospective

### Minor observations

- **XL 親 Issue が sub-issue 分割後も自身の Pre-merge AC (rubric) を保持するケースへの経路定義が `modules/size-workflow-table.md` に存在しない**: Size-to-Workflow Mapping Table は XL に「split guidance / Verify: —」を割り当て、Phase-Level Light/Full Mapping 表も patch/pr/operate の 3 列のみを持つ。しかし #1158 のように分割後も親自身が rubric 型の集約 AC を持つ場合、その AC を評価可能にするには親自身も (小さくとも) Changed Files と route を持つ必要があり、既存のテーブルはこのケースを想定していない。今回は Size を XL に維持しつつ明示 `--pr` フラグでルーティングする回避策を Notes に記録したが、同型の XL 分割 Issue が今後増えるなら `size-workflow-table.md` 側にこのパターンの記述を追加する価値がある (改善提案として記録するに留め、Issue 起票は `/verify` の集約フェーズに委ねる)
- **#1164〜#1167 の Issue 本文に古い "Blocked by #1157" 記述が残存**: #1157 は着地済みだが、#1163 以外の 4 sub-issue の本文は未更新のまま。各自の `/issue`/`/spec` 実行時に自然に解消される見込みであり、本 Issue から先回りして編集する必要はないと判断した (詳細は本 Notes 節を参照)

### Judgment rationale

- **`modules/ambiguity-detector.md` の「Size downgrade from XL to L」を「XL からの任意の縮小」へ一般化して適用した**: 文言は特定的に「to L」だが、この制約の趣旨 (「sub-issue 分割要否の構造判断を無効化しない」) は縮小先が L であろうと XS/S/M であろうと同じリスクを持つ。文言の字面ではなく制約の趣旨に従い、Changed Files 数がどうであれ XL からのダウングレードは一律 skip する判断とした
- **#1163 の「rubric AC は operate route では評価不能」という判断を親 Issue 自身にも一段上で適用した**: #1163 は自分自身 (sub-issue) の rubric AC のために記録ファイルを追加したが、親 #1158 も同型の rubric-only Pre-merge AC を持つことに Step 6 の投資調査で気づいた。「親は追跡専用で実装を持たない」という Issue 本文の額面通りの記述より、rubric grader の可視範囲という機械的制約を優先し、親にも Changed Files を持たせた

### Uncertainty resolution

- **Size=XL のまま `/code` を実行した場合に `modules/ambiguity-detector.md` の Hard-error abort 条件 (「Size is XL without sub-issue splitting」) に抵触しないか**: #1158 は GraphQL `subIssues` で 5 件の sub-issue が既に確認できるため、この hard-error 条件 (分割が存在しない場合) には該当しないと判断した。ただし `/code` 自身の実装がこの判定をどう行うかは未確認であり、次回 `/code 1158` 実行時に実際に確認されるべき残存確認事項として記録する
- **Post-merge AC の文言をそのまま流用してよいか**: #1163/#1164 のように「N 件減少」という定量表現へ調整する必要があるか検討したが、#1158 自身の Post-merge AC は元々「79 件から減少していることを確認する」という定性的表現であり、5 sub-issue 全体の合計減少を指すため調整不要と判断し、Issue 本文のまま転記した

## Code Retrospective

### Deviations from Design

- なし。Spec の Implementation Steps (precondition gate → 集約レポート作成 → 検証) をそのまま実行した。Auto Retrospective 節が示唆する「親セッションが手動挿入した `run-code.sh 1158 --pr`」の想定どおり、`--pr --non-interactive` 引数での実行だった。

### Design Gaps/Ambiguities

- Step 10 (verify command consistency) の rubric AC 5 件はいずれも Issue #1158 本文に特定ファイルを名指ししていないため、grader (本セッション自身) の入力スコープは Issue 本文 + git diff (集約レポート本体) のみだった。AC2 (「A + D2 が observation へ再型付けされている」) の実際の裏付け (Issue 本文の再型付け結果) はこの PR の diff に含まれず、`docs/reports/manual-ac-retype-a.md` / `manual-ac-retype-d2.md` (別 PR で追加済みの既存ファイル) にのみ存在する。rubric の可視範囲制約 (Spec Notes 前掲) は「集約レポートファイルを持たせれば解決する」という設計判断だったが、厳密には「rubric text で当該既存ファイルを名指しする」までは踏み込んでいない。今回は集約レポート自身に十分な要約(event= 内訳・マッチ確認結果の転記)を含めることで PASS 判定としたが、将来同種の親 Issue で rubric AC がより厳密な一次情報を要求する場合、rubric text 側で参照ファイルを明示する設計を検討する価値がある。
- 区分 B (#1166) は operate route で処理されており、独自の記録ファイル (`docs/reports/manual-ac-retype-*.md`) を持たない。集約レポートでは #1166 の `## Execution Log` Issue コメントの内容を転記したが、他区分 (A/D2/D3/C/D1) が専用ファイルを持つのに対し B だけがコメントベースという非対称性がある。

### Rework

- なし。

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- Precondition gate (#1164/#1165/#1166/#1167 が全件 `phase/done`/CLOSED) を再確認し充足を確認した上で、`docs/reports/manual-ac-retype-summary.md` を作成した (Spec Implementation Steps 1〜4 をそのまま実行)
- Pre-merge AC 5 件 (すべて `rubric`) は、集約レポートの git diff + Issue 本文を入力として grader (本セッション自身) が評価し、全件 PASS と判定してチェックボックスを更新した
- 区分別処理結果は各 sub-issue の記録ファイル (`docs/reports/manual-ac-retype-a.md` / `-d2.md` / `-d3.md` / `-c-d1.md`) および #1166 の `## Execution Log` コメントから転記・要約する方式を採用し、単純なリンク集ではなく実数値 (件数・event= 内訳・retire 理由) を集約レポート本体に含めた

### Deferred Items
- Post-merge AC (`/audit stats --retention` での Manual waiting 件数減少確認、`event=auto-run`) — `/verify` が observation 経路で評価する
- Code Retrospective に記録した rubric AC の可視範囲制約 (別 PR で追加済みの sub-issue 記録ファイルを rubric text が名指ししていない件) — 将来の改善検討事項として記録のみ、本 Issue のスコープ外

### Notes for Next Phase
- 本 PR マージ後、`/review` → `/merge` → `/verify` の通常フローに進む。Post-merge AC は `event=auto-run` の発火を待つ observation 型のため、`/verify` 初回実行時は SKIPPED (waiting for event) となる想定
- 親 Issue #1158 自身の実装はこれで完了。5 sub-issue + 本集約レポートの全体像は `docs/reports/manual-ac-retype-summary.md` を参照すること

## Auto Retrospective

### Execution Summary

| # | Title | Route | Result | Notes |
|---|-------|--------|--------|-------|
| #1164 | 区分 D2 (実行シナリオ型 13 件) を observation へ再型付け | pr (Size M) | SUCCESS | PR #1232 merged。異常なし |
| #1165 | 区分 D3 (その他 19 件) を個別判断で再型付けまたは retire | pr (Size L, review --full) | SUCCESS | PR #1230 merged。異常なし |
| #1166 | 区分 B (別 repo 6 件) を retire または downstream へ移管 | operate (Spec 由来) | SUCCESS (exit 1 / reconcile-override) | `run-auto-sub.sh` exit 1 だが `reconcile-phase-state.sh code-patch --check-completion` が `matches_expected: true`。親セッションが Tier 1 で success へ override |
| #1167 | 区分 C (故障注入 2 件) の bats テスト化 + D1 (UI 目視 5 件) の manual 維持記録 | pr (Size M) | SUCCESS | Tier 2 fallback catalog により自動 recovery 後 PR #1237 merged |

Level 1 のみ (4 件すべて独立、blocked-by #1157 は CLOSED 済み)。並列度 4 (`auto-max-concurrent` 既定 5 の範囲内)。

### Parallel Execution Issues

- **#1166: operate route が pr dispatch と噛み合わない** — `/spec 1166` は Changed Files が空・Implementation Steps が全て `gh` CLI 操作であることから `ROUTE=operate` と判定したが、`run-auto-sub.sh` は spec 後に再取得した Size (M) だけで route を決めるため `code-pr` を dispatch した。operate route は PR を作らないので `reconcile-phase-state.sh code-pr --check-completion` が `matches_expected: false` を返し、Tier 2 (anchor はマッチしたが handler 失敗) → Tier 3 (`action=skip` が `matches_expected != true` を理由に reject) と降りて exit 1。実際には `/code` 側の operate 分岐は正常に完走しており、`code-patch` の completion check は operate 実行ログマーカーを検出して `matches_expected: true` を返す。`docs/reports/orchestration-recoveries.md` に `cause=operate-route-pr-dispatch-mismatch` で記録済み。
- **#1167: Tier 2 fallback catalog が自動 recovery** — code-pr フェーズで既知パターンにマッチし catalog 経由で復旧、PR #1237 作成まで自動継続。`apply-fallback.sh` 側が recovery ログを直接コミット済み (二重記録なし)。
- 4 並列で worktree 競合・concurrent commit・push 競合は発生せず。

### Orchestration Anomalies

- **XL route に親 Issue の実装フェーズが存在しない** — `/auto` の XL route は「sub-issue 実行 → 親ラベル集約 → sub-issue verify → 親 close flow」で構成され、親自身の `/code` を回す経路を持たない。ところが #1158 の Spec は Pre-merge AC 5 件が全て `rubric` 型であるため、rubric grader の可視範囲を確保する目的で `docs/reports/manual-ac-retype-summary.md` を Changed Files に持つ (親が実装成果物を持つ)。この結果、XL route をそのまま流すと親の rubric AC は成果物不在のまま `/verify` に到達して FAIL する。本セッションでは親セッションが Step 4d の後・親 verify の前に `run-code.sh 1158 --pr` を手動挿入して回避した。

### Improvement Proposals

- **auto/run-auto-sub: sub-issue の route 判定が Spec 由来の operate route を honor しない** — `skills/auto/SKILL.md` の単一 Issue 経路には Step 3a「Operate route demotion」があり、spec 後に Spec の diff-less 判定で `ROUTE=operate` へ降格する。しかし `scripts/run-auto-sub.sh` の post-spec Size 再取得 (`INITIAL_SIZE` → `SIZE` 比較) は Size 軸しか見ておらず、同等の operate 判定を持たない。結果として operate route の sub-issue は必ず `code-pr` で dispatch され、completion check 失敗 → Tier 2/Tier 3 を空振りさせ exit 1 で終わる。本セッションの #1166 が実例 (機能的には成功しているのに wrapper は失敗扱い)。`run-auto-sub.sh` に Step 3a 相当の operate 判定を追加し、成立時は `code-patch` dispatch + `code-patch` completion check へ切り替える。バッチ/XL 経路で operate route Issue を扱う限り再発する構造的欠陥。
- **size-workflow-table / auto: XL 分割後も親が集約成果物を持つパターンの経路定義が無い** — `modules/size-workflow-table.md` は XL を「sub-issue へ分割し親は追跡のみ」と定義するが、親が rubric 型の横断 AC を持つ場合、rubric grader は Issue コメントや Spec ファイルを参照できないため親自身が成果物ファイルを持たざるを得ない (#1163 が sub-issue レベルで同じ結論に到達し、#1158 の Spec がそれを親へ一段上げて適用した)。`/auto` の XL route はこの「親の実装フェーズ」を持たないため、Spec がそう設計しても自動実行経路から漏れる。XL route に「全 sub-issue 完了後、親 Spec の Changed Files が非空なら親の code フェーズを実行する」ステップを追加するか、`size-workflow-table.md` 側で親が成果物を持つことを禁じて sub-issue へ寄せるかの二択を決める。#1158 の spec retrospective でも Deferred Items として同じ欠落が記録されている。
