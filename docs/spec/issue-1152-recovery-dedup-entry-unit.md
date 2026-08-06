# Issue #1152: collect-recovery-candidates: 除外判定を entry 単位化し誤検知と再発見落としを同時に解消

## Consumed Comments

- saito / MEMBER / first-class / `/issue 1152` の Issue Retrospective — 方針確定 (方針 2)、スコープ拡大 (`起票済み` フィルタの group-key 一括抑止)、`#1191 blocked-by #1152` の設定理由 / https://github.com/saitoco/wholework/issues/1152#issuecomment-5201365514

- saito / MEMBER / first-class / ## 実装セッションへの申し送り (Spec 作成後に着地した #1098 の影響) / https://github.com/saitoco/wholework/issues/1152#issuecomment-5202021801
## Overview

`scripts/collect-recovery-candidates.sh` の除外判定を **group-key 単位から entry 単位**へ変え、対応 Issue の解決時点との日付比較で判定する。これにより「解決済み症状の再検出 (false positive)」と「対応 Issue close 後の再発の握り潰し (false negative)」を同時に解消する。

`/verify` Step 15 と、#1191 が追加する `/audit stats --retention` Section 10 の 2 つの consumer が同じ意味論を共有できるよう、判定は collector 側の読み取り時計算に閉じる。

## Reproduction Steps

### False positive (2026-08-06 `/verify 1180` Step 15 で実測)

