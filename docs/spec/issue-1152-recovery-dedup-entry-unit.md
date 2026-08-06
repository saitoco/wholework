# Issue #1152: collect-recovery-candidates: 除外判定を entry 単位化し誤検知と再発見落としを同時に解消

## Consumed Comments

- saito / MEMBER / first-class / `/issue 1152` の Issue Retrospective — 方針確定 (方針 2)、スコープ拡大 (`起票済み` フィルタの group-key 一括抑止)、`#1191 blocked-by #1152` の設定理由 / https://github.com/saitoco/wholework/issues/1152#issuecomment-5201365514

- saito / MEMBER / first-class / ## 実装セッションへの申し送り (Spec 作成後に着地した #1098 の影響) / https://github.com/saitoco/wholework/issues/1152#issuecomment-5202021801

- saito / MEMBER / first-class / `/verify` FAIL (iteration 1/3) — cutoff となる `起票済み` entry の選び方がファイル出現順の最後 (= newest-first ファイルでは最古) になっている根本原因の特定、判別 fixture、修正の所在の提示。AC 1 / AC 10 を一般ケース (group-key 内の複数 entry が `起票済み` を持つ場合) を含む文言へ更新済み / https://github.com/saitoco/wholework/issues/1152#issuecomment-5203918716

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
   - **「いずれかの entry」の選定は entry 日時 (H2 ヘッダ) の最大値で行う。`orchestration-recoveries.md` は newest-first のため、ファイル出現順 (= パース時のスキャン順) の最後は最古のエントリになる — スキャン順に頼ると誤って最古の marker を採用する (`/verify` FAIL iteration 1 で実測)。同じ規則は次の「degrade path」の代替基準にも適用する
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

- <!-- verify: rubric "collect-recovery-candidates.sh の除外判定が entry 単位で行われている。各 entry の対応 Issue を『起票済み #N』の N から、無ければ recoveries: <group-key> のタイトル完全一致から解決し、Issue が open なら全 entry を除外、closed なら closedAt より古い entry のみを除外する。--issues-json が state/closedAt を持たない場合は、ファイル内の起票済み entry のうち **H2 ヘッダ日時が最大のもの** を代替基準にする (ファイル出現順の最後ではない — orchestration-recoveries.md は newest-first のため出現順の最後は最古のエントリになる)。group-key 内の複数 entry が起票済みを持つ場合でも正しい cutoff が選ばれることが確認できる" --> 除外判定が entry 単位の日付規則になっている
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
    - **対応 Issue が closed である group-key が、閾値超過の候補として 1 件も出力されない**。特定の group-key の列挙ではなく、`collect-recovery-candidates.sh --threshold <N>` の出力全件について「その group-key に対応する closed Issue が存在するか」を突き合わせて確認すること
    - 全 entry が `起票済み #N` を持つ group-key (`manual-recovery-respawn` / `code-pr-tier3-recovery` など、`run-auto-sub.sh` の auto-stamp により時間とともにこの状態になる) も除外対象に含まれる
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

