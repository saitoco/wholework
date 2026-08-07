# manual AC 79 件 分類別移行 集約クローズアウトレポート (#1158)

`phase/verify` に滞留する `verify-type: manual` の post-merge AC 79 件 (`docs/stats/2026-08-05.md` Section 10) を、区分 A/B/C/D1/D2/D3 の 6 区分に従って observation への再型付け・retire・bats テスト化・manual 維持のいずれかへ移行した取り組みの集約結果。実作業は 5 本の sub-issue (#1163〜#1167) が担い、本レポートはそれらの結果を集約する。

## 対象・件数内訳

| 区分 | Issue 数 (本文記載) | 実 AC 行数 | 担当 sub-issue | 状態 |
|---|---|---|---|---|
| A (次回…観察型) | 34 | 36 | #1163 | CLOSED |
| D2 (実行シナリオ型) | 13 | 16 | #1164 | CLOSED |
| D3 (その他) | 19 | 22 | #1165 | CLOSED |
| B (別 repo 依存) | 6 | 6 | #1166 | CLOSED |
| D1 (UI 目視) | 5 | 5 | #1167 | CLOSED |
| C (故障注入) | 2 | 2 | #1167 | CLOSED |
| **合計** | **79** | **87** | — | 全件 CLOSED |

Issue 単位 (79件) と AC 行単位 (87行) の件数は一致しない。`docs/stats/2026-08-05.md` の分類は Issue 単位である一方、`observation-trigger.sh` 等のマッチ対象は AC 行単位のため、1 Issue が複数の対象 AC 行を持つ場合 (例: 区分 A の #719 / #708 が各 2 行) にずれが生じる。この単位ずれは複数の sub-issue (A・D2・D3) で共通して観測された。

## 区分別処理結果

### A + D2 (observation 再型付け)

区分 A (34 Issue / 36 AC行、#1163) と区分 D2 (13 Issue / 16 AC行、#1164) を合わせて 47 Issue / 52 AC行が対象。`event=` に使用できるのは `modules/verify-classifier.md` が定める 5 有効値 (`pr-review-full` / `pr-review-light` / `auto-run` / `watchdog-kill` / `fix-cycle`) のみ。

| sub-issue | 対象 AC行 | 再型付け | 内訳 | 対象外 (manual 維持) |
|---|---|---|---|---|
| #1163 (A) | 36 | 29 | `event=auto-run` 27 / `event=fix-cycle` 2 | 7 |
| #1164 (D2) | 16 | 12 | `event=auto-run` 12 | 4 |
| **合計** | **52** | **41** | auto-run 39 / fix-cycle 2 | **11** |

再型付け後、`opportunistic-search.sh --event auto-run --dry-run` / `--event fix-cycle --dry-run` の実行で、両 sub-issue とも再型付けした全 AC 行が実際のマッチ集合に含まれることを個別に確認済み (件数の単純差分ではなく個別含有で判定。同時期に他 sub-issue や `/auto` 実行由来の新規 AC が母集団に加わるため、単純な件数差分は一致しない)。

対象外 11 行 (manual 維持) の主な理由:
- 故障注入型で 5 有効値のどの発火でも観測窓が開かない (#719条件1、#708条件1・2)
- 前提条件 (`autonomy: L2` 等) が本リポジトリの実設定と矛盾し `config=` ゲートでも表現不能 (#704)
- downstream プロジェクトでの主観評価または障害注入の二重前提で upstream から観測不能 (#501、#500)
- vault 等 downstream 固有領域がこのリポジトリに存在しない (#479)
- 別リポジトリ (`saito/trading`) 依存で upstream から機械検証不能、Issue 本文自身が明記済み (#507 条件1〜3)
- `/audit` 単独実行に対応する event が機構の語彙 (5 有効値) に存在しない (#444)

### B (retire / 移管)

区分 B の対象 6 Issue (#1061 #1044 #1042 #1041 #962 #508、#1166) はすべて **retire** と判断された。downstream への移管は **0 件**。

判断根拠: 6 件すべてで Pre-merge AC が完全にチェック済み (#1061: 10/10、#1044: 2/2、#1042: 2/2、#1041: 4/4、#962: 6/6、#508: 4/4) であり、実装の正しさは bats テスト・grep 検証・rubric 検証によって既に機械的または設計レベルで担保されている。downstream リポジトリへ確認用 Issue を新規に起票しても、既に担保済みの正しさに対して追加の検証シグナルを得られる見込みが薄く、費用対効果に見合わないと判断した。

実施内容: 6 Issue それぞれに retire 決定コメントを投稿し、`phase/verify` → `phase/done` へのラベル遷移を実施 (6/6 成功)。#1166 は Spec の Changed Files が空でリポジトリ内ファイル変更を伴わないため operate route (`## Execution Log` Issue コメントとして記録) で処理された。

### D1 (manual 維持)

区分 D1 の 5 Issue (#1059 #709 #548 #442 #441、#1167) は `docs/stats/2026-08-05.md` の棚卸し方針表でも「manual のまま維持 (正当)」と分類されており、`manual` タグ・AC 本文は変更せず維持する。判断根拠:

| Issue | manual 維持の理由 |
|---|---|
| #1059 | 複数スキルにまたがる実オーケストレーションと実 preview 環境が前提で、単一の決定的スクリプトでの模擬は統合確認としての意味を失う |
| #709 | GitHub Issue Forms のレンダリングは GitHub 側プラットフォームの責務であり、本リポジトリのテスト可能範囲外 |
| #548 | 実 downstream リポジトリの実 Web ページに対するブラウザ自動化・実スクリーンショット取得が前提で、生成画像の見た目確認には目視が必要 |
| #442 | 任意の将来 Issue に対する LLM の Spec 生成品質という主観的判断が対象で、固定 fixture でも rubric でも表現できない (rubric は対象ファイルを事前に名指しできない) |
| #441 | 実ブラウザによるレンダリング・スクリーンショット取得・pixel-diff 判定の一連の流れが前提で、数値計算のみの固定 fixture テストでは AC の主旨を代替できない |

Issue 本文の post-merge AC 行自体は変更しないため、`phase/verify` の Manual waiting 集計には引き続き残るのが意図した挙動である。

### C (bats テスト化 → auto 再型付け)

区分 C (故障注入、2 Issue: #1066 #1060、#1167) は D1 とは異なり、故障注入シナリオの機械的な核 (`wait-ci-checks.sh` の早期 break パス、`check-pre-merge-ac.sh` の境界ケース) を固定 fixture の bats テストで再現できたため、`tests/wait-ci-checks.bats` / `tests/check-pre-merge-ac.bats` へのテスト追加を行い、両 Issue の post-merge AC を `verify-type: auto` (`<!-- verify: command "bats tests/..." -->`) へ再型付けした。retire ではなく、テストによる担保を根拠とした再型付け方式を採用している。

### D3 および対象外 (再型付けしなかった AC)

区分 D3 (19 Issue / 22 AC行、#1165) は、A/B/C/D1/D2 のいずれにも当てはまらなかった残余として 1 件ずつ条件文を読んで判断した。

| 処理 | AC行数 | 内訳 |
|---|---|---|
| observation 再型付け | 16 | `event=auto-run` 14 / `event=watchdog-kill` 1 / `event=pr-review-full` 1 |
| retire | 6 | `auto-stop-at` 未設定で前提不成立 (#783)、将来拡張未実装 (#706)、downstream 固有 XL Issue (#591)、比較基準が陳腐化 (#587)、前提条件自体が不成立 (#563)、downstream 主観評価 (#484条件2) |
| manual 維持 | 0 | — |
| 対象外 (編集しない/別扱い) | 2 (22 行の外数) | #591 の既チェック済み (`- [x]`) 行、#491 のコードフェンス内サンプル行 (AC ではない) |

注: 上表の「対象 AC 行 22 行」は再型付け 16 + retire 6 の内訳であり、対象外 2 行は 22 にも 87 行合計にも含まれない (母集団の外側)。

D3 は #1163 (区分 A) の「未知 event なら manual 維持」という原則から意図的に方針変更し、前提が原理的に成立しない条件をすべて retire に倒した (詳細: `docs/spec/issue-1165-manual-ac-retype-d3.md` Notes)。

**移行対象外とした AC 全体のまとめ (AC5 対応)**: A/D2 由来の manual 維持 11 行 (前掲) と D3 の対象外 2 行 (#591 は既チェック済みのため編集不要、#491 はコードフェンス内サンプルで AC ではない) が「再型付け・retire いずれも行わなかった」項目である。D1 の 5 行は「正当な manual 維持」として別枠 (前掲) で扱う。各項目の個別理由は上表および各 sub-issue の記録ファイル (`docs/reports/manual-ac-retype-a.md` / `manual-ac-retype-d2.md` / `manual-ac-retype-d3.md`) に Issue 単位で記録済み。

## 検証

- 6 区分の Issue 数合計 (34+13+19+6+5+2=79) は `docs/stats/2026-08-05.md` Section 10 の分類件数 79 と一致することを確認した (差異なし)。この 79 件は同レポート Section 10 が集計した 90 日窓の母集団に基づく。同 Section 11 が指摘するとおり全期間へ広げると対象は増えるため、本クローズアウトは「90 日窓内の 79 件」の完了を意味する。全期間の再棚卸しは別途判断とする。
- AC 行数合計は 87 行 (Issue 単位の 79 件から、A/D2/D3 での複数行 Issue の存在により +8 のずれ)。
- A/D2 は `opportunistic-search.sh --event <name> --dry-run` で再型付け全行の含有を個別確認済み (各 `docs/reports/manual-ac-retype-a.md` / `manual-ac-retype-d2.md` 参照)。D3 は 16 行中 11〜12 行を同様に確認し、残る行はマッチ集合外だった: #1135 / #478 条件1・2 は `when=mode:batch` ゲートが `mode=single` セッションで設計どおり除外、#490 / #465 は OPEN のため `opportunistic-search.sh` が固定する `--state closed` 母集団に構造的に入らず、close されるまで dispatch されない (いずれも `gh issue view` のリテラル一致で再型付け済みを確認。詳細: `docs/reports/manual-ac-retype-d3.md` § 検証)。
- B の 6 件は `gh issue view` でラベルが `phase/done` へ遷移済みであることを確認済み。
- C の 2 件は追加した bats テストが実際に該当シナリオを検証することを確認済み。
- D1 の 5 件は Issue 本文が未変更 (manual 維持) であることを確認済み。

## `when=` 属性について

79 件全体を通じて `when=` / `keyword=` / `config=` 相当のゲート付与は最小限 (D3 の `when=mode:batch` 3行、`config=capabilities.workflow` 1行) にとどめ、包括的な実行文脈条件の宣言は #1163 の裁定を踏襲し #1118 に委ねた。

## 移行後の効果測定 (Post-merge)

移行完了後の `/audit stats --retention` で、`phase/verify` の Manual waiting 件数が移行前 (79 件) から減少していることを確認する (post-merge AC、`event=auto-run` 発火待ち)。

なお、再型付け済みでも #490 / #465 (OPEN) は `--state closed` 固定の母集団に入らず当面 dispatch されない。また `when=mode:batch` ゲート付き行は batch 実行時のみ発火する。減少幅がこれらの分だけ想定より小さくなるのは想定内である。
