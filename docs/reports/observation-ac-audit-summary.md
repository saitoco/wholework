# observation AC 実査 集約レポート (#1270)

再型付けされた `verify-type: observation` の post-merge AC を「発火時に判定可能か」で実査し、判定不能分を retire (分類 D) ・`manual` へ差し戻し (分類 E) する取り組みの集約レポート。AC 行単位の実査は 3 本の sub-issue (#1274 / #1275 / #1276) が担い、本レポートはその baseline と集約結果を記録する。

## Baseline (実装前スナップショット)

**計測日時**: 2026-08-08 (UTC)
**計測時点**: sub-issue #1274 / #1275 / #1276 の着手前 (retire・差し戻しによる母集団変化の発生前)

親 #1270 Notes「実行順序の制約」により、baseline は 3 sub-issue の着手前に確定させる必要がある。retire が始まると母集団が変化し、この数値は再取得不能になる。

### 計測方法 (post-merge で同一手順を再現すること)

```bash
# 1. 候補母集団の凍結 (副作用なし)
scripts/observation-trigger.sh --event auto-run --dry-run

# 2. 各候補 Issue の AC 行を計数
#    対象行の条件: 行頭 "- [ ]" かつ verify-type: observation かつ event=auto-run
```

`--dry-run` を用いるのは、通常実行が全マッチ Issue に通知コメントを投稿する副作用を持つため。

### 母集団

| 指標 | 値 |
|---|---|
| dispatch 候補に挙がった Issue 数 | **82** |
| うち計数対象 AC 行を含む Issue 数 | 82 |
| **候補 observation AC 行数 (分母)** | **85** |

1 Issue あたり 1 行が大多数 (79 Issue が 1 行)。複数行を持つのは #446 / #478 / #710 の 3 Issue (各 2 行)。

### 属性による機械的ゲート内訳

SKIPPED には「属性で機械的に決まるもの」と「条件文の意味解釈を要するもの」がある。前者のみ baseline 時点で確定できる。

| 属性 | 行数 | SKIPPED になる条件 |
|---|---|---|
| `when=mode:batch` | 3 | dispatch 元の `/auto` が `single` モードのとき |
| `session=next` | 16 | 同一セッション内で dispatch されたとき |
| 属性ゲートなし | 66 | 機械的には SKIPPED にならない (意味解釈が必要) |

`when=` の軸は全 3 行とも `mode:batch` で、他の軸 (`route` / `recovery-tier` / `execution-context`) は 0 行だった。

### verify-type 抽出方式の一致確認

#1273 が扱うタグ抽出の誤分類が本計測に影響しないことを確認した。substring 方式 (現行 `opportunistic-search.sh` と同等) と HTML コメント限定方式の双方で計数し、**両者は 85 行で完全一致 (不一致 0 行)** した。

ただしこれは #1273 が解決済みであることを意味しない。#1273 の欠陥は `scripts/scan-pending-ac.sh:139` の **first-match-wins** (行内で最初に現れる `verify-type:` を採る) であり、本計測が用いた「行内に `verify-type: observation` が現れるか」という判定とは別の経路である。observation dispatch 経路には影響しないことを確認したに留まる。

### 未確定事項: SKIPPED 率の分子

親 Pre-merge AC 1 は分母を「1 回の dispatch で候補に挙がった observation AC 行数」、分子を「そのうち SKIPPED を返した行数」と定義するが、**この 2 つは 1 回の dispatch では両立しない**。

`skills/auto/SKILL.md` Step 5 の dispatch は `observation-dispatch-threshold` (既定 5) 件を上限とするため、1 回の実行で実際に `/verify` へ渡り SKIPPED/PASS が確定するのは最大 5 行である。分母 85 に対する分子は構造上 5 が上限となり、率としての意味をなさない。

想定される 2 通りの読み:

| 読み | 分母 | 分子 | 評価 |
|---|---|---|---|
| 読み 1 | 85 (候補全体) | 実 dispatch 分の SKIPPED | 率が上限 5/85 に張り付き無意味 |
| 読み 2 | 実 dispatch 数 (5) | そのうちの SKIPPED | dispatch 効率として有意だが n=5 と小さい |

**読み 2 が意図に合致する**と考えられるが、baseline としては n=5 の単発測定になり分散が大きい。本レポートは分母 (母集団 85 行) を確定値として記録し、分子の測定プロトコルは #1270 の実装フェーズで確定させることとする。post-merge 比較は同一プロトコルで行うこと。

参考として、直近の実 dispatch 事例が 1 件ある。セッション `94570-1786069858` (2026-08-07) で昇順先頭 5 件 (#446 / #477 / #478 / #484 / #486) を評価した際、判定可能と見込まれたのは #484 のみで残り 4 件は前提不成立により SKIPPED 見込みだった (**4/5 = 80%**)。ただしこれは実 dispatch ではなく事前評価であり、かつ当該セッションは最終的に選抜方法を変更している (`docs/sessions/94570-1786069858-2026-08-07/session.md` § Observation Dispatch 結果) ため、参考値として扱う。

## 分類結果 (sub-issue 完了後に記入)

_3 本の sub-issue 完了後、A/B/C/D/E の内訳を区分別・合計で集計する。_

| 区分 | #1274 (#1163 由来) | #1275 (#1164 由来) | #1276 (#1165 由来) | 合計 |
|---|---|---|---|---|
| A | — | — | — | — |
| B | — | — | — | — |
| C | — | — | — | — |
| D (retire) | — | — | — | — |
| E (`manual` へ差し戻し) | — | — | — | — |
| **合計** | — | — | — | **57** |

### D と E の内訳 (型間移動の可視化)

_observation waiting の減少が「retire による純減」と「manual への移動」のどちらにどれだけ由来するかを記録する。_

### E の内訳 (capability 待ちの分離)

_E のうち「今すぐ `/verify` で判定できる」ものと「装備待ち」を区別する。後者は必要な `capability=<key>` を併記する (#1278 の `capability-unavailable` 区分へ引き継ぐため)。_

## Related

- **#1270** — 本レポートの親 Issue
- **#1274 / #1275 / #1276** — AC 行単位の実査を担う sub-issue
- **#1278** — `/verify` Step 8b の実行可否判定の記録。E の `capability=<key>` 内訳の引き継ぎ先
- **#1273** — `verify-type` タグ抽出の誤分類。本計測では影響なしを確認
- **#1242** — `opportunistic-search.sh` の走査スコープと母集団
- `docs/reports/manual-ac-retype-summary.md` — 先行する #1158 の集約レポート (本 Issue の対象 57 行の出所)
