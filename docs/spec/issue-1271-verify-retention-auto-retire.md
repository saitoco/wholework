# Issue #1271: audit: phase/verify の retention Level 3 (90 日+) を提案から自動 retire へ引き上げる

## Overview

`/audit stats --retention` の Retire-Proposal Comment Posting は、`phase/verify` dwell が Level 3 (90 日+) に達した Issue に対して「手動確認または observation 条件の削除」を促すコメントを投稿するだけで、実際の判断は誰も行わない。結果として全期間 325 件の `phase/verify` のうち 163 件が 90 日超の待機として滞留し、metric ノイズ・scan の遅さ・通知コメントノイズの 3 つの signal-to-noise 問題を生んでいる。

本 Issue は Level 3 の動作を「提案」から「実行」へ引き上げる。具体的には、Level 3 到達 Issue の未チェック post-merge 条件のうち自動 retire 対象の verify-type のものを `### Retired Post-merge Conditions` 節へ退避し、retire 理由を Issue コメントに記録し、未チェック条件がゼロになった Issue を `phase/done` へ遷移させる。autonomy tier で L1 = 提案のみ (現行動作維持) / L2・L3 = 自動実行にゲートする。

判断ロジックは bats で検証可能にするため、LLM prose ではなく決定的なスクリプト `scripts/apply-verify-retire.sh` に切り出す (`scripts/apply-run-fact-match.sh` と同型)。

## Changed Files

- `scripts/apply-verify-retire.sh`: 新規。Level 3 の autonomy-tier ゲート + retire 実行 (body 書き換え / marker コメント投稿 / `phase/done` 遷移) を行う決定的スクリプト — bash 3.2+ 互換 (`mapfile` / `${VAR,,}` 不使用)
- `skills/audit/SKILL.md`: `#### Retire-Proposal Comment Posting` 節の Level 3 分岐を `apply-verify-retire.sh` 呼び出しへ変更 (`auto-retire` の語を節内に記述)。retire 対象 verify-type とその判断理由、autonomy tier ゲートを同節に明記。frontmatter `description` の `--retention` 説明に auto-retire を追記。frontmatter `allowed-tools` に `${CLAUDE_PLUGIN_ROOT}/scripts/apply-verify-retire.sh:*` を追加
- `modules/l0-surfaces.md`: Machine-Readable Event Marker 節に `type=verify-ac-retired` の定義を追加 (属性・resolution 方針・producer)
- `tests/audit-retention.bats`: `apply-verify-retire.sh` の新規テストケースを追加 (Level 3 × L2/L3 → retire / Level 3 × L1 → 提案のみ / Level 2 以下 → retire しない、ほか)
- `docs/structure.md`: `### Scripts` の Project utilities に `scripts/apply-verify-retire.sh` を追加。`| phase/done |` を含む Label Transition Map は `docs/workflow.md` 側なので本ファイルは Scripts 行のみ
- `docs/ja/structure.md`: 上記の日本語ミラー同期 (`docs/translation-workflow.md` の Sync Procedure に従う)
- `docs/workflow.md`: Label Transition Map の `phase/done` 行の「付与するもの」に `/audit stats --retention` (Level 3 auto-retire) を追記
- `docs/ja/workflow.md`: 上記の日本語ミラー同期

**[Steering Docs sync candidate]** キーワード `Retire-Proposal Comment Posting` (`grep -rn` 対象: `docs/` `tests/` `scripts/` `modules/`、非 spec 3 hit):
- `skills/audit/SKILL.md:562` — Section 10 の相互参照文「unlike Section 8/9's Retire-Proposal Comment Posting, which stays scoped to phase/verify and Icebox only」。auto-retire 導入後は当該節がコメント投稿に加えて body 書き換え・ラベル遷移も行うため、この括弧書きの記述が最新か確認し必要なら更新する
- `docs/stats/2026-06-27.md:112` — 過去レポートの記録。歴史的記録のため除外 (Exclusions 参照)

**[Steering Docs sync candidate]** キーワード `l0-surfaces.md`: `grep -rl` が 21 ファイルにマッチ (no discriminating power) のため個別評価をスキップ。

**[Steering Docs sync candidate]** キーワード `verify-ac-retired` / `apply-verify-retire.sh`: いずれも新規導入の語のため既存 0 hit。

**[Outbound pointer sync candidate]** `modules/l0-surfaces.md` は `modules/label-conventions.md` / `modules/autonomy-tier.md` を指すが、本 Issue は新しいラベル名前空間を追加せず (Notes の判断 2 参照)、autonomy tier の matrix 自体も変更しないため、いずれも Changed Files 候補にならない。

**[allowed-tools impact chain]**
- Case 1 (新規 `scripts/*.sh`): `skills/audit/SKILL.md` が `apply-verify-retire.sh` を呼ぶが `allowed-tools` に該当エントリがない → 上記 Changed Files で追加済み。他の SKILL.md は本スクリプトを呼ばない
- Case 2 (`modules/*.md` 変更): `modules/l0-surfaces.md` の追記内容は `scripts/apply-verify-retire.sh` を producer として名指しするため軽量ゲートには合致する。ただし reader 8 件 (`skills/audit`, `code`, `auto`, `issue`, `spec`, `merge`, `review`, `verify` の各 SKILL.md) はいずれも当該モジュール経由で本スクリプトを呼ばず、マーカー定義を参照するだけであるため `allowed-tools` 追加は不要 (`skills/audit/SKILL.md` は Case 1 で追加済み)

**`.claude/settings.json.template`**: 変更不要。`Bash(${WHOLEWORK_ROOT}/scripts/*.sh *)` のワイルドカードが全スクリプトを包含しており、近年追加の `apply-run-fact-match.sh` / `rank-verify-backlog.sh` も個別登録されていない (`grep -n "apply-run-fact-match\|rank-verify-backlog" .claude/settings.json.template` が 0 hit) ことを確認済み。

**`scripts/validate-skill-syntax.py`**: 変更不要。追加するのは `allowed-tools` の Bash スクリプトパターンのみで、`KNOWN_TOOLS` に登録すべき新規ベースツール名は増えない。

## Implementation Steps