- **`/verify` FAIL (iteration 1) による degrade path の cutoff 選定バグ修正**: 初回実装 (`fae7bab8`) の degrade path (および `resolved_number`/`latest_filed_ts` の解決全般) は、group-key 内の複数 `起票済み` entry のうち「パース時のスキャン順で最後に見たもの」を採用していた。この実装は entry 配列がファイル出現順に追加される前提のコメント (`Entries are appended in file order (chronological), so the last filed marker seen while scanning is both the authoritative resolution and the latest filed timestamp.`) に基づいていたが、`orchestration-recoveries.md` の実際の並びは **newest-first** であり、スキャン順の最後は最古のエントリだった。この結果、`run-auto-sub.sh` の auto-stamp によって group-key 内の全 entry が `起票済み` を持つに至った通常のケース (`manual-recovery-respawn` 22 件全件 marked など) で cutoff が最古の marker に落ち、対応 Issue が closed 済みにもかかわらず旧 entry がほぼ全件再カウントされる false positive が実測で確認された (`/verify` FAIL コメント参照)。原因のコメントが「最新 marker を使う」という**意図**自体は正しく書いていたため、レビュー時の文面確認だけでは検出できず、newest-first という実データの並び順を踏まえた実測でのみ顕在化した。修正は「スキャン順で上書き」から「`ENTRY_TS` を明示比較して最大値を採用」への変更のみで、Spec の設計 (degrade path の意味論) 自体は変更していない。
- 上記修正に伴い、既存 3 テストのいずれも group-key 内の `起票済み` marker が単一という前提の fixture だったため検出できなかった。回帰テストとして「同一 group-key に複数 `起票済み` entry (newest-first)」のケースを 2 件追加した (cutoff が最大 timestamp になること / cutoff より新しい未 marked entry は引き続き計数されること)。

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
- `--light` 指定により review-light (1 エージェント統合レビュー、4 観点) を実施。MUST/SHOULD/CONSIDER いずれも0件で、修正コミットは発生していない。
- Pre-merge AC 1 (前ラウンド `/verify` FAIL の対象) を、実装差分のレビューに加えて `bash scripts/collect-recovery-candidates.sh docs/reports/orchestration-recoveries.md --threshold 3` を実際に実行し、出力が空 (2 group-key の消滅) であることを実測して PASS 判定した。他 8 件の Pre-merge AC は本 PR で変更されていないファイルに対応するため、diff への影響なしと確認したうえで PASS を維持した。
- Base Branch Conflict Pre-check で `changed in both` は 0 件 (`added in remote` / `merged` のみ) だったため、追加コンテキストなしで通常のレビューを実施した。

### Deferred Items
- 境界秒精度 (closedAt 分単位切り詰め) と group-key 複数回起票時の rolling cutoff 非対応は、Code Retrospective の Design Gaps に記録済みで本ラウンドでも未着手。本 Issue のスコープ外として据え置く。
- #1191 (`/audit stats --retention` Section 10) は `--with-tracking` オプションの実消費側。review では未検証 (#1191 側の責務)。

### Notes for Next Phase
- `/merge 1207` の前提条件はすべて満たされている (MUST issue ゼロ、CI 全通過、AC 1 を含む全 Pre-merge AC が PASS)。
- Post-merge の observation AC (`/verify` Step 15 出力で、対応 Issue が closed の group-key が候補として一切現れないこと、かつ closedAt 後の再発は候補に現れ続けること) は次回 `/auto` セッションで確認すること。今回は AC 文言どおり「出力全件の突き合わせ」で判定し、特定 2 group-key の列挙に留めないこと。

## Verify Retrospective

### Phase-by-Phase Review

#### issue

- 本 Issue は Icebox (`icebox:` prefix + 凍結) から解除され、タイトルも `collect-recovery-candidates: 除外判定を entry 単位化し誤検知と再発見落としを同時に解消` へリファインされた。当初の凍結時点では「close 済み group-key の重複起票を抑止」という誤検知側だけの問題として捉えられていたが、リファインで**再発見落とし (post-fix recurrence の取りこぼし)** が同じ根本原因の裏返しであることが特定され、両方を 1 つの Issue で扱う形に整理された。この統合が verify での「1 回の出力比較で両方を同時に実証できる」結果に直結している

#### spec

- 除外判定を group-key 単位から entry 単位へ移す設計により、`--issues-json` に渡すデータを open-only から all-state (`state` + `closedAt` 付き) へ変更する必要が生じ、`skills/verify/SKILL.md` Step 15 の呼び出し側もセットで変更対象に含めた。データ要件の変更が呼び出し元に波及することを spec 段階で捕捉できている

#### code

- Design Gaps として「境界秒精度 (closedAt の分単位切り詰め)」「同一 group-key が複数回起票された場合の rolling cutoff 非対応」を明示的にスコープ外として記録。いずれも本 Issue の主目的 (誤検知/取りこぼしの解消) には影響しない縁のケース

#### review

