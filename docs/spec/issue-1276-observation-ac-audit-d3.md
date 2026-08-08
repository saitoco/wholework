# Issue #1276: verify: #1165 由来の observation AC 16 行を実査し判定不能分を retire

## Overview

親 #1270 の sub-issue。#1165 が `verify-type: manual` から `verify-type: observation` へ再型付けした **16 AC 行 / 14 Issue** について、「どの event が発火したとき、何を根拠に PASS 判定できるか」を 1 行ずつ実査し、A/B/C/D/E へ分類して処理する。

実査の結果は **A 7 行 / B 1 行 / C 0 行 / D 2 行 / E 6 行**。分類根拠と処理内容は `docs/reports/observation-ac-audit-d3.md` に記録する。この記録ファイルがあることで Pre-merge の `rubric` AC が grader から参照可能になる (grader へ渡るのは Issue 本文・git diff・rubric 本文で名指しされたファイルのみで、Spec ファイルと Issue コメントは渡らない)。#1165 / #1166 と同じ構成。

observation dispatch 機構そのもの (`scripts/opportunistic-search.sh` / `scripts/observation-trigger.sh` / `modules/observation-trigger.md`) は変更しない。

## Consumed Comments

cutoff: `2026-08-08T14:14:57Z` (Issue timeline の最新 `phase/*` ラベル付与 = `phase/issue`)。Cross-phase marker (`type=verify-fail` / `type=preview-ac-unverified`) の追加スキャンは該当なし。

- saito / MEMBER / first-class / `## Issue Retrospective` — `/issue 1276 --non-interactive` の Auto-Resolve Log。「担当範囲」表の対象 Issue を 19 件 → 14 件へ修正した経緯 (本 Spec は 14 件を前提として踏襲) / https://github.com/saitoco/wholework/issues/1276#issuecomment-5226501399

## Autonomous Auto-Resolve Log

`/spec 1276 --non-interactive` で自動解決した曖昧点 3 件。

