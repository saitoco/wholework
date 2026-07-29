# Issue #1074: verify: curl 系 URL command (html_check / http_status / api_check) に Basic Auth を追加

## Overview

`modules/verify-executor.md` の curl 系 URL command (`html_check` / `http_status` / `api_check` / `http_header` / `http_redirect`) は URL 文字列のみを受け取り curl を直接実行する設計のため、Basic Auth 保護下の URL (PR preview 等) を検証できない。#1051 で `lighthouse_check` に Basic Auth 対応が入ったが、同 Issue のスコープは lighthouse-adapter に限定されており、curl 系 command は明示的にスコープ外とされていた (本 Issue はその follow-up)。

対応方針は Issue 本文の Auto-Resolved Ambiguity Points で `--config` 方式に決定済み: `PREVIEW_BASIC_USER` / `PREVIEW_BASIC_PASS` (既存の環境変数、`.wholework.yml` への新規キー追加は不要) が両方設定されている場合、`user = "USER:PASS"` の一時 config ファイルを `mktemp` で作成し (デフォルト 600 権限)、`curl --config "$config_file"` で注入する。`modules/lighthouse-adapter.md` の `header_file` パターン (一時ファイル + 600 権限 + 削除) をそのまま踏襲し、マスキング方針も `modules/browser-adapter.md` / `modules/lighthouse-adapter.md` と揃える。環境変数未設定時は現状どおり認証なしで実行する (後方互換)。

**重要な設計上の要点**: 5 つの command の翻訳テーブル各行に書かれている curl コマンドは、safe mode (URL security check 通過後に curl 実行) と full mode (制限なしで curl 実行) の両方から共有される単一の記述であるため、この curl 行に `--config` を追加するだけで両モードに Basic Auth が適用される。これにより、Issue 本文が報告する実際の障害ケース (`/review` の safe mode で実行される pre-merge-preview tier の `html_check` AC が 401 で FAIL する) が解消される。

## Changed Files

- `modules/verify-executor.md`: change — 「### Basic Authentication Support」節に curl 系 URL command 向けの Basic Auth 注入手順 (一時 `--config` ファイル、マスキング、後方互換) を追記し、5 つの翻訳テーブル行 (`http_status` / `html_check` / `api_check` / `http_header` / `http_redirect`) の curl コマンド記述に `--config` 注入を反映する

## Implementation Steps

1. `modules/verify-executor.md` の「### Basic Authentication Support」節 (現状 `browser_check`/`browser_screenshot` と `lighthouse_check` の委譲説明のみ、L256-260 付近) に、curl 系 URL command (`http_status` / `html_check` / `api_check` / `http_header` / `http_redirect`) 向けの新しい段落を追記する。要点:
   - `PREVIEW_BASIC_USER` / `PREVIEW_BASIC_PASS` が両方設定されている場合、次のシェルスニペットで一時 config ファイルを作成する:
     ```bash
     mkdir -p .tmp
     config_file="$(mktemp .tmp/curl-auth-XXXXXX.cfg)"
     printf 'user = "%s:%s"\n' "$PREVIEW_BASIC_USER" "$PREVIEW_BASIC_PASS" > "$config_file"
     ```
     (`mktemp` はデフォルトで 600 権限のファイルを作成するため、明示的な `chmod` は不要 — 実機確認済み、Notes 参照)
   - 次ステップの翻訳テーブルの curl コマンドに `curl --config "$config_file"` として注入する旨を明記する。この説明文には **リテラルな連続文字列 `curl --config`** (「curl」の直後に半角スペース 1 つと「--config」が続く形) をそのまま含めること — Pre-merge AC5 の `<!-- verify: grep "curl --config" "modules/verify-executor.md" -->` の検証対象文字列のため
   - コマンド完了後 (成功・失敗を問わず) `rm -f "$config_file"` で削除する後始末を明記する
   - `PREVIEW_BASIC_USER` / `PREVIEW_BASIC_PASS` の値・config ファイルの内容を、ログや検証結果詳細に出力しない (`****` としてマスク) 旨を、`modules/browser-adapter.md` Step 3 / `modules/lighthouse-adapter.md` Step 2 と同じマスキング方針として明記する
   - どちらか一方でも環境変数が未設定の場合は `--config` 注入をスキップし、現行の無認証動作を維持する (後方互換) 旨を明記する
   - `--allow-localhost` フラグとは独立して動作する (直交する設定) 旨を明記する
   (→ Pre-merge AC1, AC2, AC3, AC4, AC5)

