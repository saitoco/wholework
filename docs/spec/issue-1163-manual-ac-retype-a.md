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

### code phase (cutoff: `2026-08-06T04:50:47Z`, `phase/ready` ラベル付与時刻)

`phase/ready` 付与以降の新規コメントなし。Cross-phase marker の追加スキャン結果も該当なし。

## Autonomous Auto-Resolve Log

- **`phase/ready` ラベル不在での続行**: `/code 1163 --pr --non-interactive` 開始時点で Issue のラベルは `phase/code` (label timeline 上、`phase/ready` は 2026-08-06T04:56:03Z に `phase/code` へ既に遷移済み)。`reconcile-phase-state.sh --check-precondition code-pr` も `matches_expected: false` を返した。Spec (`docs/spec/issue-1163-manual-ac-retype-a.md`) は spec retrospective・issue retrospective・Phase Handoff まで完備しており、コーディング未着手のまま前回セッションが label 遷移後に中断したレジューム状態と判断。Spec が存在するため「Spec なしで Issue 本文から要件を読む」対応は不要。warn のうえ Spec を正として続行した — reason: 非対話モードのポリシー (`--warn-only` 相当) は Spec 欠落時の縮退経路であり、本件は Spec 完備のため実質的にブロッカーではない。

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

## issue retrospective

`/issue 1163 --non-interactive` による既存 Issue 精緻化を実行した。

### 実施内容

