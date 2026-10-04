# Issue #1494: audit: stats --retention と collect-verify-retention-stats.sh の関係を整合させる

## Overview

`docs/structure.md` の Key Files は `scripts/collect-verify-retention-stats.sh` を「`/audit stats --retention` 用」と記述しているが、`skills/audit/SKILL.md` はこのスクリプトを呼んでおらず (`allowed-tools` にも無い)、`--retention` の Section 8 は待機件数を LLM がセッション内で数えている。この文書と実装の食い違いを解消する。

Issue は方式 (a: `/audit` からスクリプトを呼ぶ / b: 単独の計測ツールとして文書を修正) の選択を `/spec` に委ねている。**方式 (b) を採用する** (判断理由は Notes の「方式選択の判断」)。Section 8 の集計は従来どおり LLM 集計のまま変更せず、次の 2 点を直す。

- `docs/structure.md` と `docs/ja/structure.md` の説明を、「手動実行の単独計測ツールで、`/audit stats --retention` からは呼ばれない」旨に改める
- スクリプトのヘッダーコメントにも同じ役割 (と Section 8 との定義の違い) を明記し、`--help` に表示されるようにする

## Changed Files

- `docs/structure.md`: Key Files > Scripts > Project utilities の `scripts/collect-verify-retention-stats.sh` エントリを書き換える。末尾の「for `/audit stats --retention`」を外し、手動実行の単独計測ツールで `/audit stats --retention` からは呼ばれない旨・全件実行が遅い旨・verify-type タグ抽出ルールの参照実装である旨を記す (文言は Implementation Steps 1)
- `docs/ja/structure.md`: 同エントリの日本語ミラーを同期する (`docs/translation-workflow.md` の同期手順に従う。文言は Implementation Steps 2)
- `scripts/collect-verify-retention-stats.sh`: ヘッダーコメントの冒頭概要段落の直後に Role 段落 (10 行) を追加し、`--help` の `sed -n '2,50p'` を `'2,60p'` に更新して従来の表示範囲を維持する — bash 3.2+ 互換 (コメントと `sed` の範囲のみの変更で、ロジックは不変)
- [Steering Docs sync candidate] keyword "collect-verify-retention-stats.sh" skipped: matched 13 files (no discriminating power)

## Implementation Steps

1. `docs/structure.md` の `scripts/collect-verify-retention-stats.sh` エントリ (行頭が `` - `scripts/collect-verify-retention-stats.sh` — measure `` の 1 行。現在 L196) を次の 1 行に置換する (→ 受入条件 1)。前後のエントリと同じ単一の箇条書きのままとし、件数など陳腐化しやすい数値は固定しない。

   ```
   - `scripts/collect-verify-retention-stats.sh` — standalone measurement tool, run by hand; not called by `/audit stats --retention` (whose Section 8 counts waiting AC in-session from Issue bodies): measure `phase/verify` retention by verify-type (how much post-merge AC is still waiting vs. already resolved, and how old the waiting is), with an optional comparison-window date filter; fetches one `gh issue view` per Issue, so a full run is slow (use `--cache` / `--from-cache` to re-aggregate); also the reference implementation of the verify-type tag extraction rule in `modules/verify-classifier.md`
   ```

2. `docs/ja/structure.md` の同エントリ (行頭が `` - `scripts/collect-verify-retention-stats.sh` — verify-type ごとに `` の 1 行。現在 L189) を次の 1 行に置換する (after 1) (→ 受入条件 1)。日本語文中の括弧は半角 `()` の前後に半角スペースを入れる。既存のミラーは英語版の「解決済みとの対比 (vs. already resolved)」を落としているため、この機会に英語版へ揃える。

   ```
   - `scripts/collect-verify-retention-stats.sh` — 手動で実行する単独の計測ツール。`/audit stats --retention` からは呼ばれない (Section 8 は Issue 本文から待機 AC をセッション内で数える)。verify-type ごとに `phase/verify` の滞留を測定する (マージ後 AC がどれだけ待機中か・どれだけ解決済みか、その待機がどれだけ古いか)。比較ウィンドウの日付フィルタはオプション。Issue ごとに `gh issue view` を 1 回呼ぶため全件実行は遅く、再集計には `--cache` / `--from-cache` を使う。`modules/verify-classifier.md` の verify-type タグ抽出ルールの参照実装でもある
   ```