1. `bash scripts/collect-recovery-candidates.sh docs/reports/orchestration-recoveries.md --threshold 3 --issues-json <open issues>` を実行
2. `manual-recovery-review-rerun	3` が出力される
3. 該当 3 entry (#1055 / #1061 / #1069、最新 2026-07-31 03:08 UTC) はいずれも対応 Issue #1123 (2026-07-31 03:15 UTC 起票 → 2026-08-04 10:24 UTC closed) の**起票契機となった occurrence そのもの**であり、修正後の新規発生はゼロ
4. #1123 が closed のため `--issues-json` (open 限定) の重複チェックをすり抜ける

### False negative (`/spec` 実測)

1. `docs/reports/orchestration-recoveries.md` に `起票済み #N` を持つ entry が 1 件でもあると、その group-key の集計全体が飛ばされることを合成 fixture で確認:

```
2026-08-10 probe-symptom  未起票      ← 新規発生 3 件
2026-08-09 probe-symptom  未起票
2026-08-08 probe-symptom  未起票
2026-07-01 probe-symptom  起票済み #9999

$ bash scripts/collect-recovery-candidates.sh <fixture> --threshold 1
(出力なし)
```

2. かつ `_find_known_recoveries_issue "manual-recovery-review-rerun"` は closed の #1123 に解決される (実測):

```
$ gh issue list --state closed --json number,title,closedAt --limit 1000 \
  | python3 -c "...title == 'recoveries: manual-recovery-review-rerun'..."
{'closedAt': '2026-08-04T10:24:23Z', 'number': 1123, 'title': 'recoveries: manual-recovery-review-rerun'}
```

3. したがって今日この症状が真に再発しても、新 entry は自動で `起票済み #1123` と刻印され、group-key ごと永久に検出されない

## Root Cause

除外判定が **group-key 単位**であることと、対応 Issue の**解決時点を考慮しない**ことの 2 点。

| 箇所 | 現状 | 問題 |
|---|---|---|
| `collect-recovery-candidates.sh:152-155` | `EXCLUDED_LIST` に group-key があれば集計ループを `continue` | 1 entry でも `起票済み` なら group-key 全体を無期限に抑止 |
| `collect-recovery-candidates.sh:163-172` | `--issues-json` の **open** Issue タイトルとの完全一致で除外 | close 済み対応 Issue を認識できず、旧 entry が毎回再浮上 |
| `run-auto-sub.sh:194-204` | `_find_known_recoveries_issue` が open → **closed** の順にフォールバック | close 後の再発 entry まで自動で `起票済み #N` と刻印 |

3 つが噛み合って、false positive (起票前の旧 entry が `未起票` のまま残る) と false negative (close 後の再発が自動刻印されて握り潰される) が同時に成立している。

なお `tests/collect-recovery-candidates.bats:36` の `@test "exclusion: filed improvement candidate mark -> symptom excluded from output"` が group-key 一括抑止を期待動作として固定しているため、修正には既存テストの更新が必要。

## Changed Files

- `scripts/collect-recovery-candidates.sh`: 除外判定を entry 単位化 + 対応 Issue 解決 (`起票済み #N` → タイトル完全一致の順) + `closedAt` との日付比較 + `--with-tracking` オプション追加 + 冒頭コメント更新 — bash 3.2+ 互換
- `skills/verify/SKILL.md`: Step 15 手順 1 の `gh issue list --state open --limit 200 --json number,title` を `--state all --limit 1000 --json number,title,state,closedAt` に変更
- `tests/collect-recovery-candidates.bats`: 新規 3 ケース追加 + 既存 `exclusion: filed improvement candidate mark` テストを entry 単位判定に合わせて更新
- `docs/structure.md`: L187 `collect-recovery-candidates.sh` の説明 (「exclude filed entries」「`--issues-json PATH` for duplicate detection」) を実装後の規則に更新
- `docs/ja/structure.md`: L180 同上 (日本語ミラー)
- `docs/tech.md`: [Steering Docs sync candidate] L129 の `recoveries-auto-fire` 既定 opt-out 記述 — `--threshold 1` による頻度確認の案内が中心で dedup 規則には触れていないため変更不要の見込み。実装後に読んで判断すること
- `docs/ja/tech.md`: [Steering Docs sync candidate] L121 同上 (日本語ミラー)

## Implementation Steps

1. `scripts/collect-recovery-candidates.sh` に entry 単位の除外判定と日付規則を実装する (→ 受入条件 1, 2)
   - entry のパース時に、`起票済み #N` の N と entry 日時 (H2 ヘッダの `YYYY-MM-DD HH:MM`) を entry ごとに保持する
   - group-key ごとに対応 Issue を解決する: いずれかの entry の `起票済み #N` を優先し、無ければ `--issues-json` 内で `recoveries: <group-key>` にタイトル完全一致する Issue を採る
   - 解決した Issue が `state=OPEN` → その group-key の全 entry を除外
   - `state=CLOSED` → entry 日時が `closedAt` 以前の entry のみ除外し、以降の entry は計数する
   - `--issues-json` が無い / `state`・`closedAt` を持たない場合の代替基準: ファイル内で最も新しい `起票済み` entry の日時以前の entry を除外し、以降を計数する (対応 Issue が解決できない場合の degrade。旧挙動へは戻さない)
   - 日付比較は entry 日時 `YYYY-MM-DD HH:MM` を `YYYY-MM-DDTHH:MM` に整形し、`closedAt` を先頭 16 文字に切り詰めた文字列との辞書順比較で行う (bash 3.2 で `date` 依存なしに成立させるため)
2. 同ファイルに `--with-tracking` オプションを追加し、冒頭コメントを実装後の規則に更新する (after 1) (→ 受入条件 5, 6, 7)
   - 既定の出力形式 `<group-key>\t<count>` は変更しない (既存 consumer と配布先プロジェクトの後方互換)
   - `--with-tracking` 指定時のみ 3 列目に `tracked:#N` / `untracked` を付加する
   - 冒頭コメントから `matches an open issue title are excluded` を削除し、entry 単位判定・`closedAt` 比較・`--issues-json` 欠落時の代替基準を記述する
3. `skills/verify/SKILL.md` Step 15 手順 1 の `gh issue list` を `--state all --limit 1000 --json number,title,state,closedAt` に変更する (→ 受入条件 3, 4)
   - 手順 1 の説明文とコードブロックの両方を更新する (`.tmp/open-issues-$NUMBER.json` のファイル名は変更しない)
   - 手順 3 の `group-key<TAB>count` のパース記述は既定出力が不変のため変更しない
4. `tests/collect-recovery-candidates.bats` にテストを追加・更新する (after 1, 2) (→ 受入条件 8, 9)
   - 追加 (a): 対応 Issue が closed で、`closedAt` より**後**の entry が計数される
   - 追加 (b): 対応 Issue が closed で、`closedAt` より**前**の entry が除外される
   - 追加 (c): 対応 Issue が open のとき全 entry が除外される
   - 更新: 既存 `exclusion: filed improvement candidate mark -> symptom excluded from output` を entry 単位判定の期待値に合わせる (fixture は `--issues-json` 無しのため代替基準が適用され、`起票済み #123` エントリより後の 1 件が計数される)
5. `docs/structure.md` と `docs/ja/structure.md` の `collect-recovery-candidates.sh` 説明を更新する (after 1, 2) (→ 受入条件 6 の周辺整合)

## Verification

### Pre-merge

- <!-- verify: rubric "collect-recovery-candidates.sh の除外判定が entry 単位で行われている。各 entry の対応 Issue を『起票済み #N』の N から、無ければ recoveries: <group-key> のタイトル完全一致から解決し、Issue が open なら全 entry を除外、closed なら closedAt より古い entry のみを除外する。--issues-json が state/closedAt を持たない場合は、ファイル内の最新の起票済み entry の日時を代替基準として同じ entry 単位判定を行う" --> 除外判定が entry 単位の日付規則になっている
- <!-- verify: rubric "対応 Issue の closedAt より後に追記された entry は、run-auto-sub.sh の書き戻しにより 起票済み #N が付与されていても計数される。この再発検出の negative case が実装またはテストで確認できる" --> 対応 Issue close 後の再発が握り潰されない
- <!-- verify: rubric "skills/verify/SKILL.md Step 15 が collect-recovery-candidates.sh に渡す --issues-json が、state と closedAt を含む全 state の Issue 一覧になっている" --> `/verify` Step 15 が state と closedAt を渡す
- <!-- verify: section_contains "skills/verify/SKILL.md" "Step 15" "closedAt" --> Step 15 の記述に `closedAt` が含まれる
- <!-- verify: rubric "collect-recovery-candidates.sh の出力から、各 group-key に対応する Issue が存在するか (tracked / untracked) を判別できる。既定の出力形式は後方互換のまま維持され、#1191 の /audit stats --retention Section 10 がこの情報を取得できる形になっている" --> 出力から tracked / untracked が判別できる
- <!-- verify: rubric "scripts/collect-recovery-candidates.sh 冒頭のコメントが、実装後の除外規則 (entry 単位判定 + closedAt 比較 + --issues-json 欠落時の代替基準) と一致する内容に更新されている" --> 冒頭コメントが実装と一致している
- <!-- verify: file_not_contains "scripts/collect-recovery-candidates.sh" "matches an open issue title are excluded" --> open 限定を前提とした旧コメントが残っていない
- <!-- verify: rubric "tests/collect-recovery-candidates.bats に、(a) 対応 Issue の closedAt より後の entry が計数されるケース、(b) closedAt より前の entry が除外されるケース、(c) 対応 Issue が open の場合に全 entry が除外されるケース の 3 つが追加されている。あわせて既存の『filed improvement candidate mark -> symptom excluded』テストが entry 単位判定に合わせて更新されている" --> 新旧両方向のテストケースが揃っている
- <!-- verify: github_check "gh pr checks" "Run bats tests" --> bats スイート全体が PASS する (PR 経路)

### Post-merge

- `/verify` 実行の Step 15 出力に、close 済みの対応 Issue が存在する group-key が候補として現れないことを観察する (`verify-type: observation event=auto-run session=next`)
  - 期待される出力構造:
    - `manual-recovery-review-rerun` / `review-tier3-recovery` (いずれも対応 Issue あり) が `--threshold 3` の候補として出力されない
    - 対応 Issue の `closedAt` より後に追記された entry を持つ group-key は、`起票済み #N` が付与されていても候補として出力される
    - 既定の出力形式が `<group-key>\t<count>` のままで、Step 15 手順 3 のパースが失敗しない

## Notes

### `--with-tracking` を opt-in にした理由

既定の出力形式 `<group-key>\t<count>` を変えると、`skills/verify/SKILL.md` Step 15 手順 3 のパース記述、`docs/structure.md` の出力形式記述、`tests/collect-recovery-candidates.bats` の既存アサーション、そして配布先プロジェクトの consumer すべてに波及する。#1191 は新規 consumer なので opt-in で足りる。既定不変 + opt-in 拡張は wholework の adapter/capability の既存慣行とも整合する。

### `--issues-json` 欠落時に旧挙動へ戻さない理由

`docs/tech.md` L129 は `--issues-json` なしの `--threshold 1` 直接実行を頻度確認の手段として案内している。この経路で group-key 一括抑止が残ると、本 Issue の false negative がそのまま残存する。対応 Issue を解決できないぶん精度は落ちるが、ファイル内の最新 `起票済み` entry 日時を代替基準にすれば entry 単位判定は成立する。

### 日付比較を文字列比較で行う理由

`collect-recovery-candidates.sh` は bash 3.2+ 互換で `date` の GNU/BSD 差異を持ち込みたくない。entry 日時 (`YYYY-MM-DD HH:MM`) と `closedAt` (`YYYY-MM-DDTHH:MM:SSZ`) はいずれも UTC 固定桁のため、`YYYY-MM-DDTHH:MM` の 16 文字に揃えれば辞書順比較が時系列比較と一致する。

### `_find_known_recoveries_issue` の closed フォールバックは変更しない

Root Cause の 3 行目 (`run-auto-sub.sh:194-204`) は false negative の一因だが、本 Issue では**変更しない**。書き戻し (`起票済み #N`) は「この entry がどの Issue に紐づくか」の記録として正しく、collector 側が日付で判定するようになれば刻印自体は無害になる。むしろ `#1105` のように group-key 名と一致しないタイトルの対応 Issue を紐づける唯一の手段であり、削るとその経路が失われる。

### 既存テストが欠陥を期待動作として固定している

`tests/collect-recovery-candidates.bats:36` は group-key 一括抑止を PASS 条件として書かれている。Implementation Step 4 で更新するが、これは仕様変更に伴う正当な更新であり、テストを通すための緩和ではない。

### Issue 本文との整合 (`/spec` 実測による更新)

起票時点の Issue 本文は「方針 3 (書き戻し) は未実装」を前提にしていたが、#1017 で既に実装済みであることが判明した。Background に「追加実測 5」として追記し、受入条件 1/2 を「`未起票` マーカーの有無」ではなく「対応 Issue の解決時点との日付比較」を問う形に書き換えた。旧文言のままだと、closed フォールバックによる自動刻印を見逃す実装でも PASS しうるため。

### 受入条件数が light テンプレートの目安を超えている

`SPEC_DEPTH=light` の目安は実装ステップ・pre-merge 検証項目とも 5 件だが、本 Spec は実装ステップ 5 / 検証項目 9 となっている。検証項目 9 行のうち 2 組 (3+4、6+7) は `rubric` + 機械チェックの補完ペアであり、論理的な検証観点は 7 件。Root Cause が 3 箇所にまたがるため、これ以上の統合は「どの失敗モードが未解決か」を判別できなくする。

### 測定スコープ

- `EXCLUDED_LIST` の group-key 一括抑止: 合成 fixture (`.tmp/recoveries-probe.md`、4 entry) による実行結果
- `_find_known_recoveries_issue` の closed 解決: `gh issue list --state closed --limit 1000` の全件から `title == "recoveries: manual-recovery-review-rerun"` を完全一致で抽出
- 現在の `docs/reports/orchestration-recoveries.md`: `未起票` 23 件 / `起票済み` 43 件 (`grep -c`、2026-08-06 時点)

## Code Retrospective

### Deviations from Design

- Spec の `--issues-json が state/closedAt を持たない場合の代替基準` は「ファイル内で最も新しい起票済み entry の日時」とだけ記述しており、file-global か group-key scoped かが曖昧だった。group-key を跨いだ cross-contamination を避けるため **group-key scoped** (その group-key 自身の最新 `起票済み` entry) で実装した。Implementation Steps は更新不要 (Spec の記述自体は誤っていないため) だが、この解釈選択を明記する。
- Implementation Step 4 が明示した更新対象は既存テスト `exclusion: filed improvement candidate mark` の 1 件のみだったが、同じく `--issues-json` に `state` を含まない旧形式フィクスチャを使っていた 2 件の `duplicate check` テストも新スキーマ (`state`/`closedAt` 前提) の下では意味が変わってしまうため、両方の `issues.json` フィクスチャに `"state": "OPEN"` を追加して意図 (「対応 Issue が存在すれば除外される」) を保った。旧コントラクトが暗黙に "open issues のみのリスト" だったことの明示化であり、テストの検証意図は変えていない。

### Design Gaps/Ambiguities

- 独立サブエージェントによるアドバーサリアルレビューで、AC の対象外の 2 点が見つかった (blocking ではないため据え置き):
  - **境界の秒精度**: `closedAt` を 16 文字 (分単位) に切り詰めて比較するため、Issue close 直後・同一分内に記録された entry は `<=` 判定で除外側になる (取りこぼす可能性がある)。Spec Notes の「日付比較を文字列比較で行う理由」が明示的に受け入れているトレードオフであり、本 Issue のスコープ外。
  - **group-key の複数回起票**: 同じ group-key が生涯で 2 回以上 `起票済み #N` された場合、現在の実装は「最後に検出した起票済みマーカーの Issue」のみを解決対象とし、直近の fix の closedAt のみを cutoff に使う。過去の fix ごとの rolling cutoff は考慮しない。Spec もこのケースを明示的に扱っていない (単一 Issue 解決を前提とした設計) ため、実装追随した。将来的に同一 group-key の再起票が頻発するようなら別 Issue で扱う。

### Rework

- なし (実装は Spec の設計通りに 1 パスで完了)

## review retrospective

### Spec vs. implementation divergence patterns

- 構造的な乖離なし。review-light (Spec Deviation 観点) が Implementation Steps / rubric 文言と実装 (解決順序、OPEN/CLOSED 分岐、degrade path、`--with-tracking`、SKILL.md Step 15) を突き合わせ、すべて一致していることを確認した。Code Retrospective が明記した唯一の解釈選択 (degrade path の group-key scoped 化) も Spec の記述と矛盾しない追加情報として扱った。

### Recurring issues

- review-light が 1 件 SHOULD 指摘 (`scripts/collect-recovery-candidates.sh:104` — `--issues-json` の python→bash 受け渡しに `\t` 区切りを使っており、Issue title にリテラルタブが含まれると欠陥が生じる潜在バグ) を発見し、`\x1f` (unit separator) への変更で即時修正した。今後同種の「python3 出力を tab 区切りで bash に渡す」パターンを新規実装する際は、区切り文字にタイトル文字列と衝突しうる `\t` を避け `\x1f` を既定に据えるとよい (ワークフロー改善候補としては小粒すぎるため Issue 起票はしない)。
- Base Branch Conflict Pre-check が `docs/spec/issue-1152-*.md` を "changed in both" として検出したが、`git merge-file` による 3-way merge 検証で無害 (重複領域なし) と確認できた。3 引数 `--trivial-merge` 形式が誤検知気味の "changed in both" を出すケースとして記録に値するが、今回は 1 件のみで頻度が低く、個別の改善提案は起票しない。

### Acceptance criteria verification difficulty

- UNCERTAIN 判定はゼロ。9 件の Pre-merge AC のうち rubric 6 件・section_contains 1 件・file_not_contains 1 件はいずれも diff から機械的に確認でき、残る `github_check` 1 件も CI 全 9 checks SUCCESS で PASS 判定できた。Spec Notes が自認する通り AC 数 (9) は light テンプレートの目安 (5) を超えているが、review 側の検証コストとしては rubric の記述が具体的だったため大きな負荷にはならなかった。verify command の過不足や不正確さは見当たらない。

## Phase Handoff
<!-- phase: review -->

### Key Decisions
- review-light (1 エージェント統合レビュー、4 観点) を採用し、MUST issue はゼロと確認。SHOULD issue 1 件 (`--issues-json` 区切り文字の tab 依存脆弱性) は即座に修正しコミット・push した。
- Base Branch Conflict Pre-check で `docs/spec/issue-1152-*.md` の "changed in both" を検出したため、`git merge-file` による 3-way merge 検証を review-light に依頼し、データ損失なしを確認した。
- 全 9 Pre-merge AC を PASS 判定し、Issue #1152 のチェックボックスを更新した (`github_check` 含む)。Step 13 のポリシー変更検出は該当なし (SHOULD 修正は純粋な堅牢性改善で AC に影響しない)。

### Deferred Items
- 境界秒精度 (closedAt 分単位切り詰め) と group-key 複数回起票時の rolling cutoff 非対応は、Code Retrospective の Design Gaps/Ambiguities に記録済みで review でも追加の指摘なし。本 Issue のスコープ外として据え置く。
- #1191 (`/audit stats --retention` Section 10) は `--with-tracking` オプションの実消費側。review では未検証 (#1191 側の責務)。

### Notes for Next Phase
- `/merge 1198` の前提条件はすべて満たされている (MUST issue ゼロ、CI 全通過、AC 全 PASS)。
- Post-merge の observation AC (`/verify` Step 15 出力で `manual-recovery-review-rerun` / `review-tier3-recovery` が候補から消えていること) は次回 `/auto` セッションで確認すること。