- **分類 E のうち母集団定義を欠く 3 行 (#513 / #512 / #477) は、タグ差し戻しと同時に条件文も #1251 規約に従って書き換える** — reason: 親 #1270 の E の処理は「差し戻し理由と判定手順を記録する」のみだが、差し戻し先の `/verify` Step 8b が読むのは条件文であって記録ファイルではない。「次の同種 Issue で」「次のユースケースで」のように母集団を欠いたまま `manual` へ戻すと、Step 8b は毎回 UNCERTAIN を返し滞留先が変わるだけになる。条件文が既に具体的な 3 行 (#1056 / #710 条件1 / #710 条件2) はタグ差し替えのみとし、書き換え量を必要最小限に抑える
  - Other candidates: 6 行すべてタグ差し替えのみ (曖昧な 3 行が Step 8b で判定できず滞留が移動するだけ) / 6 行すべて条件文も書き換え (具体的な 3 行に不要な編集リスクを持ち込む)
- **分類 D で未チェック条件がゼロになる #490 は `phase/done` 遷移に加えて close する** — reason: #490 は Pre-merge AC 3 件が全件チェック済みで実装は着地しており、OPEN のまま残っているのは post-merge 条件の待ちだけである。retire でその待ちが消える以上、`phase/done` かつ OPEN は phase セマンティクスと矛盾し、`gh issue list --state open` のバックログに未完了として残り続ける。#1166 方式の対象 6 件はいずれも CLOSED 済みだったため close の可否は前例がなく、ここで明示的に決める
  - Other candidates: `phase/done` ラベルのみ付与し OPEN のまま残す (AC 6 の文言は満たすがバックログに未完了として残存) / close せず Issue 本文に retire 注記を書く (#1166 方式は本文を編集しない方式であり矛盾する)
- **既に `- [x]` かつ `phase/done` へ到達済みの 3 行 (#1135 / #961 / #484 条件1) は分類 A として記録のみ行い、Issue 本文もラベルも触らない** — reason: #1165 の再型付け後に実際に PASS 判定されており、「発火時に判定できる」ことが実績で実証済みである。AC 1 は 16 行すべての分類記載を求めるため記録対象からは外せないが、処理は不要
  - Other candidates: 実査対象から除外し 13 行として扱う (AC 1 の「16 AC 行すべて」に反する) / 再度分類し直す (既に PASS した AC を再評価する意味がない)

## Changed Files

- `docs/reports/observation-ac-audit-d3.md`: 新規作成 — 16 AC 行の A/B/C/D/E 分類表、A 7 行の判定根拠 (情報源)、B 1 行 / E 6 行の変更内容、D 2 行の retire 理由、E 6 行の `/verify` 実行時判定手順、`event=watchdog-kill` / `event=pr-review-full` の event 固有観測窓、#477 の処理、母集団前提の訂正 (#1242 による `--state all` 化)、マッチ集合の確認結果
- `docs/structure.md`: 変更不要 — Directory Layout tree に `docs/reports/` は既出 (line 62)。Key Files 側は「スクリプトが消費する report ファイル」のみ列挙する方針 (`orchestration-recoveries.md` / `orchestration-fallbacks-archive.md` が該当) であり、本記録ファイルは消費側スクリプトを持たない (`grep -n "reports" docs/structure.md` で確認済み)
- `docs/ja/` 同期: 対象外 — `docs/translation-workflow.md` § Exclusions が `docs/reports/` を明示的に除外 (line 21 で確認済み)
- リポジトリ外 (GitHub Issue 本文, 6 AC 行 / 5 Issue): 分類 E — `<!-- verify-type: observation event=auto-run -->` → `<!-- verify-type: manual -->`。うち #513 / #512 / #477 の 3 行は条件文も同時に書き換え
- リポジトリ外 (GitHub Issue 本文, 1 AC 行 / 1 Issue): 分類 B — #465 の条件文を書き換え (`event=auto-run` は維持)
- リポジトリ外 (GitHub Issue コメント, 2 Issue): 分類 D — #490 / #491 へ retire 決定コメントを投稿 (本文の `### Post-merge` は編集しない)
- リポジトリ外 (GitHub ラベル, 2 Issue): #490 / #491 を `phase/verify` → `phase/done` へ遷移
- リポジトリ外 (GitHub Issue state, 1 Issue): #490 を close

## 実査結果: 16 AC 行の分類

### 分類 A (7 行) — 維持。判定根拠を記録

| Issue / 条件 | event タグ | 判定根拠 (どの情報源で PASS/FAIL が決まるか) |
|---|---|---|
| #1135 | `auto-run when=mode:batch` | **既に `- [x]` / `phase/done`**。再型付け後に実際に PASS 判定されており「発火時に判定できる」ことが実績で実証済み。処理不要 |
| #961 | `auto-run` | **既に `- [x]` / `phase/done`**。同上 |
| #484 条件1 | `auto-run` | **既に `- [x]` / `phase/done`**。同上 (同 Issue の条件2 は #1165 が `### Retired Post-merge Conditions` へ退避済みで本 sub-issue の対象外) |
| #478 条件1 | `auto-run when=mode:batch` | batch run 自身が観測対象。`when=mode:batch` ゲートが batch 実行に絞り込んだうえで、その run の wrapper ログのスキップ警告メッセージで判定できる。blocked Issue を含まない batch では SKIPPED になるが、これは `modules/observation-trigger.md` § Conditions That Cannot Be Pre-Excluded のとおり設計どおりの挙動 |
| #478 条件2 | `auto-run when=mode:batch` | 同上。checkpoint JSON (`.tmp/auto-checkpoint-*.json`) の `remaining` 配列がスキップされた Issue 番号を保持しているかで判定できる |
| #535 | `watchdog-kill` | 後述「event 固有の観測窓」参照 |
| #575 | `pr-review-full config=capabilities.workflow when=execution-context:main` | 後述「event 固有の観測窓」参照 |

### 分類 B (1 行) — 条件文を書き換え

| Issue | 現在の条件文 | 書き換え後 | 理由 |
|---|---|---|---|
| #465 | `/auto` 実行で silent no-op（exit 0 だが実装なし）が自動検出され、3-tier recovery へ流れることを実運用でモニタする | `/auto` 実行で silent no-op (exit 0 だが実装なし) が `reconcile-phase-state.sh --check-completion` により検出され 3-tier recovery へ流れた事例が、`docs/reports/orchestration-recoveries.md` に 1 件以上記録されている | 観測対象 (silent no-op 検出 → recovery) は `/auto` run 内で発生し `event=auto-run` の観測窓は正しく開くが、「実運用でモニタする」には終端がなく、いつ PASS になるかが一意に決まらない。#1251 の規約に従い判定に必要な情報源 (`orchestration-recoveries.md`) と終端 (1 件以上) を条件文自身に含める。`event=auto-run` は維持 |

### 分類 C (0 行)

該当なし。判定不能と判断した 2 行 (#490 / #491) と差し戻す 6 行のいずれも、`modules/verify-classifier.md` § observation Type が定める 5 つの有効値 (`pr-review-full` / `pr-review-light` / `auto-run` / `watchdog-kill` / `fix-cycle`) のどれに差し替えても観測窓が開かない。特に #710 条件2 が待つ `/triage` 実行に対応する event 名は存在しない。

### 分類 D (2 行) — #1166 方式で retire

| Issue | 条件文 | retire 理由 | retire 後 |
|---|---|---|---|
| #491 | `/verify` 実行前に `workflow_dispatch` を促す運用が実際のワークフローで機能することを確認 | 本リポジトリの `.github/workflows/` は `dco.yml` / `kanban-automation.yml` / `test.yml` の 3 件で、いずれも `schedule:` トリガーを持たない (実測)。cron 依存 post-merge AC が本リポジトリに発生しない以上、「`/verify` 前に `workflow_dispatch` で事前トリガーする運用」が機能する場面が原理的に生じない。`modules/verify-patterns.md` §13 のガイドラインは downstream プロジェクト向けであり、upstream からは観測不能。実装の正しさは Pre-merge AC (全件チェック済み) が担保 | `phase/done` へ遷移 (CLOSED のまま) |
| #490 | 実際の Issue AC で cron 依存条件に注記が付くことを 1 件以上のサンプルで確認 | 同根。cron スケジュールワークフローが存在しない以上、本リポジトリの Issue AC に cron 依存条件が現れず、注記対象のサンプルが原理的に生じない。#490 自身の本文も「#491: workflow_dispatch 推奨ガイドラインとして §13 追加済み（本 Issue の受け入れ条件を実質カバー）」と記録しており、実装の正しさは Pre-merge AC 3 件 (全件チェック済み、`section_contains` による機械検証) が担保 | `phase/done` へ遷移 + **close** |

いずれも #1166 方式: AC 行は編集せず (`### Post-merge` を触らない)、retire 理由を Issue コメントとして投稿し、ラベルを `phase/verify` → `phase/done` へ遷移させる。

### 分類 E (6 行) — `verify-type: manual` へ差し戻し

いずれも「指定 event の発火が、条件文の要求する観測対象をその run 自身の中に生成しない」型である。`auto-run` の発火は `/auto` が完走したことしか保証せず、条件文が要求する**内容的性質を持つ成果物**や**特定環境での実行**は保証しない。一方 `/verify` 実行時に Claude が能動的にコマンドを実行するか蓄積済み成果物を横断検索すれば判定できる。全 6 行が「今すぐ `/verify` で判定できる」側であり、**capability 待ちは 0 行** (`capability=<key>` の併記対象なし)。

| Issue / 条件 | 差し戻し理由 | `/verify` 実行時の判定手順 | 条件文の書き換え |
|---|---|---|---|
| #1056 | `auto-run` の発火は「`pup` 未インストール環境で `html_check` を含む AC が実行された」ことを保証しない | 本リポジトリで `command -v pup` が不在を返すことを確認 (2026-08-09 実測: 不在) したうえで、`html_check` verify command を 1 件実際に実行し、UNCERTAIN ではなく PASS/FAIL が返ることを確かめる | なし (条件文は具体的) |
| #710 条件1 | `auto-run` の発火は `/issue` phase が走ったことしか示さず、`Blocked by #N` を body に持つ Issue が起票されたかは保証しない | body に `Blocked by #N` を含む既存 Issue を 1 件選び、`scripts/get-blocked-by.sh <N>` / `gh-graphql.sh` の `blockedByIssues` クエリで relationship が設定済みかを確認する | なし (条件文は具体的) |
| #710 条件2 | 同上。`/triage` に対応する有効 event 名も存在しない | body-only `Blocked by #N` を持つ既存 Issue に対し `scripts/gh-check-blocking.sh <N>` を実行し、GraphQL 側へ backfill されることを確認する | なし (条件文は具体的) |
| #513 | 「次の同種 Issue」は内容的性質であり `event=` でも `when=` 3 軸でも表現できない | #513 のマージ (2026-06-09) 以降に作成された Issue のうち間接反映 AC を含むものを `gh issue list` + 本文検索で列挙し、post-merge manual または verify command 型に分類されているかを確認する | あり — 母集団 (「#513 マージ以降に作成された Issue のうち間接反映 AC を含むもの」) を条件文に明記 |
| #512 | 「次のユースケース」は内容的性質であり事前排除できない | #512 のマージ (2026-06-09) 以降に作成された `docs/spec/*.md` のうち距離ルールを定義するものを grep で列挙し、「A 以上かつ B 以下」表記が使われているかを確認する | あり — 母集団 (「#512 マージ以降に作成された `docs/spec/*.md` のうち距離ルールを定義するもの」) を条件文に明記 |
| #477 | 親 #1270 が名指しした実例。「外部 API 統合 Spec」という Spec の内容的性質は event で表現できない (親 Issue の表がそのまま該当) | #477 のマージ (2026-06-14) 以降に作成された `docs/spec/*.md` のうち外部 API を呼ぶ実装を含むものを grep で列挙し、実レスポンスフォーマットと異常コード対処方針が明記されているかを確認する | あり — 母集団 (「#477 マージ以降に作成された `docs/spec/*.md` のうち外部 API 統合を含むもの」) を条件文に明記 |

### event 固有の観測窓 (`watchdog-kill` / `pr-review-full`)

本 sub-issue は 3 つの担当範囲のうち唯一 `auto-run` 以外の event を含む。両者は `auto-run` と観測窓の開き方が異なる。

**#535 (`event=watchdog-kill`, 分類 A)**

- 観測窓: `scripts/claude-watchdog.sh:138-140` の kill handler が `observation-trigger.sh --event watchdog-kill` を呼ぶ時点。`auto-run` が「`/auto` の完走」で開くのに対し、こちらは **`/auto` が完走しなかったとき**にだけ開く。両者は排他に近い関係にある
- 判定根拠: `docs/reports/orchestration-recoveries.md` の該当エントリ。`### Recovery Applied` に Tier 3 の `recover` plan が `validate-recovery-plan.sh` を通過して適用されたことが記録され、`unsupported op` エラーが記録されていなければ PASS
- 補強事実: #535 のマージ (2026-06-06) 後、2026-07-02 の `code-pr-external-timeout-kill` エントリ (Issue #875) で Tier 3 が `run_command` ベースの 3 step plan (`git push` → `gh pr create` → `gh-label-transition.sh`) を提出し、validate 通過・適用成功している。ただしこの kill は外部 Bash-tool timeout によるもので `claude-watchdog.sh` の内部 watchdog kill ではないため、`event=watchdog-kill` の発火実績としては数えない。条件文の核心 (`unsupported op` なしに commit→push→PR create で復旧できる) は既に一度実証されている
- watchdog kill が「PR 作成前」でないタイミングで起きた run では SKIPPED になる。`when=` の `recovery-tier` 軸は run facts JSON (= `/auto` 実行の記述) に対して評価されるため `event=watchdog-kill` では意味を持たず (`modules/observation-trigger.md` § Condition Check Gate (`when=`))、事前排除は行わない

**#575 (`event=pr-review-full config=capabilities.workflow when=execution-context:main`, 分類 A)**

- 観測窓: `/review --full` の完了時。`auto-run` が `/auto` パイプライン全体の完走で開くのに対し、こちらは review フェーズ単体で開く
- 2 段のゲートが掛かる。`config=capabilities.workflow` は本リポジトリで `true` (`.wholework.yml` の `capabilities: workflow: true`) のため通過する。`when=execution-context:main` は `/review` が main context (ユーザーの直接実行) で走った run にのみ通す
- `execution-context:main` ゲートは正しい。`skills/review/workflow-guidance.md` は「re-invocation guarantee が無い実行面 (headless `claude -p`、fork 実行された Skill) では Workflow tool を起動せず static Task fan-out へフォールバックする」と定めており、`/auto` 経由の `/review` (= `run-review.sh` の fork context) では Workflow 経路自体が走らない。つまり条件文が要求する「Workflow 経路で完走」は main context でしか成立しない
- 判定根拠: `/review` Step 14 の完了レポートに `skills/review/workflow-guidance.md` § Completion Report Addition が定める `Workflow mode (capabilities.workflow: true):` 見出しと概算トークン使用量が出力されているか

## Implementation Steps

1. `docs/reports/observation-ac-audit-d3.md` を新規作成する。本 Spec の「実査結果: 16 AC 行の分類」節 (分類 A/B/C/D/E の各表 + event 固有の観測窓) をそのまま記録内容とし、加えて後掲 Notes の「母集団前提の訂正」「#478 の対象外事項」を記載する (→ acceptance criteria 1, 2, 3, 4)
2. (after 1) 分類 E の 6 AC 行 / 5 Issue (#1056 / #710 条件1 / #710 条件2 / #513 / #512 / #477) について、Issue 本文の当該行の `<!-- verify-type: observation event=auto-run -->` を `<!-- verify-type: manual -->` へ置換する。#513 / #512 / #477 の 3 行は同じ編集で条件文も分類 E 表の「条件文の書き換え」列のとおり母集団定義を含む形に書き換える。手順は Issue ごとに `gh issue view <N> --json body` → `.tmp/issue-body-<N>.md` へ Write → `scripts/gh-issue-edit.sh <N> .tmp/issue-body-<N>.md` → 一時ファイル削除
3. (after 1) 分類 B の 1 AC 行 (#465) について、分類 B 表の「書き換え後」列のとおり条件文を書き換える。`<!-- verify-type: observation event=auto-run -->` タグは維持する。手順は step 2 と同じ (parallel with 2)
4. (after 2, 3) step 2 / step 3 で書き戻した 6 Issue 分の `.tmp/issue-body-<N>.md` に対し `bash ${CLAUDE_PLUGIN_ROOT}/scripts/check-ac-checkbox-format.sh .tmp/issue-body-<N>.md` を実行し exit 0 (形式違反なし) を確認する。親 #1270 Notes の指示に従う。権限で拒否された場合は同等判定を `python3` ワンライナーで代替する (後掲 Tool Dependencies 参照)
5. (after 1) 分類 D の 2 Issue (#491 / #490) へ retire 決定コメントを投稿する。本文には (a) `## Retire 決定` 見出し、(b) 分類 D 表の該当セルの retire 理由、(c) 起点 Issue (#1276) と retire 方式の出典 (#1166) への参照 を含める。`.tmp/retire-comment-<N>.md` へ Write → `scripts/gh-issue-comment.sh <N> .tmp/retire-comment-<N>.md` → 一時ファイル削除。**Issue 本文の `### Post-merge` は編集しない** (→ acceptance criteria 5)
6. (after 5) `scripts/gh-label-transition.sh 491 done` / `scripts/gh-label-transition.sh 490 done` を実行し `phase/verify` → `phase/done` へ遷移させる。さらに #490 は OPEN のため `gh api -X PATCH repos/{owner}/{repo}/issues/490 -f state=closed` で close する (→ acceptance criteria 6)
7. (after 2, 3) `scripts/opportunistic-search.sh --event auto-run --dry-run` を実行し、(a) 分類 B の #465 が条件文書き換え後もマッチ集合に含まれること、(b) 分類 E の 5 Issue が `manual` への差し戻しにより意図的にマッチ集合から外れたこと、を Issue 番号単位で確認する。件数差分ではなく個別含有で判定する (#1163 Code Retrospective の指摘に従う) (→ acceptance criteria 7)
8. (after 6, 7) step 4 / step 6 / step 7 の実行結果を `docs/reports/observation-ac-audit-d3.md` の `## 実施記録` 節へ追記する。retire 2 件については「本文の `### Post-merge` を編集していないこと」と「`phase/done` 遷移後の GitHub 実状態 (ラベル / state)」を Issue 単位で明記する (→ acceptance criteria 5, 6, 7)

## Verification

### Pre-merge

- <!-- verify: rubric "docs/reports/observation-ac-audit-d3.md に 16 AC 行すべての分類 (A/B/C/D/E) と、A については判定根拠 (どの情報源で PASS/FAIL が決まるか)、B/C については変更内容、D については retire 理由、E については差し戻し理由と /verify 実行時の判定手順が Issue 番号・AC 行単位で記載されている" --> 担当する 16 AC 行すべてについて、A/B/C/D/E の分類と判断根拠が記録ファイルに Issue 単位・AC 行単位で記載されている
- <!-- verify: file_exists "docs/reports/observation-ac-audit-d3.md" --> 記録ファイル `docs/reports/observation-ac-audit-d3.md` が作成されている
- <!-- verify: rubric "docs/reports/observation-ac-audit-d3.md に event=watchdog-kill の 1 行と event=pr-review-full の 1 行について、それぞれの event 固有の観測窓と判定根拠が個別に記載されている" --> `event=watchdog-kill` / `event=pr-review-full` の 2 行について、`auto-run` とは異なる観測窓の開き方を踏まえた判定根拠が個別に記録されている
- <!-- verify: rubric "docs/reports/observation-ac-audit-d3.md に #477 の分類結果と処理内容が記載されている" --> 親 Issue が名指しした #477 が A/B/C/D/E のいずれかに分類され処理されている
- <!-- verify: rubric "分類 D と判定した AC 行について、retire 理由が対象 Issue のコメントとして投稿され、かつ対象 Issue 本文の ### Post-merge 節が編集されていないことが docs/reports/observation-ac-audit-d3.md に Issue 単位で記載されている" --> 分類 D の AC 行が #1166 方式で retire され、対象 Issue 本文の `### Post-merge` は編集されていない
- <!-- verify: rubric "retire 完了により未チェック条件がゼロになった Issue が phase/done へ遷移していることが docs/reports/observation-ac-audit-d3.md に Issue 単位で記載され、GitHub 上の実状態と一致している" --> 分類 D の retire により未チェック post-merge 条件が残らなくなった Issue が `phase/done` へ遷移している
- <!-- verify: rubric "条件文を変更した AC について、変更後のマッチ集合への含有が個別に確認され docs/reports/observation-ac-audit-d3.md に記録されている" --> 分類 B/C で条件文を変更した AC 行が、変更後も `opportunistic-search.sh --event <name> --dry-run` のマッチ集合に含まれる (または意図的に外れたことが記録されている)

### Post-merge

なし (効果測定は親 #1270 に集約)

## Tool Dependencies

### Bash Command Patterns

- `gh api:*` — #490 の close に使用 (`gh api -X PATCH repos/{owner}/{repo}/issues/490 -f state=closed`)。`skills/code/SKILL.md` の `allowed-tools` に `gh issue close:*` は含まれないが `gh api:*` は含まれるため、SKILL.md の変更なしで実行できる
- `${CLAUDE_PLUGIN_ROOT}/scripts/check-ac-checkbox-format.sh:*` — step 4 の形式検証に使用。**`skills/code/SKILL.md` の `allowed-tools` に含まれていない** (実測確認済み)。プロジェクトの `.claude/settings.json` は `Bash(/Users/saito/src/wholework/scripts/*.sh *)` を許可しているため通る可能性が高いが、拒否された場合は `python3:*` (allowed-tools に含まれる) による同等判定へフォールバックする。#1165 が同じ制約に当たり python3 ワンライナーで代替した前例がある。本 Issue のスコープでは `skills/code/SKILL.md` の変更は行わない

### Built-in Tools

- `Read` / `Write` / `Edit` / `Grep` / `Glob` — いずれも `skills/code/SKILL.md` の `allowed-tools` に既存

### MCP Tools

なし

## Notes

### 母集団前提の訂正 — 一次資料の「OPEN 2 件は dispatch 母集団に入らない」は失効している

一次資料 `docs/reports/manual-ac-retype-d3.md` § 「OPEN 2 件 (#490 / #465) は dispatch 母集団に入らない」は、`scripts/opportunistic-search.sh:202` の母集団取得が `--state closed` 固定であることを根拠にしていた。しかし **#1242 (commit `5bf85f5f` / PR #1272) により該当行は `--state all` へ変更済み** である (現行 line 293、コメントに「all states — OPEN Issues that stay in `phase/verify` are structurally excluded from this pipeline otherwise; Issue #1242」と明記)。

実測 (2026-08-09) でも `gh issue list --label phase/verify --state all --search "verify-type: observation in:body"` の母集団 120 件に #490 / #465 がともに含まれることを確認した。したがって本 sub-issue では OPEN 2 件も他と同じ扱いで実査する。この訂正は記録ファイルにも記載する。

### Issue 本文との齟齬 — 16 AC 行のうち 3 行は既に判定済み

Issue 本文の「担当範囲」表は 16 AC 行を実査対象とするが、実測 (2026-08-09) では **#1135 / #961 / #484 条件1 の 3 行が既に `- [x]` かつ所属 Issue が `phase/done` へ到達済み**である。再型付け後に実際に PASS 判定されており、「発火時に判定できる」ことが実績で実証されている。AC 1 は 16 行すべての分類記載を求めるため、この 3 行は分類 A として記録対象に含めるが、Issue 本文もラベルも編集しない (Auto-Resolve Log 参照)。Issue 本文側にもこの事実を追記する。

### #478 の対象外事項 (記録ファイルに注記のみ)

#478 は本 sub-issue の 2 AC 行 (どちらも分類 A) とは別に、`### Pre-merge (auto-verified)` に未チェックの `github_check "gh run list --workflow=test.yml --commit=$(git rev-parse HEAD) ..."` 行を 1 件持つ。`modules/verify-classifier.md` § 「Why `--commit` is not used」が「`--commit=` を `git rev-parse HEAD` で解決する形は `/verify` 実行時の base branch HEAD を指すため、この Issue 自身の実装を検証できない」と明記している既知の欠陥形である。本 sub-issue のスコープ (post-merge observation AC の実査) 外のため処理せず、記録ファイルに事実として注記するに留める。

### `manual` 型名について

分類 E は現行の型名 `manual` へ差し戻す。`manual` は #1278 で `deferred` への改名が設計済みだが保留中であり、親 #1270 も「本 Issue は現行の型名 `manual` で差し戻す」と明記している。改名が着地した場合の追従は #1278 側で扱う。

### 分類 E に capability 待ちが 0 行である理由

親 #1270 は「`.wholework.yml` に該当 capability が無いだけの条件は D ではなく E とし、`capability=<key>` を併記する」と定めるが、本 sub-issue の E 6 行はいずれも `gh` / `git` / grep / 既存スクリプトのみで判定でき、`capabilities.browser` や `capabilities.visual-diff` を要する条件を含まない。したがって「今すぐ `/verify` で判定できる」6 行 / 「装備待ち」0 行となる。親の集約レポート § 「E の内訳 (capability 待ちの分離)」へはこの内訳を引き渡す。

### ドキュメント更新の要否

`modules/doc-checker.md` の Impact Determination Criteria のいずれにも該当しない。本 Issue は既存の retire / 再型付けパターンを 16 の具体的な AC 行に適用する一回限りの運用作業であり、新しい仕組みの導入もディレクトリ構成変更も含まない。`docs/workflow.md` / README / Steering Documents の更新は不要。