2. (after 1) 翻訳テーブルの `http_status` / `html_check` / `api_check` / `http_header` / `http_redirect` の 5 行 (現状 L73-77 付近) それぞれの curl コマンド記述に、`--max-time 10` の直後へ `[--config "$config_file"]` (両環境変数設定時のみ含まれる意の表記) を挿入する。各行の curl コマンドは safe mode ("external URLs executed with curl") と full mode (制限なしの明示コマンド) の両方から共有される単一の記述であるため、この 1 箇所の追記だけで両モードに Basic Auth が適用される。
   (→ Pre-merge AC1, AC5)

## Verification

### Pre-merge

- <!-- verify: rubric "modules/verify-executor.md の curl 系 URL command (html_check / http_status / api_check / http_header / http_redirect) が PREVIEW_BASIC_USER / PREVIEW_BASIC_PASS を読んで Basic 認証を付与する手順を持つ" --> curl 系 URL command が Basic Auth を通せる
- <!-- verify: rubric "認証情報がコマンドライン引数としてプロセスリストに露出しない方式 (一時ファイル経由等) が採用され、一時ファイルの権限設定と削除が定義されている" --> 認証情報がプロセスリストに露出しない
- <!-- verify: rubric "PREVIEW_BASIC_USER / PREVIEW_BASIC_PASS の値および導出物をログ・検証結果に出力しないマスキング方針が、browser-adapter / lighthouse-adapter と同じ方針で明記されている" --> マスキング方針が既存 adapter と揃っている
- <!-- verify: rubric "環境変数が未設定の場合は認証なしで実行される後方互換の挙動が明記されている" --> 後方互換が保たれている
- <!-- verify: grep "curl --config" "modules/verify-executor.md" --> curl 系 URL command が `--config` 経由の一時ファイルで認証情報を注入している

### Post-merge

- Basic Auth 保護下の preview URL に対して `html_check` を実行し、401 ではなく実際の HTML に対する判定結果 (PASS/FAIL) が返ることを確認する <!-- verify-type: manual -->
- 環境変数を未設定にして同じ AC を実行し、従来どおり認証なしで動作することを確認する <!-- verify-type: manual -->

## Notes

