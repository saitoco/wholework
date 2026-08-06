# Issue #1163: verify: manual AC 区分 A (次回…観察型 34 件) を observation へ再型付け

## Overview

`phase/verify` に滞留する `verify-type: manual` の post-merge AC のうち、区分 A (「次回 X が発生した際に…を観察する」型) に分類された 34 Issue を対象に、条件文が待っているイベントへ対応付けて `verify-type: observation event=<name>` へ再型付けする。

対象 34 Issue が持つ `verify-type: manual` の post-merge AC は **36 行** (#719 と #708 が各 2 行)。全件を精査した結果、**29 行を再型付け** (`auto-run` 27 / `fix-cycle` 2)、**7 行を対象外** (`manual` 維持) とする。

再型付け結果と対象外理由は `docs/reports/manual-ac-retype-a.md` に記録する。この記録ファイルがあることで、Pre-merge の `rubric` AC が grader から参照可能になる (grader へ渡るのは Issue 本文・git diff・rubric 本文で名指しされたファイルのみ。Spec ファイルと Issue コメントは渡らない)。

## Consumed Comments

cutoff: `2026-08-06T04:23:59Z` (`phase/issue` ラベル付与時刻、Issue timeline から取得)

| login | authorAssociation | trust tier | 意図の要約 | URL |
|---|---|---|---|---|
| saito | MEMBER | first-class | `/issue 1163 --non-interactive` の Issue Retrospective。event 有効値 5 種の制約明記、#1157/#1170 の close 済み反映、AC2 が実スクリプト実行で確認可能になったことの確認を報告 | https://github.com/saitoco/wholework/issues/1163#issuecomment-5200391669 |

Cross-phase marker (`type=verify-fail` / `type=preview-ac-unverified`) の追加スキャン結果: 該当なし。

## Changed Files

- `docs/reports/manual-ac-retype-a.md`: 新規作成 — 区分 A 36 AC 行のマッピング表 (Issue 番号 / 条件文要約 / 付与 event または対象外 / 選定根拠)、対象外 7 行の理由、`opportunistic-search.sh` 実行による検証結果
- `docs/structure.md`: 変更不要 — Directory Layout tree に `docs/reports/` は既出 (line 62)。Key Files 側は「スクリプトが消費する report ファイル」のみ列挙する方針 (`orchestration-recoveries.md` / `orchestration-fallbacks-archive.md` が該当) であり、本記録ファイルは消費側スクリプトを持たないため追加不要 (`grep -n "reports" docs/structure.md` で確認済み)
- `docs/ja/` 同期: 対象外 — `docs/translation-workflow.md` § Exclusions が `docs/reports/` を明示的に除外
- リポジトリ外 (GitHub Issue 本文, 29 AC 行 / 29 Issue): 後掲「再型付けマッピング」表のとおり `<!-- verify-type: manual -->` を `<!-- verify-type: observation event=<name> -->` へ置換

## 再型付けマッピング

### `event=auto-run` (27 AC 行)

| Issue | 条件文の要約 | 選定根拠 |
|---|---|---|
| #1045 | 次回 external kill 発生時に `wrapper_alive` と kill 時刻の差分から control-flow / subprocess kill を判別 | external kill 検出 (`detect-external-kill.sh`) は `skills/auto/SKILL.md` の phase 完了判定内で実行される |
| #869 | 次回 silent no-op が観測された session で `code_retry_fire` が記録される | silent no-op 検出と retry 発火は `/auto` の code phase 内 |
| #861 | 次回並列セッション環境で phase 開始時に他セッション由来 dirty が warning 表示 | phase 開始は `/auto` 実行の内側。「並列セッション」は `when=` の宣言可能軸 (route / mode / recovery-tier) に無く事前排除できない |
| #859 | 次回並列セッション環境で他セッション作業ファイルと自セッション作業中ファイルを区別して判定 | 同上 |
| #856 | 次回 merge なし reopen Issue に `/auto $N` 実行時 fix-cycle と誤判定されない | 条件文が `/auto` 実行そのものを待っている |
| #852 | 次回 reopen 後の Issue に `/auto $N` 実行時 code phase が正しく実行される | 同上 |
| #822 | 次回 manual recovery 発生時に対象 sub-issue の Spec へ `## Auto Retrospective` が自動追記 | manual recovery は `/auto` orchestration 内で発生する |
| #807 | 次回 batch session で wrapper レベル自動 retry が試行され recoveries.md に記録 | `/auto --batch` 実行の内側 |
| #806 | 次回 `run-auto-sub.sh` kill 発生時に `/auto --resume N` で正常完走 | `/auto --resume` 実行の内側 |
| #804 | 次回 migration/rename/削除 Issue の `/spec` で Changed Files に symbol grep 結果が反映 | `/spec` は `/auto` の spec phase として実行される |
| #778 | 次回 migration Issue の Spec に SKILL.md + script の対称的 `file_not_contains` AC が含まれる | 同上 |
| #770 | 2 つの `/auto --batch` 同時起動で各 session の report が他 session の Issue を含まない | `/auto --batch` 実行の内側 |
| #769 | 次回 batch 実行後の `/audit auto-session --full` で Per-Issue Durations が実処理件数と一致 | batch 完走が観測の前提 |
| #765 | 次回 PR で正当な記述が commit に含まれた際 Forbidden Expressions check が PASS | 当該 check は `/code` (`forbidden-expressions-check.md`)・`/review` (`skill-dev-recheck.md`)・CI (`test.yml`) で実行され、いずれも `/auto` の内側。`pr-review-full` は `--full` review でのみ発火するため取りこぼす |
| #762 | 次回 batch/XL session でデータ層レポート末尾に L3 retrospective への See also リンクが出力 | batch/XL 実行の内側 |
| #761 | 次回 Tier 2 fallback catalog 適用 Issue の Spec の `## Auto Retrospective` に anomaly エントリが含まれる | Tier 2 fallback は `/auto` orchestration 内 |
| #760 | 次回 batch で Tier 2 リカバリ発生時に report の Improvement Candidates Surfaced に symptom 表示 | 同上 |
| #759 | 次回 Tier 2/3 自動回復発生 Issue の `/verify` で新基準に従った判断が一意に行われる | `/auto` 実行内の verify phase が観測窓 |
| #758 | 次回新 SSoT モジュール作成時に checklist が実行され review phase で SSoT 乖離 SHOULD が出ない | checklist は `/code`、SHOULD 指摘は `/review`。SHOULD は `--light`/`--full` 双方で発生しうるため `pr-review-full` 固定では取りこぼす |
| #755 | 次回新 skill 作成時に `execution-context.md` を参照して context check が標準化 | spec / code phase の内側 |
| #737 | 次回 `get-sub-issue-progress.sh` 変更 Issue で direct test が regression を検出 | bats regression は CI (`/review` が完了を待機) で顕在化。対象 Issue の Size が読めず review depth が確定しないため `pr-review-full` 固定は不適 |
| #736 | 次回 `get-auto-session-report.sh` 変更 Issue で direct unit test が regression を検出 | 同上 |
| #732 | 次回 `phase-handoff.md` 変更 Issue で `bats tests/phase-handoff.bats` が regression を検出 | 同上 |
| #731 | 次回 `test-runner.md` 変更 Issue で `bats tests/test-runner.bats` が regression を検出 | 同上 |
| #724 | 次回 git diff ベース比較ロジックの Spec で当該節が参照され code phase の rework がゼロ | spec / code phase の内側 |
| #520 | `/auto` 実行で skill mis-dispatch 由来の silent no-op が観察されない | 条件文が `/auto` 実行を明示している |
| #719 条件2 | pre-existing FAILURE 解消後、`pre-merge-check.sh` が baseline=PASS 状態で正常動作 | `bash scripts/check-forbidden-expressions.sh` は 2026-08-06 時点で exit 0 (実測) — 前提は充足済み。`pre-merge-check.sh` は `/code`・`/review` で実行される |

### `event=fix-cycle` (2 AC 行)

| Issue | 条件文の要約 | 選定根拠 |
|---|---|---|
| #707 | `/verify N` を FAIL させ機械可読 marker 付き comment が append され grep できる | `skills/verify/SKILL.md` の FAIL → reopen 経路が、marker comment 投稿と `observation-trigger.sh --event fix-cycle` を同一ステップで実行する |
| #700 | `auto-retry-on-fail.enabled: true` 下で `/verify` FAIL → `/code` 再発火 → PASS または budget 枯渇 | 同じ FAIL → reopen 経路が観測窓。本リポジトリの `.wholework.yml` は `auto-retry-on-fail.enabled: true` |

### 対象外 (`manual` 維持、7 AC 行)

| Issue | 条件文の要約 | 対象外の理由 |
|---|---|---|
| #719 条件1 | 別 PR で意図的に Forbidden Expressions FAIL を作り abort を観察 | 故障注入型。人為的に失敗 PR を用意しない限り 5 有効値のどの発火でも観測窓が開かない (`docs/stats/2026-08-05.md` の区分 C 相当) |
| #708 条件1 | 試験的に `phase/ready` のみ付与・Spec 無しの M Issue で `matches_expected: false` を確認 | 試験的コマンド実行が前提の故障注入型。bats テスト化が本筋 |
| #708 条件2 | 試験的に XS Issue (Spec 無し) で `matches_expected: true` を確認 | 同上 |
| #704 | `autonomy: L2` の状態で skill が許可経路のみ実行することを観察 | 本リポジトリは `autonomy: L3` で前提が成立しない。`config=` ゲートは boolean 専用で enum キー (`autonomy`) を表現できない (`modules/observation-trigger.md` § Condition Check Gate (`config=`)) |
| #501 | downstream プロジェクトで phase 間の文脈喪失が体感的に減ることを観察 | 別リポジトリでの主観評価。upstream から観測不能 (区分 B 相当) |
| #500 | downstream で mid-run API 障害時に Tier 2 内で自動 reconcile + retry を実行し復旧 | 別リポジトリ + 障害注入の二重前提。upstream から観測不能 |
| #479 | 次回 vault 領域に触れる `/code` 実行でファイル編集が実装される | vault 領域は downstream 固有でこのリポジトリに存在しない。upstream の `/auto` 実行では観測窓が開かない |

## Implementation Steps

1. `docs/reports/manual-ac-retype-a.md` を新規作成し、本 Spec の「再型付けマッピング」3 表 (36 AC 行) を転記する。冒頭に対象 Issue 一覧・件数内訳 (再型付け 29 / 対象外 7) と、`event=` 有効値が `modules/verify-classifier.md` の 5 種に限られる制約を記す (→ AC1, AC3)
2. `.tmp/retype-mapping.json` を Write ツールで作成する (after 1)。各要素は `{"issue": N, "match": "<AC 行を一意に特定する部分文字列>", "event": "auto-run"|"fix-cycle"}`。`match` は本 Spec の表の「条件文の要約」ではなく、Issue 本文の実際の AC 行から取った一意な部分文字列を使う (例: #869 なら `code_retry_fire` イベントが)
3. `.tmp/retype-ac.py` を Write ツールで作成する (after 2)。既定は dry-run、`--apply` で適用。処理は Issue ごとに: `gh issue view N --json body -q .body` で本文取得 → `match` と `<!-- verify-type: manual -->` の両方を含む行を抽出 → **ちょうど 1 行でなければ当該 Issue を skip して警告** → 該当行の `<!-- verify-type: manual -->` のみを `<!-- verify-type: observation event=<event> -->` へリテラル置換 → 本文全体を `.tmp/issue-body-N.md` へ書き出し → `scripts/gh-issue-edit.sh N .tmp/issue-body-N.md` を呼ぶ (`--apply` 時のみ)
4. `python3 .tmp/retype-ac.py` (dry-run) を実行し、29 件すべてについて置換前後の行を目視確認する。skip 警告が 1 件でも出た場合は `match` 文字列を修正して再実行する (after 3) (→ AC1)
5. `python3 .tmp/retype-ac.py --apply` を実行し、29 AC 行を再型付けする (after 4) (→ AC1, AC4, AC5)
6. 対象外 7 AC 行 (#719 条件1 / #708 条件1・2 / #704 / #501 / #500 / #479) は **一切編集しない**。`.tmp/retype-mapping.json` に含めないことで機械的に保証する (parallel with 5) (→ AC3, AC6)
7. `${CLAUDE_PLUGIN_ROOT}/scripts/opportunistic-search.sh --event auto-run` と `--event fix-cycle` を実行し、返却 JSON に再型付けした Issue 番号が含まれることと event 別マッチ件数を確認する (after 5) (→ AC2)
8. Step 7 の実行結果 (event 別マッチ件数、再型付け前 baseline `auto-run` = 31 AC 行 / 2026-08-06 実測、含有を確認した Issue 番号) を `docs/reports/manual-ac-retype-a.md` の `## 検証` 節へ追記する (after 7) (→ AC2)
9. `.tmp/retype-mapping.json` / `.tmp/retype-ac.py` / `.tmp/issue-body-*.md` を削除し、コミット対象を `docs/reports/manual-ac-retype-a.md` のみにする (after 8)

## Verification

### Pre-merge

- <!-- verify: rubric "docs/reports/manual-ac-retype-a.md に区分 A の対象 Issue 全件のマッピング表があり、各行が『Issue 番号 / 元の条件文の要約 / 付与した event= 名または対象外 / 選定根拠』を持つ。再型付け対象の行には verify-classifier.md の 5 有効値のいずれかが記録されている" --> 対象全件のマッピング表と event 選定根拠が記録されている
- <!-- verify: rubric "docs/reports/manual-ac-retype-a.md に opportunistic-search.sh または observation-trigger.sh の実行結果 (event 名ごとのマッチ件数、および再型付けした Issue 番号がマッチ集合に含まれること) が記録されており、再型付け前後の件数差が示されている" --> 再型付け後の AC がマッチ対象になることを実行結果で確認済み
- <!-- verify: rubric "docs/reports/manual-ac-retype-a.md に、再型付けの対象外とした AC について Issue 単位で理由が記載されている。理由は verify-classifier.md の 5 有効値に対応付けられない旨を具体的な条件文の性質 (故障注入 / downstream 依存 / enum 設定依存など) とともに説明している" --> 対象外とした AC の理由が Issue 単位で記録されている
- <!-- verify: github_check "gh issue view 869 --json body --jq .body" "verify-type: observation event=auto-run" --> 代表 Issue #869 の post-merge AC が `observation event=auto-run` へ再型付けされている (GitHub 上の実状態)
- <!-- verify: github_check "gh issue view 707 --json body --jq .body" "verify-type: observation event=fix-cycle" --> 代表 Issue #707 の post-merge AC が `observation event=fix-cycle` へ再型付けされている (GitHub 上の実状態)
- <!-- verify: github_check "gh issue view 704 --json body --jq .body" "verify-type: manual" --> 対象外とした #704 は `verify-type: manual` のまま維持されている

### Post-merge

- 移行完了後の `/audit stats --retention` で、phase/verify の Manual waiting 件数が、本 Issue で再型付けした AC 行数分だけ減少している (対象外とした AC 行は減少しない) ことを確認する

## Tool Dependencies

### Bash Command Patterns

- `gh issue view:*`: 各対象 Issue の本文取得 (`/code` の `allowed-tools` に登録済み)
- `${CLAUDE_PLUGIN_ROOT}/scripts/gh-issue-edit.sh:*`: Issue 本文の書き戻し (登録済み)
- `${CLAUDE_PLUGIN_ROOT}/scripts/opportunistic-search.sh:*`: 再型付け後のマッチ確認 (登録済み)
- `python3:*`: 一括置換ヘルパの実行 (登録済み)

### Built-in Tools

- `Write`: 記録ファイル・一時ヘルパ・Issue 本文の書き出し
- `Read` / `Grep`: 置換結果の確認

### MCP Tools

- なし

## Notes

### `observation-trigger.sh` ではなく `opportunistic-search.sh` を検証に使う

Issue 本文の Related は AC2 の確認手段として `observation-trigger.sh --dry-run` を挙げているが、`skills/code/SKILL.md` の `allowed-tools` に `observation-trigger.sh` は登録されていない (`opportunistic-search.sh` は登録済み)。`observation-trigger.sh` はマッチ判定を `opportunistic-search.sh` へ委譲する薄いラッパで、独自に行うのはコメント投稿 (副作用) と stdout 整形のみ。したがって `opportunistic-search.sh --event <name>` の実行はマッチ集合の確認として等価であり、かつ完全に read-only で安全側。`allowed-tools` の追加は本 Issue のスコープ外とする。

### 一括置換ヘルパは `.tmp/` に置き `scripts/` へ残さない

親 #1158 の対応方針候補 A は「`scripts/` に移行スクリプトを追加」だったが、区分 A・D2・D3 で置換対象の条件が異なるため汎用化の利得が薄く、移行完了後は dead code になる。`.tmp/` に置いて Write ツールで内容を可視化し、dry-run → apply の 2 段階で安全性を担保する。何を実行したかは `docs/reports/manual-ac-retype-a.md` に残るため再現性も確保される。

### operate route を採らなかった理由

親 #1158 は各 sub-issue の処理方式として operate route (Issue 本文編集のみ) を想定していたが、本 Issue の Pre-merge AC は全て `rubric` であり、`modules/verify-executor.md` の定義上 grader が受け取るのは Issue 本文・git diff・rubric 本文で名指しされたファイルのみ (Spec ファイルと Issue コメントは渡らない)。operate route では成果物が `## Execution Log` コメントにしか残らず、rubric が原理的に評価不能になる。記録ファイルを 1 本置く pr route に切り替えることで rubric が評価可能になり、親 #1158 の Pre-merge AC1 (分類結果の構造化記録) も同時に満たせる。

### 「34 件」の単位ずれ

Issue 本文と `docs/stats/2026-08-05.md` Section 10 の「区分 A = 34 件」は Issue 単位の数え方。実際の `verify-type: manual` AC 行数は 36 行 (#719 と #708 が各 2 行)。記録ファイルでは AC 行単位で数え、Issue 単位との対応を明記する。

### `when=` / `keyword=` / `config=` ゲートは付与しない

`event=` の付与のみを本 Issue のスコープとする。実行文脈条件 (`when=`) は #1118 が明示的に引き受けている。`keyword=` は `--context-file` を渡す `/review` 経由でのみ有効で、`skills/auto/SKILL.md` の `auto-run` 発火は `--context-file` を渡さないため `auto-run` に付与しても不活性。`config=` は boolean 専用のため `autonomy` のような enum キーには使えない。

### 母集団の増加とその許容根拠

2026-08-06 実測で `opportunistic-search.sh --event auto-run` のマッチは 31 AC 行。本 Issue で 27 行が加わり約 2 倍になる。文脈条件で事前排除できない条件が SKIPPED に解決するのは `modules/observation-trigger.md` § "Conditions That Cannot Be Pre-Excluded" が正しい挙動と定めており、コメント蓄積は #1099 の idempotency guard (24h)、dispatch 回数は `observation-dispatch-threshold` (既定 5) が抑える。より踏み込んだ削減は #1118 (`when=`) と #1162 (セッション内 verify 済み除外) の担当。

### GitHub 検索インデックスの遅延

`opportunistic-search.sh` の母集団取得は `gh issue list --search "verify-type: observation in:body"` に依存する。Issue 本文編集の直後は検索インデックスが未更新で、再型付けした Issue が母集団に現れないことがある。Step 7 でマッチが確認できない場合は、本文が正しく置換されていること (`gh issue view N --json body`) を先に確認したうえで時間を置いて再実行する。判定を急いで「マッチしない」と結論づけないこと。

### `session=next` は不要

`modules/verify-classifier.md` の `session=next` は、Issue が `skills/*/SKILL.md` を変更し、その skill 自身の挙動を観察する post-merge 条件に付ける宣言。対象 34 件はいずれも変更が既に main へ着地して久しく、skill 内容の伝播は完了しているため付与しない。

### `modules/observation-trigger.md` の記述ずれ (スコープ外)

同ファイル § Notes に「`fix-cycle` イベントは定義済みだが emitter が未実装」とあるが、`skills/verify/SKILL.md` は FAIL → reopen 経路で `observation-trigger.sh --event fix-cycle` を実際に呼んでいる (同ファイルの Emitter Lookup Table 側は「implemented in #656」と正しく記載されており、Notes だけが古い)。本 Issue の `fix-cycle` 割り当ての妥当性には影響しないが、ドキュメント側の矛盾として別途起票候補。
