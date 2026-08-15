# Issue #1358: docs: CronCreate の永続性に関する記述をドキュメントに実態に合わせて修正

## Overview

#1351 の実装セッションで実証された `CronCreate` の実際の挙動 (session-scoped・in-memory only・7日で自動失効・`permission-mode: auto` 下では無人実行からの自己登録が分類器にブロックされる) と、現在のドキュメント記述 (`modules/autonomy-tier.md` L0 Layer Table、`docs/guide/autonomy.md` L3 tier 節、`docs/tech.md` Autonomy tier 項目) との乖離を解消する。該当3ファイル (+ 日本語ミラー1件) の記述を実態に整合させる。

## Changed Files

- `modules/autonomy-tier.md`: `## L0 Layer Table (exhaustive)` 節の CronCreate 行 (line 25: `| **L3: OS / \`CronCreate\`** | Crontab / cron registry | OS scheduler | Environment-dependent |`) を、session-scoped/in-memory・非 OS レベル・`permission-mode: auto` 下での自己登録制限を反映する記述に修正
- `docs/guide/autonomy.md`: `### L3 Unattended` 節 (line 42-49) の導入文および `Use L3 when:` 箇条書きを、`CronCreate` の実際の制約 (session-scoped/in-memory、7日自動失効、`permission-mode: auto` 下での分類器ブロック) を反映する記述に修正。`Allowed L2→L1 paths: **A, B (CronCreate), C**` の行 (line 51) は変更しない (スコープ外、Notes 参照)
- `docs/tech.md`: `## Architecture Decisions` 節内の Autonomy tier 箇条書き (line 73) の "and L3 (OS scheduler)." 部分を、CronCreate は既に同箇条書き内で L1 に分類済みであり L3 (OS scheduler) は現状いかなる Wholework 機構でも使用されていないことを明記する記述に修正
- `docs/ja/tech.md`: 上記 `docs/tech.md` の変更に対応する日本語ミラー (line 73、「L3（OS スケジューラ）」部分) を同期。`docs/translation-workflow.md` の Sync Procedure により、top-level `docs/*.md` の変更時は必須 (Notes 参照)

## Implementation Steps

1. `modules/autonomy-tier.md` の `## L0 Layer Table (exhaustive)` 節にある CronCreate 行を修正する。Layer 列を `**L3: OS / \`CronCreate\`**` → `**L3: \`CronCreate\`**` (先頭の "OS /" を除去)、Loop state location 列を "Session memory (in-memory only; nothing written to disk)"、Drive mechanism 列を "`CronCreate` (Claude Code primitive; not an OS-level scheduler)"、Persistence 列を "Volatile, session-scoped — recurring jobs auto-expire after 7 days. Under `permission-mode: auto`, unattended self-registration is blocked by the Claude Code auto mode classifier." に変更する (→ acceptance criteria 1, 2)
2. `docs/guide/autonomy.md` の `### L3 Unattended` 節の導入段落 ("Skills write GitHub state and may register persistent cron schedules via `CronCreate`. **Fully unattended operation.**") を、`CronCreate` が session-scoped/in-memory であり永続的な OS レベルスケジューラではないこと、`permission-mode: auto` 下では無人実行からの自己登録が Claude Code auto mode classifier にブロックされ登録には attended session が必要であることを明記する記述に修正する。後続の `Use L3 when:` 箇条書き2・3項目目 ("without any human trigger" / "register cron jobs autonomously" という表現) も、GitHub state 変更 (label 遷移・close/reopen・comment) は無人で行われる一方 `CronCreate` の新規登録には attended session が必要である旨と矛盾しないよう整合させて修正する。`Allowed L2→L1 paths: **A, B (CronCreate), C**` の行 (line 51) はそのまま変更しない (→ acceptance criteria 3, 4)
3. `docs/tech.md` の Autonomy tier 箇条書き末尾 "and L3 (OS scheduler)." を "and L3 (OS scheduler — not currently used by any Wholework mechanism; `CronCreate`, listed under L1 above, is the closest available primitive but is itself session-scoped/in-memory, not an OS-level persistent scheduler — see `modules/autonomy-tier.md`)." に修正する。`docs/translation-workflow.md` の Sync Procedure に従い、同じ修正意図を `docs/ja/tech.md` line 73 の対応箇所 (「L3（OS スケジューラ）」) にも日本語で反映する (→ acceptance criteria 5)