- **外部仕様確認 (`curl --config`、実機検証済み)**: `man curl` で `-K`/`--config` オプションの存在を確認した上で、実際にローカル HTTP サーバ (Python `http.server`) を立て、`user = "testuser:testpass"` を書いた config ファイルを `curl --config` で読ませたところ、`Authorization: Basic dGVzdHVzZXI6dGVzdHBhc3M=` ヘッダが正しく送信されることを実機で確認した (`dGVzdHVzZXI6dGVzdHBhc3M=` は `testuser:testpass` の base64 エンコードと一致)。また `mktemp` が作成する一時ファイルの権限が `-rw-------` (600) であることも実機で確認した (Implementation Step 1 で明示的な `chmod` を不要とした根拠)。
- **safe/full mode 両対応が本 Issue の核心**: 翻訳テーブルの各行は curl コマンドを 1 箇所にしか記述しておらず、safe mode ("external URLs executed with curl") と full mode (明示コマンド) の両方がこれを共有する構造になっている。したがって Implementation Step 2 の 1 箇所追記で両モードに Basic Auth が適用される。Issue 本文が報告する実害 (`/review` の safe mode 実行時に 401 で FAIL) は full mode 限定の対応では解消しないため、この点は実装時に見落とさないよう明記した。
- **クレデンシャル/セキュリティポリシー確認 (確認済み、矛盾なし)**: `SECURITY.md` および `grep -rl "credential\|security" docs/ SECURITY.md` (repo ルート) でヒットしたポリシー文書を確認したが、`PREVIEW_BASIC_USER` / `PREVIEW_BASIC_PASS` の取り扱いを制約する明示的な記述はなく (#1051 と同一の結論)、`SECURITY.md` の "Wholework does not store or transmit credentials" は GitHub CLI 認証に関する記述で本件とは別スコープ。
- **他ファイルへの影響なし (確認済み)**: `grep -rln "html_check\|http_status\|api_check\|http_header\|http_redirect" docs/guide/ docs/environment-adaptation.md skills/verify/ modules/` で言及箇所を確認したが、`docs/guide/customization.md` (pre-merge-preview tier 対象コマンド一覧)・`docs/environment-adaptation.md` (safe/full mode 実行可否表)・`modules/execution-context.md`・`modules/browser-verify-security.md`・`modules/verify-patterns.md` はいずれも Basic Auth の有無を主張する記述がなく、更新不要と判断した (#1051 の同種チェックと同じ結論)。`docs/guide/customization.md` は `PREVIEW_BASIC_USER` / `PREVIEW_BASIC_PASS` 自体を未記載のままだが、これは本 Issue 以前からの既存ギャップでありスコープ外 (Changed Files が `SKILL.md` / `scripts/` を含まないため Steering Docs sync candidate check の対象外)。
- **アダプタパターン調査**: 本 Issue が扱う 5 command はいずれも `modules/verify-executor.md` の built-in translation table に既存の command type であり、新規 command type を導入しないため `docs/environment-adaptation.md` Extension Guide Step 0 の対象外と判断した。
- **Issue 本文と実装の整合性チェック (確認済み、矛盾なし)**: Issue 本文が主張する現行実装 (curl 系 5 command が URL 文字列のみを受け取り `-u` / `--header` / `--config` 相当のオプションを持たない) は `modules/verify-executor.md` の該当行と完全に一致することを確認した。
- **Smoke Test セクション不採用**: 本 Issue の verify command は `mcp_call` を含まず `capabilities.mcp` も無関係のため、Smoke Test セクションの採用条件に該当しない。また wholework 自身のリポジトリには Basic Auth 保護下の preview URL が存在しないため、pre-merge での実地スモークテストは対象読者環境でのみ可能 (Post-merge AC で確認する設計、#1051 と同じ扱い)。

## Consumed Comments

- saito (MEMBER, first-class): `/issue` 非対話フローの Issue Retrospective コメント (2026-07-29T03:48:20Z)。Size=S / Type=Feature / Value=3 のトリアージ結果、AC verify command 監査で発見した常時 PASS defect (`grep "PREVIEW_BASIC_USER"` から `grep "curl --config"` への修正)、`--config` 方式の自動解決根拠を記録したもので、いずれも本 Issue 本文の Acceptance Criteria / Auto-Resolved Ambiguity Points に既に反映済みのため、Spec 作成上の追加対応は不要と判断した。 (https://github.com/saitoco/wholework/issues/1074#issuecomment-5112604944)

## Autonomous Auto-Resolve Log

- **`phase/ready` ラベル不在 (Step 3 precondition check)**: `/code` 開始時点で Issue #1074 のラベルは `triaged` / `phase/code` / `retro/verify` で、`phase/ready` が付与されないまま `phase/code` に遷移していた (`reconcile-phase-state.sh code-patch 1074 --check-precondition` も `matches_expected: false` を返した)。ただし Spec (`docs/spec/issue-1074-curl-url-command-basic-auth.md`) 自体は Design Complete コメントまで完了した内容で既に存在するため、「Spec なしで Issue 本文から直接実装」ではなく、既存の完成済み Spec を正としてそのまま実装を進めた。

## Auto Retrospective

### Manual recovery (code-patch)
- **Date**: 2026-07-29 04:34 UTC
- **Issue**: #1074, phase: code-patch
- **Source**: parent session manual recovery
- **Recovery type**: push-only
- **Wrapper exit code**: unknown
- **Outcome**: success

### Execution Summary

| Phase | Route | Result | Notes |
|-------|-------|--------|-------|
| issue | -     | SUCCESS | Size=S / Type=Feature / Value=3 を設定、`phase/issue` へ遷移 |
| spec  | patch | SUCCESS | `phase/ready` へ遷移。Step 3a の operate 判定は非該当 (リポジトリファイル変更あり) |
| code  | patch | SUCCESS (manual push-only recovery) | 1 回目は silent no-op で auto-retry 発火、2 回目は commit 後・push 前に外部 kill。親セッションが `worktree-merge-push.sh` で push を完了 |
| verify | -    | SUCCESS | Pre-merge AC 5/5 PASS。Post-merge manual 2 件は未検証のまま `phase/verify` |

### Orchestration Anomalies

- **code phase 1 回目: silent no-op (既知パターン)**: バックグラウンドの `bats tests/` 完了待ちのまま `claude -p` が exit 0 し、コミットを残さず終了した。`run-code.sh` の completion check が `commits_found: false` を返し、`code-patch-silent-no-op` として `auto-retry-on-fail` が正しく発火 (`code_retry_fire`, iteration 1)。**復旧は自動、介入なし**
- **code phase 2 回目: 外部 kill (`external-kill-parent-respawn`)**: 実装完了コミット `5724906f` (`closes #1074`) を worktree に作成した直後、push 前に wrapper のプロセスグループが外部 kill された。`.tmp/wrapper-out-1074-code-patch.log` に `Exit code:` トレーラなし、`auto-events.jsonl` に `wrapper_exit` イベントなし。`detect-external-kill.sh` が `external-kill` を返し検出は正常に機能した
- **カタログ手順からの意図的な逸脱**: `external-kill-parent-respawn` の Fallback Step 2 は respawn を指示するが、`scripts/run-code.sh` の idempotency guard は `--pr` 限定 (L164-176) で、その直後の stale worktree cleanup (L178-191) は route 無条件に `git worktree remove --force` + `git branch -D` を実行する。また `code_phase_milestone` は pr route 限定。したがって patch route の respawn は完成済みコミットを確実に破棄する。親セッションは respawn せず `worktree-merge-push.sh --from worktree-code+issue-1074 --base main` で push を完了させる `push-only` 復旧に切り替え、`--write-manual-recovery` で記録した (上記 Manual recovery エントリ)
- **並行セッションとの干渉なし**: 本セッション実行中、別セッションが #1069 (code) と #1060 (spec/review) を並行実行していたが、patch lock と PGID 単位の session pointer により競合は発生しなかった。他セッションの dirty file (`docs/spec/issue-1069-*.md`) にも触れていない

### Improvement Proposals

本セクションの改善提案は `## Verify Retrospective` → `### Improvement Proposals` に集約済みで、`/verify` Step 16 (retro-proposals) が以下のとおり起票を完了している。重複起票を避けるため、ここでは起票結果への参照のみを記録する。

- #1081 — auto: patch route の外部 kill respawn で worktree の未 push コミットを破棄しない
- #1082 — reconcile-phase-state: code-patch の completion check に worktree コミット有無の hint を追加

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- `/issue` の AC 監査が `<!-- verify: grep "PREVIEW_BASIC_USER" -->` を「変更前から常時 PASS する」defect として検出し `grep "curl --config"` に差し替えた判断は有効に機能した。差し替え後の AC5 は実装後にのみ PASS する状態になっており、verify 時に実質的な回帰検知として働いた
- 一時ファイル方式の曖昧点 (`--config` vs `--netrc-file`) を `/issue` 段階で確定させたため、`/spec` 以降で方式の再議論が発生しなかった

#### design
- Spec の Notes に `curl --config` の実機検証結果 (`Authorization: Basic ...` ヘッダ送信確認) と `mktemp` のデフォルト権限 600 の実測を残したため、verify 側は再実測なしに AC2 の「権限設定が定義されている」根拠を確認できた
- 翻訳テーブルの curl 記述を safe mode と full mode が共有する構造を Spec が明示していたため、実装が 1 箇所の追記で両モードをカバーでき、Issue 本文が報告する実害 (`/review` の safe mode で 401 FAIL) を取りこぼさなかった
- 影響範囲調査 (`docs/guide/customization.md` 等は更新不要) の結論が Spec に残っていたため、verify 側で追加の波及確認が不要だった

#### code
- 実装は Spec の Implementation Steps に 1:1 対応し、Pre-merge AC 5 件すべてを一発で満たした (fixup/amend コミットなし)
- 1 回目の code 試行はバックグラウンドの `bats tests/` 完了待ちのまま exit 0 となり commit を残さなかった (既知の `code-patch-silent-no-op` パターン)。`auto-retry-on-fail` が正しく発火し、2 回目の試行が実装コミット `5724906f` まで到達した
- ただし 2 回目は commit 直後・push 前に external kill を受け、完成済みコミットが worktree に取り残された状態で phase が終了した

#### review
- Size S の patch route のため `/review` は実行されていない。Pre-merge AC が rubric 中心で実装直後に機械判定でき、review 不在に起因する検知漏れは observed されなかった

#### merge
- patch route のため `/merge` は実行されていない。push は parent session の manual recovery (`worktree-merge-push.sh --from worktree-code+issue-1074`) で完了した (`## Auto Retrospective` に記録済み)

#### verify
- Pre-merge 5 件すべて PASS。rubric の根拠確認では記述の存在だけでなく、`modules/browser-adapter.md` Step 3 / `modules/lighthouse-adapter.md` Step 2 という相互参照先が実在しマスキング記述 (`mask as ****`) も一致することまで突き合わせた
- Post-merge 2 件は Basic Auth 保護下の preview 環境とその認証情報を必要とし、wholework 自身のリポジトリには該当環境がないため検証不能。#1051 と同一構造であり、この種の AC は downstream 環境でしか閉じられない

### Improvement Proposals

- **`external-kill-parent-respawn` の respawn 手順が patch route で完成済みコミットを破棄する**: `modules/orchestration-fallbacks.md#external-kill-parent-respawn` の Fallback Step 2 は「`phase/*` ラベルと `code_phase_milestone` checkpoint が既存の進捗を復元するため respawn は最初からやり直しにならない」と述べているが、この前提は pr route でしか成立しない。`scripts/run-code.sh` の idempotency guard (L165-176) は `ROUTE_FLAG == "--pr"` の場合のみ動作し、その直後の stale worktree cleanup (L178-191) は route に関係なく `git worktree remove --force` + `git branch -D` を無条件に実行する。また `code_phase_milestone` は設計上 pr route 限定 (`skills/auto/SKILL.md` § Checkpoint Design)。本 Issue では external kill 時点で worktree に実装完了コミット `5724906f` (`closes #1074`) が残っていたため、カタログ通りに respawn していれば約 13 分の完成済み作業を破棄して再実装させていた。parent session は破棄を避けるため `worktree-merge-push.sh --from worktree-code+issue-1074` で push を完了させる manual recovery (`push-only`) に切り替えた。対応候補: (a) fallback catalog に patch route 版の「commit 済み・push 未完」エントリ (pr route の `code-completed-no-pr` 相当) を追加する、(b) `run-code.sh` の stale worktree cleanup を「worktree branch に base より先行するコミットが存在する場合は削除せず push 経路へ回す」よう条件付きにする、(c) `external-kill-parent-respawn` の Fallback Steps に patch route の分岐を明記する
- **`code-patch` の完了判定が「worktree コミット済み・push 未完」を「未着手」と区別できない**: `reconcile-phase-state.sh code-patch --check-completion` は origin/main 上の `closes #N` コミット有無のみを見るため、worktree にコミット済みだが push 前の中間状態が `commits_found: false` (= 未着手) と同じ観測値になる。本 Issue では 1 回目の試行がこの判定で `silent_no_op` と分類されて auto-retry が発火したが、external kill 後の 2 回目についても同じ判定では「実装が存在しない」と誤読される状態だった (実際には完成済みコミットが worktree に存在した)。対応候補: `_completion_code_patch()` の `actual` に worktree branch の先行コミット有無を示す hint フィールド (例: `worktree_commits_found`) を追加し、Tier 1/2 の診断と `code-patch-silent-no-op` の判定が push 未完状態を区別できるようにする