1. `scripts/apply-verify-retire.sh` を新規作成し、引数解析と入力バリデーションを実装する (→ 受入条件 3, 5)
   - Usage: `scripts/apply-verify-retire.sh --issue <N> --dwell <days> [--dry-run]`
   - `--issue` は正の整数、`--dwell` は非負整数。欠落・非数値・未知オプションは stderr に usage を出して exit 1
   - `set -euo pipefail` を使う。`pipefail` 下でパイプラインの終了ステータスを条件分岐に使う箇所は、必ず一旦変数に退避してから評価する (`if cmd | grep -q ...` の形を避ける) — #1060 で `pipefail` 由来の意図しない fail-open が発生した事例に基づく
   - bash 3.2+ 互換 (`mapfile`・`${VAR,,}` を使わない)

2. 同スクリプトに level × autonomy tier のルーティングを実装する (→ 受入条件 3)
   - `LEVEL` は `"$SCRIPT_DIR/compute-escalation-level.sh" verify "$DWELL"` の出力。`SCRIPT_DIR` は `${WHOLEWORK_SCRIPT_DIR:-$(cd "$(dirname "$0")" && pwd)}` (BATS Mocking Convention、`docs/tech.md` § BATS Mocking Convention)
   - `TIER` は環境変数 `AUTONOMY_TIER` を優先し、未設定なら `"$SCRIPT_DIR/get-config-value.sh" autonomy L1`。`L1`/`L2`/`L3` 以外の値はすべて `L1` にフォールバック (`apply-run-fact-match.sh` と同一の解決順)
   - 分岐 (exhaustive):
     - `LEVEL` < 3 → 標準出力に `action=none` のみ。L0 書き込みは一切行わず exit 0 (Level 0/1/2 は従来どおり `skills/audit/SKILL.md` 側のルーティングが所有する)
     - `LEVEL` = 3 かつ `TIER` = `L1` → `action=propose` のみ出力し exit 0。L0 書き込みなし。呼び出し側の SKILL.md が従来どおり判断プロンプトコメントを投稿する
     - `LEVEL` = 3 かつ `TIER` ∈ {`L2`, `L3`} → `action=retire` を出力し Step 3 以降へ進む
   - `compute-escalation-level.sh` の呼び出しが非ゼロ終了した場合は fail-**closed**: stderr に警告を出し `action=none` を出力して exit 0。判定不能な dwell から retire を導いてはならない