## Verification

### Pre-merge

- <!-- verify: rubric "modules/autonomy-tier.md の L0 Layer Table (CronCreate の行) が、CronCreate は session-scoped/in-memory であり OS レベルの永続スケジューラではないこと、および permission-mode: auto 下では無人実行からの自己登録が制限されうることを反映する記述に修正されている" --> autonomy-tier.md の記述が実態に整合している
- <!-- verify: section_contains "modules/autonomy-tier.md" "L0 Layer Table" "permission-mode" --> L0 Layer Table 節に permission-mode に関する言及がある (rubric の補完機械チェック)
- <!-- verify: rubric "docs/guide/autonomy.md の L3 tier 節の CronCreate に関する説明 ('may register persistent cron schedules' / 'Fully unattended operation') が、実際の制約 (session-scoped、7日自動失効、permission-mode: auto 下での分類器ブロック) を反映する記述に修正されている" --> autonomy.md の記述が実態に整合している
- <!-- verify: section_contains "docs/guide/autonomy.md" "L3 Unattended" "permission-mode" --> L3 Unattended 節に permission-mode に関する言及がある (rubric の補完機械チェック)
- <!-- verify: rubric "docs/tech.md の Autonomy tier に関する記述箇所が、CronCreate を 'OS scheduler' と表現している部分について同様の整合が取られている" --> tech.md の記述が実態に整合している

### Post-merge

- N/A (ドキュメント記述の修正のため、post-merge の追加確認は不要)

## Notes

- **スコープ判断: `docs/product.md` は対象外**: コードベース調査で `docs/product.md` (line 79, Future Direction 箇条書き) にも `docs/tech.md` と酷似した "L1 (... CronCreate) / ... / L3 (OS scheduler)" という表現が存在することを検出した。Issue 本文 (Background) が明示的に引用する対象は `modules/autonomy-tier.md` / `docs/guide/autonomy.md` / `docs/tech.md` の3箇所のみであり、`docs/product.md` は含まれていない。`/issue` フェーズの Issue Retrospective (Auto-Resolve Log) も同種の追加箇所 (`modules/autonomy-tier.md` の L2→L1 Path Catalog B 行「registers a persistent schedule」、同ファイル Tier×Path Matrix の L3 Unattended 行「CronCreate allows self-rescheduling」、`docs/guide/autonomy.md` の "B (CronCreate)" 列挙) を検出した上で明示的にスコープ外とし、「追加ドリフトとして気づかれた場合は別 Issue または本 Issue の scope 拡張として扱う」判断を後続フェーズに委ねていた。非対話モードでの安全側の判断として、本 Issue のスコープは Issue 本文の AC が明示する3ファイルに限定し、`docs/product.md` および上記3箇所は Follow-up 候補として記録するに留める (新規 Issue はこのセッションでは起票しない。起票判断は `/audit drift` の自動検知または人間判断に委ねる)。
- **`docs/ja/tech.md` 同期の根拠**: `docs/translation-workflow.md` の Sync Procedure により、top-level `docs/*.md` ファイルの変更時は `docs/ja/` ミラーの同期が必須 (`docs/spec/`・`docs/reports/`・`docs/ja/` 自身のみ除外対象)。`docs/tech.md` は top-level に該当するため `docs/ja/tech.md` の同期が必須で、line 73 に `docs/tech.md` line 73 と同一パターンの日本語表現 (「L3（OS スケジューラ）」) が存在することを確認済み。一方 `docs/guide/autonomy.md` は `docs/guide/` 配下の nested ファイルであり Sync Procedure の "top-level `docs/*.md`" スコープに含まれない (`docs/ja/guide/autonomy.md` 自体が現時点で未作成であることも確認済み — `docs/guide/autonomy.md` 冒頭の言語切り替えリンクは実際にはリンク切れだが、これは本 Issue のスコープ外の既存ギャップ)。
- **Comment Consumption Procedure による Issue 本文修正**: `/spec` 実行前のコメント消化で、2026-08-15T13:12:09Z の first-class コメント (MEMBER, Triage AC audit) により、Issue 本文の2件の `section_contains` verify command で `heading` 引数に `##`/`###` プレフィックスが残ったままになっているバグを検出した。`modules/verify-executor.md` の `section_contains` 仕様は heading 引数を「対象ファイルの見出し行から先頭の `#` と空白を除去した上で部分一致」させるため、heading 引数側に `#` が残っていると恒久的に UNCERTAIN になる。対象ファイルの実見出し (`## L0 Layer Table (exhaustive)` / `### L3 Unattended`) を確認した上で、Issue 本文の該当2行を `"## L0 Layer Table"` → `"L0 Layer Table"`、`"### L3 Unattended"` → `"L3 Unattended"` に修正し (`gh-issue-edit.sh` で反映済み)、本 Spec の Verification 節にも修正後の値を転記した。

