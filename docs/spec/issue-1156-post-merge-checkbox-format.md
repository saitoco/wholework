# Issue #1156: issue/verify: Post-merge 条件のチェックボックス形式を強制し解決不能条件による phase/verify 永久滞留を防ぐ

## Consumed Comments

cutoff (最新の `phase/*` ラベル付与時刻) は `2026-08-06T01:33:03Z`。

| login | authorAssociation | trust tier | 意図要約 | URL |
|-------|-------------------|-----------|---------|-----|
| saito | MEMBER | first-class | issue retrospective — Background の技術的主張 (`/verify` Step 8b/8c の SKIPPED 判定、Step 11(a) の phase/verify 維持ロジック、`skills/issue/SKILL.md` L75/L83/L213 の記述) を実装と突き合わせ確認済み。AC2 の検出対象を `verify-type` マーカー行限定から `### Pre-merge` / `### Post-merge` 配下の条件行全般に拡大した判断根拠を記録 (Issue 本文の "Auto-Resolved Ambiguity Points" に反映済み)。Post-merge observation AC に `session=next` を追加した理由も記録 (本 Issue が `skills/issue/SKILL.md` を変更対象とするため) | https://github.com/saitoco/wholework/issues/1156#issuecomment-5199402284 |

上記コメントの内容は既に Issue 本文に反映済みであり、本 Spec の設計に対する追加の意思決定は不要だった。

### code フェーズ (cutoff: 2026-08-06T02:06:32Z)

No new comments since last phase.

## Overview

`/issue` が生成する Post-merge 条件が、チェックボックス形式 (`- [ ]`) ではなくプレーン箇条書き (`- `) で書かれるケースが過去に 10 件発生した (2026-06-19〜07-13)。`verify-type` マーカーは正しく付与されるため条件文としては成立するが、チェックを入れる先のチェックボックス自体が存在しないため、`/verify` が PASS 判定してもその結果を記録できず、Issue は CLOSED のまま `phase/verify` に永久滞留する。`skills/issue/SKILL.md` の AC 生成規約にはチェックボックス形式を明示的に要求する記述がなく、これを機械的に強制するガードも存在しない。