- review-light で MUST ゼロ、SHOULD 1 件 (`--issues-json` の区切り文字が tab 依存で脆い) を即座に修正してコミット
- **Spec ファイルの "changed in both" を Base Branch Conflict Pre-check が検出**し、`git merge-file` による 3-way merge 検証をレビューエージェントに依頼してデータ損失なしを確認。並行セッション環境での Spec 競合を検出・検証する経路が機能した

#### merge

- pre-merge AC gate は 9 件全チェック済みで通過、`mergeable=true (clean)` によりコンフリクト解消をスキップして squash merge

#### verify

- ~~**実装前後の出力比較が同一セッション内で取れた**点で最も明快な検証になった。... `manual-recovery-respawn` (21) と `code-pr-tier3-recovery` (6) が現れた。誤検知の解消と再発見落としの解消が 1 回の比較で同時に確認できている~~ **(iteration 2 で訂正: 誤判定)** — 実装前後で出力が変化したこと自体は事実だが、**新たに現れた 2 件はそもそも出力されるべきでなかった**。`manual-recovery-respawn` の対応 Issue #1014 と `code-pr-tier3-recovery` の #799 はいずれも CLOSED であり、AC 10 の条件「close 済みの対応 Issue が存在する group-key が候補として現れない」に違反していた。21 / 6 という数字は cutoff 選定バグの産物 (下記 iteration 2 参照)
- Pre-merge 9 件は機械的検証 (`section_contains` / `file_not_contains` / `github_check` / bats 14 件) と rubric の組み合わせで全 PASS。特に AC 4 の `section_contains "skills/verify/SKILL.md" "Step 15" "closedAt"` は heading 引数に `#` を含めておらず、#1083 の Pattern 6 サブパターン 1 を回避した書き方になっている
- ~~**`## Phase Handoff` セクションが 2 つ残存している**~~ **(iteration 2 で解消)** — `<!-- phase: review -->` と `<!-- phase: merge -->` の 2 セクションが残っていたが、PR #1207 (fix cycle) で 1 つに統合された。原因は review の Key Decisions が記録した Spec の "changed in both" 3-way merge と推測される

#### verify (iteration 2 — fix cycle 後)

