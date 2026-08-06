# manual AC 区分 A: observation 再型付けマッピング (#1163)

親 Issue #1158 の分割対応。`phase/verify` に滞留する `verify-type: manual` の post-merge AC のうち、区分 A (「次回 X が発生した際に…を観察する」型) の 34 Issue / 36 AC 行を対象に、`verify-type: observation event=<name>` への再型付けを行った記録。

## 対象・件数内訳

- 対象 Issue: 34 件 (#1045 #869 #861 #859 #856 #852 #822 #807 #806 #804 #778 #770 #769 #765 #762 #761 #760 #759 #758 #755 #737 #736 #732 #731 #724 #719 #708 #707 #704 #700 #520 #501 #500 #479)
- 対象 AC 行: 36 行 (#719 と #708 が各 2 行を持つため、Issue 単位の 34 件と AC 行単位の 36 行にずれがある)
- 再型付け: **29 行** (`event=auto-run` 27 行 / `event=fix-cycle` 2 行)
- 対象外 (`manual` 維持): **7 行**

## `event=` 有効値の制約

`event=` に使用できるのは `modules/verify-classifier.md` § observation Type が定める 5 つの有効値のみ: `pr-review-full` / `pr-review-light` / `auto-run` / `watchdog-kill` / `fix-cycle`。未知の event 名は `observation-trigger.sh` 側で warning を出したうえ `opportunistic` へフォールバックし、実質的に自動評価パイプラインに乗らない。条件文が待つ将来イベントがこの 5 値のいずれにも一致しない場合は、`manual` のまま維持し対象外として理由を記録する (過去の類似判断: #869 条件6 `code_retry_fire`、#704 条件2 `skill-invocation`、#700 条件A1 `verify-retry`)。

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

## 検証

`${CLAUDE_PLUGIN_ROOT}/scripts/opportunistic-search.sh --event <name> --dry-run` (read-only、コメント投稿なし) を実行し、再型付け後の AC がマッチ対象になることを確認した。

### `--event auto-run`

- 実行結果: マッチ 59 AC 行 (2026-08-06 実測)
- 再型付け前 baseline (Spec 記載, 2026-08-06 実測): 31 AC 行
- 本 Issue で再型付けした 27 AC 行 (#1045 #869 #861 #859 #856 #852 #822 #807 #806 #804 #778 #770 #769 #765 #762 #761 #760 #759 #758 #755 #737 #736 #732 #731 #724 #520 #719条件2) は **全件マッチ集合に含まれることを確認済み** (Python で目視突合)
- baseline 31 との単純差分 (+28) は再型付け 27 行と一致しない。同期間に他 sub-issue (#1164〜#1167 等、親 #1158 の並行対応) や `/auto` 実行由来の新規 `observation event=auto-run` AC が母集団に加わった可能性があり、本 Issue の再型付けだけが変動要因ではない。目視突合で対象 27 行の含有を直接確認しているため、件数差分の厳密一致よりもこちらを正とする

### `--event fix-cycle`

- 実行結果: マッチ 5 AC 行 (#1006 #700 #707 #569 #586)
- 本 Issue で再型付けした 2 AC 行 (#707 #700) は **マッチ集合に含まれることを確認済み**

### GitHub 上の実状態 (Pre-merge AC4〜AC6 相当)

- `gh issue view 869 --json body`: `verify-type: observation event=auto-run` へ再型付け済みを確認
- `gh issue view 707 --json body`: `verify-type: observation event=fix-cycle` へ再型付け済みを確認
- `gh issue view 704 --json body`: `verify-type: manual` のまま維持されていることを確認 (対象外)