3. `scripts/collect-verify-retention-stats.sh` を編集する (parallel with 1, 2) (→ 受入条件 1)。
   - 挿入位置: ヘッダー冒頭の概要段落 (`# waiting, how much has already been resolved, and how old the waiting is.` で終わる) の直後の `#` 単独行の次、`# Usage:` の直前。次の 10 行 (末尾の `#` 単独行を含む) を挿入する。

     ```
     # Role: standalone measurement tool, run by hand. It is NOT called by
     #   `/audit stats --retention`; that skill's Section 8 counts waiting AC in-session
     #   from Issue bodies (skills/audit/SKILL.md) under its own definition -- fenced
     #   code blocks excluded, the `ac-tier: preview` rule, the Manual-waiting
     #   executability breakdown -- none of which this script applies, so the two can
     #   differ for the same repository state. Use this script to re-measure a past
     #   report's population (--window) or the resolved side (phase/done), which
     #   Section 8 does not report. It is also the reference implementation of the
     #   verify-type tag extraction rule (modules/verify-classifier.md).
     #
     ```
   - 続けて `--help` 節の `sed -n '2,50p' "$0"` を `sed -n '2,60p' "$0"` に変更する。挿入行数 (10) だけ範囲を伸ばし、従来 `--help` に出ていた末尾 (`# (scripts/gh-label-transition.sh removes the previous phase/* label).` まで) の表示を維持する。ロジックの他の行は変更しない。

4. 自己確認 (after 1, 2, 3) (→ 受入条件 1)。
   - `bash scripts/collect-verify-retention-stats.sh --help` を実行し、Role 段落が出力され、出力の末尾が従来どおり `(scripts/gh-label-transition.sh removes the previous phase/* label).` であることを確認する。**fetch 経路 (引数なし、または `--cache` のみ) は実行しない** (Notes「検証時の注意」)
   - `bats tests/collect-verify-retention-stats.bats` が PASS すること (既存 12 ケース。ロジック不変のため新規ケースは追加しない)
   - `bash scripts/check-forbidden-expressions.sh` が PASS すること
   - `bash scripts/check-translation-sync.sh` で `docs/structure.md` が OUTDATED と表示されないこと (情報出力のみ)
   - `grep -c "collect-verify-retention-stats" skills/audit/SKILL.md` が 0 のままであること (方式 (b) の前提。`skills/audit/SKILL.md` は変更しない)

## Verification

### Pre-merge

- <!-- verify: rubric "skills/audit/SKILL.md の --retention Section 8 が scripts/collect-verify-retention-stats.sh を呼び出して集計する形になっている (allowed-tools への追加を含む)、または docs/structure.md の同スクリプトの説明が /audit からは呼ばれない単独の計測ツールである旨に修正されている" --> Section 8 とスクリプトの関係が実装と文書で一致している

### Post-merge

- 次回 `/audit stats --retention` の実行で、Section 8 の待機件数が、`/spec` で採用し Spec に記録された方式 (スクリプト呼び出し、または従来どおりの LLM 集計) のとおりに算出されることを確認する <!-- verify-type: opportunistic -->
  - 採用方式は (b): Section 8 は従来どおり `skills/audit/SKILL.md` の Observation / Opportunistic / Manual Waiting Count 定義に従ってセッション内で集計され、`collect-verify-retention-stats.sh` は呼び出されない。評価時は「実行ログにスクリプトの呼び出しが無いこと」と「Section 8 の表が従来どおりの項目 (Observation waiting / Opportunistic waiting / Manual waiting の内訳) で出ること」を確認する

## Notes

### 方式選択の判断 (Issue から委譲された判断)

Issue 本文は方式 (a) / (b) の選択を `/spec` に委ね、Spec に判断理由を記録するよう求めている。non-interactive 実行のため、モデル判断で自動解決した。採用は **(b) 単独の計測ツールとして文書を修正する**。(a) は採らない。判断理由 (いずれも 2026-10-04 時点で確認):

