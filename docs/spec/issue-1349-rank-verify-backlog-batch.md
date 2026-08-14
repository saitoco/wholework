# Issue #1349: audit: phase/verify backlog をランキング選抜してバッチ verify するコマンドを追加

## Overview

`phase/verify` backlog (300 件超) を能動的に消化する経路が存在しない (既存の opportunistic-verify は副産物依存、observation dispatch はイベント駆動 + 頭打ち)。2026-08-10〜11 の手動試行 (unchecked AC のうち verify command 付きの件数でランキング → 上位 10 件ずつ選抜 → `/verify` 順次実行、計 4 バッチ) が高い `phase/done` 到達率を示したため、この選抜ロジックをスクリプト化し、再現可能なコマンドとして提供する。

具体的には (1) `phase/verify` ラベル付き Issue (state=all) の未チェック Post-merge AC を verify command 有無でスコアリングし上位 N 件を出力するランキングスクリプト、(2) その出力を受けて `wholework:verify` skill を順次実行する `/audit` 新規サブコマンド、の 2 点を実装する。

## Changed Files

- `scripts/rank-verify-backlog.sh`: 新規ファイル — ランキング選抜スクリプト
- `tests/rank-verify-backlog.bats`: 新規ファイル — 上記スクリプトの bats テスト
- `skills/audit/SKILL.md`: `verify-backlog` サブコマンドを追加 (Command Routing / Usage / 新セクション / `description:` frontmatter / `allowed-tools` frontmatter)
- `docs/structure.md`: Scripts 一覧 (Project utilities) に `rank-verify-backlog.sh` を追加。Directory Layout の `scripts/ (86 files)` を `(87 files)` に更新 [Steering Docs sync candidate]
- `docs/workflow.md`: `/audit` の説明段落に `verify-backlog` サブコマンドの一文を追加 [Steering Docs sync candidate — `/audit` の全サブコマンドを列挙する段落が既に存在し、`skills/audit/SKILL.md` の `description:` と同期している]
- `docs/guide/workflow.md`: `/audit` コマンド一覧 (コードフェンス) に `/audit verify-backlog` の行を追加 [Steering Docs sync candidate — 既存一覧は `progress`/`auto-session` が未掲載という先行 drift があるが、本 Issue のスコアではないため放置し、自分の追加分のみ反映する]
- `docs/ja/structure.md`: `docs/structure.md` 変更分の日本語ミラー同期 (`docs/translation-workflow.md` 準拠)
- `docs/ja/workflow.md`: `docs/workflow.md` 変更分の日本語ミラー同期 (`docs/translation-workflow.md` 準拠)

## Implementation Steps

1. `scripts/rank-verify-backlog.sh` を新規作成する (→ 受入条件 AC1, AC2, AC3)。仕様:
   - Usage: `scripts/rank-verify-backlog.sh [--top N] [--limit L]`。`--top`: 出力する Issue 件数 (デフォルト `10`)。`--limit`: `gh issue list` のページサイズ (デフォルト `500`。`scan-pending-ac.sh` と同じ規約で、取得件数が `--limit` に達した場合は stderr に警告)。不正な引数は exit 1。
   - `gh issue list --label "phase/verify" --state all --json number,body --limit "$LIMIT"` で対象 Issue を取得 (`scan-pending-ac.sh` と同じ `--state all` 規約)。`gh` 失敗時は fail-open (stdout 空、exit 0)。
   - 各 Issue の body を AWK で走査し、`### Post-merge` / `## Post-merge` 見出しの次行から次の `^## ` / `^### ` 見出し直前までを対象区間とする (`scan-pending-ac.sh` と同じ区間規約)。
   - **コードフェンス除外 (AC2)**: 区間内・区間外を問わず、`^[ \t]*```` にマッチする行で `in_fence` フラグをトグルする。`in_fence` が真の間は行内容の判定を一切行わない (checkbox 行としてもカウントしない)。これは `check-pre-merge-ac.sh` / `scan-pending-ac.sh` の既存グローバル index 実装には無い挙動であり、#1071 (未実装、OPEN) が目指す checkbox 列挙全体のインデックス解決とは別問題 — 本スクリプトは特定 Issue に対する global index を返さず件数の集計のみ行うため、#1071 のインデックス解決ロジックへの依存は不要。#1071 が先に着地した場合は、本スクリプトのコードフェンス除外を #1071 の共有 SSoT ルールに置き換えることを検討する (Notes 参照)。
   - 対象区間内・`in_fence` が偽の `^- \[ \]` (未チェック) 行について、行内に `<!--[ \t]*verify:` (正規表現) がマッチするかどうかで2値分類する:
     - マッチする → `auto_count` を加算 (`<!-- verify-type: observation -->` 等のタグが同一行に併記されていても、`<!-- verify: ... -->` が存在する限り auto 側に計上する — `l0-surfaces.md` の Option B 形式 (`<!-- verify-type: observation event=... --> <!-- verify: rubric "..." -->`) がこのケースに該当する。`scan-pending-ac.sh` / `collect-verify-retention-stats.sh` の `verify-type` タグ優先の4値分類 (`vtype`) とは別基準であり、それらの流用ではなく本スクリプト独自の2値判定を実装する)
     - マッチしない → `manual_count` を加算
   - Issue ごとに `auto_count` を集計し、`auto_count` 降順 (同数は Issue 番号昇順) でソート、上位 `--top` 件に切り詰める。
   - stdout: 切り詰め後の Issue 番号のみを1行1件、ランク順に出力 (`observation-trigger.sh` と同じ stdout contract — 他の出力を混在させない)。stderr: Issue ごとの `#<N>: auto=<auto_count> manual=<manual_count>` 形式のスコア明細 (デバッグ・透明性用)。
   - bash 3.2+ 互換 (`mapfile` 不使用)。