本 Spec では、(1) `skills/issue/SKILL.md` の AC 生成規約にチェックボックス形式の明記を追加し、(2) 新規スクリプト `check-ac-checkbox-format.sh` による機械検出を `/issue` Step 4 に組み込み、(3) 既存の未解決 3 件 (#734 / #735 / #1006) を処理する。設計は、直近の類似修正である #1168 (`check-skill-change-observation-ac.sh` の追加、warn-only 機械チェックを `/issue` Step 4 に組み込む同型パターン) を踏襲した。

## Reproduction Steps

1. `/issue` が Post-merge 条件を `verify-type: manual` または `verify-type: observation` タグ付きのプレーン箇条書き (`- text <!-- verify-type: ... -->`) として生成する — `skills/issue/SKILL.md` Step 4 にはチェックボックス形式 (`- [ ] text <!-- verify-type: ... -->`) を要求する規約もガードも存在しない。
2. Issue が code→review→merge を経て `phase/verify` に到達する。
3. `/verify` はプレーン箇条書きの行を条件文として解釈するが、チェックを入れる先のチェックボックスが存在しない。`scripts/check-pre-merge-ac.sh` の `^- \[[ xX]\]` パターンや同種の下流処理からは、この行が AC として一切見えない。
4. `/verify` Step 11(a) は「未解決の observation/manual 条件が残る」と判断し `phase/verify` を維持する。
5. Issue は永久に `phase/verify` に滞留する — CLOSED 状態のまま、チェックを入れる先が存在しないため。

## Root Cause

`skills/issue/SKILL.md` Step 4 (`Classify Acceptance Criteria and Assign Verify Commands`) は Post-merge 条件に `verify-type` タグを割り当てる手順を規定するが、条件行自体がチェックボックス形式でなければならないという規約を明文化していない。L717-737 の「Standard Format」テンプレートは `- [ ]` を例示するのみで拘束力を持たず、LLM 駆動の生成過程でプレーン箇条書きへ drift しうる。一度この形式で Issue 本文に書き込まれると、チェックボックスベースの下流処理 (`check-pre-merge-ac.sh`、`/audit stats --retention` の verify-type breakdown、`gh-issue-edit.sh --checkbox`) から一切不可視になり、プログラム的にチェックする手段が存在しなくなる。

## Changed Files

- `scripts/check-ac-checkbox-format.sh`: new file — bash 3.2+ compatible。Issue 本文の `### Pre-merge` / `### Post-merge` セクション配下でチェックボックス形式でない条件行 (プレーン箇条書き) を機械検出する
- `tests/check-ac-checkbox-format.bats`: new file — 上記スクリプトの bats テスト
- `skills/issue/SKILL.md`: `### Step 4: Classify Acceptance Criteria and Assign Verify Commands` の末尾 (「BRE metacharacter detection in verify commands」の直後、`### Step 5` の直前) にチェックボックス形式規約 + 機械検出サブステップを追加。frontmatter `allowed-tools` の `Bash(...)` に `${CLAUDE_PLUGIN_ROOT}/scripts/check-ac-checkbox-format.sh:*` を追加
- `tests/issue.bats`: Step 4 が新規則・新スクリプト名を含むことを検証する content-assertion `@test` を 1 件追加
- `docs/structure.md`: **Tooling:** の `check-skill-change-observation-ac.sh` 行の直後に `check-ac-checkbox-format.sh` の 1 行を追加。Directory Layout の `scripts/ ... (69 files)` を `(74 files)` に更新 (Steering Docs sync candidate — 詳細は Notes)
- `docs/ja/structure.md`: [translation sync] 上記 2 箇所の日本語版を追加・更新 (`docs/translation-workflow.md` の同期手順に従う。既存の全角括弧スタイルに合わせる)

**外部 GitHub 操作 (リポジトリファイルではない):**
- Issue #734 本文: Post-merge のプレーン箇条書きを `- [ ]` チェックボックス形式に修正
- Issue #735 本文: Post-merge のプレーン箇条書きを `- [ ]` チェックボックス形式に修正

**変更不要と確認済み (grep/gh issue view 実施):**
- Issue #1006 本文: Post-merge 条件は investigation 時点で既にチェックボックス形式 (`gh issue view 1006` で確認済み) — 詳細は Notes
- `scripts/scan-pending-ac.sh` / `scripts/check-pre-merge-ac.sh` / `scripts/apply-run-fact-match.sh` / `scripts/get-auto-session-report.sh` / `scripts/opportunistic-search.sh`: いずれも `^- \[[ xX]\]` 形式のチェックボックス行を正しくパースしており、スクリプト自体にバグはない。AC1/AC2/AC3 でソースデータを修復すれば変更不要 (詳細は Notes)
- `docs/environment-adaptation.md` Extension Guide: 非該当 — 新しい `<!-- verify: ... -->` コマンドタイプの追加ではなく、`/issue` Skill 内部の手続き的チェック
- `modules/verify-classifier.md`: 非該当 — 本修正は markdown チェックボックス構文の問題であり `verify-type` タグの意味論とは無関係

## Implementation Steps

1. `scripts/check-ac-checkbox-format.sh` と `tests/check-ac-checkbox-format.bats` を新規作成する (→ 受け入れ条件2)
   - スクリプト仕様: 第 1 引数に Issue 本文の Markdown ファイルパスを受け取る。`### Pre-merge` / `### Post-merge` を見出しプレフィックス一致で検出し、次の `##`/`###` 見出しまでを対象セクションとする (`scripts/check-pre-merge-ac.sh` の awk セクション追跡と同じ方式)。対象セクション内で `- ` から始まるがチェックボックス形式 `^- \[[ xX]\]` に一致しない行を検出する。`verify-type:` マーカーの有無に関わらず検出対象とする
   - exit code (exhaustive): `0` — `### Pre-merge` / `### Post-merge` セクションが存在しない、またはセクション内の全条件行がチェックボックス形式。`1` — usage error (引数欠落、またはファイルが読めない)。`2` — チェックボックス形式でない行を 1 件以上検出 (該当行を 1 行 1 件で stdout へ)
   - `set -euo pipefail` + `#!/usr/bin/env bash` で開始し、`scripts/check-skill-change-observation-ac.sh` のヘッダコメント形式 (Usage / Exit codes) を踏襲する。bash 3.2+ 互換 (`mapfile` / 連想配列を使わない、`awk` と `[[ ]]` のみ)
   - テストケース (`tests/check-skill-change-observation-ac.bats` の構成に揃える、exhaustive): 全条件がチェックボックス形式 → exit 0 かつ出力なし / Post-merge 配下のプレーン箇条書き → exit 2 かつ該当行が出力 / Pre-merge 配下のプレーン箇条書き → exit 2 かつ該当行が出力 / `verify-type` マーカーが一切ないプレーン箇条書き → exit 2 (AC2 の「マーカーの有無によらず検出」要件を確認) / `### Pre-merge` / `### Post-merge` セクションが本文に存在しない → exit 0 / `- [x]` (チェック済み) は誤検出しない / セクション終端 (次の `##`/`###` 見出し) の外側のプレーン箇条書きは検出しない / 引数なし・存在しないパス・ディレクトリパス → いずれも exit 1
   - self-reference 除外は不要: 本スクリプトは引数で渡されたファイルのみを走査しリポジトリ全体を grep しないため、bats fixture が検出対象に混入する経路が存在しない (`check-skill-change-observation-ac.sh` と同じ理由)

2. `skills/issue/SKILL.md` を更新する (after 1) (→ 受け入れ条件1, 受け入れ条件2)
   - 挿入位置: `### Step 4: Classify Acceptance Criteria and Assign Verify Commands` の「BRE metacharacter detection in verify commands」の例示コードブロックの直後、`### Step 5: Clarification Questions` の直前
   - 追加するサブステップの要旨: 「`### Pre-merge (auto-verified)` / `### Post-merge` 配下の条件行は必ず `- [ ]` (または既にチェック済みの場合 `- [x]`) から始まらなければならず、プレーン箇条書き (`- `) は不可」という規約を明記する (Pre-merge / Post-merge 両セクション対象、`verify-type` マーカーの有無によらない — Issue 本文の Auto-Resolved Ambiguity Points の判断に整合)。理由として、下流処理 (`/verify`、`check-pre-merge-ac.sh`、`/audit stats --retention`) が `^- \[[ xX]\]` でパースするため、プレーン箇条書きは永久に不可視になり `phase/verify` 滞留を引き起こす (#1156) ことを記す
   - 機械検出: Issue 本文を `.tmp/issue-body-check.md` に書き出す (直前の "Skill self-update propagation check" サブステップが使う固定ファイル名を再利用 — New Issue Creation 経路では Issue 未作成で `$NUMBER` が未束縛のため、`$NUMBER` を含むファイル名は使わない) 。次を実行する:
     ```bash
     ${CLAUDE_PLUGIN_ROOT}/scripts/check-ac-checkbox-format.sh .tmp/issue-body-check.md
     ```
     exit 2 のときは出力された行を警告として提示し、各行の箇条書きマーカー直後に `[ ] ` を挿入 (`- ` → `- [ ] `) してから本文を更新する。exit 1 は warn-only として扱い処理を継続する。処理後に一時ファイルを削除する: `rm -f .tmp/issue-body-check.md`
   - 既存 Issue 精錬経路への伝播: `### Step 7: Classify Acceptance Criteria and Assign Verify Commands` (Existing Issue Refinement) は「New Issue Creation → Step 4 の手順に従う」と参照しているため、Step 4 への追加のみで両経路がカバーされる (#1168 と同型の委譲構造)。Step 7 側の文言修正は不要
   - frontmatter `allowed-tools` の `Bash(...)` リストに、既存の `${CLAUDE_PLUGIN_ROOT}/scripts/check-skill-change-observation-ac.sh:*` の直後として `${CLAUDE_PLUGIN_ROOT}/scripts/check-ac-checkbox-format.sh:*` を追加する (`scripts/check-allowed-tools.sh` の SKILL.md 本文 ↔ allowed-tools 差分検出のため必須)
   - SKILL.md 本文制約: 半角 `!` を使わない / Step 番号は整数のみ / トリプルバッククォートはコードフェンス内のみ

3. `tests/issue.bats` に content-assertion テストを 1 件追加する (after 2) (→ 受け入れ条件1, 受け入れ条件2)
   - 既存の `@test "issue skill Step 4 documents skill self-update propagation check"` の直後に追加し、Step 4 本文が `check-ac-checkbox-format.sh` と、規約文中のキーワード (例: チェックボックス形式を表す一意な文字列) の両方を含むことを、既存テストと同じ `grep -q '<keyword>' "$PROJECT_ROOT/skills/issue/SKILL.md"` パターンで検証する

4. `docs/structure.md` と `docs/ja/structure.md` を更新する (after 1) (→ SHOULD レベルのドキュメント同期)
   - `docs/structure.md`: **Tooling:** の `scripts/check-skill-change-observation-ac.sh` 行の直後に、`scripts/check-ac-checkbox-format.sh` の説明行 (役割 + `skills/issue/SKILL.md` Step 4 から warn-only で呼び出される旨) を追加。Directory Layout の `scripts/ ... (69 files)` を `(74 files)` へ更新 (実測 73 件 + 本 Issue の新規 1 件。既存の "69" は本 Issue の変更前から既に stale だった — 詳細は Notes)
   - `docs/ja/structure.md`: 上記 2 箇所の日本語版を `docs/translation-workflow.md` の同期手順に従って追加・更新する。ファイル件数注記は既存の全角括弧スタイル (`（74 ファイル）`) に合わせる

5. Issue #734 と #735 の Post-merge チェックボックス形式を修正する (1-4 と並行実行可) (→ 受け入れ条件3)
   - 外部 GitHub Issue 本文編集 (リポジトリファイルではない)。#734, #735 それぞれについて: `gh issue view <N> --json body --jq '.body'` で本文を取得し、唯一の Post-merge プレーン箇条書き行の箇条書きマーカー直後に `[ ] ` を挿入する (`<!-- verify-type: manual -->` タグを含む行末までそのまま保持)。更新後の本文全体を `.tmp/issue-body-<N>-fix.md` に Write ツールで書き出し、`${CLAUDE_PLUGIN_ROOT}/scripts/gh-issue-edit.sh <N> .tmp/issue-body-<N>-fix.md` で適用し、一時ファイルを削除する
   - チェックは未チェック (`- [ ]`) のまま維持する — 条件文自体 (「次回 ... で regression が test で検出されることを観察」) はまだ観測されていないため、書式修正のみを行い状態は変更しない
   - #1006 は変更不要 (詳細は Notes)

## Verification

### Pre-merge

- <!-- verify: rubric "skills/issue/SKILL.md に、### Pre-merge / ### Post-merge セクション配下の受け入れ条件行がチェックボックス形式 (- [ ]) で始まらなければならない旨の規約が明記されている" --> AC 行のチェックボックス形式が `/issue` の規約として明記されている (Pre-merge / Post-merge 両セクション対象)
- <!-- verify: rubric "### Pre-merge / ### Post-merge セクション配下の受け入れ条件行がチェックボックス形式 (- [ ]) で始まることを機械的に検証する仕組み (スクリプトまたは既存 AC 監査ステップへの追加) が実装されており、verify-type マーカーの有無によらずプレーン箇条書きを検出できる" --> 形式違反を機械検出する仕組みが実装されている (Pre-merge / Post-merge 両セクション対象)
- <!-- verify: rubric "既存の未解決 3 件 (#734 / #735 / #1006) の Post-merge プレーン箇条書きがチェックボックス形式に修正されている、または修正しない判断とその理由が記録されている" --> 既存の残存 3 件が処理されている

### Post-merge

- 次回 `/issue` で Post-merge 条件を含む Issue を起票した際、チェックボックス形式で生成されることを観察する <!-- verify-type: observation event=auto-run session=next -->

## Autonomous Auto-Resolve Log

- **`phase/ready` ラベル欠如の扱い**: `/code 1156 --pr --non-interactive` 実行時、Issue のラベルは `triaged` / `phase/code` / `audit/drift` で `phase/ready` が存在しなかった (`reconcile-phase-state.sh code-pr 1156 --check-precondition` は `matches_expected: false` を返した)。調査の結果、前回セッションが既に Step 1 (コメント消化, cutoff `2026-08-06T01:59:41Z`) と Step 4 (ラベル遷移 `phase/ready` → `phase/code`, cutoff `2026-08-06T02:06:32Z`) を実行済みで、その後 worktree を残さずに中断していたと判明した (docs/spec 側に未コミットの Step 1 記録のみが main の作業ツリーに残存)。Spec 自体は `/spec` により完備しているため、"Spec がない" ケース向けの auto-resolve ポリシー (Issue 本文から直接要件を読む) は適用せず、既存の完備した Spec を正として実装を継続した。

## Notes

### #1006 は変更不要 (grep/gh issue view で確認済み)

Issue 本文の実測テーブル (2026-08-05 `/audit stats --retention`) は #1006 を「プレーン箇条書き」10 件の一つとして分類しているが、本 `/spec` の investigation 時点で `gh issue view 1006` を実行したところ、Post-merge 条件 (`- [ ] 次回 verify FAIL → auto-retry 発生時、3 イベントが events.jsonl に session_id 付きで記録されることを観察 <!-- verify-type: observation event=fix-cycle -->`) は既にチェックボックス形式だった。監査実行 (2026-08-05) から本 `/spec` 実行 (2026-08-06) までの間に修正された可能性、または当時の分類の誤検知の可能性があるが、いずれにせよ現時点の実態を優先し #1006 への変更は行わない。これは受け入れ条件3 が許容する「修正しない判断とその理由が記録されている」に該当する。#1006 が `phase/verify` に留まっている理由は、observation イベント (`event=fix-cycle`) の emitter が未実装 (#650 系列待ち、Issue 本文の Auto-Resolved Ambiguity Points に記載済み) という、本 Issue のスコープ外の別要因による。

### 下流処理 (check-pre-merge-ac.sh 等) を変更しない判断

Issue 本文が挙げる「`- [ ]` を機械走査する下流処理」(`check-pre-merge-ac.sh`、`/audit stats --retention` の verify-type breakdown) は、いずれも `^- \[[ xX]\]` パターンでチェックボックス行を正しくパースしている。これらのスクリプト自体にバグはなく、入力データ (Issue 本文の書式) が壊れていたことが原因だった。受け入れ条件1 (規約明記) + 受け入れ条件2 (機械検出) でソース側 (`/issue` の生成時点) を塞ぎ、受け入れ条件3 で既存の壊れたデータを修復すれば、下流処理は変更なしで正しく動作する。

### `/verify` 側の検出は不採用

Issue 本文の対応方針候補 2 は「`/issue` の AC 監査ステップ、または `/verify` の入力バリデーションから呼ぶ」と両方を候補に挙げていたが、本 Spec は `/issue` 側のみを採用した。理由:
- 唯一の発生源は `/issue` の New Issue Creation (Step 4) と Existing Issue Refinement (Step 7 → Step 4 に委譲) の 2 経路であり、両方とも Step 4 への 1 箇所の追加でカバーされる (#1168 と同型の委譲構造)
- `--from-decomposition-file` 経路 (Step 3) は独自の Standard Format テンプレートを使うが、Post-merge は常に「なし」で生成されるため、このバグのリスクが構造的に存在しない
- ソース側で防いだ上に既存データも修復すれば、`/verify` 側に検出ロジックを追加する追加コストに見合う残存リスクがない。Size M の light-depth Spec の Implementation Steps 上限 (5 件) にも合致する

### docs/structure.md のスクリプト件数drift

`docs/structure.md` の `scripts/ ... (69 files)` は、本 Issue の変更前時点で実測 73 件 (`find scripts -maxdepth 1 -type f \( -name "*.sh" -o -name "*.py" \) | wc -l`、`scripts/git-hooks/` は対象外) であり、既に 4 件分の drift があった (過去の複数 Issue がスクリプト追加時にこのカウント更新を省略した結果と推測される、本 Issue のスコープ外の既存事象)。本 Issue はこの行を編集対象に含めるため、実測に基づき 74 件 (73 + 本 Issue の新規 1 件) へ修正する。

### #1168 との類似性

本 Spec の設計 (新規 warn-only チェッカースクリプト + `/issue` Step 4 への組み込み + `allowed-tools` 更新 + `tests/issue.bats` content-assertion + `docs/structure.md`/`docs/ja/structure.md` 同期) は、直近の #1168 (`check-skill-change-observation-ac.sh` の追加) と同型である。#1168 の Verify Retrospective が指摘した MUST 不具合 (Spec 実行時点で未確定な `## Changed Files` をゲート条件にした、`$NUMBER` 未束縛のファイル名を使った) は本 Spec では該当しない — 新スクリプトの適用条件は Issue 本文テキストそのもの (`### Pre-merge` / `### Post-merge` 見出しの有無) であり Spec 由来の未確定情報に依存せず、ファイル名も既存の "Skill self-update propagation check" サブステップが使う固定ファイル名 `.tmp/issue-body-check.md` をそのまま再利用するため、`$NUMBER` 未束縛の問題も生じない。

## Code Retrospective

### Deviations from Design
- Implementation Step 5 (#734 / #735 のチェックボックス形式修正) は、`/code` 実行時点で `check-ac-checkbox-format.sh` を両 Issue の本文に対して実行したところ既に exit 0 (チェックボックス形式) だったため、外部 GitHub 操作 (`gh-issue-edit.sh` での本文更新) は実行しなかった。原因は、本セッション開始前に一度中断した `/code 1156` の前回実行が、リポジトリファイル変更 (Step 1-4) に到達する前に Step 5 の外部操作のみを先に完了させていたためと判断した (Autonomous Auto-Resolve Log 参照)。受け入れ条件3 が要求する「修正されている」状態は満たされているため、実装ステップとしては完了扱いとする。

### Design Gaps/Ambiguities
- N/A — Spec の設計 (#1168 と同型のパターン踏襲) はそのまま実装でき、Root Cause / Changed Files / Implementation Steps に記載された前提と実装時の codebase 実態 (`skills/issue/SKILL.md` の該当挿入位置、`check-pre-merge-ac.sh` の awk セクション追跡方式) に齟齬はなかった。

### Rework
- N/A

## review retrospective

### Spec vs. implementation divergence patterns

Nothing to note — PR diff は Spec の Implementation Steps / Changed Files と完全に一致していた。AC1 (規約明記) / AC2 (機械検出) / AC3 (既存3件処理) の 3 条件はいずれも diff 上の対応箇所を直接特定でき、`review-light` エージェントによる Spec Deviation 観点でも issue なしと判定された。

### Recurring issues

`scripts/check-ac-checkbox-format.sh` の awk セクション終端判定 (`^## ` / `^### ` の完全一致のみ) が、深いサブ見出しやフェンスコードブロック内の見出し文字列を区別しない CONSIDER 級の指摘を受けた。これは同型の `check-pre-merge-ac.sh` の awk パターンに既に存在する簡略化であり、本 PR 固有の新規不具合ではない。#1168 (`check-skill-change-observation-ac.sh`) から続く「warn-only チェッカースクリプトを awk セクション追跡で実装する」パターンの共通の弱点として、将来同種スクリプトを追加する際は再確認が必要。

### Acceptance criteria verification difficulty

AC3 (rubric "既存の未解決 3 件 (#734 / #735 / #1006) が処理されている、または修正しない判断とその理由が記録されている") の判定に、`rubric` verify command の grader 入力スコープ (`modules/verify-executor.md` により Issue 本文 + git diff + rubric text で明示的に named されたファイルのみ、Spec は対象外) だけでは根拠が不足していた。本 PR の diff は #734/#735/#1006 を一切変更しておらず、修正不要と判断した理由は Spec の Code Retrospective (grader スコープ外) にのみ記録されている。実際の判定は `/review` 実行者が `gh issue view` で #734/#735/#1006 の Post-merge 行を直接確認し、既にチェックボックス形式であることを確認する形で行った — これは grader の正規スコープを超えた追加調査であり、rubric grader 単体では UNCERTAIN になっていた可能性が高い。「他 Issue の外部状態確認」を要求する rubric 条件は、根拠を Spec ではなく Issue 本文または Issue コメントに明示的に記録するよう Issue 起票時に促すと、grader スコープ内で完結できる。

## Phase Handoff
<!-- phase: review -->

### Key Decisions
- Base Branch Conflict Pre-check (`git merge-tree` 3-引数形式) を実行したが `changed in both` は検出されず (main 側が独立に触った `docs/spec/issue-1175-*.md` は本 PR ブランチ側は無変更のためクリーンマージ) 、conflict context ファイルは作成しなかった
- REVIEW_DEPTH=light (`--light` 明示指定) のため Step 10.0 の 1 エージェント統合レビューのみ実行し、Workflow path (10.1–10.3 static fan-out や workflow-guidance.md の Workflow tool 経路) は評価対象外とした
- AC3 の rubric 判定は Spec 記載の根拠だけでなく `gh issue view 734/735/1006` による実地確認を追加で行い PASS と判断した (grader 正規スコープ外の追加検証、詳細は review retrospective 参照)

### Deferred Items
- CONSIDER 指摘 (awk セクション終端判定の簡略化) は対応不要と判断し未修正のまま — 姉妹スクリプト `check-pre-merge-ac.sh` 側の既存の弱点でもあるため、再発した場合は別 Issue で awk パターンの一括見直しを検討
- Post-merge の observation AC (`session=next`) は今回未発火のため引き続き `/verify` フェーズでの評価待ち

### Notes for Next Phase
- Pre-merge AC 3 件すべて PASS、CI 9 ジョブ SUCCESS、MUST/SHOULD なし (CONSIDER 1件のみ) — `/merge 1189` は追加のブロッカーなしで進行可能
- Post-merge AC (observation, session=next) が唯一の未チェック項目。`/verify` 実行時に `session=next` の発火判定に従うこと