3. 同スクリプトに retire 対象条件の抽出を実装する (→ 受入条件 2, 4)
   - `gh issue view "$N" --json body --jq '.body'` で body を取得。取得失敗時は fail-**open**: stderr に警告を出し `retired=0` を出力して exit 0 (プロジェクト全体を走査する `/audit` 実行を 1 件の GitHub 障害で中断させない)
   - post-merge 節の範囲は `scripts/scan-pending-ac.sh` と同一規約 — `^### Post-merge` または `^## Post-merge` の次行から、次の `^## ` / `^### ` 行の直前まで
   - `^[ \t]*``` ` 行で `in_fence` をトグルし、`in_fence` が真の行は一切対象にしない (`modules/l0-surfaces.md` § AC Enumeration Convention (b)。参照実装: `scripts/check-pre-merge-ac.sh:59-61`)
   - 未チェック行 (`^- \[ \]`) の verify-type は HTML コメント内からのみ読む: awk `match($0, /<!--[ \t]*verify-type:[ \t]*[a-zA-Z_]+/)` → 一致部分から `<!--[ \t]*verify-type:[ \t]*` を `sub` で除去 (`modules/verify-classifier.md` § Tag Extraction Rule。参照実装: `scripts/collect-verify-retention-stats.sh:159-161`)。条件文が本文中でタグ名を引用しているだけの行を実タグと誤認してはならない
   - **retire 対象は verify-type が `observation` または `opportunistic` の行に限定する**。`manual` と `auto` は対象外 (理由は Notes の判断 1)
   - 対象行が 0 件のときは `retired=0` を出力し、L0 書き込みを行わず exit 0。これが冪等性ガードを兼ねる (retire 済み Issue を再走査しても対象が 0 件になる)

4. 同スクリプトに body 書き換えを実装する (→ 受入条件 4)
   - 対象行を `### Post-merge` 節から取り除く
   - `### Post-merge` 節に `- [` で始まる行が 1 つも残らない場合のみ、プレーン散文行 (先頭が `- ` でない行) を 1 行挿入する: `すべての post-merge 条件は #1271 の自動 retire で退避済み (下記 ` + バッククォート付き `### Retired Post-merge Conditions` + ` を参照)。` — `scripts/check-ac-checkbox-format.sh` は `^- ` で始まり `^- \[[ xX]\]` に合致しない行のみを違反として検出するため、散文行は抵触しない
   - `### Post-merge` 節の直後に `### Retired Post-merge Conditions` 見出しを作る (既に存在する場合はその節へ追記する)。`check-ac-checkbox-format.sh` の awk は任意の `^### ` 行で `in_section` を 0 に戻すため、この節配下の箇条書きは形式ガードの対象外になる (#1165 / Issue #706 で確立した退避形式)
   - 退避行の形式: `- ~~{元の条件文}~~ — **retired (auto, dwell {D}d)**: 90 日間 event が発火せず、または発火しても判定に至らなかった (verify-type: {t}, 最終 dispatch: {TS|none})`
   - **文字列の取り扱い (fail-safe critical)**: body はすべてファイル経由で受け渡し、シェル変数へ展開して再解釈しない。行末に `\r` (CRLF) がある場合は取り消し線を可視テキストのみに適用し `\r` を復元する。条件文に `>` `"` 全角文字が含まれても素通しする (`gh-issue-edit.sh` はファイルを読むため shell quoting の影響を受けない)
   - `gh-issue-edit.sh "$N" "$TMPFILE"` で書き戻す。失敗時は stderr に警告を出し、**Step 5 のコメント投稿とラベル遷移を実行せずに** exit 0 (`apply-run-fact-match.sh` と同じ順序ゲート — 着地していない retire を主張するコメントを残さない)

5. 同スクリプトに retire 理由コメント投稿と `phase/done` 遷移を実装する (→ 受入条件 5)
   - `gh-issue-comment.sh` で marker コメントを投稿する。1 行目: `<!-- wholework-event: type=verify-ac-retired phase=audit issue={N} dwell={D} ac={i,j} verify-types={observation,opportunistic} -->`。本文には dwell 日数・最終 dispatch 日時・retire 根拠・退避した条件の一覧を含める (後から retire の妥当性を検証できる情報)
   - 最終 dispatch 日時は、当該 Issue のコメントのうち `<!-- wholework-event: type=observation-trigger` または `<!-- wholework-event: type=batch-verify-dispatch` を含むものの `createdAt` の最大値。該当なしの場合は `none` と記録する
   - コメント投稿失敗は stderr 警告のみで続行 (fail-open)
   - 書き換え後の body で未チェック post-merge 条件を verify-type を問わず再カウントし、0 件なら `gh-label-transition.sh "$N" done` を実行する。Issue state が `OPEN` の場合のみ `gh issue close "$N"` を併せて実行する (`skills/verify/SKILL.md` の done 遷移と同一規約。`phase/verify` の Issue は通常すでに CLOSED)
   - 標準出力の最終形 (exhaustive): `action=<none|propose|retire>` / `retired=<件数>` / `remaining=<未チェック post-merge 条件の残数>` / `transitioned=<true|false>`
   - `--dry-run` 指定時は Step 3・4 の読み取りと算出のみ行い、L0 書き込みを一切行わずに上記 4 行を「実行した場合の値」として出力する

6. `skills/audit/SKILL.md` の `#### Retire-Proposal Comment Posting` 節を更新する (→ 受入条件 1, 2, 3)
   - Level 3 の行を、`${CLAUDE_PLUGIN_ROOT}/scripts/apply-verify-retire.sh --issue <N> --dwell <dwell_days>` を呼び、その `action=` 出力で分岐する手順に書き換える。`action=retire` のときはスクリプトが retire を完了しているので追加のコメント投稿を行わない。`action=propose` のときは従来の判断プロンプトコメントを投稿する
   - 同節に **`auto-retire` の語を含む** 記述を置く (受入条件 1 の `section_contains "skills/audit/SKILL.md" "Retire-Proposal Comment Posting" "auto-retire"` が判定対象とするのは h4 見出し `#### Retire-Proposal Comment Posting` から次の h4 以上の見出し `### Step 4: Save` 直前までの範囲)
   - 同節に retire 対象 verify-type (`observation` / `opportunistic`) と、`manual` / `auto` を含めない判断の理由を明記する
   - 同節に autonomy tier ゲート (L1 = 提案のみで現行動作維持、L2/L3 = 自動実行) を明記する
   - frontmatter `description` の `--retention` 説明に auto-retire の記述を追記し、frontmatter `allowed-tools` に `${CLAUDE_PLUGIN_ROOT}/scripts/apply-verify-retire.sh:*` を追加する
   - 同ファイル 562 行目の Section 10 相互参照文 (「unlike Section 8/9's Retire-Proposal Comment Posting, which stays scoped to phase/verify and Icebox only」) を読み、auto-retire 導入後も記述が正しいか確認する。当該節がコメント投稿に加えて body 書き換え・ラベル遷移も行うようになるため、必要なら文言を更新する (Changed Files の Steering Docs sync candidate)
   - SKILL.md 本文には半角感嘆符・小数点付き Step 番号・3 連バッククォートを書かない (`scripts/validate-skill-syntax.py` の MUST 制約)

7. `modules/l0-surfaces.md` の Machine-Readable Event Marker 節に `type=verify-ac-retired` の定義を追加する (→ 受入条件 5)
   - 属性 (`phase=audit`, `issue=`, `dwell=`, `ac=`, `verify-types=`)、producer (`scripts/apply-verify-retire.sh`)、resolution 方針 (`type=batch-verify-dispatch` と同じく「1 件以上存在するか」のみを見る。latest-wins 解決は不要 — 追記専用の履歴として複数回の retire がそれぞれ有効な記録になる) を記述する
   - 記述箇所は既存の `type=batch-verify-dispatch` 定義の直後 (同節末尾の bot 例外の説明より前)

8. `tests/audit-retention.bats` に `apply-verify-retire.sh` のテストケースを追加する (→ 受入条件 6, 7)
   - 既存スイートが PASS することだけでなく、新規ロジックを検証する以下の新規テストケースを追加したうえでスイートが PASS すること (対象ファイルは既存の `tests/audit-retention.bats` へ追加する — 同ファイルが既に `compute-escalation-level.sh` の Level 判定を所有しており、Level 判定と Level 3 の実行判断は同一関心事のため)
   - 必須 3 ケース: (1) Level 3 (dwell 90+) かつ `AUTONOMY_TIER=L2` および `L3` で `action=retire` かつ retire が実行される、(2) Level 3 かつ `AUTONOMY_TIER=L1` で `action=propose` かつ L0 書き込みが発生しない、(3) Level 2 以下 (dwell 89 以下) では tier を問わず `action=none` かつ retire しない
   - 追加ケース: verify-type 限定 (`manual` / `auto` 行が退避されない)、fenced code block 内の `- [ ]` が退避されない、対象 0 件時に `retired=0` で L0 書き込みなし (冪等性)、未チェック条件が残る場合に `transitioned=false`、`compute-escalation-level.sh` 失敗時の fail-closed、引数バリデーション (`--issue` 欠落 / 非数値) で exit 1
   - モックは `docs/tech.md` § BATS Mocking Convention に従う: `export WHOLEWORK_SCRIPT_DIR="$MOCK_DIR"` を設定し、`$MOCK_DIR` に `gh-issue-edit.sh` / `gh-issue-comment.sh` / `gh-label-transition.sh` / `get-config-value.sh` / `compute-escalation-level.sh` のモックを配置する。`gh` は `PATH` 先頭に置いたモックで差し替える (`tests/run-fact-matching.bats` と同一パターン)
   - `tests/audit-retention.bats` は既に `WHOLEWORK_SCRIPT_DIR` を使っていないため、既存テストに影響しないよう新規テストの `setup` 内でのみ export する

9. ドキュメント 4 件を同期する (→ 受入条件 1)
   - `docs/structure.md` の `### Scripts` > Project utilities に `scripts/apply-verify-retire.sh` の 1 行説明を追加 (`scripts/apply-run-fact-match.sh` の行と同じ粒度・同じ位置づけ)
   - `docs/workflow.md` の Label Transition Map の `| phase/done | Complete | /verify (on all auto-verify PASS + all post-merge conditions checked) | — |` 行に、`/audit stats --retention` (Level 3 auto-retire) を付与主体として追記
   - `docs/ja/structure.md` / `docs/ja/workflow.md` の対応箇所を `docs/translation-workflow.md` の Sync Procedure に従って同期する (`docs/ja/structure.md:215` 付近が `apply-run-fact-match.sh` 行、`docs/ja/workflow.md:193` が `phase/done` 行)

## Alternatives Considered

| 案 | 内容 | 採否 | 理由 |
|---|---|---|---|
| SKILL.md の prose だけで実装 | 新規スクリプトを作らず `skills/audit/SKILL.md` の Level 3 分岐に手順を書き下す | 不採用 | 受入条件 6 が bats による 3 ケース検証を要求するが、LLM prose は bats で検証できない。判断ロジックを決定的スクリプトへ切り出すのが唯一の充足経路 |
| `retention-auto-retire.enabled` 設定キーを追加 | `recoveries-auto-fire` と同型の opt-in 設定キーで二重ゲートする | 不採用 | Notes の判断 3 を参照 |
| `auto-retired` 追跡ラベルを追加 | retire 実行済み Issue を label で識別可能にする | 不採用 | Notes の判断 2 を参照 |
| `manual` も自動 retire 対象に含める | 163 件中 104 件を占める `manual` を含めて一度に解消する | 不採用 | Notes の判断 1 を参照 |
| 1 回の実行あたりの retire 件数に上限を設ける | `docs/stats/2026-06-27.md:112` が Level 2 の 130 件一括投稿を safety scope 超過と記録している先例に倣う | 不採用 | Notes の判断 5 を参照 |

## Verification

### Pre-merge

- <!-- verify: section_contains "skills/audit/SKILL.md" "Retire-Proposal Comment Posting" "auto-retire" --> `skills/audit/SKILL.md` の Level 3 分岐が、コメント投稿だけでなく条件の retire と `phase/done` 遷移を行う手順に変更されている
- <!-- verify: rubric "Level 3 の自動 retire がどの verify-type を対象とするかが明記され、manual を含める/含めない判断の理由が示されている" --> retire 対象の verify-type が明示されている (`manual` を含めるか否かの判断と理由が記述されている)
- <!-- verify: rubric "AUTONOMY_TIER が L1 のとき Level 3 の動作が現行のコメント投稿のままであり、L2/L3 でのみ自動 retire が実行されることが手順上明確である" --> autonomy tier によるゲートが実装され、L1 では現行の提案動作が維持される
- <!-- verify: rubric "retire 手順が #1165 の Retired Post-merge Conditions 退避形式を踏襲しており、check-ac-checkbox-format.sh の形式ガードに抵触しない" --> retire された条件が `### Retired Post-merge Conditions` 節へ退避され、`### Post-merge` 配下にプレーン箇条書きを作らない
- <!-- verify: rubric "retire 実行時に記録されるコメントの内容が定義され、後から retire の妥当性を検証できる情報が含まれている" --> retire 理由 (dwell 日数・最終 dispatch 日時・retire 根拠) が Issue コメントに記録される手順になっている
- <!-- verify: rubric "tests/ 配下の bats テストに、Level 3 かつ L2/L3 で retire が実行される・Level 3 かつ L1 では提案のみ・Level 2 以下では retire しない、の 3 ケースを検証するテストが存在する" --> bats テストが追加され、3 ケースを検証している
- <!-- verify: command "bats tests/" --> `bats tests/` 全件が PASS する

### Post-merge

- retire 実行後に `scripts/collect-verify-retention-stats.sh --window 2026-05-07` を実行し、「90 日より古い待機」の合計が 163 件から減少していることを確認する
- 同スクリプトの出力で `phase/verify` 総件数が 325 件 (全期間) から減少していることを確認する
- retire 実行後に `opportunistic-search.sh` の走査対象件数が減り、1 回あたりの実行時間が短縮していることを観察する (起票時点の実測: 約 2 分 / 回、走査対象 325 Issue)

## Tool Dependencies

### Bash Command Patterns

- `${CLAUDE_PLUGIN_ROOT}/scripts/apply-verify-retire.sh:*` — `skills/audit/SKILL.md` の `allowed-tools` へ新規追加が必要 (Level 3 分岐からの呼び出し)

### Built-in Tools

- なし (`skills/audit/SKILL.md` の既存 `allowed-tools` に `Read` / `Write` / `Edit` / `Bash` はすべて登録済み)

### MCP Tools

- なし

## Uncertainty

- **`section_contains` の判定範囲**: 受入条件 1 の `section_contains "skills/audit/SKILL.md" "Retire-Proposal Comment Posting" "auto-retire"` は、h4 見出し `#### Retire-Proposal Comment Posting` から次の h4 以上の見出しまでを対象とする。現状その次の見出しは `### Step 4: Save` (611 行目から 652 行目までが節の範囲)。
  - **検証方法**: `modules/verify-executor.md:70` の `section_contains` 定義を確認済み (「from the specified heading line to just before the next heading of the same or higher level」)。`auto-retire` の語が現在 `skills/audit/SKILL.md` に 0 件であることも `grep -c "auto-retire" skills/audit/SKILL.md` で確認済み (実装後にのみ現れる語であり、常時 PASS バグにならない)
  - **影響範囲**: Implementation Step 6 — `auto-retire` の語をこの範囲内に置くこと。範囲外 (frontmatter の `description` など) に置いても受入条件 1 は PASS しない
  - **解決**: 解決済み。Implementation Step 6 にこの制約を明記した

- **`### Post-merge` 節が空になった場合の形式ガード**: 全条件を retire すると `### Post-merge` 節に箇条書きが残らない。
  - **検証方法**: `scripts/check-ac-checkbox-format.sh` の awk を読み、`^- ` で始まり `^- \[[ xX]\]` に合致しない行のみを違反として検出すること、および任意の `^### ` 見出し行で `in_section` が 0 に戻ることを確認済み。Issue #706 の実際の body でも同形式が使われていることを `gh issue view 706 --json body` で確認済み
  - **影響範囲**: Implementation Step 4
  - **解決**: 解決済み。散文行 (先頭が `- ` でない行) を挿入する形とし、Implementation Step 4 に明記した

## Notes

### 自動解決した判断 (Issue 本文が `/spec` へ明示的に委譲したもの)

**判断 1 — retire 対象の verify-type は `observation` と `opportunistic` に限定する。`manual` と `auto` は対象外。**

- `manual`: 「人間が見る必要がある」と明示的に判断された条件であり、自動 retire は当初の判断を機械的に覆すことになる。Issue 本文の推奨案どおり Level 3 の提案動作に留める
- `auto`: verify command を持ち機械的に判定可能な条件であるため、正しい処置は retire ではなく dispatch (`/audit verify-backlog` 経由の `/verify` 実行) である。1 回の `/verify` で満たせる条件を retire すると回復可能な検証機会を失う
- **影響 (measurement scope: `scripts/collect-verify-retention-stats.sh --window 2026-05-07` の 2026-08-08 実測、母集団は `phase/verify` ラベル保持の全期間 325 Issue)**: 90 日より古い待機 163 件のうち、本 Issue の初版が対象とするのは opportunistic 56 件 + observation 0 件 = **56 件**。Issue 本文 Background の「滞留のおよそ半分を一度に解消する」は 163 件全体を対象とした場合の見積もりであり、初版の実効範囲はそれより小さい。post-merge 受入条件は「163 件から減少していること」を求めているため 56 件の削減で充足する。observation は機構が新しく現時点で 0 件だが、時間経過で同じ尾を持つため TTL は先回りで効く

**判断 2 — `auto-retired` 等の追跡用ラベルは追加しない。**

- Level 3 に到達した Issue は必ず Level 2 を通過しており `stale-verify` が既に付与済み。retire の事実自体は `<!-- wholework-event: type=verify-ac-retired ... -->` marker コメントで機械可読に記録されるため、ラベルによる識別は重複する
- 新規ラベル追加は `scripts/setup-labels.sh` + `docs/tech.md` § Label Groups の Always-group 件数 (17 → 18) + `docs/ja/tech.md` + `modules/label-conventions.md` の 4 ファイルの SSoT 更新を伴う (`docs/tech.md` § Modification Rules)。得られる機能は marker コメントで既に得られているため、割に合わない
- `phase/done` 遷移時に `stale-verify` を外すこともしない。Level 2 エスカレーションに到達した履歴の監査証跡として保持する。`skills/audit/SKILL.md:1019` の Stale 分類は `state == "OPEN"` を前提とするため、CLOSED である retire 済み Issue が誤分類されることはない

**判断 3 — `retention-auto-retire.enabled` 等の設定キーは追加しない。autonomy tier ゲートのみとする。**

- `modules/autonomy-tier.md` は「この tier でこの L0 書き込みが許されるか」の指定 SSoT であり、auto-retire が行う書き込み (Issue body 編集 / コメント投稿 / ラベル遷移) はいずれも Tier × L0 Write Matrix が L2/L3 で既に許可している通常の L0 書き込みである。二重ゲートは同じ判断軸を 2 箇所に分散させる
- Issue 本文が参考先として挙げる `recoveries-auto-fire` が追加の設定キーを持つのは、当該機能が **新規 Issue を作成する** (matrix が L3 限定とする「Recurring template / cross-issue creation」行) ためであり、#1179 で実運用のノイズを受けて既定 opt-out 化された経緯による。auto-retire は Issue を作成せず、退避した条件は `### Retired Post-merge Conditions` 節に原文のまま保持されるため可逆である
- 設定キーを既定 `false` で追加すると、L2/L3 かつ既定設定の環境で auto-retire が実行されなくなり、受入条件 3 の「L2/L3 でのみ自動 retire が実行される」を決定的に満たしにくくなる

**判断 4 — 判断ロジックを `scripts/apply-verify-retire.sh` へ切り出す。**

- 受入条件 6 が bats による 3 ケース検証を要求するため、LLM prose のままでは充足できない
- 先例として `scripts/apply-run-fact-match.sh` が同型 (決定的な autonomy-tier ゲート / `action=` 標準出力 / `--dry-run` / fail-open / `WHOLEWORK_SCRIPT_DIR` モックによる bats テスト) であり、命名・引数形式・出力形式・fail-safe 方針をこれに揃える

**判断 5 — 1 回の実行あたりの retire 件数に上限を設けない。**

- `docs/stats/2026-06-27.md:112` は Level 2 の 130 件一括コメント投稿を safety scope 超過と記録しているが、auto-retire は対象 0 件で無書き込み終了する自然な冪等性を持つため、再実行しても件数が積み上がらない
- 上限を設けると本 Issue の目的 (滞留に上限を設けて一度に解消する) と直接矛盾する。件数は実行サマリとして報告されるため silent truncation にはならない

### fail-safe critical 判定

本スクリプトは fail-safe critical と判定した。判定基準 (a) 何らかの操作を許可/阻止するゲート (retire を実行するか提案に留めるかを決める) と (b) 入力検証で accept/reject を決めるバリデータ (dwell・tier・verify-type から対象条件を選別する) の双方に該当する。依存コマンド失敗時の方向を意図的に非対称にしている:

| 失敗箇所 | 方向 | 理由 |
|---|---|---|
| `compute-escalation-level.sh` 失敗 | fail-**closed** (`action=none`) | 判定不能な dwell から retire を導いてはならない |
| `gh issue view` (body 取得) 失敗 | fail-**open** (`retired=0`, exit 0) | プロジェクト全体を走査する `/audit` 実行を 1 件の GitHub 障害で中断させない |
| `gh-issue-edit.sh` (body 書き戻し) 失敗 | fail-**open** かつ後続処理を実行しない | 着地していない retire を主張するコメント・ラベル遷移を残さない (`apply-run-fact-match.sh` と同じ順序ゲート) |
| `gh-issue-comment.sh` 失敗 | fail-**open** (警告のみ、続行) | body 書き換えは既に着地しており、コメントは監査証跡の付随物 |

エッジケース (Implementation Steps に反映済み): 空 body / `### Post-merge` 節なし → 無書き込みで `retired=0`。条件文に `>` `"` 改行 CRLF 全角文字を含む場合 → body をファイル経由でのみ受け渡し、行末 `\r` を保存する。`set -euo pipefail` の `pipefail` によりパイプライン終了ステータスが意図せず条件分岐を通過する経路を作らない (#1060)。

### Issue 本文と実装の矛盾 (1 件)

Issue 本文 Notes は「`scripts/scan-pending-ac.sh:134` の `match(line, /verify-type: [a-zA-Z_]+/)` は行内の最初の出現を取るため、条件文がタグ名を引用している行 (#1167 の post-merge AC が該当) を誤分類する」と記述しているが、**この記述は現在の実装と食い違う (既に修正済み)**。

- 実際: `scripts/scan-pending-ac.sh:181` は `match(line, /<!--[ \t]*verify-type:[ \t]*[a-zA-Z_]+/)` を使っており、HTML コメント内に限定した抽出になっている (`modules/verify-classifier.md` § Tag Extraction Rule 準拠)。同スクリプトの冒頭コメント 48-54 行目にもその旨が明記されている。134 行目は現在 Rule 2 のキーワードリストであり無関係
- 解決: Issue 本文自身が「本 Issue の対象範囲外」と述べているため設計変更は不要。ただし本 Spec で新規実装する verify-type 抽出は、この HTML コメント限定パターンが**例外ではなくコードベース全体の規範**であることを前提に書く (Implementation Step 3)。`/code` が Issue 本文の記述をそのまま前提にして緩いパターンを採用しないよう、ここに明示する

### 既知の相互作用 (本 Issue の対象範囲外)

`scripts/collect-verify-path-done-rate.sh` (`/audit stats --retention` Section 12) は dispatch 経路ごとの `phase/done` 到達率を測る。auto-retire で `phase/done` へ遷移した Issue が、過去に observation-trigger / batch-verify-dispatch の marker を受け取っていた場合、その経路の done 率に「検証によらない done」が混入して到達率を押し上げる。

本 Issue は Issue 本文の受入条件を変更しない (`/issue` (What) と `/spec` (How) の責務境界) ため対処を追加しないが、`type=verify-ac-retired` marker が付くので後から除外可能な形にはなっている。`/verify` フェーズの Improvement Proposal 候補として記録する。

### Exclusions (grep 対象からの除外)

- `docs/stats/2026-06-27.md` — 過去レポートの歴史的記録。当時の Level 2 一括投稿の判断を記述したものであり、auto-retire 導入後も書き換えない
- `docs/spec/*.md` — 破棄前提の Spec 群 (`docs/spec/issue-1165-manual-ac-retype-d3.md` などが `### Retired Post-merge Conditions` に言及するが、いずれも過去の作業記録)
- `docs/sessions/*/session.md` — セッションレトロスペクティブの歴史的記録

### 新規テストケース要件のまとめ

Implementation Step 8 が新規分岐ロジック (Level 3 × tier のルーティング、verify-type 限定、冪等性ガード、fail-closed / fail-open の非対称性) を導入するため、受入条件 7 の `command "bats tests/"` は既存スイートの PASS だけでなく、`tests/audit-retention.bats` への新規テストケース追加を伴って PASS することを要求する。必須 3 ケース + 追加 6 ケースの内訳は Implementation Step 8 に列挙した。

## Consumed Comments

- saito / MEMBER / first-class / `/issue` フェーズの Issue Retrospective — verify command 2 件の修復 (常時 PASS の `grep -n "Level 3" ...` → `section_contains ... "auto-retire"`、常時 UNCERTAIN の `ls tests/` → `rubric`)、post-merge 条件 3 件への `session=next` 付与、および「`manual` の扱い / 追跡ラベル / config key 名は `/spec` へ意図的に委譲」の記録 / https://github.com/saitoco/wholework/issues/1271#issuecomment-5378996458

## issue retrospective

(`/issue` フェーズの retrospective コメントから転記。verify command の原文マーカーは、Spec 内で実マーカーとして解釈されないよう記法を崩して引用している)

### 修正内容

前回の triage AC audit コメント (2026-08-08、`saito`、first-class) で指摘された verify command の不具合 2 件を修正した:

1. **常時 PASS バグ**: `grep -n "Level 3" skills/audit/SKILL.md` 形式の verify command は `skills/audit/SKILL.md` が現時点で既に "Level 3" を含むため実装 0 行で PASS してしまう。`section_contains "skills/audit/SKILL.md" "Retire-Proposal Comment Posting" "auto-retire"` へ変更 (指摘コメントの修復案どおり)。加えて、修正前の verify command 自体が `modules/verify-executor.md` の `grep "pattern" "path"` 構文 (2 引数、フラグなし) に反していた点も同時に是正した。
2. **常時 UNCERTAIN バグ**: `ls tests/` 形式は `ls` が未定義のコマンド名で恒久的に UNCERTAIN になる。テスト対象ファイルが実装時点で未確定 (`tests/audit-retention.bats` への追加か新規ファイルかは Spec が判断) なため、存在しないファイルを前提とする `file_contains` は使わず、`rubric` のみで置き換えた。

### session=next の付与

`skills/audit/SKILL.md` を変更対象とし、post-merge 条件 3 件がいずれも `verify-type: observation` だったため、`scripts/check-skill-change-observation-ac.sh` が `session=next` の欠落を検出 (exit 2)。3 件すべてに `session=next` を付与した。

### Ambiguity Detection

Background / 対応方針セクション内の「`manual` を含めるか否か」「追跡用ラベルの要否」「config key 名」は、いずれも Issue 本文で既に「実装時に判断し Spec に記録する」と明示的に委譲されている。`/issue` (What) / `/spec` (How) の責務境界に沿った意図的な委譲と判断し、追加のクラリフィケーションは行わなかった。

## spec retrospective

### Minor observations

- Issue 本文が「実装時に判断する」と明示的に委譲した論点が 3 件あり、`/issue` フェーズ側でも意図的な委譲として記録されていた。委譲の意図が両フェーズで一致していたため `/spec` 側の判断が宙に浮かず、Notes へ判断 1-3 として直接書き下せた。委譲を Issue 本文と retrospective の両方に書き残す運用は機能している
- Issue 本文 Notes の実装参照 1 件 (`scripts/scan-pending-ac.sh:134` の緩い verify-type 抽出パターン) が起票後の修正で陳腐化していた。Issue 本文の「対象範囲外」記述はそのまま残っていたため、grep で実物を確認しなければ `/code` が古い前提を引き継ぐ経路があった。Issue 本文が引用する行番号付き実装参照は、対象範囲外と明記されていても spec フェーズで実在確認する価値がある
- `docs/stats/2026-06-27.md:112` に「Level 2 の 130 件一括コメント投稿は unattended 実行の safety scope を超える」という過去判断が記録されていた。同種の一括処理を扱う本 Issue で上限を設けない判断をするにあたり、この記録が対比材料として直接使えた。`docs/stats/` の過去レポートは数値だけでなく判断の記録としても再利用価値がある

### Judgment rationale

- 受入条件 6 が bats による 3 ケース検証を要求している時点で、Level 3 の判断ロジックを LLM prose のままにする選択肢は消える。「テスト可能性の要求が実装形態を決める」という制約の向きを最初に確定させたことで、スクリプト切り出しの是非を議論せずに済んだ
- `retention-auto-retire.enabled` 設定キーを追加しない判断は、`recoveries-auto-fire` との差分 (あちらは新規 Issue を作成する = matrix が L3 限定とする行に該当、こちらは可逆な body 編集のみ) を見て決めた。「先例と同型に見えるが、ゲートが必要だった理由が異なる」ケースを、先例の表面形ではなく成立理由まで遡って比較したのが分岐点
- 対象 verify-type から `auto` を外した理由は `manual` とは別系統である。`manual` は「人間が見ると明示的に判断された」ため、`auto` は「1 回の `/verify` で満たせる = retire すると回復可能な検証機会を捨てる」ため。Issue 本文は `manual` の扱いだけを論点として提示していたが、`auto` も同じ判断軸で明示的に除外する必要があった

### Uncertainty resolution

- `section_contains` の判定範囲 (h4 見出しから次の h4 以上の見出しまで) を `modules/verify-executor.md:70` で確認し、`auto-retire` の語を置くべき範囲を Implementation Step 6 に確定させた。あわせて `grep -c "auto-retire" skills/audit/SKILL.md` が 0 であることを確認し、受入条件 1 が常時 PASS にならないことを裏取りした
- `### Post-merge` 節が空になったときに `scripts/check-ac-checkbox-format.sh` の形式ガードへ抵触しないかは、awk 本体を読んで「`^- ` で始まり `^- \[[ xX]\]` に合致しない行のみを違反とする」「任意の `^### ` 見出しで `in_section` が 0 に戻る」の 2 点を確認して解決した。Issue #706 の実 body でも同形式が使われていることを `gh issue view` で併せて確認している
- 本 Spec の新規実装が使う verify-type 抽出パターンは、`modules/verify-classifier.md` § Tag Extraction Rule と 2 つの参照実装 (`scripts/collect-verify-retention-stats.sh:159-161`、`scripts/scan-pending-ac.sh:181`) を突き合わせて HTML コメント限定形に確定した

### 新規テストケース要件

Implementation Step 8 が新規分岐ロジックを導入するため、受入条件 7 (`command "bats tests/"`) は既存スイート PASS に加えて新規テストケースの追加を伴う。必須 3 ケース (Level 3 × L2/L3 → retire、Level 3 × L1 → 提案のみ、Level 2 以下 → retire しない) + 追加 6 ケース (verify-type 限定、fenced code block 除外、冪等性、`transitioned=false`、fail-closed、引数バリデーション) を `tests/audit-retention.bats` へ追加する。

## Code Retrospective

### Deviations from Design

N/A — Implementation Steps 1–9 を Spec の記述順どおりに実装した。順序の入れ替え・省略・統合は発生していない。

### Design Gaps/Ambiguities

- Implementation Step 4 の「`### Post-merge` 節に `- [` で始まる行が 1 つも残らない場合のみプレーン散文行を挿入する」という条件判定は、Spec 本文では fenced code block の除外に明示的に触れていなかった。実装時、手動テストで「実条件はすべて retire 対象だが、fenced code block 内のサンプル `- [ ]` 行だけが Post-merge 節に残る」ケースを検証したところ、fence 内容を除外せずに `- [` を素朴にスキャンする実装では散文行が誤って挿入されず (fenced sample を「実条件が残っている」と誤認)、`### Post-merge` 節が箇条書きなしの裸プロークで終わる不整合が起きることを発見した。`modules/l0-surfaces.md` § AC Enumeration Convention (b) の fence 除外規約はこの判定にも一律適用されるべきという前提を Spec は明文化していなかったため、Implementation Step 3 の fence 追跡 (in_fence) をこの残数判定にも流用する形で対処した (awk に `fence_state[NR]` 配列を追加)。同種の「fence 除外はどの判定に適用されるか」を Spec に書く際は、AC Enumeration Convention への参照だけでなく、具体的にどの計算箇所に適用が及ぶかを明示すると実装時の手戻りを防げる

### Rework

- 上記の fence 除外漏れは、`scripts/apply-verify-retire.sh` を書き上げた直後の手動統合テスト (`.tmp/manual-test/` に一時的なモック環境を作り、Post-merge 節の全条件が fenced sample を除いて retire される fixture を用意して実行) で発見した。修正は awk の main ブロックに `fence_state[NR] = in_fence` を追加し、END ブロックの `remaining_pm_checkbox` ループで `fence_state[i]` が真の行をスキップするよう変更する 1 箇所のみで、bats テスト (`fenced sample checkbox is excluded from retire targets` および他の既存ケース) は影響を受けなかった

## review retrospective

### Spec vs. implementation divergence patterns

- Spec の Implementation Steps は「body を 1 つの連続領域として awk で 1 パス抽出し、3 スライスで再構成する」という設計だったが、Post-merge 節や Retired Post-merge Conditions 節が複数回出現する、または想定と逆順に出現するケースへの防御が Spec に明記されていなかった。実装レビューで実際に fixture を実行したところ、(a) `### Post-merge` 見出しが 2 回出現する body、(b) `### Retired Post-merge Conditions` が `### Post-merge` より前に出現する body の 2 パターンで、スライス境界の前提が崩れて条件が重複計上される (retire 済みとして strikethrough 表示されつつ、元の生きた unchecked checkbox としても残る) ことを確認した。Spec の「Body rewrite」記述は正常系の 1 パターンしか想定しておらず、構造前提が崩れた場合のガードが設計段階で要求されていなかった
- Spec Notes の「manual/auto は Level 3 の提案動作に留める」という設計意図と、実装の `action=` 決定ロジック (body を読む前に LEVEL×TIER だけで action を確定する) との間に乖離があった。manual/auto のみの Post-merge を持つ Level 3 Issue が L2/L3 下で `action=retire` かつ `retired=0` に解決され、SKILL.md 側が `action=retire` に対して追加コメント投稿を禁止していたため、結果として提案コメントも retire コメントもどちらも投稿されない状態になっていた。Spec の設計意図は正しかったが、`action=` の決定タイミングと SKILL.md 側の分岐条件の組み合わせを Spec レベルで検証していなかった

### Recurring issues

- HTML コメント形式のタグ (`<!-- verify-type: ... -->`) を扱うスクリプトが、閉じタグ `-->` の有無を検証せずに開始タグだけでマッチしてしまう問題は、`modules/verify-classifier.md` § Tag Extraction Rule に既に「full span through the comment's own closing `-->`」という canonical pattern が明文化されているにもかかわらず、本 PR の初版実装ではその canonical pattern を踏襲していなかった (bare-tag-value 形式のみを使用し、閉じタグの存在を検証していなかった)。同一モジュールに既存の canonical pattern がある場合、実装時に該当箇所を明示的に参照するチェックリスト項目があると同種の手戻りを防げる
- 日本語文字列をシングルクォートで囲んだ bash `printf` リテラルが `check-language-convention.py` のダブルクォート限定除外パターンに引っかからず CI FAILURE になる問題は、本 PR で初めて顕在化したものではなく、チェッカー自体の既知の非対称性 (ダブルクォートのみ除外、シングルクォートは除外しない) に起因する。今後 Issue 本文や Issue コメントに書き込む日本語プロースを含む新規スクリプトを書く際は、`printf` リテラルをダブルクォートで統一するか、チェッカー側の非対称性自体を別 Issue で是正するかの判断が必要

### Acceptance criteria verification difficulty

- Pre-merge AC 7 件はすべて Issue 起票時点で `[x]`済みだったが、これは rubric/section_contains の設計判断が正しかったことを意味するだけで、実装の正確性 (edge case 耐性) までは検証していなかった。今回 2 件の MUST バグ (body 構造前提の崩壊、タグ終端未検証) は AC の rubric テキストでは検出できず、Parser/Validator Edge Case Pre-check による実行ベースの検証で初めて発見された。Issue body/Spec を解析・検証する新規スクリプトについては、AC の rubric 判定だけでなく edge case 実行検証を必須とする現行の `/review` 設計 (Step 10 Parser/Validator Edge Case Pre-check) が有効に機能した実例として記録する
- verify command は 6/7 件が `rubric` で、いずれも「設計が文書化されているか」を問う形だった。実装の正確性 (body 書き換えロジックの境界条件) を問う verify command は Issue 側に存在せず、bats テストの充実度に依存していた。本 PR のように body/comment 生成を伴うスクリプトでは、rubric に加えて「境界条件を bats がカバーしているか」を問う verify command を追加する余地があった

## Phase Handoff
<!-- phase: merge -->

### Key Decisions

- PR #1436 は pre-merge AC 7 件全チェック済み、`review_incomplete_fallback` なしでゲートを通過したため、非対話モードのオーバーライド無しでそのまま squash merge した
- `mergeable=true` / `reason=clean` (CI success, review approved) だったため conflict 解決ステップは発生せず、rebase やテスト再実行は不要だった

### Deferred Items

- None

### Notes for Next Phase

- `/verify` は Spec Notes for Next Phase (review handoff由来) が既に指摘している Post-merge 条件 3 件 (`verify-type: observation event=auto-run session=next`) を引き続き判定対象とする。実測基準は `/review` の最終コミット状態 (2 回の追加コミット: バグ修正 + ドキュメント同期) を含む
- `scripts/collect-verify-retention-stats.sh --window 2026-05-07` を実行し、90 日超待機の合計・`phase/verify` 総件数の減少を確認すること (Issue #1271 Verification (post-merge) 節)

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- 特になし。Pre-merge AC 7 件は起票時点で全件 [x] 済みで、rubric/section_contains/command のいずれも UNCERTAIN なし。

#### design
- Code Retrospective (Design Gaps) の指摘どおり、Spec の Implementation Steps は「fence 除外がどの計算箇所に適用されるか」を明示しておらず、Post-merge 節の残数判定で fenced sample の誤認が実装時に発覚した。fence 除外規約 (`modules/l0-surfaces.md` § AC Enumeration Convention (b)) を参照する Spec は、適用範囲を「AC 列挙」だけでなく「関連する残数・件数判定全般」まで明示すべき。

#### code
- MUST 相当の手戻りなし (fixup/amend パターンは fence 除外漏れの 1 件のみ、手動統合テストで発見・即修正)。

#### review
- MUST 2件: (1) body 構造前提 (`### Post-merge`/`### Retired Post-merge Conditions` の複数出現・逆順出現) への防御が Spec レベルで要求されていなかった、(2) `modules/verify-classifier.md` § Tag Extraction Rule が既に明記する canonical pattern (HTML コメントの閉じタグ `-->` まで検証) を初版実装が踏襲していなかった。(2) は既存ドキュメントに正解が書かれていたにもかかわらず参照されなかった再発パターンであり、実装時チェックリストでの明示参照が有効な対策候補。
- CI FAILURE 1件 (Language Convention check): `check-language-convention.py` のシングルクォート日本語文字列除外パターン非対称性 (ダブルクォートのみ除外) に起因。本 PR 固有の欠陥ではなく、チェッカー自体の既知の非対称性。

#### merge
- 特になし。pre-merge AC 全チェック済み、`review_incomplete_fallback` なし、conflict なしで squash merge。

#### verify
- FAIL/UNCERTAIN なし。Post-merge 条件 3 件は `event=auto-run` 未発火のため SKIPPED (`session=next` の判定は次回発火時、かつ本セッションとは別セッションでの評価が必要)。
- review phase で watchdog silent 5400s 超過 → Tier 3 recovery (`action=retry`) が発火し `run-review.sh` の再実行で回復。`docs/reports/orchestration-recoveries.md` (Issue #1271, phase: review) に既に記録済みのため、本セクションでは重複記録しない。

### Improvement Proposals

1. **HTML コメントタグ抽出の canonical pattern 参照チェックリスト化**: `modules/verify-classifier.md` § Tag Extraction Rule に既に「閉じタグ `-->` まで検証する」canonical pattern が明文化されているにもかかわらず、本 Issue の初版実装ではこれを踏襲せず bare-tag-value 形式のみでマッチしていた (review MUST で検出)。同種のタグ抽出スクリプトを新規実装する際、`modules/verify-classifier.md` の canonical pattern を明示的に参照するチェックリスト項目があれば同種の手戻りを防げる可能性がある。
2. **`check-language-convention.py` のシングルクォート除外パターン非対称性の是正**: ダブルクォートで囲んだ日本語文字列は除外対象だが、シングルクォートは除外されないため、bash `printf` のシングルクォートリテラルが CI FAILURE になる。本 PR で初めて顕在化したものではなく、チェッカー自体の既知の非対称性。今後 Issue コメントや日本語プロースを含む新規スクリプトを書く機会が増える中で再発しうる。
