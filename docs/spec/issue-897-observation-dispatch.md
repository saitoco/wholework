# Issue #897: auto: observation event の interactive emitter が通知のみで /verify を dispatch しない設計乖離を解消

## Overview

`modules/observation-trigger.md` の Output Processing Contract は「dispatch 可能な場合は `/verify` を dispatch し、shell-only context (`claude-watchdog.sh`) の場合のみコメント投稿にフォールバックする」ことを定めているが、実装 `scripts/observation-trigger.sh` は呼び出し元の実行コンテキストを区別せず常にコメント投稿のみを行う。これにより `/auto`・`/review` (LLM セッション内で実行され `Skill` ツールを呼び出せる emitter) が observation event 発火時にコメントは投稿するが `/verify` を実際に dispatch せず、条件成立後もチェックボックスが長期間更新されないまま放置される (実例: #875)。

本 Issue では `scripts/observation-trigger.sh` に matched Issue 番号一覧の stdout 出力を追加し、`/auto`・`/review` の Event-based observation scan ステップでその一覧を受け取って `Skill(skill="wholework:verify", args="$N")` を dispatch する処理を追加する。dispatch は `AUTONOMY_TIER` が `L2`/`L3` の場合のみ実行し (`L1` は既存の advisory-only 挙動を維持)、`skills/triage/SKILL.md` の blocked-by backfill と同型の tier 分岐パターンを踏襲する。`scripts/claude-watchdog.sh` (shell-only context) は変更せず既存のコメント投稿のみのフォールバックを維持する。

## Reproduction Steps

1. Issue に `verify-type: observation event=auto-run` タグ付きの未チェック AC があり、その Issue が `phase/verify` (CLOSED) 状態にある。
2. 別の Issue に対して `/auto` (または `/auto --batch`) を完走させる。完了後、"Event-based observation scan" ステップで `${CLAUDE_PLUGIN_ROOT}/scripts/observation-trigger.sh --event auto-run` が実行される。
3. `observation-trigger.sh` は対象 Issue に `/verify <N>` の実行を促すコメントを投稿するが、`/verify` 自体は呼び出されない。
4. 対象 Issue のチェックボックスは、人間が手動で `/verify <N>` を実行するまで未チェックのまま残る。
5. 実例: Issue #875 は `/auto --batch` セッション (`10389-1783051154`, 2026-07-03) 中に条件が実際には成立していたが `/verify` が dispatch されず、2026-07-04 にユーザーが手動確認するまで放置された。

## Root Cause

`modules/observation-trigger.md` の Emitter Lookup Table は4つの emitter (`/review`、`/auto`、`scripts/claude-watchdog.sh`、`/verify` fix-cycle) を定義し、Output Processing Contract は「dispatch 可能な場合は dispatch、shell-only context の場合のみコメント投稿」と明記している。しかし #656 の実装時、全 emitter 呼び出しを単一の one-liner (`observation-trigger.sh --event <name>`) に統一することが優先され、その結果 `claude-watchdog.sh` (LLM セッションを持たない純粋な shell context で `/verify` を dispatch する手段がない) の制約に合わせて、LLM セッション内で実行される他の emitter (`/auto`、`/review`) も一律コメント投稿のみに単純化された。`scripts/observation-trigger.sh` は呼び出し元が dispatch 判断に使える情報 (matched Issue 番号一覧) を一切外部に返しておらず、これが是正を妨げていた。

## Changed Files

- `scripts/observation-trigger.sh`: 既存のコメント投稿ループの後に matched Issue 番号一覧を改行区切りで stdout に出力する処理を追加する (副作用のコメント投稿は変更しない)
- `tests/observation-trigger.bats`: `success: single match posts one comment` と `success: multiple matches post one comment each` の2テストに stdout 出力内容 (Issue 番号) のアサーションを追加する
- `skills/auto/SKILL.md`: "Event-based observation scan (auto-run event, ...)" 見出し (single-issue route) と "Event-based observation scan (batch, best-effort)" 見出し (batch route) の2箇所に、stdout キャプチャ・`AUTONOMY_TIER` 分岐・`Skill(skill="wholework:verify", args="$N")` dispatch 処理を追加する
- `skills/review/SKILL.md`: "Event-based observation scan (runs regardless of `opportunistic-verify` setting)" 見出し配下に同様の dispatch 処理を追加する。あわせて frontmatter `allowed-tools` に `Skill` を追加する (現状含まれておらず、interactive session での直接実行時に許可プロンプトが発生し得るため)
- `modules/observation-trigger.md`: `## scripts/observation-trigger.sh (実装済み #656)` セクションの説明文を更新し、stdout 出力と LLM セッション emitter 側の dispatch 責務を明記する (SSoT ドキュメントを実装と一致させる)
- `docs/structure.md` / `docs/ja/structure.md`: [Steering Docs sync candidate] `observation-trigger.sh` の一行説明 ("posts comment to each matched Issue recommending /verify re-run") が新挙動を反映しているか確認し、必要なら更新する (`docs/translation-workflow.md` の同期手順に従い ja 版も更新)

## Implementation Steps

1. `scripts/observation-trigger.sh`: 既存の comment-posting `for` ループの直後に `echo "$NUMBERS"` を追加し、matched Issue 番号一覧 (改行区切り、マッチなしの場合は空) を stdout に出力する。早期 `exit 0` する2箇所 (空結果時・`NUMBERS` 空時) は出力なしのまま維持する (→ 受入条件 A)
2. `tests/observation-trigger.bats` (after 1): `@test "success: single match posts one comment"` に `[ "$output" = "42" ]` を追加する。`@test "success: multiple matches post one comment each"` に `[[ "$output" == *"10"* ]]` と `[[ "$output" == *"20"* ]]` を追加する (→ 受入条件 A)
3. `skills/auto/SKILL.md` (parallel with 1, 2): 上記2箇所の "Event-based observation scan" ステップに以下を追加する — `observation-trigger.sh` の stdout を `OBSERVATION_MATCHES` としてキャプチャ → 非空なら `modules/detect-config-markers.md` 経由で `AUTONOMY_TIER` をロード → `L2`/`L3` の場合、`OBSERVATION_MATCHES` の各番号 (single-issue route は現在処理中の `$NUMBER` を除外、batch route は `BATCH_LIST` に含まれる番号を除外) に対して `Skill(skill="wholework:verify", args="$N")` を直列 dispatch する。`L1` の場合は dispatch をスキップし既存の advisory-only 挙動 (コメントのみ) を維持する (→ 受入条件 B)
4. `skills/review/SKILL.md` (parallel with 1, 2): 該当ステップに Step 3 と同型の dispatch 処理を追加する (現在処理中の Issue = `$ISSUE_NUMBER` を除外)。frontmatter `allowed-tools` に `Skill` を追加する (→ 受入条件 C)
5. `modules/observation-trigger.md` (after 1, 3, 4): `## scripts/observation-trigger.sh` セクションの説明文を更新し、stdout 出力・`/auto`/`/review` 側の dispatch 責務・`AUTONOMY_TIER` 分岐を明記する。`scripts/claude-watchdog.sh` は無変更 (stdout を読み取らないため既存のコメント専用フォールバックが自動的に維持される) であることを確認する (→ 受入条件 A, B, C のドキュメント整合 + 受入条件 D の現状維持確認)

## Verification

### Pre-merge

- <!-- verify: rubric "scripts/observation-trigger.shがmatched Issue番号の一覧を呼び出し元が取得できる形でstdoutに出力している" --> `scripts/observation-trigger.sh` が matched Issue 番号一覧を stdout に出力するようになっている (コメント投稿の副作用に加えて)
- <!-- verify: rubric "skills/auto/SKILL.mdのEvent-based observation scanステップが、observation-trigger.shのmatched Issueに対してSkill(wholework:verify)をdispatchする処理を含む" --> `skills/auto/SKILL.md` の Event-based observation scan ステップが、matched Issue に対して `Skill(wholework:verify, args=N)` を dispatch する処理を含む
- <!-- verify: rubric "skills/review/SKILL.mdのEvent-based observation scanステップがobservation-trigger.shのmatched Issueに対してSkill(wholework:verify)をdispatchする処理を含む" --> `skills/review/SKILL.md` の Event-based observation scan ステップ (`## Opportunistic Verification` 配下) にも、matched Issue に対して `Skill(wholework:verify, args=N)` を dispatch する処理が追加されている
- <!-- verify: rubric "scripts/claude-watchdog.shからのobservation-trigger.sh呼び出しが引き続きコメント投稿のみで、dispatchを試みない" --> `scripts/claude-watchdog.sh` からの呼び出しは既存のコメント投稿のみのフォールバック挙動を維持している (dispatch 不可能な shell-only context のため)

### Post-merge

- 次回 `/auto --batch` 実行で、バッチ対象外の Issue に observation 条件が発火した場合に `/verify` が自動 dispatch されることを観察

## Notes

- **dispatch 件数上限・コスト制御 (Issue Proposal B) の設計判断**: `AUTONOMY_TIER` による gating (`L1`: advisory-only / `L2`・`L3`: dispatch) を採用した。根拠: (1) `skills/triage/SKILL.md` の blocked-by backfill (Dependency blocked-by check) が同型の L1/L2/L3 分岐を既に採用しており直接の precedent がある、(2) `modules/autonomy-tier.md` の Tier × L0 Write Matrix では L1 は「advisory print only; human acts」と定義されており、`/verify` dispatch (チェックボックス更新・Issue の close/reopen という L0 write を誘発する) はこの粒度に合致する、(3) Issue 本文が明示的にこの precedent を「判断材料」として申し送っていた。明示的な数値上限 (numeric cap) や dry-run 確認は採用しなかった — `opportunistic-search.sh` が `phase/verify` (closed) かつ未チェック observation AC という条件で対象を既に絞り込んでおり、実運用上大量発火するケースは想定しにくいため。運用実績で問題が確認された場合は follow-up Issue で数値上限を検討する
- **stdout 出力フォーマット**: 改行区切りのプレーンな Issue 番号一覧を採用した (JSON 配列ではない)。理由: 呼び出し元 (`/auto`・`/review` の SKILL.md ステップ) は LLM が読んで直接ループ処理する想定であり、`observation-trigger.sh` 内部で `opportunistic-search.sh` の JSON 出力から既に `NUMBERS` (改行区切り) を計算済みのため、これをそのまま出力するのが最小差分となる。`opportunistic-search.sh` 自体の JSON 配列規約は変更しない
- **スコープ外の確認**: `skills/verify/SKILL.md` の fix-cycle emitter は Issue 本文の Auto-Resolved Ambiguity Point により本 Issue のスコープ外。`modules/observation-trigger.md` の Notes にある「fix-cycle イベントは定義されているが emitter は未実装」という記述は本 Issue では変更しない
- **`scripts/claude-watchdog.sh` 無変更の根拠**: `observation-trigger.sh --event watchdog-kill` の呼び出し箇所 (137行目付近) では stderr のみ `2>/dev/null` で捨てられ、stdout は変数キャプチャも `$()` 展開もされない裸の呼び出しになっている。そのため stdout に新たに数値一覧が出力されても既存の挙動 (コメント投稿のみ) に影響はなく、コード変更は不要 (受入条件 D は現状維持の確認のみで満たされる)
- Issue 本文の技術的記述 (`skills/review/SKILL.md` の既存 Event-based observation scan ステップの存在、`scripts/observation-trigger.sh` の実装内容) はコードベース調査で独立に再確認し、相違点は見つからなかった

## Consumed Comments

- saito / MEMBER / first-class / `/issue 897` の Issue Retrospective コメント (トリアージ結果: Type=Bug, Size=M, Value=3。Auto-Resolve Log 3点の詳細説明。内容は Issue 本文末尾の `## Auto-Resolved Ambiguity Points` セクションと重複しており、本 Spec の設計判断に新規情報の追加はなし) / https://github.com/saitoco/wholework/issues/897#issuecomment-4883649759

No new comments since last phase (`phase/ready` 付与時刻 2026-07-04T20:21:51Z 以降のコメントなし).

## Code Retrospective

### Deviations from Design

- N/A — Implementation Steps 1〜5 は Spec 記載順序・内容通りに実装した (変数名 `OBSERVATION_MATCHES`、tier 分岐、`BATCH_LIST` 除外ロジック、`allowed-tools` への `Skill` 追加、`docs/structure.md`/`docs/ja/structure.md` 同期を含む)。

### Design Gaps/Ambiguities

- Spec の Implementation Steps には明記されていなかったが、`modules/observation-trigger.md` の新規セクション見出しに使った語が `scripts/check-forbidden-expressions.sh` が検出する旧称 (`/auto` の旧称) と一致していた。`docs/tech.md` § Forbidden Expressions は `check-forbidden-expressions.sh` 実行時のみ判明する制約であり、Spec 段階では見えにくい。同様に emitter 関連の Issue で prose を書く際は、この旧称の大文字始まり表記を避け "invoke" 等の言い換えを使う判断が必要になる。

### Rework

- 上記の forbidden expression 検出により、`modules/observation-trigger.md` の見出し・文言を1箇所リワードする追加コミットが発生した (実装ロジック自体の手戻りではなく、用語選択のみの修正)。

## Phase Handoff
<!-- phase: review -->

### Key Decisions
- Pre-merge rubric AC 4件 (A〜D) はすべて実装内容から直接 PASS 判定し、UNCERTAIN・FAIL なし
- review-light agent (light mode, 4 perspectives) で CONSIDER 1件 (Resume mode の dispatch 除外漏れ) を検出し、影響が低く既存パターンの踏襲であることから修正はスキップと判断した
- CI 全ジョブ SUCCESS、MUST issue なしのため Step 12 修正作業・Step 12.3 再チェックは実施なし

### Deferred Items
- CONSIDER issue (`skills/auto/SKILL.md:1135`, Resume mode の `BATCH_LIST`/`REMAINING` 再利用による dispatch 除外漏れ) は対応見送り。将来 batch checkpoint と合わせた「dispatch/processed 済み」セット永続化を検討する余地がある (review retrospective に記録済み)
- Post-merge AC (`次回 /auto --batch 実行での自動 dispatch 観察`, `verify-type: observation event=auto-run`) は引き続き `/verify` フェーズで観察待ち

### Notes for Next Phase
- `/merge` フェーズでは MUST issue なし・CI 全SUCCESSのため通常のマージ手順で進行可能
- Post-merge AC の観察は次回 `/auto --batch` 実行時まで保留のままでよい

## review retrospective

### Spec vs. implementation divergence patterns

Nothing to note — review-light agent (4 perspectives) は Spec の Implementation Steps 5件・rubric AC 4件すべてで実装と Spec の一致を確認した。乖離なし。

### Recurring issues

Nothing to note — 検出された issue は CONSIDER 1件のみで、複数箇所にまたがる同種の繰り返し issue ではない。

### Acceptance criteria verification difficulty

Nothing to note — Pre-merge AC 4件はすべて rubric 形式で、UNCERTAIN 判定なく PASS 判定できた。verify command の記述・網羅性に問題は見られなかった。

### Improvement proposals

- **[CONSIDER] Resume mode (`--batch --resume`) の `BATCH_LIST`/`REMAINING` 再利用による dispatch 除外漏れ** — `skills/auto/SKILL.md:1135` の observation scan dispatch 除外判定が resume 後の `REMAINING` を参照するため、resume 前に処理済みの Issue が除外対象から漏れ、冗長な `/verify` dispatch が発生しうる。本 PR のスコープ外の既存パターン (line 1104 の Pending manual confirmation と同型) であり、影響も低い (概ね idempotent) ため今回は対応見送り。将来的に batch checkpoint と合わせた「dispatch/processed 済み」セット永続化を検討する余地がある。