- **iteration 1 の AC 10 判定は誤りだった。** `--threshold 3` の出力に現れた `manual-recovery-respawn` (21, tracked:#1014 CLOSED) と `code-pr-tier3-recovery` (6, tracked:#799 CLOSED) は AC 10 に明確に違反していたが PASS と判定した。`--with-tracking` で tracking 情報を取得しており、続く `/verify 1191` では「#1014 は CLOSED」と明記までしていながら、AC の文言と突き合わせていない。実装前後の出力変化が劇的だったため「誤検知の解消 + 再発見落としの解消」という自分の解釈に合わせて読み、**出力に現れた側の妥当性を検証しなかった**
- **根本原因は別セッション (`74631-1786005349`) の `/verify` が特定した。** `orchestration-recoveries.md` が newest-first であるのに、cutoff となる `起票済み` entry を**ファイル出現順の最後 (= 最古)** で選ぶ実装だった。cutoff が最古に落ちるため「cutoff より後」がほぼ全件カウントされる。同セッションは最小再現 fixture を作り、3 件 (probe / `manual-recovery-respawn` / `code-pr-tier3-recovery`) すべてで「最古の起票済み entry を cutoff とする」仮説と実測値が一致することを検算している
- **fix cycle での修正**: cutoff 解決を `ENTRY_TS` の明示比較 (最大値選択) に変更。FAIL コメントの判別 fixture が bats 回帰テスト 2 件としてそのまま実装された (test 4 = cutoff が max timestamp であること、test 5 = 全 marker より新しい unmarked な再発が計上され続けること)。test 5 が negative check として機能し、修正が再発検出を壊していないことを担保している
- **iteration 2 の判定手順を固定した**: (1) Step 15 と同じ閾値 3 で実行 → 出力が空であることを確認、(2) `--threshold 1 --with-tracking` で全件取得し over-exclusion がないか確認、(3) 残った tracked の count を対応 Issue の closedAt と突き合わせて検算。検算結果は `manual-recovery-worktree-rebase/ff-only-merge-base-advanced` (#1076 closedAt 07:37:58Z → 後の entry は 08:26 の 1 件、出力 1) と `code-pr-tier3-recovery` (#799 closedAt 2026-06-27T22:23:54Z → 後の entry は 07-12 / 07-04 の 2 件、出力 2) の両方で一致。「除外しすぎ」でも「除外不足」でもないことを実データで確認した
- iteration 1 で誤検知として出ていた group-key はすべて消滅または closedAt 後の分のみに減少: `manual-recovery-respawn` 21 → 消滅、`code-pr-tier3-recovery` 6 → 2、`manual-recovery-worktree-rebase/ff-only-...` 2 → 1、`review-tier3-recovery` / `manual-recovery-review-rerun` / `code-patch-tier3-recovery` は各 2 → 消滅

### Improvement Proposals

- ~~**Tier 2 (memory 候補)**: `## Phase Handoff` の rotation が並行編集下で破れうる~~ **(iteration 2 で解消済み)** — PR #1207 で 2 セクションが 1 つに統合された。再発したら phase-handoff 側に重複検出を入れる判断材料にする
- ~~**注目事項**: `manual-recovery-respawn` が 21 件~~ **(iteration 2 で訂正: 誤り)** — 21 件は cutoff 選定バグの産物であり、実際の再発件数ではない。修正後は同 group-key は候補から消滅している (#1014 の closedAt 後の entry がゼロ)。この誤った数字を根拠に #1205 を起票したため、同 Issue に訂正コメントを投稿済み
- **AC 例示が一般ケースを捕捉できていなかった (iteration 1 の FAIL を招いた要因)**: post-merge AC 10 の「期待される出力構造」が `manual-recovery-review-rerun` / `review-tier3-recovery` の 2 件のみを例示していたが、この 2 件は本 Issue 着地前に**手作業で** `起票済み` を付与したもので、いずれも「最新エントリのみ marked」という形だった。`run-auto-sub.sh` は entry 書き込み時に自動で `起票済み #N` を刻印するため、**対応 Issue が存在する group-key は時間とともに全件 marked になるのが常態**であり、例示していた 2 件のほうが例外的だった。AC に期待値を例示する際は、その例が一般ケースか例外かを意識する必要がある (起票せず — 本件は AC 文言の更新で解消済み)

## review retrospective

### Spec vs. implementation divergence patterns

- 特になし。今回の PR は `/verify` FAIL (iteration 1) の指摘を受けた 1 点修正 (`起票済み` marker 選定基準をスキャン順から `ENTRY_TS` 明示比較へ変更) のみで、Spec の rubric 文言・ヘッダコメント・inline コメント・実装コードの 4 者が一貫して同じ規則 (最大 timestamp を採用) を記述しており、構造的な乖離は見られなかった。

### Recurring issues

- 特になし。review-light の 4 観点 (Spec 逸脱・エッジケース/堅牢性・セキュリティ・ドキュメント整合性) いずれも MUST/SHOULD/CONSIDER 0件。前ラウンド (`/review 1198`) で発見された SHOULD 1 件 (`--issues-json` の tab 区切り依存) は本ラウンドの diff に含まれておらず、再発なし。

### Acceptance criteria verification difficulty

- UNCERTAIN 判定はゼロ。9 件の Pre-merge AC のうち、今回のバグ修正対象である AC 1 (rubric) は文言が「entry 単位判定」「ファイル出現順の最後ではなく H2 ヘッダ日時が最大のもの」を明示しており、実装差分の確認に加えて `bash scripts/collect-recovery-candidates.sh docs/reports/orchestration-recoveries.md --threshold 3` を実行して出力が空になることを直接実測できたため、rubric の記述と実行可能な検証コマンドの両方が揃っている好例だった。残る8件は本 PR で変更されていないファイルに対応するため、diff への影響なしの確認のみで PASS 判定を維持した。verify command の過不足や不正確さは見当たらない。