- **Background 補強**: `event=` に使用できるのは `modules/verify-classifier.md` の 5 有効値 (`pr-review-full`/`pr-review-light`/`auto-run`/`watchdog-kill`/`fix-cycle`) のみである制約を明記し、非該当条件は `manual`(対象外) 維持が正しい判断であることを過去の類似判断 (#869 条件6, #704 条件2, #700 条件A1) を根拠に追記した。対象 34 Issue を実サンプリングした結果、`auto-run` に対応付けられそうな条件 (#856 #852 #770 #769 等) がある一方、並列セッション観察系 (#861 #859)・downstream プロジェクト観察系 (#501 #500)・スクリプト変更時の regression 観察系 (#737 #736 #732 #731) など、5 値のいずれにも対応しない条件文も相当数含まれることを確認した。AC の文言自体は変更していない — AC1 (34件再型付け目標) と AC3 (対象外の記録) の既存設計がこの現実を吸収できる構造になっているため。
- **Blocked by セクションの現況更新**: `#1157`・`#1170` がいずれも close 済みであることを `gh issue view` で確認し、「着地が前提」と読める旧文言を「解消済み」に更新した。Related セクションの該当行も合わせて更新。
- **AC2 (--dry-run 確認) の実行可能性を再確認**: `#1170` の着地により `observation-trigger.sh --dry-run` / `opportunistic-search.sh --dry-run` が検索は実行しつつ副作用 (コメント投稿) のみ抑止する意図通りの挙動になっていることをスクリプト読解で確認した (以前は検索前に短絡していた)。

### Auto-Resolve Log

Issue 本文の `## Auto-Resolved Ambiguity Points` セクションを参照。

### 機械チェック結果

- `check-skill-change-observation-ac.sh`: exit 0 (該当なし — `skills/*/SKILL.md` への参照なし)
- `check-ac-checkbox-format.sh`: exit 0 (フォーマット違反なし)
- `gh-check-blocking.sh`: exit 0 (`#1157` は CLOSED のためスキップ、オープンなブロッカーなし)

### スキップした処理

- **Step 12 (サブ issue 分割スコープ評価)**: non-interactive モードのため High-Stakes Decision としてスキップ。Size L・単一区分 (34件) の scope であり分割候補にはそもそも該当しない。

## spec retrospective

### Minor observations

- `modules/observation-trigger.md` § Notes の「`fix-cycle` は emitter 未実装」という記述が、同ファイルの Emitter Lookup Table (「implemented in #656」) および `skills/verify/SKILL.md` の実装と矛盾している。Notes 側だけが古い。本 Issue の設計には影響しないが、SSoT を謳うモジュール内部での不整合であり別途起票候補。
- `opportunistic-search.sh` の母集団取得は `gh issue list --label phase/verify --state closed` で、対象 34 件はいずれもこの条件を満たすことを実測確認した (全件 CLOSED + `phase/verify`)。再型付けが母集団に効く前提が成立している。
- 「区分 A = 34 件」は Issue 単位の数え方で、実際の `verify-type: manual` AC 行数は 36 行だった (#719 と #708 が各 2 行)。`docs/stats/2026-08-05.md` 側の分類は Issue 単位と AC 行単位を明示していない。他の sub-issue (#1164/#1165/#1166/#1167) でも同じずれが起きうる。

### Judgment rationale

- **`/issue` 時点の見込みを `/spec` の全件精査で覆した**: `/issue` のサンプリングは「並列セッション観察系」「スクリプト変更時の regression 観察系」を 5 有効値に非該当と見込んでいたが、いずれも観測窓が `/auto` 実行の内側にあり `auto-run` で拾える。`modules/observation-trigger.md` § "Conditions That Cannot Be Pre-Excluded" が「実行文脈で事前排除できない条件は dispatch → SKIPPED が正しい挙動」と明記しているため、文脈条件の有無は対象外判定の根拠にならない。結果として対象外は 12 AC 行の見込みから 7 AC 行へ縮小した。
- **`event=` の選定規則を「観測窓を開く最も狭いイベント」ではなく「取りこぼさない最も広いイベント」に倒した**: `pr-review-full` は Size L の `--full` review でのみ発火するため、対象 Issue の Size が事前に読めない条件 (スクリプト変更・SSoT モジュール作成など) では取りこぼす。`/review` は `/auto` の内側で走るので `auto-run` が上位集合になる。dispatch 精度より観測機会の確実性を優先した。
- **operate route を pr route へ切り替えた**: Pre-merge AC が全て `rubric` であり、`modules/verify-executor.md` の定義上 grader は Issue コメントも Spec ファイルも受け取らない。operate route では成果物が `## Execution Log` コメントにしか残らず AC が原理的に評価不能になるため、記録ファイル 1 本を追加する pr route を選択した。親 #1158 の「operate route 想定」からの意図的な逸脱であり、Spec Notes に理由を明記した。
- **`keyword=` ゲートを見送った**: `auto-run` 発火経路 (`skills/auto/SKILL.md`) は `--context-file` を渡さないため、`auto-run` に `keyword=` を付けても不活性。`keyword=` を効かせるには `event=pr-review-full` へ倒す必要があり、それは上記の取りこぼし問題を招く。ゲート追加と event 選定はトレードオフ関係にある。
- **Auto-Resolve Log の記録先**: `modules/ambiguity-detector.md` は `spec` フェーズの Auto-Resolve Log を issue retrospective コメントとして投稿する指定だが、Step 13 が同じコメントを Spec へ転記する設計のため循環になる。Issue 本文の `## Auto-Resolved Ambiguity Points` に追記済み (5 件) であり、本 Spec の Notes と本節にも判断根拠が残るため、追加のコメント投稿は行わなかった。

### Uncertainty resolution

- **AC2 の確認手段**: Issue 本文は `observation-trigger.sh --dry-run` を挙げるが、`skills/code/SKILL.md` の `allowed-tools` に同スクリプトは未登録だった (`opportunistic-search.sh` は登録済み)。`observation-trigger.sh` はマッチ判定を委譲する薄いラッパで独自処理はコメント投稿と stdout 整形のみのため、`opportunistic-search.sh --event <name>` の実行で等価かつ副作用なしに確認できると判断した。`allowed-tools` 追加はスコープ外。
- **母集団増加の許容可否**: `opportunistic-search.sh --event auto-run` の現行マッチを実測 (31 AC 行) し、本 Issue で 27 行増えて約 2 倍になることを定量把握した。#1099 の idempotency guard (24h) と `observation-dispatch-threshold` (既定 5) が影響を抑えるため許容可能と判断。さらなる削減は #1118 / #1162 の担当。
- **`#719` 条件2 の前提充足**: 「pre-existing FAILURE を別 Issue で解消後」という前提が現在成立しているかを `bash scripts/check-forbidden-expressions.sh` の実行 (exit 0) で確認し、`auto-run` への再型付けが妥当と判断した。前提未充足なら対象外にすべき条件だった。
- **`#704` の `config=` 表現可能性**: `autonomy` は enum (`L1`/`L2`/`L3`) で、`config=` ゲートは boolean 専用 (`modules/observation-trigger.md` § Condition Check Gate (`config=`))。本リポジトリは `L3` のため条件の前提自体が成立せず、対象外が妥当と確認した。

## Code Retrospective

### Deviations from Design

- Implementation Steps 2〜5 (`.tmp/retype-mapping.json` 作成 → `.tmp/retype-ac.py` 作成 → dry-run 確認 → `--apply` 実行) を実行しなかった。`/code` 開始時点で `reconcile-phase-state.sh --check-precondition code-pr` が `phase/ready` ラベル不在 (label timeline 上、既に `phase/code` へ遷移済み) を報告し、対象 29 AC 行を個別に確認したところ、全件が GitHub Issue 本文側で既に `verify-type: observation event=<name>` へ再型付け済みだった。対象外 7 AC 行も個別確認し誤編集がないことを確認した。前回セッションが label 遷移後・コミット/PR作成前に中断したレジューム状態と判断し、実質的な追加作業は Step 1 (report file 作成) と Step 7〜9 (opportunistic-search.sh による検証・記録・cleanup) のみとした。Spec Implementation Steps は Deviations として本節に記録するのみとし、Step 2〜5 の記述自体は変更しない (次回同種の再型付け Issue で `.tmp/` ヘルパパターンを再利用する際の参照価値を残すため)。

### Design Gaps/Ambiguities

- Step 8 で baseline 比較を行ったところ、`opportunistic-search.sh --event auto-run` のマッチ件数は baseline 31 行 → 実測 59 行で、再型付けした 27 行の単純加算 (31+27=58) と 1 件ずれた。目視突合で対象 27 行の含有は個別確認済みのため AC2 の充足には影響しないが、母集団が本 Issue の作業以外の要因 (他 sub-issue の並行対応や `/auto` 実行由来の新規 AC) でも変動しうることが分かった。件数差分だけで再型付け完了を判定する設計は将来的に誤検知の余地がある — 個別 Issue 番号の含有確認を必須の一次情報とすべき (report ファイルの `## 検証` 節に既に反映済み)。

### Rework

- なし。Spec の「再型付けマッピング」節の設計 (29 行再型付け / 7 行対象外) をそのまま `docs/reports/manual-ac-retype-a.md` へ転記し、想定通り完了した。

## Phase Handoff
<!-- phase: code -->

### Key Decisions

- `.tmp/retype-mapping.json` / `.tmp/retype-ac.py` を作成・実行せず、既に完了していた Issue 本文の再型付け状態を検証してそのまま採用した (上記 Deviations 参照)。再実行や差し戻しは不要。
- `docs/reports/manual-ac-retype-a.md` を新規作成し、Spec の「再型付けマッピング」3 表と `## 検証` 節 (opportunistic-search.sh 実行結果) を記録した。Pre-merge AC 6 件は全て PASS 判定し Issue のチェックボックスを更新済み。
- PR #1194 を作成 (`closes #1163`)。テスト `bats tests/` は 1430/1430 PASS、`validate-skill-syntax.py` は 0 error、`check-forbidden-expressions.sh` は exit 0。

### Deferred Items

- `modules/observation-trigger.md` § Notes の `fix-cycle` emitter 未実装という古い記述の修正 — 本 Issue のスコープ外、別途起票候補 (spec retrospective から引き継ぎ)。
- 再型付け後の AC への `when=` 条件付与 — #1118 が担当。
- #708 の 2 条件の bats テスト化 — 区分 C 相当として #1167 の領域。
- Post-merge AC (`/audit stats --retention` での Manual waiting 件数減少確認) — merge 後に `/verify` が `observation event=auto-run` 経路で評価する。

### Notes for Next Phase

- `/review` は Pre-merge AC が全て `rubric` であることを踏まえ、`docs/reports/manual-ac-retype-a.md` の内容と GitHub Issue 本文の実状態 (#869 #707 #704 など代表 Issue) の整合を優先的に確認すること。
- 対象外 7 AC 行 (#719 条件1 / #708 条件1・2 / #704 / #501 / #500 / #479) が `manual` のまま維持されていることは commit 前に個別確認済み。`/review` でも再確認する場合は report の「対象外」表と突合すること。
- baseline 比較の件数ずれ (Design Gaps/Ambiguities 参照) は AC2 の充足を妨げないが、`/verify` が post-merge AC を評価する際に母集団件数の単純比較ではなく個別 Issue 番号の含有確認を優先すること。
