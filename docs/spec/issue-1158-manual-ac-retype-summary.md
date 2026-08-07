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
