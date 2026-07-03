# Issue #882: review: capabilities.workflow 有効時に review-spec/review-bug エージェント未登録で fallback

## Overview

`.wholework.yml` で `capabilities.workflow: true` を設定した環境で `/review --full` を実行すると、`skills/review/workflow-guidance.md` の Workflow パスが `review-spec` / `review-bug` カスタム agentType を Agent tool registry から解決できず即座に失敗する。原因は `scripts/run-*.sh` (`run-spec.sh` / `run-code.sh` / `run-review.sh` / `run-merge.sh` / `run-issue.sh` の 5 ファイル) が `claude -p` を headless 実行する際に `--plugin-dir` を指定しておらず、wholework プラグイン自体 (および `agents/*.md` 由来のカスタム agentType) がそのセッションにロードされないことにある。本 Spec では、(1) 根本原因を `--plugin-dir` 追加で修正し、(2) `capabilities.workflow: true` 設定時に期待 agentType が利用不可能な場合の検出・警告フォールバックを追加し、(3) 調査過程で見つかった関連ドキュメントの陳腐化を是正する。

## Consumed Comments

- login: saito / authorAssociation: MEMBER / trust tier: first-class — `/issue 882` の Issue Retrospective。当初仮説 (`~/.claude/agents/` インストール先問題) を、実地観測 (`/issue 882` セッション自身が `run-issue.sh` 経由の headless 実行であり、`CLAUDE_PLUGIN_ROOT` が空文字列・カスタム agentType 一覧が空だったこと) に基づき「`run-*.sh` が `--plugin-dir` を使わないためプラグイン自体がロードされない」という仮説に再定義した根拠、AC2 呼び出し元を `skills/review/SKILL.md:300` と明示した根拠、警告の出力形式を意図的に AC 文言で規定せず実装フェーズの裁量に委ねた理由を記録している。 (https://github.com/saitoco/wholework/issues/882#issuecomment-4872860603)

## Reproduction Steps

1. `.wholework.yml` に `capabilities:\n  workflow: true` を設定する。
2. いずれかの `run-*.sh` 経由で headless 実行する (本 Issue #882 自身の `/issue 882 --non-interactive` セッション、および本 Spec を作成した `/spec 882 --non-interactive` セッション自身が、この経路での実行例として直接該当する)。
3. セッション内で `CLAUDE_PLUGIN_ROOT` を確認すると空文字列である。
4. セッションの Agent tool 利用可能 agentType 一覧 (システムコンテキストに提示される) を確認すると、`agents/*.md` (review-spec, review-bug, review-light, issue-scope, issue-risk, issue-precedent, orchestration-recovery, frontend-visual-review の 8 ファイル) 由来の agentType が一件も含まれない。
5. `/review --full` が Step 10 の Workflow パスに到達すると、`agent(prompt, { agentType: 'review-spec' })` (`skills/review/workflow-guidance.md` の Inline Workflow Script) の呼び出しが agentType 未解決で即座に失敗する。

## Root Cause

**確定した根本原因**: `scripts/run-spec.sh` / `run-code.sh` / `run-review.sh` / `run-merge.sh` / `run-issue.sh` (`scripts/run-*.sh` 全 5 ファイル) は共通して `"$SCRIPT_DIR/claude-watchdog.sh" claude -p "$PROMPT" --model ... --effort ... $PERMISSION_FLAG` の形で `claude -p` を呼び出しているが、`--plugin-dir` フラグを一切指定しておらず、`CLAUDE_PLUGIN_ROOT` も export していない (`scripts/*.sh` 全体を grep した限り `--plugin-dir` の使用は 0 件。`CLAUDE_PLUGIN_ROOT` は `scripts/claude-watchdog.sh` に読み取り専用参照が 1 件あるのみで、書き込み/export 箇所はどこにもない)。

`docs/tech.md` § Plugin directory distribution によれば、wholework は `claude --plugin-dir <path>` で読み込まれるローカルプラグインとして配布され、Claude Code はプラグインロード時にのみ `${CLAUDE_PLUGIN_ROOT}` を設定し `agents/*.md` のカスタム agentType を登録する。`claude --help` で `--plugin-dir <path>` の実仕様を確認したところ "Load a plugin from a directory or .zip for this session only" と説明されており、`-p` (headless print モード) と併用可能なフラグであることは `--bare` フラグの説明文 ("Explicitly provide context via: ... --plugin-dir") からも確認できる。したがって `run-*.sh` の `claude -p` 呼び出しに `--plugin-dir` が欠落していることが、headless 実行時に wholework プラグイン (および `agents/*.md` 由来のカスタム agentType) がロードされない直接原因である。

**実地確認**: 本 Issue の `/issue 882 --non-interactive` セッション、および本 Spec を作成した `/spec 882 --non-interactive` セッション自身がこの `run-*.sh` (`run-issue.sh` / `run-spec.sh`) 経由の headless 実行であり、両セッションで `CLAUDE_PLUGIN_ROOT` が空文字列であること、Agent tool の利用可能 agentType 一覧 (システムコンテキスト提示分) に `agents/*.md` 由来のカスタム agentType が 8 ファイル中 0 件しか含まれないことを直接観測した。一方、同セッションには他プラグイン (`coderabbit:code-reviewer` 等) の namespace 化された agentType が正しく登録されており、「ロードされたプラグインの custom agentType 登録機構自体は機能しているが、wholework プラグインだけがこの headless 経路でロードされていない」という解釈と整合する。

**副次的な確証 (hooks、関連 Issue #888)**: `hooks/hooks.json` は `${CLAUDE_PLUGIN_ROOT}/scripts/hook-rename-on-auto.sh` (UserPromptSubmit) と `${CLAUDE_PLUGIN_ROOT}/scripts/hook-worktree-path-guard.sh` (PreToolUse: Edit|Write|NotebookEdit) をプラグインスコープの hook として宣言している。プラグインがロードされない headless 実行では、これらの hook も同様に発火していない可能性が高い。実際、issue #881 の Verify Retrospective (`docs/spec/issue-881-run-merge-cwd-after-worktree.md`) では `run-spec.sh` の `claude -p` サブプロセスセッション内で `hook-worktree-path-guard.sh` が発火しなかったと見られる事故が報告されており、その Improvement Proposal から issue #888 (`hook: claude -p サブプロセスセッションでの hook-worktree-path-guard.sh 発火を検証`) が既に起票されている。本 Issue で確定した根本原因 (`run-*.sh` の `--plugin-dir` 欠落) は、issue #888 が調査対象とする hook 未発火現象の原因としても整合する。本 Issue のスコープは `agents/*.md` カスタム agentType (AC1/AC2) に限定し、hook 修正自体は issue #888 のスコープとして残すが、本 Spec の `--plugin-dir` 追加が実装されれば hook も副次的に復旧する可能性が高いことを issue #888 の参考情報として残す。

**却下した仮説と、その残存資料**: `docs/spec/issue-875-abolish-data-layer-md.md` の retrospective (本 Issue の起票元) は当初 `~/.claude/agents/` へのインストール有無を疑っていた。調査の結果、`~/.claude/agents/` ディレクトリ自体がこのマシンに存在せず、かつ現行 `install.sh` はシンボリックリンク作成ロジックを持たない (`claude --plugin-dir` の利用を案内するコメントのみ) ことを確認した。この仮説は `/issue 882` の refinement 時点で既に「裏付けとなる観測事実がない」として却下されていたが、`skills/review/SKILL.md` の「10.1. Group Definitions」テーブルには今も `~/.claude/agents/review-spec.md` という陳腐化した参照が残っている (`docs/spec/issue-2-repo-structure-foundation.md` / `issue-18-agents-migration.md` に記録された、`--plugin-dir` 配布方式へ移行する前の旧シンボリックリンク方式の名残)。この陳腐化した参照が当初の誤った仮説を誘発した一因と考えられるため、本 Spec で合わせて是正する。

**残留する不確実性**: `--plugin-dir` でロードされたプラグインのカスタム agentType が、他プラグインと同様に `wholework:review-spec` のように namespace 化されて登録されるか、それとも bare 名 `review-spec` のまま登録されるかは、静的なコード調査だけでは断定できない (本セッションで観測できる他プラグインの agentType は軒並み `plugin-name:agent-name` 形式である一方、Workflow ツール自体のドキュメント例は bare 名 `'code-reviewer'` を使っており、両方の可能性を示唆する手がかりが存在する)。`skills/review/workflow-guidance.md` / `skills/review/SKILL.md` の `agentType:` / `subagent_type=` 参照は現状の bare 名 (`review-spec` 等) のまま変更しない一方、Implementation Step 3 の検出・警告フォールバックを defense-in-depth として追加することで、この不確実性が的中し `--plugin-dir` 追加だけでは agentType が解決しない場合でも AC2 を満たす。

## Changed Files

- `scripts/run-spec.sh`: `claude -p "$PROMPT"` 呼び出しに `--plugin-dir "$(dirname "$SCRIPT_DIR")"` を追加 (1 箇所) — bash 3.2+ compatible
- `scripts/run-code.sh`: 同上 (2 箇所: `AUTO_EVENTS_LOG` 分岐 / else 分岐) — bash 3.2+ compatible
- `scripts/run-review.sh`: 同上 (2 箇所) — bash 3.2+ compatible
- `scripts/run-merge.sh`: 同上 (2 箇所) — bash 3.2+ compatible
- `scripts/run-issue.sh`: 同上 (1 箇所) — bash 3.2+ compatible
- `tests/run-spec.bats`: mock `claude` スクリプトに `--plugin-dir` フラグ検出を追加し、主要成功パスのテストにアサーションを追加 — bash 3.2+ compatible
- `tests/run-code.bats`: 同上 — bash 3.2+ compatible
- `tests/run-review.bats`: 同上 — bash 3.2+ compatible
- `tests/run-merge.bats`: 同上 — bash 3.2+ compatible
- `tests/run-issue.bats`: 同上 — bash 3.2+ compatible
- `skills/review/workflow-guidance.md`: `## Processing Steps (Workflow Path)` の直前に `## Pre-flight: agentType Availability Check` セクションを新設 — `review-spec` / `review-bug` が利用可能 agentType 一覧に無い場合は警告し、静的 Task fan-out (`skills/review/SKILL.md` Steps 10.1–10.3) にフォールバックする
- `skills/review/SKILL.md`: 「10.1. Group Definitions」テーブルの Agent file 列を `~/.claude/agents/review-spec.md` → `agents/review-spec.md`、`~/.claude/agents/review-bug.md` → `agents/review-bug.md` に修正 (陳腐化した参照の是正)
- `docs/tech.md`: Architecture Decisions テーブルの review 行の Execution Platform 列を `In-session (Workflow opt-in via capabilities.workflow: true) / headless fallback` → `headless (run-review.sh) / in-session (direct)` に修正 (実装と一致しない記述の是正)
- `docs/ja/tech.md`: 上記の日本語ミラー行を同様に修正 (`docs/translation-workflow.md` 準拠の同期。既存テーブルの全角括弧の慣習に合わせる)

## Implementation Steps

1. `scripts/run-spec.sh` / `run-code.sh` / `run-review.sh` / `run-merge.sh` / `run-issue.sh` の計 5 ファイルにある `"$SCRIPT_DIR/claude-watchdog.sh" claude -p "$PROMPT"` の呼び出しブロックすべて (`run-code.sh` と `run-merge.sh` は各 2 箇所) に `--plugin-dir "$(dirname "$SCRIPT_DIR")"` を追加する。挿入位置は既存の `--model` / `--effort` フラグと同じ並びの行 (`$PERMISSION_FLAG` の直前または直後)。`SCRIPT_DIR` は全ファイル共通で `scripts/` を指すため、`$(dirname "$SCRIPT_DIR")` がプラグインルート (`.claude-plugin/plugin.json` の場所) に一致することを確認済み。 (→ acceptance criteria AC2)
2. `tests/run-spec.bats` / `run-code.bats` / `run-review.bats` / `run-merge.bats` / `run-issue.bats` それぞれの mock `claude` スクリプト内 `case` 文に `--plugin-dir) echo "FLAG_PLUGIN_DIR=1" >> "$CLAUDE_CALL_LOG" ;;` を追加し、各ファイルの主要成功パステストに `grep -q "FLAG_PLUGIN_DIR=1" "$CLAUDE_CALL_LOG"` のアサーションを追加する。各ファイルに mock `claude` 定義ブロックが複数箇所存在する場合は、テストシナリオごとの mock 内容整合性を保つため全ブロックに同じ `case` 分岐を追加する。 (after 1) (→ acceptance criteria AC2)
3. `skills/review/workflow-guidance.md` の `## Processing Steps (Workflow Path)` 見出しの直前に `## Pre-flight: agentType Availability Check` セクションを追加する。内容: Workflow パイプラインを実行する前に、`review-spec` と `review-bug` がセッションの Agent tool 利用可能 agentType 一覧 (システムコンテキストに提示されるもの) に含まれるか確認し、いずれか欠落していれば issue #882 を参照する旨を含む警告メッセージを出力した上で、`skills/review/SKILL.md` Steps 10.1–10.3 の静的 Task fan-out にフォールバックする。両方存在する場合は現行の Processing Steps をそのまま実行する。 (parallel with 1, 2) (→ acceptance criteria AC2)
4. `skills/review/SKILL.md` の「10.1. Group Definitions」テーブル、`docs/tech.md` と `docs/ja/tech.md` の Architecture Decisions テーブル review 行を、Root Cause セクションに記載の通り修正する。 (parallel with 1, 2, 3) (→ acceptance criteria AC1 の記録内容を裏付け、将来の再調査コストを削減する)

## Verification

### Pre-merge

- <!-- verify: rubric "self-hosting 実行環境 (`--plugin-dir` 使用時、および `run-*.sh` 経由の `claude -p` headless 実行時の両方) で agents/review-spec.md および agents/review-bug.md が Agent tool registry から解決できない原因調査の結果がIssueコメントまたはSpecに記録されている" --> `agents/*.md` のカスタム agentType が Agent tool registry に登録されない原因 (`--plugin-dir` 未使用時の `CLAUDE_PLUGIN_ROOT` 未設定を含む) が調査され、Issue コメントまたは Spec に記録されている
- <!-- verify: rubric "根本原因の修正、または capabilities.workflow: true 設定時に期待カスタムagentType不在を検出し警告するロジックが skills/review/workflow-guidance.md またはその呼び出し元 skills/review/SKILL.md に追加されている" --> 根本原因が修正されるか、または `capabilities.workflow: true` 設定時に期待されるカスタム agentType (`skills/review/SKILL.md` から呼び出される `skills/review/workflow-guidance.md` が利用) が利用不可能な場合に警告を出す検出機構が追加されている

### Post-merge

なし

## Notes

- 本 Spec の Root Cause セクション、および Step 15 で `/spec` が投稿する Issue コメントが AC1 の検証対象となる。AC1 に対応する独立した実装ステップは設けていない。
- **agentType namespace 化の残留不確実性**: Root Cause 参照。`/code` フェーズは実装後、可能であれば実際に `run-review.sh` (または同等の headless 呼び出し) を一度実行し、`review-spec` が意図通り解決されるか経験的に確認することが望ましい。namespace 化されていることが判明した場合は `agentType:` / `subagent_type=` 参照値への追加修正が必要になる可能性があるが、Implementation Step 3 の検出・フォールバックが defense-in-depth として機能するため、その場合でも AC2 は満たされる。
- **スコープについて**: `capabilities.workflow` を実際に消費するのは現状 `/review` のみだが、`--plugin-dir` の欠落は `run-*.sh` 全 5 ファイルに共通する構造的な問題であり (`/issue` の L/XL サブエージェント分割 `issue-scope` / `issue-risk` / `issue-precedent` も同じ agentType 未解決リスクを抱える)、5 ファイル全てへの適用が妥当と判断した。
- **issue #888 との関係**: Root Cause 参照。issue #888 は `hook-worktree-path-guard.sh` が `claude -p` サブプロセスで発火するかどうかを別スコープで調査中であり、本 Issue の根本原因 (`--plugin-dir` 欠落) が同じ現象の原因である可能性が高い。本 Issue のスコープには含めないが、issue #888 側の調査で参照される可能性がある。

## Code Retrospective

### Deviations from Design
- N/A — 4 つの Implementation Step をすべて設計通りに実装した (順序も Spec 記載どおり)。

### Design Gaps/Ambiguities
- N/A

### Rework
- worktree セッション中、最初の Edit 呼び出しで `file_path` にメインリポジトリの絶対パス (`/Users/saito/src/wholework/scripts/...`) を誤って指定し、worktree ではなくメインリポジトリ側のファイルが変更されてしまった (`modules/worktree-lifecycle.md` の「Edit/Write path conventions in worktree sessions」に明記された既知の失敗パターン)。`git status`/`grep` の不一致で即座に検知し、`git checkout --` でメインリポジトリ側を復元してから worktree 絶対パス (`.claude/worktrees/code+issue-882/...`) で全編集をやり直した。実害 (誤コミット) は発生していない。

### Post-merge follow-up (not blocking, recorded per Spec Notes)
- Spec Notes の「agentType namespace 化の残留不確実性」に記載の通り、`run-review.sh` を実際に headless 実行して `review-spec` agentType が意図通り解決されるかの経験的確認は本 PR ではスコープ外とし、PR body の Verification (post-merge) に記録した。namespace 化されていた場合は追加修正が必要になる可能性があるが、Implementation Step 3 の Pre-flight 検出・フォールバックが defense-in-depth として機能するため AC2 は本 PR の変更のみで満たされる。

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- `--plugin-dir "$(dirname "$SCRIPT_DIR")"` を全 5 run-*.sh・計 8 箇所に追加。`run-merge.sh` の `MAIN_REPO_ROOT` フォールバック分岐でも `SCRIPT_DIR` は常に scripts/ ディレクトリを指すため、`dirname` で一貫してプラグインルートに解決できることを確認済み。
- Pre-flight 検出は `skills/review/workflow-guidance.md` 側 (Workflow パス直前) に置いた。呼び出し元の `skills/review/SKILL.md` ではなく Domain file 側に置いたのは、Workflow パスの実行判断そのものがこのファイルの責務だからで、静的 Task fan-out 側には変更を加えていない。
- bats mock の更新は、arg-parsing `case` 文を持つブロックのみに `--plugin-dir` ケースを追加した (catch-all `echo "$@"` ブロックや counter/exit-code 専用ブロックは元々全引数をログするか case 文自体を持たないため変更不要と判断)。

### Deferred Items
- `review-spec` / `review-bug` agentType が `--plugin-dir` ロード後に namespace 化されずに解決されるか (bare 名 vs `wholework:review-spec` 形式) の経験的確認は post-merge 作業として PR body に記録し、本 PR ではスコープ外とした。
- `docs/product.md` / `docs/guide/index.md` / `docs/guide/troubleshooting.md` / `docs/ja/guide/autonomy.md` の翻訳同期ギャップ (`check-translation-sync.sh` で検出) は本 Issue と無関係の既存差分のため未着手。

### Notes for Next Phase
- `/review` フェーズで実際に `capabilities.workflow: true` 環境の Workflow パスを通す機会があれば、Pre-flight ログ (agentType 一覧に review-spec/review-bug が含まれるか) を確認し、`--plugin-dir` 修正が意図通り機能しているか経験的に検証してほしい。
- AC1/AC2 とも rubric 型検証であり、`/code` フェーズで自己判定して Issue チェックボックスを更新済み。`/verify` フェーズで改めて rubric grader によるフル評価が行われる。
