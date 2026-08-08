# observation AC 実査記録 (#1165 由来 区分 D3)

Issue #1276 (親 #1270 の sub-issue) の実査記録。#1165 が `verify-type: manual` から `verify-type: observation` へ再型付けした **16 AC 行 / 14 Issue** について、「どの event が発火したとき、何を根拠に PASS 判定できるか」を 1 行ずつ実査し、A/B/C/D/E へ分類した。

実査結果: **A 7 行 / B 1 行 / C 0 行 / D 2 行 / E 6 行**。

## 母集団前提の訂正

一次資料 `docs/reports/manual-ac-retype-d3.md` § 「OPEN 2 件 (#490 / #465) は dispatch 母集団に入らない」は、`scripts/opportunistic-search.sh` の母集団取得が `--state closed` 固定であることを根拠にしていたが、**#1242 (commit `5bf85f5f` / PR #1272) により `--state all` へ変更済み**であり、この前提は失効している。実測 (2026-08-09) でも `gh issue list --label phase/verify --state all --search "verify-type: observation in:body"` の母集団 120 件に #490 / #465 がともに含まれることを確認した。本 sub-issue では OPEN 2 件も他と同じ扱いで実査した。

## 実査対象の現況

16 AC 行のうち **3 行 (#1135 / #961 / #484 条件1) は既に `- [x]` かつ所属 Issue が `phase/done` へ到達済み**である。#1165 の再型付け後に実際に PASS 判定されており、「発火時に判定できる」ことが実績で実証されている。これらは分類 A として記録対象に含めるが、Issue 本文もラベルも編集していない。

## 分類 A (7 行) — 維持。判定根拠を記録

| Issue / 条件 | event タグ | 判定根拠 (どの情報源で PASS/FAIL が決まるか) |
|---|---|---|
| #1135 | `auto-run when=mode:batch` | **既に `- [x]` / `phase/done`**。再型付け後に実際に PASS 判定されており「発火時に判定できる」ことが実績で実証済み。処理不要 |
| #961 | `auto-run` | **既に `- [x]` / `phase/done`**。同上 |
| #484 条件1 | `auto-run` | **既に `- [x]` / `phase/done`**。同上 (同 Issue の条件2 は #1165 が `### Retired Post-merge Conditions` へ退避済みで本 sub-issue の対象外) |
| #478 条件1 | `auto-run when=mode:batch` | batch run 自身が観測対象。`when=mode:batch` ゲートが batch 実行に絞り込んだうえで、その run の wrapper ログのスキップ警告メッセージで判定できる。blocked Issue を含まない batch では SKIPPED になるが、これは `modules/observation-trigger.md` § Conditions That Cannot Be Pre-Excluded のとおり設計どおりの挙動 |
| #478 条件2 | `auto-run when=mode:batch` | 同上。checkpoint JSON (`.tmp/auto-checkpoint-*.json`) の `remaining` 配列がスキップされた Issue 番号を保持しているかで判定できる |
| #535 | `watchdog-kill` | 「event 固有の観測窓」参照 |
| #575 | `pr-review-full config=capabilities.workflow when=execution-context:main` | 「event 固有の観測窓」参照 |

## 分類 B (1 行) — 条件文を書き換え

| Issue | 現在の条件文 | 書き換え後 | 理由 |
|---|---|---|---|
| #465 | `/auto` 実行で silent no-op（exit 0 だが実装なし）が自動検出され、3-tier recovery へ流れることを実運用でモニタする | `/auto` 実行で silent no-op (exit 0 だが実装なし) が `reconcile-phase-state.sh --check-completion` により検出され 3-tier recovery へ流れた事例が、`docs/reports/orchestration-recoveries.md` に 1 件以上記録されている | 観測対象 (silent no-op 検出 → recovery) は `/auto` run 内で発生し `event=auto-run` の観測窓は正しく開くが、「実運用でモニタする」には終端がなく、いつ PASS になるかが一意に決まらない。#1251 の規約に従い判定に必要な情報源 (`orchestration-recoveries.md`) と終端 (1 件以上) を条件文自身に含める。`event=auto-run` は維持 |

## 分類 C (0 行)

該当なし。判定不能と判断した 2 行 (#490 / #491) と差し戻す 6 行のいずれも、`modules/verify-classifier.md` § observation Type が定める 5 つの有効値 (`pr-review-full` / `pr-review-light` / `auto-run` / `watchdog-kill` / `fix-cycle`) のどれに差し替えても観測窓が開かない。特に #710 条件2 が待つ `/triage` 実行に対応する event 名は存在しない。

## 分類 D (2 行) — #1166 方式で retire

| Issue | 条件文 | retire 理由 | retire 後 |
|---|---|---|---|
| #491 | `/verify` 実行前に `workflow_dispatch` を促す運用が実際のワークフローで機能することを確認 | 本リポジトリの `.github/workflows/` は `dco.yml` / `kanban-automation.yml` / `test.yml` の 3 件で、いずれも `schedule:` トリガーを持たない (実測)。cron 依存 post-merge AC が本リポジトリに発生しない以上、「`/verify` 前に `workflow_dispatch` で事前トリガーする運用」が機能する場面が原理的に生じない。`modules/verify-patterns.md` §13 のガイドラインは downstream プロジェクト向けであり、upstream からは観測不能。実装の正しさは Pre-merge AC (全件チェック済み) が担保 | `phase/done` へ遷移 (CLOSED のまま) |
| #490 | 実際の Issue AC で cron 依存条件に注記が付くことを 1 件以上のサンプルで確認 | 同根。cron スケジュールワークフローが存在しない以上、本リポジトリの Issue AC に cron 依存条件が現れず、注記対象のサンプルが原理的に生じない。#490 自身の本文も「#491: workflow_dispatch 推奨ガイドラインとして §13 追加済み（本 Issue の受け入れ条件を実質カバー）」と記録しており、実装の正しさは Pre-merge AC 3 件 (全件チェック済み、`section_contains` による機械検証) が担保 | `phase/done` へ遷移 + **close** |

いずれも #1166 方式: AC 行は編集せず (`### Post-merge` を触らない)、retire 理由を Issue コメントとして投稿し、ラベルを `phase/verify` → `phase/done` へ遷移させる。

## 分類 E (6 行) — `verify-type: manual` へ差し戻し

いずれも「指定 event の発火が、条件文の要求する観測対象をその run 自身の中に生成しない」型である。`auto-run` の発火は `/auto` が完走したことしか保証せず、条件文が要求する**内容的性質を持つ成果物**や**特定環境での実行**は保証しない。一方 `/verify` 実行時に Claude が能動的にコマンドを実行するか蓄積済み成果物を横断検索すれば判定できる。全 6 行が「今すぐ `/verify` で判定できる」側であり、**capability 待ちは 0 行** (`capability=<key>` の併記対象なし)。

| Issue / 条件 | 差し戻し理由 | `/verify` 実行時の判定手順 | 条件文の書き換え |
|---|---|---|---|
| #1056 | `auto-run` の発火は「`pup` 未インストール環境で `html_check` を含む AC が実行された」ことを保証しない | 本リポジトリで `command -v pup` が不在を返すことを確認 (2026-08-09 実測: 不在) したうえで、`html_check` verify command を 1 件実際に実行し、UNCERTAIN ではなく PASS/FAIL が返ることを確かめる | なし (条件文は具体的) |
| #710 条件1 | `auto-run` の発火は `/issue` phase が走ったことしか示さず、`Blocked by #N` を body に持つ Issue が起票されたかは保証しない | body に `Blocked by #N` を含む既存 Issue を 1 件選び、`scripts/get-blocked-by.sh <N>` / `gh-graphql.sh` の `blockedByIssues` クエリで relationship が設定済みかを確認する | なし (条件文は具体的) |
| #710 条件2 | 同上。`/triage` に対応する有効 event 名も存在しない | body-only `Blocked by #N` を持つ既存 Issue に対し `scripts/gh-check-blocking.sh <N>` を実行し、GraphQL 側へ backfill されることを確認する | なし (条件文は具体的) |
| #513 | 「次の同種 Issue」は内容的性質であり `event=` でも `when=` 3 軸でも表現できない | #513 のマージ (2026-06-09) 以降に作成された Issue のうち間接反映 AC を含むものを `gh issue list` + 本文検索で列挙し、post-merge manual または verify command 型に分類されているかを確認する | あり — 母集団 (「#513 マージ以降に作成された Issue のうち間接反映 AC を含むもの」) を条件文に明記 |
| #512 | 「次のユースケース」は内容的性質であり事前排除できない | #512 のマージ (2026-06-09) 以降に作成された `docs/spec/*.md` のうち距離ルールを定義するものを grep で列挙し、「A 以上かつ B 以下」表記が使われているかを確認する | あり — 母集団 (「#512 マージ以降に作成された `docs/spec/*.md` のうち距離ルールを定義するもの」) を条件文に明記 |
| #477 | 親 #1270 が名指しした実例。「外部 API 統合 Spec」という Spec の内容的性質は event で表現できない (親 Issue の表がそのまま該当) | #477 のマージ (2026-06-14) 以降に作成された `docs/spec/*.md` のうち外部 API を呼ぶ実装を含むものを grep で列挙し、実レスポンスフォーマットと異常コード対処方針が明記されているかを確認する | あり — 母集団 (「#477 マージ以降に作成された `docs/spec/*.md` のうち外部 API 統合を含むもの」) を条件文に明記 |

## event 固有の観測窓 (`watchdog-kill` / `pr-review-full`)

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

## #477 の処理

親 Issue #1270 が名指しした実例。分類 E (差し戻し) とし、母集団 (「#477 マージ以降に作成された `docs/spec/*.md` のうち外部 API 統合を含むもの」) を条件文に明記した上で `verify-type: manual` へ差し戻した。詳細は上記「分類 E」表を参照。

## #478 の対象外事項

#478 は本 sub-issue の 2 AC 行 (どちらも分類 A) とは別に、`### Pre-merge (auto-verified)` に未チェックの `github_check "gh run list --workflow=test.yml --commit=$(git rev-parse HEAD) ..."` 行を 1 件持つ。`modules/verify-classifier.md` § 「Why `--commit` is not used」が「`--commit=` を `git rev-parse HEAD` で解決する形は `/verify` 実行時の base branch HEAD を指すため、この Issue 自身の実装を検証できない」と明記している既知の欠陥形である。本 sub-issue のスコープ (post-merge observation AC の実査) 外のため処理せず、事実として注記するに留める。

## 実施記録

### 分類 E (6 行 / 5 Issue) の書き戻し

`#1056` / `#710` (条件1・条件2) / `#513` / `#512` / `#477` の 6 AC 行について、`<!-- verify-type: observation event=auto-run -->` を `<!-- verify-type: manual -->` へ置換した。`#513` / `#512` / `#477` の 3 行は条件文も母集団定義を含む形に書き換えた (`#1056` / `#710` 条件1・条件2 の 3 行は条件文が既に具体的なためタグ差し替えのみ)。書き戻しは `.tmp/issue-body-<N>.md` 経由 (`gh-issue-edit.sh`) で行い、対象 AC 行の HTML コメントと条件文のみを置換し、他の記述は変更していない。

### 分類 B (1 行) の書き戻し

`#465` の post-merge 条件文を、`docs/reports/orchestration-recoveries.md` への記録件数 (1 件以上) を判定根拠として明記する形に書き換えた。`event=auto-run` タグは維持した。

### checkbox 形式検証 (Implementation Step 4)

書き戻した 6 Issue 分の `.tmp/issue-body-<N>.md` (削除前) に対し `scripts/check-ac-checkbox-format.sh` を実行し、全件 `exit=0` (形式違反なし) を確認した。権限拒否は発生しなかったため python3 フォールバックは使用していない。

| Issue | 結果 |
|---|---|
| #1056 | exit=0 |
| #710 | exit=0 |
| #513 | exit=0 |
| #512 | exit=0 |
| #477 | exit=0 |
| #465 | exit=0 |

### 分類 D (2 行) の retire (Implementation Step 5, 6)

- **#491**: retire 決定コメントを投稿した (https://github.com/saitoco/wholework/issues/491#issuecomment-5228218405)。Issue 本文の `### Post-merge` 節は編集していない。ラベルを `phase/verify` → `phase/done` へ遷移させた。CLOSED のまま。
- **#490**: retire 決定コメントを投稿した (https://github.com/saitoco/wholework/issues/490#issuecomment-5228218581)。Issue 本文の `### Post-merge` 節は編集していない。ラベルを `phase/verify` → `phase/done` へ遷移させたうえで、`gh api -X PATCH .../issues/490 -f state=closed` により OPEN → CLOSED へ遷移させた (`state_reason: completed` を確認)。

いずれも retire により未チェック post-merge 条件がゼロになったため `phase/done` 遷移が GitHub 上の実状態 (ラベル・close) と一致している。

### opportunistic-search dry-run 確認 (Implementation Step 7)

`scripts/opportunistic-search.sh --event auto-run --dry-run` を実行し (母集団 120 Issue)、以下を Issue 番号単位で確認した:

- **分類 B の #465**: マッチ集合に含まれることを確認した (書き換え後の条件文「`/auto` 実行で silent no-op (exit 0 だが実装なし) が `reconcile-phase-state.sh --check-completion` により検出され 3-tier recovery へ流れた事例が、`docs/reports/orchestration-recoveries.md` に 1 件以上記録されている」がそのまま出力に現れている)。
- **分類 E の 5 Issue (#1056 / #710 / #513 / #512 / #477)**: いずれもマッチ集合から意図的に外れていることを確認した (`verify-type: manual` への差し戻しにより observation dispatch の母集団から除外された)。

件数差分ではなく個別含有で判定した (#1163 Code Retrospective の指摘に従う)。
