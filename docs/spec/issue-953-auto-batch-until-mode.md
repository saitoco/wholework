# Issue #953: auto: --batch に条件駆動 (--until) モードを追加

## Consumed Comments

cutoff: `2026-08-10T06:10:45Z` (直近の `phase/issue` label 付与時刻)

| login | authorAssociation | trust tier | intent | URL |
|-------|-------------------|-----------|--------|-----|
| saito | MEMBER | first-class | `/issue 953 --non-interactive` の Issue Retrospective (auto-resolve 3 件・#1322 との blocked-by 不設定の政策決定・Priority high 確認) | https://github.com/saitoco/wholework/issues/953#issuecomment-5236558615 |

cutoff 前の 2026-08-10T02:42:26Z コメント (テーマ駆動 Backlog 消化のユースケース具体化) は `/issue` フェーズで既に Issue 本文へ統合済みのため、本 Spec では本文経由で取り込んでいる。cross-phase marker (`verify-fail` / `preview-ac-unverified`) は該当なし。

## Overview

`/auto --batch` に第 3 のモード `--until <query>` を追加する。既存の Count mode (`--batch N`) / List mode (`--batch N1 N2 ...`) はそのまま維持し、「クエリ実行 → List mode 相当の処理 → 再クエリ → 0 件になるまで繰り返す」条件駆動ループを新設する。

設計の骨子は 3 点:

1. **クエリ解決は決定的スクリプトに分離** — Issue が「LLM が毎回自然言語から再解釈するのではなく機械的に評価できる形にする」と明示しているため、`scripts/resolve-batch-query.sh` を新設し、`label:` / `status:` 句の解析と Issue 列挙を LLM プロンプト外で行う
2. **ラウンド内処理は List mode をそのまま流用** — 新設するのは「ラウンドを回す外枠」だけで、Issue 1 件あたりの処理 (triage → size gate → blocked-by gate → `run-auto-sub.sh` → verify orchestration → `update_batch`) は `### List mode` の手順を参照するに留める
3. **収束保証は in-session の処理済み集合で担保** — label 単独クエリでは完了済み Issue も再ヒットするため、complete / fail となった Issue をラウンド跨ぎで除外する。seed file (#1214 で撤去済み) は再導入しない

## Changed Files

### 実装

- `skills/auto/SKILL.md`:
  - frontmatter `description`: `--batch --until <query>` の 1 文を追記 (`--batch --resume` の説明の後)
  - frontmatter `allowed-tools`: `Bash(...)` の中に `${CLAUDE_PLUGIN_ROOT}/scripts/resolve-batch-query.sh:*` を追加 (挿入位置は `${CLAUDE_PLUGIN_ROOT}/scripts/auto-checkpoint.sh:*` の直後)
  - Step 1 の `**\`--batch\` detection:**` サブセクション: `--resume` 分岐の直後、numeric token 収集の分岐の**前**に `--until` 分岐を追加。あわせて `--max-rounds` / `--checkin-per-round` の抽出規則を記載
  - `## Batch Mode (--batch)` 冒頭の "Two modes" 列挙を "Three modes" に変更し `--until` 行を追加
  - `### Until mode (--batch --until <query>)` セクションを新設。挿入位置は `### List mode (--batch N1 N2 ...)` セクションの末尾 (`delete_batch` のコードフェンス直後) と `### Resume mode (--batch --resume)` 見出しの直前 (行番号ではなく前後の見出しで特定すること)
  - `loop-paths-used: [A]` は**変更しない** (下記 Notes 参照)
- `scripts/resolve-batch-query.sh`: 新規。`--query` 文字列を解析し該当 Issue 番号を昇順で 1 行 1 件出力する — bash 3.2+ 互換 (`mapfile` / 連想配列を使わず `while read` + `case` glob で実装)

### テスト

- `tests/resolve-batch-query.bats`: 新規。クエリ解析・除外集合・エラー分岐を検証 (`gh` は `$MOCK_DIR` の mock で置換)
- `tests/auto-batch.bats`: `### Until mode` セクション用の awk 抽出ヘルパーと構造テストを追加 (既存の `list_mode_section` / `count_mode_section` と同じ形式)。既存 12 テストは変更しない

### ドキュメント

- `docs/workflow.md`: `**\`--batch --resume\`**:` 段落の直後に `**\`--batch --until <query>\`**:` 段落を追加 (クエリ文法・`--max-rounds` 既定 3・`--checkin-per-round`・収束条件・除外規則)
- `docs/ja/workflow.md`: 同段落の日本語ミラー (`docs/translation-workflow.md` の Sync Procedure に従う)
- `docs/guide/workflow.md`: `### \`/auto\` — Full Automation` のコードフェンスに `/auto --batch --until "label:retro/*"` の 1 行を追加し、"Situation → Recommended" 表に「特定テーマの Issue を条件が尽きるまで消化」行を追加
- `docs/ja/guide/workflow.md`: 同変更の日本語ミラー
- `docs/structure.md`: Directory Layout の `scripts/` 行を `(82 files)` → `(83 files)`、`tests/` 行を `(117 files)` → `(118 files)` に更新。Key Files > Scripts > **Process management** に `scripts/resolve-batch-query.sh` の 1 行説明を追加
- `docs/ja/structure.md`: 同変更の日本語ミラー (`（82 ファイル）` → `（83 ファイル）`、`（117 ファイル）` → `（118 ファイル）`)

### Steering Docs sync candidate (`/code` が個別に読んで採否を判断)

- `docs/product.md`: [Steering Docs sync candidate] § Terms の `/auto` 行が `--batch N` を列挙しているため、`--until` の言及追加が妥当か確認する (prose 1 行のみ。表セルと本文の両方に `--batch` 表現がないかも確認)
- `docs/ja/product.md`: [Steering Docs sync candidate] 上記を採用した場合の日本語ミラー
- `docs/guide/autonomy.md`: [Steering Docs sync candidate] L2 節の「`/auto --batch` を自分で叩く」記述に対し `--until` が新たな選択肢として記載を要するか確認 (現行文脈は「手動トリガー」の例示のみのため変更不要の可能性が高い)

### 変更不要 (grep 確認済み)

- `README.md` / `CLAUDE.md`: `--batch` の列挙・script 一覧ともに存在しない (`grep -n -- "--batch\|/auto" README.md CLAUDE.md` で `/auto` の総論言及 3 行のみ)
- `.claude/settings.json.template`: `auto-checkpoint.sh` / `scan-pending-ac.sh` / `observation-trigger.sh` / `collect-run-facts.sh` のいずれも未登録 (grep hit 0) であり、`${CLAUDE_PLUGIN_ROOT}` 経由の呼び出しは既存の wildcard 2 行でカバーされる
- `scripts/validate-skill-syntax.py`: `KNOWN_TOOLS` は `Bash(...)` の**基底ツール名**のみを検証するため、`Bash(...)` 内へのスクリプトパス追加では更新不要
- `scripts/auto-checkpoint.sh`: `write_batch` が `REMAINING COMPLETED FAILED` を受け取れるため、累積 completed/failed を渡すだけで新規 subcommand なしにラウンド跨ぎ状態を保持できる

## Implementation Steps

1. `scripts/resolve-batch-query.sh` を新規作成する (→ 受入条件 AC1, AC5)
   - **入力**: `--query "<query string>"` (必須)、`--exclude "<space-separated numbers>"` (任意、既定は空)、`--limit <N>` (任意、既定 200 — Count mode の `gh issue list --limit 200` に揃える)
   - **クエリ文法 (exhaustive)**: 空白区切りの `key:value` 句。対応 key は `label` (必須、`*` glob 可) と `status` (任意、project board の Status single-select field に対する完全一致・大小文字区別あり) の 2 つのみ
   - **処理**: (a) `gh issue list --state open --json number,labels --limit <N>` で候補取得 → (b) `case "$name" in $LABEL_PATTERN)` による glob 一致で label 絞り込み (bash 3.2 の `case` glob。`[[ ... == ... ]]` は使わない) → (c) `status:` 句がある場合のみ、残った Issue ごとに `scripts/get-issue-size.sh` と同形の GraphQL (`projectItems.fieldValues` から `field.name=="Status"` を選択) を実行し完全一致で絞り込み → (d) `--exclude` の番号を除外 → (e) 昇順ソートして 1 行 1 件で stdout に出力
   - **分岐の全列挙**:
     - 正常終了: exit 0。stdout は Issue 番号の昇順改行区切り。一致 0 件でも exit 0 かつ stdout 空
     - パースエラー (`--query` 未指定 / 空文字 / `label:` 句なし / 未知の key / 同一 key の重複): exit 1、stderr に `resolve-batch-query: <理由>` を出力、stdout なし
     - `gh issue list` 失敗 (非 0 終了): exit 2、stderr にエラー、stdout なし
     - 個別 Issue の Status 解決失敗 (GraphQL エラー / project item 未登録 / Status 未設定): その Issue を **非一致として除外** し (fail-closed)、stderr に警告 1 行を出して残りの処理を継続。実行全体は exit 0
   - `--exclude` は `while read` ではなく `for n in $EXCLUDE` で読み、空文字を安全に扱う
2. `tests/resolve-batch-query.bats` を新規作成する (after 1) (→ 受入条件 AC5)
   - `$MOCK_DIR` に `gh` の mock を置き `PATH` の先頭に追加する既存パターン (`tests/run-auto-sub.bats` を参照) に揃える
   - ケース: label glob 一致 / `status:` 句ありの絞り込み / `status:` 句なしで GraphQL を呼ばないこと / `--exclude` 除外 / 一致 0 件で exit 0 かつ空出力 / `--query` 未指定で exit 1 / 未知 key で exit 1 / `label:` 句なしで exit 1 / `gh issue list` 失敗で exit 2 / Status 解決失敗の fail-closed 除外 / 空白を含むクエリを単一引数として受け取れること
3. `skills/auto/SKILL.md` Step 1 の `**\`--batch\` detection:**` に `--until` 分岐を追加する (parallel with 1, 2) (→ 受入条件 AC1, AC3)
   - `--resume` 分岐の直後・numeric token 収集分岐の**前**に配置する (`--batch --until "..."` は `--batch` の後に numeric token を持たないため、後段の収集分岐に落ちると Count/List どちらにも該当しない未定義状態になる)
   - 記載内容: `--until` の直後の引数 (ダブルクォートで囲まれた単一トークン) を `UNTIL_QUERY` に記録し、`### Until mode (--batch --until <query>)` に分岐する (**Steps 2–6 を skip**)
   - あわせて `--max-rounds <N>` を `MAX_ROUNDS` (未指定時は `3`、数値でない値・0 以下は警告のうえ `3` にフォールバック)、`--checkin-per-round` の有無を `CHECKIN_PER_ROUND` (既定 `false`) として抽出する規則を記載する
4. `skills/auto/SKILL.md` に `### Until mode (--batch --until <query>)` セクションを新設する (after 3) (→ 受入条件 AC1, AC2, AC4)
   - 見出しレベルは `###` (`### List mode` / `### Resume mode` と同階層)。挿入位置は List mode セクション末尾の `delete_batch` コードフェンス直後・`### Resume mode (--batch --resume)` 見出しの直前
   - ラウンドループの手順 (整数ステップで記述):
     1. `BATCH_ID="${PPID}-$(date +%s)"` を生成し、`ROUND=0` / `PROCESSED=""` / `COMPLETED=""` / `FAILED=""` / `ALL_TARGETS=""` を初期化する
     2. `ROUND` を 1 増やす。`ROUND > MAX_ROUNDS` なら `Until mode: max-rounds ($MAX_ROUNDS) reached; stopping.` を出力し手順 7 へ
     3. `${CLAUDE_PLUGIN_ROOT}/scripts/resolve-batch-query.sh --query "$UNTIL_QUERY" --exclude "$PROCESSED"` を実行する。exit 1 (パースエラー) はクエリ自体が不正なため Until mode 全体を中止する (`delete_batch` は未作成なら不要)。exit 2 (gh 失敗) は、`ROUND == 1` なら中止、`ROUND >= 2` なら警告を出して収束扱いで手順 7 へ
     4. 出力が空なら `Until mode: query returned 0 issues at round $ROUND; converged.` を出力し手順 7 へ
     5. 出力を `ROUND_LIST` とし、`${CLAUDE_PLUGIN_ROOT}/scripts/auto-checkpoint.sh write_batch "$BATCH_ID" "$ROUND_LIST" "$COMPLETED" "$FAILED"` を実行する (List mode 側の checkpoint 初期化はこの呼び出しで代替する)。`ROUND_LIST` を `ALL_TARGETS` に追加したうえで、`### List mode (--batch N1 N2 ...)` の手順 1〜7 をそのまま適用して各 Issue を処理する。`update_batch ... complete` / `... fail` を呼んだ Issue 番号は `COMPLETED` / `FAILED` および `PROCESSED` に追加する。blocked-by で skip した Issue は `PROCESSED` に**追加しない** (blocker が同一セッション中に解消しうるため次ラウンドで再評価する)
     6. `CHECKIN_PER_ROUND` が `true` かつ ARGUMENTS に `--non-interactive` が**ない** 場合のみ、AskUserQuestion で次ラウンドへ進むか確認する。continue 以外が選ばれたら手順 7 へ。`--non-interactive` がある場合は `Warning: --checkin-per-round ignored in non-interactive mode.` を出力してそのまま継続する。いずれの場合も手順 2 へ戻る
     7. `${CLAUDE_PLUGIN_ROOT}/scripts/auto-checkpoint.sh delete_batch "$BATCH_ID"` を実行し、`BATCH_LIST` を `ALL_TARGETS` (全ラウンドの対象 Issue の和集合) とみなして `### Batch Completion Report` 以降 (Batch Completion Report → 観測スキャン → run-fact AC 照合 → next-cycle 引き継ぎ → L3 auto-retrospective) をそのまま実行する
   - 安全弁として `--max-rounds` の既定値が 3 であること、および opt-out 不可 (フラグ未指定でも有効) であることを明記する
5. `skills/auto/SKILL.md` frontmatter を更新する (after 4) (→ 受入条件 AC1, AC3)
   - `description` に `--batch --until <query>` の 1 文を追記
   - `allowed-tools` の `Bash(...)` 内に `${CLAUDE_PLUGIN_ROOT}/scripts/resolve-batch-query.sh:*` を追加 (挿入位置は `${CLAUDE_PLUGIN_ROOT}/scripts/auto-checkpoint.sh:*` の直後)
   - `## Batch Mode (--batch)` 冒頭の "Two modes" 列挙を "Three modes" にし `--until` 行を追加
6. `tests/auto-batch.bats` に `### Until mode` セクションの構造テストを追加する (after 4) (→ 受入条件 AC1, AC2)
   - `until_mode_section()` を既存 2 ヘルパーと同形 (`awk '/^### Until mode/{found=1} /^### / && !/Until mode/{found=0} found{print}'`) で追加
   - 検証内容: `resolve-batch-query.sh` の参照 / `--max-rounds` の既定値 3 / `write_batch` と `delete_batch` の再利用 / `PROCESSED` 除外の記述 / `--checkin-per-round` の non-interactive 無視
7. `docs/workflow.md` と `docs/ja/workflow.md` に `--batch --until` の説明段落を追加する (parallel with 1, 2) (→ 受入条件 AC6)
   - 挿入位置は `**\`--batch --resume\`**:` 段落の直後
   - 記載内容: クエリ文法 (`label:` 必須 / `status:` 任意)、クォート必須、ラウンドループの収束条件、処理済み Issue の除外、`--max-rounds` 既定 3、`--checkin-per-round` の opt-in と非対話時の無視
8. `docs/guide/workflow.md` と `docs/ja/guide/workflow.md` に使用例を追加する (after 7) (→ 受入条件 AC6)
9. `docs/structure.md` と `docs/ja/structure.md` を更新する (after 1, 2) (→ 受入条件 AC6)
   - Directory Layout の `scripts/` を 82 → 83、`tests/` を 117 → 118 に更新
   - Key Files > Scripts > **Process management** に `scripts/resolve-batch-query.sh` の説明行を追加

## Alternatives Considered

| 案 | 内容 | 採否 |
|---|---|---|
| クエリ解決を SKILL.md 内の prose (LLM 判断) で行う | 新規スクリプトなし。`gh issue list` + jq を毎ラウンド LLM が組み立てる | **不採用**。Issue が「LLM が毎回自然言語から再解釈するのではなく機械的に評価できる形にする」と明示。ラウンド間で抽出条件がぶれると収束判定そのものが信頼できなくなる |
| ラウンドごとに新しい `BATCH_ID` を採番 | 各ラウンドが独立した List mode batch になる | **不採用**。`--batch --resume` の復旧対象が最終ラウンドのみになり、累積 completed/failed が checkpoint 上で分断される。`write_batch` が累積リストを受け取れるため単一 `BATCH_ID` で足りる |
| 安全弁を wall-clock 上限で実装 (または max-rounds と併用) | 経過時間で打ち切る | **不採用 (単独では)**。Issue は「いずれか (両方でも可)」を許容。ラウンド数のほうが「何件処理したか」と対応が取れて挙動が予測しやすく、Spec Simplicity Rules の範囲にも収まる。wall-clock は運用実績を見てからの追加候補として Notes に記録 |
| 処理済み Issue の除外を行わない | クエリ結果をそのまま毎ラウンド処理 | **不採用**。label 単独クエリ (`label:retro/*`) では完了済み Issue も再ヒットし、`--max-rounds` を使い切るまで同じ Issue を再処理し続ける。収束条件「0 件になるまで」が成立しない |
| `.tmp/until-state.json` などの seed file にラウンド状態を書き出す | ラウンド間状態を外部ファイル化 | **不採用**。#1214 が「書き込み専用の死んだ機能」として next-cycle seed を撤去した直後であり、同じ形の状態ファイルを再導入しない。既存 checkpoint の `completed` / `failed` で足りる |

## Verification

### Pre-merge

- <!-- verify: rubric "skills/auto/SKILL.mdに--batch --untilモードの条件駆動ループ(クエリ実行→List mode処理→再クエリ→空になるまで繰り返す)が実装されている" --> `skills/auto/SKILL.md` (または関連 module) に `--batch --until <query>` の処理ステップが実装されている
- <!-- verify: rubric "--untilモードにデフォルトで有効な安全弁(ラウンド数上限またはwall-clock上限)が実装されている" --> 安全弁 (max-rounds またはwall-clock上限) が既定で有効になっている
- <!-- verify: file_contains "skills/auto/SKILL.md" "--max-rounds" --> 安全弁 flag `--max-rounds` (既定値 3) が `skills/auto/SKILL.md` に定義されている
- <!-- verify: rubric "--untilモードがauto-checkpoint.shおよびL3 auto-retrospective機構をList modeから再利用しており、重複実装がない" --> 既存の checkpoint・Batch Completion Report・L3 auto-retrospective 機構が新規実装なしで再利用されている
- <!-- verify: command "bats tests/resolve-batch-query.bats" --> クエリ解決スクリプト `scripts/resolve-batch-query.sh` の bats テストが PASS する
- <!-- verify: file_contains "docs/workflow.md" "--until" --> `--until` / `--max-rounds` / `--checkin-per-round` の使用方法が `docs/workflow.md` に文書化されている

### Post-merge

- 次回 `--batch --until` を実運用で使用した際、動的に増減する対象を正しく処理し安全弁が意図通り機能することを観察 (`verify-type: opportunistic`)

## Tool Dependencies

### Bash Command Patterns

- `${CLAUDE_PLUGIN_ROOT}/scripts/resolve-batch-query.sh:*` — `--until` クエリの解決 (`skills/auto/SKILL.md` の `allowed-tools` に追加が必要)

### Built-in Tools

- なし (既存の Read / Bash / Skill で足りる)

### MCP Tools

- なし

## Uncertainty

- **project board Status field の値表記**: `status:Backlog` の照合は Status single-select の option 名との完全一致で行う。本 Spec 作成時に `gh api graphql` で Issue #1328 の Status を実測し `Backlog` が返ることを確認済み。他 option 名 (`In progress` 等、空白を含む) を使う場合は、クエリ側で `status:"In progress"` のようなクォートが必要になるが、初期実装では**空白を含む status 値を非対応**とし、パースエラー (exit 1) にする
  - **検証方法**: `tests/resolve-batch-query.bats` に「空白を含む status 値でパースエラー」のケースを含める
  - **影響範囲**: Implementation Steps 1, 2
- **`--batch --resume` で `--until` セッションを再開した場合の挙動**: 中断ラウンドの `remaining` を List mode として処理して終了し、until ループは再開しない (再開したい場合は `--batch --until` を再実行する)。これは仕様として Notes に記載し、実装で特別扱いはしない
  - **検証方法**: `docs/workflow.md` の `--until` 段落に明記する (Implementation Step 7 に含む)
  - **影響範囲**: Implementation Steps 4, 7

## Notes

### Issue 本文と既存実装の矛盾 (非対話モードで auto-resolve)

- **矛盾内容**: 元の受入条件 4 は `modules/skill-help.md` に `--until` の使用方法が文書化されていること (`file_contains "modules/skill-help.md" "--until"`) を求めていた
- **Issue 本文の記述**: 「`modules/skill-help.md` に `--until` の使用方法が文書化されている」
- **実際の実装**: `modules/skill-help.md` は 10 skill 全てが Read する汎用フォーマッタで、skill 固有の flag を一切保持しない (Processing Steps 2 が「呼び出し元 SKILL.md の body から `--` で始まる flag を抽出する」と規定)。実測でも本文中の flag は `--help` のみ、Output Format は `{flag1}` / `{flag2}` の placeholder
- **解決 (auto-resolve)**: `/auto --help` の出力は `skills/auto/SKILL.md` の frontmatter + body から生成されるため、`--until` を SKILL.md に記載すること自体が help への文書化に等しい。受入条件 4 の検証対象をユーザー向けドキュメント `docs/workflow.md` に付け替え、SKILL.md 側は受入条件 1 (rubric) と新設の受入条件 3 (`file_contains "skills/auto/SKILL.md" "--max-rounds"`) でカバーする。Issue 本文の受入条件も同内容に更新済み
  - Other candidates: `modules/skill-help.md` に `--until` の例示を追記して literal に満たす (全 skill 共有モジュールに 1 skill 固有の flag を持ち込むことになり、モジュールの設計意図に反するため不採用)

### 受入条件の追加 (非対話モードで auto-resolve)

- **`file_contains "skills/auto/SKILL.md" "--max-rounds"` を追加** — reason: 受入条件 2 の rubric が「既定値 3」という数値リテラルを含むため、`modules/verify-patterns.md` §9 の「rubric の記述が数値リテラル/定数名/閾値を含む場合は対応する `file_contains` を併記する」規則に従い、決定的な機械検証を並置した
- **`command "bats tests/resolve-batch-query.bats"` を追加** — reason: 新規スクリプトを伴う変更であり、script layer は決定的にテスト可能 (`skills/spec/skill-dev-constraints.md` § LLM-assisted Skill Phase Test Strategy の「Script layer」に該当)。ラウンドループ本体は LLM 実行部のため rubric + 構造テストで担保する

### その他の設計判断 (非対話モードで auto-resolve)

- **収束保証のための処理済み Issue 除外を追加** — reason: Issue 本文はクエリの再実行までしか規定しておらず、除外規則がない。label 単独クエリでは完了済み Issue も再ヒットするため、除外なしでは「0 件になるまで」が成立せず必ず `--max-rounds` 打ち切りになる。既存 checkpoint の `completed` / `failed` をそのまま累積集合として使い、新規実装を避けた
  - Other candidates: クエリ側に `-label:phase/done` 相当の除外句を足す (`--non-interactive` では verify が skip され `phase/verify` のまま残るため、label だけでは処理済みを表現しきれず不採用)
- **安全弁は `--max-rounds` のみ実装 (wall-clock は見送り)** — reason: Issue が「いずれか (両方でも可)」を許容。ラウンド数のほうが処理件数と対応が取れ挙動が予測しやすく、実装ステップ数も Spec Simplicity Rules に収まる。wall-clock 上限は運用実績を見てからの追加候補
  - Other candidates: 両方実装 (実装・テスト範囲が倍増し、初期値の根拠も実測にないため不採用)
- **ラウンド内の処理順序は Issue 番号昇順** — reason: Count mode の `createdAt` 降順は「新しい順に N 件だけ取る」ための順序で、全件を消化する `--until` には意味を持たない。`scripts/observation-trigger.sh` が「古い pending から」の昇順を既に採っており、その慣例に揃えた

### 既存機構の再利用範囲

- `scripts/auto-checkpoint.sh` は**変更しない**。`write_batch <BATCH_ID> <REMAINING> <COMPLETED> <FAILED>` が累積リストを受け取れるため、ラウンド開始ごとに累積 completed/failed を渡し直すだけでラウンド跨ぎ状態を保持できる
- Batch Completion Report / 観測スキャン / run-fact AC 照合 / L3 auto-retrospective は `### Batch Completion Report` 以降の既存記述をそのまま呼び出す。`ROUTE="batch"` を設定する点も List mode と同一
- frontmatter の `loop-paths-used: [A]` は変更しない。`modules/autonomy-tier.md` の L2→L1 Path Catalog は「skill (L2) から Claude Code primitive / 外部トリガ (L1) への発火経路」を指すもので、`--until` のラウンドループは skill 内部で完結する L2 内ループのため新たな path には該当しない

### 実装上の注意

- **クォート**: `--until` の値は空白を含む。`skills/auto/SKILL.md` の記述例・`docs/workflow.md` の例ともに必ずダブルクォートで囲む。#1318 (zsh の単語分割で PR 候補ループが機能しなかった事例) と同種の失敗を避けるため、`resolve-batch-query.sh` 側でも `"$UNTIL_QUERY"` を常にクォートして受け取る
- **bash 3.2 互換**: `resolve-batch-query.sh` では `mapfile` / 連想配列 / `${var,,}` を使わない。glob 一致は `case "$name" in $LABEL_PATTERN) ... esac` で行う (macOS system bash 3.2 対応)
- **read-then-write の jq guard**: 本 Spec の実装は既存 JSON を読み書きしない (`auto-checkpoint.sh` に委譲) ため、jq failure guard の追加は不要
- **bats self-reference 除外**: `resolve-batch-query.sh` は検出系スクリプトではなく、`tests/resolve-batch-query.bats` を走査対象にしないため self-reference 除外は不要
- **`WHOLEWORK_SCRIPT_DIR` mock**: `tests/run-auto-sub.bats` は `export WHOLEWORK_SCRIPT_DIR="$MOCK_DIR"` を設定するが、`resolve-batch-query.sh` は `run-auto-sub.sh` から呼ばれず親セッション (`skills/auto/SKILL.md`) からのみ呼ばれるため、`$MOCK_DIR` への mock 追加は不要

## issue retrospective

(`/issue 953 --non-interactive` のコメントから転記: https://github.com/saitoco/wholework/issues/953#issuecomment-5236558615)

### 実施内容 (非対話モード, `/issue 953 --non-interactive`)

Step 1 のコメント消費手続きで、2026-08-10 の MEMBER コメント (1件、first-class) を検出。このコメントは「テーマ駆動での Backlog 消化」というユースケースが実運用要望として具体化したことを報告し、`--max-rounds` の既定値レンジ (3〜5) と #1322 (`theme/*` label 導入) との関係を提示していた。これを Issue 本文の Background / Proposal / Related に統合した。

### Auto-Resolve 判断 (非対話モード三層ポリシー適用)

Size=L のため検出上限5件のうち、以下3件を auto-resolve した (いずれも High-Stakes Decision に該当せず、既存コードパターン・実測データから一意に推定可能と判断):

1. **`--max-rounds` 既定値を 3 に確定** — コメントが示したレンジ (3〜5) のうち、暴走防止の観点で least-risk な下限値を採用。2026-08-08 セッション (発散: 7件処理 vs 新規8件供給) と 2026-08-09 セッション (3 batch連鎖で2段収束) の実測を根拠として明記。`/spec` 側での調整余地も残した。
2. **クエリ形式に label 単独指定 (status 句省略) を許容** — #1322 のコメント例 `"label:theme/observability"` が status 句を含まないため、既存の「label + status 必須」という記述のままでは #1322 のユースケースと矛盾する。status 句を optional として明確化した。
3. **`--checkin-per-round` の名称を確定** — 「仮称」表記を削除。他に代替案が提示されておらず、コメントでも同名がそのまま使われていたため。Acceptance Criteria のテキストには影響しない変更。

### Acceptance Criteria の変更

Pre-merge / Post-merge の内容自体は変更していない (rubric ベースの4件 + opportunistic の1件を維持)。変更したのは Background / Proposal / Related セクションのみ — 具体的な `--max-rounds` の値、クエリ文法の柔軟性、#1322 との関係を明記し、`/spec` フェーズでの実装判断の土台を明確にした。

### 政策決定

- #1322 との **blocked-by は設定しない** — 両 Issue のコメントが揃って「独立着地可能」と述べているため (`gh-check-blocking.sh` も blocked-by 対象なしと判定し exit 0)。
- Priority は GitHub Projects 側で既に `high` に更新済みであることを確認 (コメントが言及した low→high の変更は本セッション開始前に反映済み)。
- Size は L のまま据え置き (`/spec` の判断で分割要否を再評価する前提は Background に既述の通り)。

## spec retrospective

### Minor observations

- `modules/skill-help.md` を検証対象に指定した受入条件が `/issue` フェーズで生成されていた。全 10 skill が Read する汎用フォーマッタに 1 skill 固有の flag を要求する形で、「その AC の検証対象ファイルは単一 skill 固有の内容を置く場所か」を確認する観点が AC 生成時に無かった
- `skills/auto/SKILL.md` Step 1 の `--batch` 検出は「`--batch` の後に numeric token が 0 個」のケースが未定義のまま残っていた。`--batch --resume` は明示分岐で救われていたが、`--batch` 直後に新フラグを置く設計は同じ穴を踏みやすい

### Judgment rationale

- 収束保証 (処理済み Issue のラウンド跨ぎ除外) は Issue 本文に一切書かれていなかったが、これが無いと「0 件になるまで繰り返す」という中心的な受入条件が構造的に成立しない (label 単独クエリでは完了済み Issue が毎ラウンド再ヒットする)。仕様の欠落ではなく前提の暗黙化と判断し、Issue 本文の Proposal に明示追記したうえで Spec に落とした
- 安全弁を `--max-rounds` 単独とした判断は、Issue が「いずれか (両方でも可)」を許容していることに加え、ラウンド数が処理件数と 1:1 で対応し運用者が挙動を予測しやすい点を重視した。wall-clock は初期値の実測根拠が無い
- クエリ解決のスクリプト分離は Spec の独自判断ではなく、Issue 本文の「LLM が毎回自然言語から再解釈するのではなく機械的に評価できる形にする」を実装レベルに翻訳した結果。ここを prose に留めるとラウンド間で抽出条件がぶれ、収束判定自体が信頼できなくなる

### Uncertainty resolution

- project board の Status field 値は設計時に `gh api graphql` で Issue #1328 に対して実測し、`Backlog` が返ることを確認した。`status:Backlog` の照合仕様を推測で書かずに済んだ
- 空白を含む Status option (`In progress` 等) は初期実装で非対応 (パースエラー) と決め、検証方法込みで Uncertainty セクションに残した。実装フェーズで仕様追加を迫られうる箇所を先に可視化している
- `.claude/settings.json.template` への新規スクリプト登録要否は、同格の 4 スクリプト (`auto-checkpoint.sh` / `scan-pending-ac.sh` / `observation-trigger.sh` / `collect-run-facts.sh`) が全て未登録であることを grep で確認して「不要」と確定した。未確認のまま「変更不要」と書かない規則 (#749) に従った

## Code Retrospective

### Deviations from Design

- N/A — Implementation Steps 1〜9 を Spec 記載順のまま実装した。ステップの入れ替え・省略・統合は発生していない

### Design Gaps/Ambiguities

- なし。Uncertainty セクションで既に洗い出されていた 2 点 (Status 値の空白非対応、`--batch --resume` の再開範囲) は実装時に追加確認を要さなかった

### Rework

- `tests/resolve-batch-query.bats` の `status resolution failure` / `query with whitespace` の 2 テストで、bats の `run` がデフォルトで stdout+stderr を `$output` に合流させることを見落とし、fail-closed 警告 (stderr) を含む出力を等価比較して初回 FAIL した。`run --separate-stderr` (既存 `tests/check-allowed-tools.bats` と同じパターン) に切り替えて解消した — 新規スクリプトが stderr に warning を出す設計そのものは変更していない

### Judgment rationale (実装フェーズでの追加判断)

- **Steering Docs sync candidate は不採用** — `docs/product.md` § Terms の `/auto` 行は List mode (`--batch N1 N2 ...`) 導入時も追記されなかった前例があり (grep で確認: 同行は `--batch N` の説明のみ)、この Terms エントリは `--batch` の全バリアントを網羅する設計になっていない。同じ理由で `--until` も追記しないと判断し、`docs/product.md` / `docs/ja/product.md` は変更しなかった。`docs/guide/autonomy.md` の L2 節も「手動トリガーの例示」のみで flag 網羅の趣旨ではないため同様に不採用とした
- **`tests/post_merge_check.bats` の並列実行フレークは対応しない** — Behavioral Change Detection により `bats --jobs 18 tests/` を実行したところ `not ok 877 fail: gh issue reopen called when FAIL input given` が再現 (2 回とも同一テスト)。単体実行 (`bats tests/post_merge_check.bats`) では PASS するため `--jobs` 並列実行時のみのテスト分離不足と判断。`git diff origin/main -- tests/post_merge_check.bats scripts/post_merge_check.sh` で本ブランチが同ファイルを一切変更していないことを確認し、既存 Issue #1308 (`tests/post_merge_check.bats: bats --jobs 並列実行時に 2 件 FAIL するフレークを解消`) と重複するため新規 Follow-up Issue の起票をスキップした (Duplicate check 手順に従い #1308 を参照)

## review retrospective

### Spec vs. implementation divergence patterns

- Spec の `## Uncertainty` セクションが明示的に要求していた bats テストケース (「空白を含む status 値でパースエラー」) が実装フェーズで欠落していた。Code Retrospective は「Uncertainty セクションで既に洗い出されていた 2 点は実装時に追加確認を要さなかった」と記載していたが、実際には該当テストケースが存在せず、Spec の明示的なマンデートと実装結果に乖離があった。動作自体は正しかった (`*)` アームへの偶発的フォールスルーで exit 1 になる) が、regression-unprotected な状態だった。review-spec エージェントが Spec 本文を直接参照して検出した — Code フェーズの自己申告 (Retrospective の「なし」記載) だけでは拾えない典型例

### Recurring issues

- 新規スクリプト `resolve-batch-query.sh` で「サイレント失敗が成功/収束と区別できない」パターンが 1 ファイル内に複数箇所 (stderr の JSON への混入、リダイレクト内コマンド置換の exit status 無視、`shift 2` の値なし失敗) 出現した。fail-closed 設計を明示的に header で謳うスクリプトほど、個々の失敗パスの exit status 伝播を丁寧に扱う必要がある — 新規スクリプト作成時のチェックリスト項目として持つ価値がある
- `### Until mode` が List mode を「steps 1-7 unchanged」と限定的に参照したことで、List mode の numbered steps の外側にある前提ブロック (stop-at 設定ロード) が漏れた。対照的に `### Resume mode` は List mode セクション全体を無限定で参照しており、この漏れを踏んでいない。既存モードの一部だけを prose で再利用する設計をとる際は、対象範囲外に prerequisite block がないか確認する一手間が要る

### Acceptance criteria verification difficulty

- rubric 系 AC 4 件はいずれも UNCERTAIN なく明確に PASS 判定でき、verify command の記述品質は良好だった
- `command "bats tests/resolve-batch-query.bats"` という AC の書き方は「既存テストが全て PASS する」ことしか検証せず、「Spec が要求する特定のテストケースが実際に存在する」ことまでは保証しない。今回のような Spec-mandated だが未実装のテストケースを AC 側で機械的に検出する手段がなく、review エージェントの目視確認に依存した。次回以降、Spec の Uncertainty セクションが特定のテストケースを明示的に要求する場合は、AC 側にも `grep`/`file_contains` などでそのテストケース名の存在を確認する verify command を追加検討する余地がある

## Phase Handoff
<!-- phase: merge -->

### Key Decisions

- Pre-merge AC ゲート (6 件) は全て `[x]` 済み、review_incomplete_fallback も検出されず (Review Response Summary を organic に検出)。追加のオーバーライド確認なしでマージ可能と判定した
- `gh-pr-merge-status.sh` が `mergeable=true reason=clean ci_status=success review_status=approved` を返したため、conflict 解決 (Step 3) はスキップし直接 squash merge を実行した
- `gh pr merge 1333 --squash --delete-branch` を実行し正常完了。base branch は main のため `closes #953` により Issue は自動クローズされる想定

### Deferred Items

- CONSIDER 級の 3 件 (shift 2 のサイレント失敗、docs/product.md の status: 未文書化、ROUND_LIST 区切り文字の prose 不整合) は review フェーズから未対応のまま持ち越し。将来 Follow-up Issue 化するかは運用実績次第
- Spec の Deferred Items (wall-clock 上限、`--batch --resume` の until ループ非再開、空白を含む status 値非対応) は変更なし
- `tests/post_merge_check.bats` の並列実行フレークは既存 Issue #1308 に委ねたまま (無関係、対応不要)

### Notes for Next Phase

- Post-merge AC (opportunistic) は次回 `--batch --until` 実運用時に `/verify` が観察する。それまで `- [ ]` のまま
- Issue #953 の状態遷移 (CLOSED + `phase/verify` label) を Step 6 のフォールバックで確認すること

## Verify Retrospective

### Phase-by-Phase Review

#### spec

- Pre-merge AC 6件は `/spec`〜`/review` の各フェーズで前倒し確認され、`/verify` 実行時点で全て `[x]` 済みだった。rubric 系 AC の記述品質が高く、`/verify` 側での再判定に UNCERTAIN が一切発生しなかった

#### design

- 収束保証 (処理済み Issue のラウンド跨ぎ除外) は Issue 本文に明記されていなかった暗黙の前提を `/spec` が明示化した判断が妥当だった。「0件になるまで繰り返す」という中心的な受入条件は、除外ロジックなしには構造的に成立しないため

#### code

- Implementation Steps は Spec 記載順のまま逸脱なく実装され、Rework は bats の `run` が stdout/stderr を合流させる仕様の見落とし1件のみ (`run --separate-stderr` で解消、既存パターンの再利用)

#### review

- review-spec エージェントが Spec 本文の明示的マンデート (空白を含む status 値のテストケース) と実装の乖離を検出した一方、Code Retrospective の自己申告 (「追加確認を要さなかった」) では拾えていなかった。第三者視点によるレビューが自己申告のギャップを補完した好例
- 新規スクリプト `resolve-batch-query.sh` で「サイレント失敗が成功と区別できない」パターンが1ファイル内に複数箇所検出された。fail-closed を謳うスクリプトほど個々の失敗パスの exit status 伝播を丁寧に扱う必要がある

#### merge

- Pre-merge AC ゲート・CI・review 承認状態がすべて clean で、コンフリクト解決なしに直接 squash merge が完了した。特筆すべき問題は発生していない

#### verify

- Pre-merge 6件は SKIPPED (already checked)、FAIL/UNCERTAIN は0件。Post-merge の opportunistic 条件1件は本実行のスコープ外 (実運用待ち) のため `phase/verify` を維持し Issue はクローズ済みのまま据え置いた

### Improvement Proposals

- **AC の `command` 検証が「Spec が明示要求する特定テストケースの存在」まで保証しない** — `command "bats tests/resolve-batch-query.bats"` のような書き方は「既存テストが全て PASS する」ことしか検証せず、Spec の `## Uncertainty` セクションが個別テストケースを明示要求していても、そのケースが実際に実装されているかは AC 側で機械的に検出できない。今回は review エージェントの目視確認で捕捉できたが、目視に依存する設計は再発しうる。Spec の Uncertainty が特定テストケース名を明示する場合、AC 側にも `grep`/`file_contains` でそのテストケース名の存在を確認する verify command を追加する運用ガイドを検討する余地がある (対象: `docs/workflow.md` または AC 作成時のガイダンス)
- **新規スクリプト作成時の「サイレント失敗チェックリスト」が存在しない** — fail-closed 設計を謳う新規スクリプトで、stderr への JSON 混入・リダイレクト内コマンド置換の exit status 無視・`shift` の値なし失敗、といった複数のサイレント失敗パターンが1ファイル内に同時発生した。新規スクリプト作成時にこれらのパターンを機械的にチェックするガイド/チェックリストがあれば review フェーズでの検出漏れリスクを下げられる可能性がある