1. **経緯: 文書の記述が最初から実装と合っていなかった。** スクリプトは 748e3cbe (2026-08-08) で「`/auto 1158` の phase/verify 滞留診断に使った 4 本の使い捨てスクリプトを 1 本に集約し、#1271 の post-merge AC が同じ測定を再実行できるようにする」目的の診断ツールとして追加された。`docs/structure.md` の「for `/audit stats --retention`」は翌日の docs drift 修正 chore (856c3cc2, #1280) が主題の近さから追記した記述で、呼び出し関係を設計した結果ではない。実際に `/audit` が呼ぶスクリプトの記述は「for `/audit stats --retention` Section 11」「for `/audit stats --retention` Section 12」「used by `/audit stats --retention` for retire-proposal comment routing」と節や用途まで書かれており、本エントリだけが節の無い同形の言い回しで呼び出し関係を誤読させていた。したがって本件は機能の格下げではなく、文書の誤りの訂正である。
2. **実行が有界でない。** スクリプトは `phase/verify` と `phase/done` の全 Issue に対して `gh issue view` を 1 回ずつ呼ぶ。実測の母集団は 299 + 704 = 1003 件で、Issue 本文の「約 800」は古い見積もりである。`docs/spec/issue-1273-verify-type-tag-scoping.md` の `/verify` 記録では 300 秒超・メモリ逼迫でプロセスごと kill され、stdout が空だった。さらに既定の `--limit 500` では `phase/done` (704 件) が切り捨てられ、stderr に警告が出る。`--from-cache` は事前のキャッシュ生成が前提で、`/audit` 側にキャッシュの更新方針がない。`/audit stats --retention` はセッション内で動く対話スキルなので、呼ぶとこの kill リスクを持ち込む。(a) を成立させるには取得方式の作り替え (`gh issue list --json number,body` の 1 回取得など) が必要になる。
3. **Section 8 の定義を満たさない。** スクリプトは verify-type 別の生集計のみを出す。Section 8 の Waiting Count は (i) フェンス付きコードブロックの除外 (`modules/l0-surfaces.md` § AC Enumeration Convention)、(ii) `ac-tier: preview` 行の per-line ルール (`resolve-preview-ac-fallback.sh`)、(iii) Manual waiting の 4 バケット内訳 N1〜N4 / N0 (Issue ごとに `verify-executability-marker.sh resolve` を呼ぶ) を要するが、スクリプトの `count_body()` はいずれも持たない。出力は件数のみで Issue 番号も AC index も返さないため、(iii) の入力も作れない。置き換えると Section 8 の既存の意味論が退行するか、スクリプトの大幅な拡張が必要になる。実際、Section 8 の定義はスクリプトの追加 (2026-08-08) 以降も #1278 (内訳)、#1072 / #1371 / #1386 (preview ルール)、#1071 (フェンス除外、2026-08-21) と拡張され続けたが、スクリプトに追随した変更は無い (`git log -- scripts/collect-verify-retention-stats.sh` は追加コミット 748e3cbe のみ)。#1273 はむしろ Section 8 側をスクリプトのタグ抽出に揃えた変更で、スクリプトは Section 8 の裏側として保守されてきたのではなく、参照実装の位置づけにとどまっている。
4. **確立済みの設計方針と整合する。** `modules/verify-classifier.md` § Tag Extraction Rule (consumers) の Consumers 表は、`scripts/collect-verify-retention-stats.sh` (参照実装) と `skills/audit/SKILL.md` (Waiting Count 定義) を別々の consumer として並べている。#1273 の Spec は「SSoT は文書側 (`verify-classifier.md`) に置き、実装は各 consumer にインライン展開する。共通ヘルパー化はしない」と決めている。(a) は 2 つの兄弟 consumer を 1 つの依存関係に畳む案で、この方針と逆向きになる。
5. **規模。** (a) はスクリプトの拡張 (フェンス除外・preview ルール・Issue 単位の出力・有界な取得) + SKILL.md の Section 7 / 8 書き換え + `allowed-tools` 追加 + bats テスト + 文書更新を要し、Size S を超える。加えて過去の `docs/stats/` レポートとの比較可能性を再び損なう (#1273 で測定方式変更の注記を導入済み)。

(a) を将来検討する場合の注記 (起票はしない): Section 8 を決定的な集計にしたいなら、土台に適するのは本スクリプトではなく `scripts/scan-pending-ac.sh` である (`gh issue list --label phase/verify --state all --json number,body` の 1 回取得、フェンス除外済み、HTML コメント限定のタグ抽出、AC 単位の JSON 出力 `number` / `ac_index` / `verify_type` / `condition`)。ただし 4 バケット内訳と preview ルールの再実装が必要なため、別 Issue での設計判断になる。

### Issue 本文と実装の食い違い (Conflict with implementation)

Issue 本文の Background にある事実主張を実装と照合した結果、次の 3 点は実装と異なる。いずれも方式 (b) の結論は変えない (light のため Notes への記録のみで、ユーザー確認は行っていない)。

- 「スクリプトは Issue あたり `gh issue view` を 1 回呼ぶ (約 800 Issue)」: 実測は 1003 件 (下の計測範囲を参照)
- 「スクリプトの母集団は `phase/verify` ラベル保持の全 Issue」: 実装は `phase/verify` (待機) と `phase/done` (解決済み) の 2 集団を取得し、それぞれ全期間と `--window` の両方で集計する。Section 8 に相当するのは前者のみ
- 「Section 8 の待機件数定義と同一の基準で数える参照実装」: 共有しているのは verify-type タグ抽出ルール (HTML コメント限定) だけである。フェンス除外・`ac-tier: preview` ルール・4 バケット内訳は持たない。この差は今回スクリプトのヘッダー Role 段落に明記する (スクリプトの数え方自体は直さない。スコープ外)

あわせて、Issue 本文の「このスクリプトを参照しているのは、`modules/verify-classifier.md` の reference implementation としての言及と、`scripts/collect-verify-path-done-rate.sh` のコメントだけ」は、コード・モジュール側の参照としては正しいが、専用の `tests/collect-verify-retention-stats.bats` と、手動実行の例として `docs/reports/observation-ac-audit-summary.md` (L115) も参照している。結論に影響しない。

### 計測範囲 (measurement-scope)

| 項目 | 値 | スコープ / 測定コマンド |
|------|-----|--------------------------|
| `phase/verify` ラベルの Issue 数 | 299 | saitoco/wholework、全期間、open + closed、2026-10-04 実測。`gh issue list --label phase/verify --state all --json number --limit 1000 --jq length` (上限 1000 には未到達) |
| `phase/done` ラベルの Issue 数 | 704 | 同上で `--label phase/done` |
| スクリプトの全件実行で呼ばれる `gh issue view` の回数 | 1003 | 上の 2 値の合計 (スクリプトは両集団を Issue ごとに 1 回取得する) |
| キーワード `collect-verify-retention-stats.sh` に一致するファイル数 | 13 | `grep -rl "collect-verify-retention-stats.sh" docs/ tests/ scripts/ modules/`。内訳: `docs/spec/` 6、`docs/reports/` 1、`docs/ja/` 1、`docs/structure.md` 1、`modules/` 1、`scripts/` 2 (自身を含む)、`tests/` 1 |
| `skills/audit/SKILL.md` 内のスクリプト名の出現数 | 0 | `grep -c "collect-verify-retention-stats" skills/audit/SKILL.md` |

### 同期候補の確認結果 (Steering Docs sync candidate)

Changed Files にスクリプトを含むため sync candidate check を実施した。キーワード `collect-verify-retention-stats.sh` は 13 ファイルに一致し、判別力フィルタ (8 件超) によりスキップ扱いとした (Changed Files に 1 行記録)。ただし Step 6 の調査で全ヒットを個別に確認済みで、結果は次のとおり。

- 変更する: `docs/structure.md`、`docs/ja/structure.md` (ミラー)、`scripts/collect-verify-retention-stats.sh` (自身)
- 変更不要 (grep / Read で確認済み):
  - `skills/audit/SKILL.md`: スクリプト名の出現 0 件。方式 (b) では Section 8 の記述も `allowed-tools` も変えない。SKILL.md は `/audit` の実行ごとに全文が読み込まれるため、呼ばれないスクリプトの説明を足すとトークンコストだけが増える。関係の説明は `docs/structure.md` とスクリプトのヘッダーに置く
  - `modules/verify-classifier.md` (L222-223, L234, L239): スクリプトを「参照実装」として挙げ、`skills/audit/SKILL.md` (Waiting Count 定義) を別 consumer として並べている。方式 (b) と矛盾しない
  - `scripts/collect-verify-path-done-rate.sh` (L18-19): 本スクリプトの `gh issue view` per Issue (N+1) パターンとの対比として言及しているだけで、呼び出し関係の主張はない
  - `tests/collect-verify-retention-stats.bats`: 集計経路 (`--from-cache`) の 12 ケースのみ。`--help` の出力は検証していないので、ヘッダー追記と `sed` 範囲の変更で壊れない
  - `docs/reports/observation-ac-audit-summary.md` (L115): 過去の報告。スクリプトを `--window 2026-05-07` で手動実行した例で、単独ツールとしての位置づけと整合する。doc-checker の検索対象外 (`docs/reports/`)
  - `docs/spec/` の 6 ファイル: disposable。変更しない
  - `README.md` / `CLAUDE.md`: 該当する記述なし
- Listing-side sub-check: スキップ。サブコマンドの追加・削除、ファイルの追加・削除・改名、ディレクトリ構成の変更のいずれも行わない (説明文の書き換えのみ)。Directory Layout の `scripts/` ファイル数コメント (99 files) も変わらない
- Outbound pointer sync check: スキップ。新しい文言が指す `modules/verify-classifier.md` と `skills/audit/SKILL.md` は、いずれも本変更で更新が要る内容を持たない (上記のとおり)

### 判定の記録

- **fail-safe critical か**: 否。スクリプトは読み取り専用の計測ツールで、`2>/dev/null` / `|| true` を含む (`grep -nF` で確認) が、ゲートでも検証器でもない。今回の変更はコメントと `sed` の範囲のみで、失敗時の挙動には触れない
- **audit / investigation-type か**: 否。Issue は文書と実装の整合の修正であり、複数の既存項目を分類して根拠を成果物に残す性質ではない (タイトルの `audit:` は生成元の `audit/drift` ラベルに由来する)。ただし本 Spec が引用する識別子 (節見出し、コミット ID、行番号付近の記述) は `grep` / `git show` で存在を確認してから書いた
- **新規テストケース要件**: 対象外。既存スクリプトに新しい分岐ロジックを足さない (コメントと `sed` の範囲のみ)
- **allowed-tools impact chain**: 対象外。新規 `scripts/*.sh` も `modules/*.md` の変更も無い
- **UI Design / 外部仕様確認 / 依存パッケージ / adapter**: 対象外 (UI なし、`sed -n 'N,Mp'` は POSIX 標準、新規依存なし、verify command は組み込みの `rubric` のみ)
- **Count alignment**: Issue 本文の Pre-merge 1 件、Spec の Pre-merge 1 件で一致。verify command は Issue 本文から逐語コピー
- **premise marker**: Issue 本文の `<!-- premise: grep_count "collect-verify-retention-stats" "skills/audit/SKILL.md" -eq 0 -->` は方式 (b) では真のまま残る (`/audit premise` で失効しない)。対応は不要

### 検証時の注意

- `/code` と `/review` は、**スクリプトの fetch 経路 (引数なし、または `--cache` のみ) を実行してはならない**。母集団 1003 件の `gh issue view` を呼び、過去に 300 秒超・メモリ逼迫でプロセスごと kill された実績がある (#1273)。`--help` は fetch の前に終了するので安全
- Pre-merge の rubric は二択 (SKILL.md が呼ぶ / structure.md が単独ツールと説明する) の後者で満たす。判定者が迷わないよう、`docs/structure.md` の文言には「standalone measurement tool」と「not called by `/audit stats --retention`」の両方を含める (Implementation Steps 1 の文言)

### 自動解決の記録 (non-interactive)

- 方式 (a) / (b) の選択: モデル判断で (b) を採用 (上記)。可逆であり、将来 (a) を選ぶ場合は別 Issue で `scan-pending-ac.sh` を土台に設計する
- スクリプトのヘッダーに Role 段落を足し、`--help` の `sed` 範囲を伸ばす点は Issue の受入条件が要求しない任意の追加だが、実装側にも関係を明記する目的 (Purpose の「実装と文書で一致」) で含めた。不要と判断された場合は Implementation Steps 3 を除外しても受入条件は満たされる

## Consumed Comments

No new comments since last phase.