2. `tests/rank-verify-backlog.bats` を新規作成する (after 1) (→ 受入条件 AC1, AC2, AC3)。`scan-pending-ac.bats` / `tests/run-fact-matching.bats` と同じ `gh` モック規約 (`PATH` 経由でモック `gh` を差し込み、`gh issue list` 呼び出しに対して固定 JSON を返す) を使う。最低限のケース:
   - 2 Issue (auto_count が異なる) を与え、ランキング順 (auto_count 降順) で出力されることを確認
   - Post-merge 区間内に code fence (` ``` ` で開始・終了) を含む Issue body を与え、フェンス内の `- [ ]` サンプル行 (#709 相当の再現ケース: フェンス内に `<!-- verify: ... -->` を含む sample checkbox 行を配置) が auto_count・manual_count のいずれにもカウントされないことを確認 (AC2 の回帰テスト)
   - `--top` 指定件数で出力が切り詰められることを確認
   - `<!-- verify-type: observation --> <!-- verify: rubric ... -->` の併記行が auto_count に計上されることを確認 (Option B 形式)
   - `gh` 失敗時に空出力・exit 0 で fail-open することを確認

3. `skills/audit/SKILL.md` に `verify-backlog` サブコマンドを追加する (after 1) (→ 受入条件 AC4)。
   - **Command Routing**: `If ARGUMENTS is \`premise\` or starts with \`premise\`...` の行の直後に以下を追加:
     `If ARGUMENTS is \`verify-backlog\` or starts with \`verify-backlog\` (e.g., \`verify-backlog --top 10\`): execute the "verify-backlog Subcommand" section and exit.`
   - **Usage 行**: `Usage: /audit [drift|fragility|stats|progress <XL-parent>|auto-session <session-id>|premise] ...` の角括弧内に `verify-backlog` を追加し、オプション列挙に `[--top N]` を追加する。
   - **新セクション**: `## premise Subcommand` セクションの直後に `## verify-backlog Subcommand` を新設する。内容:
     1. Option Parsing: ARGUMENTS から `--top N` を抽出 (デフォルト `10`)。
     2. `bash ${CLAUDE_PLUGIN_ROOT}/scripts/rank-verify-backlog.sh --top $TOP` を実行し、stdout (Issue 番号、1行1件、ランク順) を `ISSUE_NUMBERS` として取得する。
     3. `ISSUE_NUMBERS` が空の場合、"No ranked verify-backlog candidates found." と出力して終了する。
     4. `ISSUE_NUMBERS` の各番号 `$N` について、ランク順に `Skill(skill="wholework:verify", args="$N")` を順次呼び出す (`--session-id` は付与しない — `/verify` は単体実行で自己解決するため不要。`skills/auto/SKILL.md` の observation dispatch と同じ順次呼び出しパターン)。
     5. 全件処理後、処理した Issue 番号一覧と `gh issue list --label phase/done -- ` 等による簡易な到達状況サマリを出力する。
   - **`description:` frontmatter**: 既存の `/audit premise` の説明文の直後に、`/audit verify-backlog [--top N]` の一文を追加する (`rank-verify-backlog.sh` でランキング選抜した上位 N 件の `phase/verify` Issue に対して `wholework:verify` を順次実行する旨)。
   - **`allowed-tools` frontmatter**: `Bash(...)` 内に `${CLAUDE_PLUGIN_ROOT}/scripts/rank-verify-backlog.sh:*` を追加する。トップレベルのツール一覧に `Skill` を追加する (現状の `allowed-tools` には `Skill` が含まれておらず、このサブコマンドが初めて `/audit` から他 skill を呼ぶケースになるため新規追加が必須 — `validate-skill-syntax.py` の `BODY_TOOL_CHECK_SKIP` に `Skill` が含まれるため CI の自動検出では検知されない箇所であり、実装時に見落とさないこと)。

4. ドキュメント同期を行う (after 3):
   - `docs/structure.md`: `### Scripts` > `Project utilities:` の `scripts/scan-pending-ac.sh` の行の直後に `scripts/rank-verify-backlog.sh` の1行説明を追加する。Directory Layout の `scripts/ (86 files)` を `(87 files)` に更新する (`tests/ (122 files)` は現状の実カウント 121 に本 Issue の追加分 1 を加えると 122 で既存表記と一致するため変更不要)。
   - `docs/workflow.md`: `### \`/audit\` — Drift and Fragility Detection` 段落の `/audit premise` を説明する文の直後・"Details:" リンクの直前に、`/audit verify-backlog` の一文を追加する。
   - `docs/guide/workflow.md`: `/audit premise` の行の直後に `/audit verify-backlog [--top N]  # rank phase/verify backlog and batch-run /verify` の行を追加する。
   - `docs/ja/structure.md` / `docs/ja/workflow.md`: 上記2ファイルの変更分を日本語で反映する (`docs/translation-workflow.md` の Sync Procedure に従う。コードフェンス数の一致を確認)。

## Verification

### Pre-merge

- <!-- verify: rubric "phase/verify ラベル付き Issue (state=all) を取得し、各 Issue の未チェック Acceptance Criteria のうち verify command (`<!-- verify: ... -->`) が付与されている件数と、manual/no-verify-command である件数をスコアリングして、auto-checkable な件数が多い順に上位N件を出力するスクリプトが実装されている" --> ランキング選抜スクリプトが実装されている
- <!-- verify: rubric "ランキング選抜スクリプトが、Issue本文中のコードフェンス (```) 内に含まれるチェックボックス様の文字列 (- [ ] 等) を実際の Acceptance Criteria としてカウントしない" --> コードフェンス内の偽陽性チェックボックスを除外する処理が実装されている (本試行の #709 で実際に踏んだ誤検出パターン)
- <!-- verify: rubric "選抜件数 N がコマンドライン引数または同等の方法で指定可能になっている" --> 選抜件数が可変である
- <!-- verify: rubric "ランキング選抜の出力 (Issue番号リスト) を受け取り、各 Issue に対して順次 wholework:verify skill を実行するエントリポイント (skill またはラッパースクリプト) が実装されている" --> 選抜結果を順次 verify するエントリポイントが実装されている

### Post-merge

- 実際の `phase/verify` backlog に対して本コマンドを実行し、選抜された候補が手動選抜時と同程度の `phase/done` 到達率を示すことを観察する <!-- verify-type: opportunistic -->

## Notes

- **#1071 との関係 (Issue コメントより)**: #1071 (「fenced code block 内の checkbox を AC 列挙から除外」、OPEN・未実装) は checkbox 列挙全体の global index 解決 (`gh-issue-edit.sh --checkbox` 等) を対象とする別問題であり、本 Issue のスコープ (件数集計のみ、index 解決なし) とは重なるが同一ではない。#1071 が本 Issue より先に着地し `modules/` 配下に共有除外ルールが定義された場合、`rank-verify-backlog.sh` のフェンス除外実装をそれに合わせてリファクタリングすることを検討する (現時点では #1071 未着地のため独自実装する)。
- **AC1 rubric 文字列内の入れ子コメントについて**: AC1 の rubric 引数には説明目的で `` `<!-- verify: ... -->` `` という文字列がそのまま埋め込まれており、厳密な「最初の `-->` で閉じる」パーサでは outer コメントが意図せず早期終端する構造になっている。本スクリプトは `<!--[ \t]*verify:` の**存在有無のみ**を判定する (コマンド引数を抽出しない) ため、この入れ子は判定結果に影響しない。
- `--top` のデフォルト値 10、`--limit` のデフォルト値 500 は、Issue Background に記載の手動試行 (上位10件ずつ) および現行 backlog 規模 (300件超) を踏まえた初期値。
- `docs/guide/workflow.md` の `/audit` コマンド一覧は `progress` / `auto-session` サブコマンドが既に未掲載という先行 drift があるが、本 Issue の変更範囲外のため追補しない (将来 `/audit drift` が検出することを期待する)。

## Consumed Comments

- saito / MEMBER / first-class / #1071 (fenced code block 内 checkbox 除外) との重複可能性を指摘。#1071 が先行着地した場合は本 Issue の実装をそのロジックに寄せるよう `/spec` でのスコーピングを依頼 (do not auto-close) / https://github.com/saitoco/wholework/issues/1349#issuecomment-5252687982