## Consumed Comments

- login: saito / authorAssociation: MEMBER / trust tier: first-class — Issue Retrospective (`/issue 1358 --non-interactive` 実行結果)。Auto-Resolve Log として、修正スコープを Issue 本文が明示的に引用する3箇所に限定する判断と、2件の rubric 補完 `section_contains` AC を追加した理由を記録。https://github.com/saitoco/wholework/issues/1358#issuecomment-5302371969
- login: saito / authorAssociation: MEMBER / trust tier: first-class — Triage AC audit。Issue 本文の2件の `section_contains` verify command で heading 引数に `#`/`##`/`###` プレフィックスが残り恒久的に UNCERTAIN になるバグを指摘。本 `/spec` 実行で Issue 本文を修復案の通り修正済み (Notes 参照)。https://github.com/saitoco/wholework/issues/1358#issuecomment-5302385400

## Code Retrospective

### Deviations from Design
- None — Implementation Steps 1-3 を Spec の記述通りに実施した。

### Design Gaps/Ambiguities
- None newly found。Step 9 の `docs/ja/` sync gap-detection チェックで、`docs/guide/autonomy.md` が翻訳同期スコープ外である Notes 記載の既存判断 (`docs/ja/guide/autonomy.md` 自体が未作成、`docs/guide/` 配下 nested ファイルのため top-level sync procedure 対象外) を機械チェックで再確認した。新規ギャップは見つからなかった。

### Rework
- None。

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- Issue 本文が明示する3ファイル (`modules/autonomy-tier.md` / `docs/guide/autonomy.md` / `docs/tech.md`) + `docs/translation-workflow.md` Sync Procedure が要求する `docs/ja/tech.md` の計4ファイルのみを修正対象とし、`/issue` retrospective・`/spec` Notes が検出した追加ドリフト候補 (`docs/product.md`、`modules/autonomy-tier.md` の Path Catalog B 行・Tier×Path Matrix の L3 Unattended 行、`docs/guide/autonomy.md` の "B (CronCreate)" 列挙行) はスコープ外のまま維持した。
- `docs/guide/autonomy.md` の "Allowed L2→L1 paths: **A, B (CronCreate), C**" 行は Spec 指示通り変更しなかった (CronCreate 自体は依然として L3 で利用可能な経路であり、変わったのは「無人で自己登録できるか」であって「経路として許可されているか」ではないため)。

### Deferred Items
- `docs/product.md` (line 79) の類似表現 ("L1 (... CronCreate) / ... / L3 (OS scheduler)") は Follow-up 候補として記録するに留め、本セッションでは新規 Issue を起票しなかった (Spec Notes の既存判断を維持)。
- `modules/autonomy-tier.md` の Path Catalog B 行「registers a persistent schedule」、Tier×Path Matrix の L3 Unattended 行「CronCreate allows self-rescheduling」も同様に Follow-up 候補としてスコープ外のまま。

### Notes for Next Phase
- Pre-merge AC 5件 (rubric 3件 + section_contains 2件) はすべて `/code` 内で PASS 判定済みで Issue 本文のチェックボックスも更新済み。Post-merge AC は Issue 本文記載の通り N/A。
- ドキュメントのみの変更のため CI 上の追加リスクは低いが、`docs/ja/tech.md` の同期漏れがないか `/verify` でも念のため確認するとよい。
