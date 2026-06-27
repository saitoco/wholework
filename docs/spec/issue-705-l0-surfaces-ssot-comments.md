# Issue #705: config: L0 surface 一覧を modules/l0-surfaces.md で SSoT 化、comment を consumable な一級入力として扱う

## Overview

Wholework のループ substrate である **L0 (GitHub state: Issue / Label / PR / blockedBy / `closes #N` / comments)** について、touching する surface の SSoT を `modules/l0-surfaces.md` (新規) に確立する。あわせて **Issue / PR comment を「プロンプトと同レイヤの一級入力 (consumable)」として扱う方針** を `/spec` `/code` `/verify` に展開し、各 phase 開始時に「直前 phase 以降に追加された comment」を context に取り込む。これにより #704 (autonomy tier) の Tier × L0 write マトリクスが具体的なルックアップになり、ユーザ comment が後続 phase に自然伝播する。

scope (本 Issue):
- `modules/l0-surfaces.md` の新規作成 (SSoT 表 + 信頼境界 + machine-readable marker + Comment Consumption Procedure)
- `comments_consumed` イベント型を `scripts/emit-event.sh` に文書化
- `/spec` `/code` `/verify` の SKILL.md に comment 取り込みステップを追加
- `docs/workflow.md § Related Documents` への link 追加
- `docs/structure.md` のモジュールカタログ更新 (count + Key modules) と ja mirror 同期

非 scope: `/review` (既に PR comment を consume 済み)、cross-Issue audit、`/audit recoveries` 連携 (将来拡張)。

## Changed Files

- `modules/l0-surfaces.md`: new file — L0 surface SSoT 表、信頼境界 (`authorAssociation`)、machine-readable marker (`wholework-event:`)、Comment Consumption Procedure。Standard 4-section structure (Purpose / Input / Processing Steps / Output) ベース + 参照セクション。(AC1-4)
- `scripts/emit-event.sh`: add `comments_consumed` event schema to the "Documented event schemas" comment block (コメントのみの追加。emit_event() 関数本体は汎用なので変更不要)。bash 3.2+ compatible (コメント追加のみ)。(AC5)
- `skills/spec/SKILL.md`: Step 1 に "Consume comments since the last phase (L0 input)" サブセクション追加 (l0-surfaces を Read and follow); frontmatter `allowed-tools` の `Bash(...)` に `gh api:*` を追加 (timeline API 用)。(AC6)
- `skills/code/SKILL.md`: Step 1 に同サブセクション追加 (l0-surfaces を Read and follow); frontmatter `allowed-tools` の `Bash(...)` に `gh api:*` を追加。(AC7)
- `skills/verify/SKILL.md`: Step 4 に同サブセクション追加 (l0-surfaces を Read and follow)。`gh api:*` は既存のため allowed-tools 変更不要。(AC8)
- `docs/workflow.md`: `## Related Documents` に `modules/l0-surfaces.md` への link 追加。(AC9)
- `docs/structure.md`: Directory Layout の `modules/` カウント `(36 files)` → `(37 files)`; Key Files > Modules リストに `modules/l0-surfaces.md` エントリ追加。(AC10)
- `scripts/run-spec.sh`: `AUTO_EVENTS_LOG="${AUTO_EVENTS_LOG:-.tmp/auto-events.jsonl}"; export AUTO_EVENTS_LOG` を追加 (run-code.sh L48-49 と同形)。/auto 配下の /spec 子プロセスで `comments_consumed` イベントが捕捉できるようにする。bash 3.2+ compatible。(post-merge AC #11 の spec phase 観測を可能にする)
- `docs/ja/workflow.md`: `## 関連ドキュメント` に `modules/l0-surfaces.md` への link を日本語で追加 (mirror sync)。
- `docs/ja/structure.md`: `（36 ファイル）` → `（37 ファイル）`; `主要モジュール:` リストに `modules/l0-surfaces.md` エントリ追加 (mirror sync)。

## Implementation Steps

1. `modules/l0-surfaces.md` を新規作成 (→ acceptance criteria 1, 2, 3, 4)。以下を含める:
   - **Purpose / Input / Output** (4-section backbone)。
   - **`## L0 Surface SSoT`**: Issue body の表を移植 (Issue title / Issue body / Issue state / Labels / **Issue comments** / **PR comments** / Project v2 fields / PR body & review state / Sub-issue graph / `closes #N`)。表末尾に **(exhaustive)** マーカーを付与し、`triaged` のような bare-namespace ラベル例外は #R2 で扱う旨を注記。`Issue comments` 行で comment を append + read の consumable (一級入力) として宣言する (AC2)。
   - **`## Trust Boundary`**: 各 comment の信頼境界を `authorAssociation` フィールドで判定。本文に「conceptually the comment author's `author.association`」と記載 (AC3 の `author.association` 文字列を満たしつつ実フィールド名 `authorAssociation` を明示)。表 (exhaustive): `OWNER`/`MEMBER`/`COLLABORATOR` → first-class (プロンプト相当で inject)、`CONTRIBUTOR`/`NONE` → external (inject するが「外部入力」マーク)、login が `[bot]` 末尾の actor → skip (例外: `<!-- wholework-event: -->` marker や既知の wholework retro/recovery heading を持つ自身の自動 comment は consume)。
   - **`## Machine-Readable Event Marker`**: フォーマット `<!-- wholework-event: type=<event-type> phase=<phase> issue=<N> -->` を定義 (AC4 の `wholework-event:` 文字列)。machine-readable marker は HTML comment、人間可読本文は通常 Markdown で両立する旨を明記。
   - **`## Processing Steps` > `### Comment Consumption Procedure`**: 後述「Comment Consumption Procedure 詳細」の手順を記述。新規見出しレベルは h2 (`##`) / h3 (`###`)。

2. `scripts/emit-event.sh` の "Documented event schemas" コメントブロック (L14-23 付近、`verify_reopen_cycle` スキーマの直後) に `comments_consumed` スキーマを追記 (after 1) (→ acceptance criteria 5)。記述形式:
   - `comments_consumed: skill consumed comments added since the previous phase`
   - `phase=<phase-name>` / `count=<n>` / `authors=<comma-separated logins>` / `trust_breakdown=<compact: OWNER:n,MEMBER:n,COLLABORATOR:n,CONTRIBUTOR:n,NONE:n>`
   - emit_event() の value サニタイズ (引用符エスケープ) を避けるため、`trust_breakdown` は JSON ではなく `KEY:n` 区切りの flat 文字列とする旨を注記。

3. `skills/spec/SKILL.md` を更新 (after 1) (→ acceptance criteria 6):
   - frontmatter `allowed-tools` の `Bash(...)` パターン内、`gh issue view:*` の近傍に `gh api:*` を追加。
   - Step 1 "Fetch Issue Information" の末尾 (get-issue-type 取得の後) に新規サブセクション (h4 相当の太字見出し) "**Consume comments since the last phase (L0 input):**" を追加。第1段落に Read 指示を置く: `${CLAUDE_PLUGIN_ROOT}/modules/l0-surfaces.md` を Read and follow the "Comment Consumption Procedure" section、パラメータ `ISSUE_NUMBER=$NUMBER`、`COMMENT_SCOPE=issue`、`PHASE_NAME=spec`。Step 3 のラベル遷移より前に実行されるため、cutoff は直前の `phase/issue` 遷移時刻に解決される。

4. `skills/code/SKILL.md` を更新 (parallel with 3) (→ acceptance criteria 7):
   - frontmatter `allowed-tools` の `Bash(...)` パターン内、`gh issue view:*` の近傍に `gh api:*` を追加。
   - Step 1 "Fetch Issue Info" の末尾に同サブセクションを追加。パラメータ `ISSUE_NUMBER=$NUMBER`、`COMMENT_SCOPE=issue` (resume 時は `issue+pr`)、`PHASE_NAME=code`。Step 4 のラベル遷移より前に実行されるため cutoff は直前の `phase/ready` 遷移時刻に解決される。

5. `skills/verify/SKILL.md` を更新 (parallel with 3, 4) (→ acceptance criteria 8):
   - Step 4 "Fetch Issue Acceptance Conditions" の Phase Handoff read サブセクション近傍に同サブセクションを追加。パラメータ `ISSUE_NUMBER=$NUMBER`、`COMMENT_SCOPE=issue`、`PHASE_NAME=verify`。`gh api:*` は既存のため allowed-tools 変更なし。

6. `docs/workflow.md` の `## Related Documents` セクションに行を追加 (parallel with 3) (→ acceptance criteria 9): `- [modules/l0-surfaces.md](../modules/l0-surfaces.md) — L0 (GitHub) surface SSoT and comment consumption policy`。

7. `docs/structure.md` を更新 (parallel with 3) (→ acceptance criteria 10):
   - Directory Layout の `├── modules/ ... (36 files)` を `(37 files)` に変更。
   - Key Files > Modules の "Key modules:" リストに `- modules/l0-surfaces.md — L0 (GitHub) surface SSoT and comment-as-first-class-input policy` を追加。

8. `scripts/run-spec.sh` に `AUTO_EVENTS_LOG="${AUTO_EVENTS_LOG:-.tmp/auto-events.jsonl}"; export AUTO_EVENTS_LOG` を追加 (after 2)。引数パース後・claude 起動前の早い位置 (run-code.sh L48-49 と同位置相当)。これにより /auto 配下の /spec 子 claude プロセスが `AUTO_EVENTS_LOG` を見て `comments_consumed` を emit できる (post-merge AC #11 の spec phase 観測を可能にする)。

9. ja mirror を同期 (parallel with 6, 7):
   - `docs/ja/workflow.md` の `## 関連ドキュメント` に `- [modules/l0-surfaces.md](../modules/l0-surfaces.md) — L0 (GitHub) surface の SSoT と comment 消費ポリシー` を追加。
   - `docs/ja/structure.md` の `（36 ファイル）` → `（37 ファイル）`、`主要モジュール:` リストに `modules/l0-surfaces.md` エントリを追加。

### Comment Consumption Procedure 詳細 (modules/l0-surfaces.md に記述する手順)

Input: `ISSUE_NUMBER`、`COMMENT_SCOPE` (`issue` | `issue+pr`)、`PHASE_NAME`。

1. **cutoff 時刻の決定** (フォールバックラダー):
   - Primary: `gh api "repos/{owner}/{repo}/issues/$ISSUE_NUMBER/timeline" --paginate --jq '[.[] | select(.event=="labeled" and (.label.name|startswith("phase/"))) | .created_at] | last'` で最新の `phase/*` ラベル付与時刻を取得 (`{owner}`/`{repo}` は gh が自動展開)。
   - Fallback A: timeline が空/失敗の場合、`.tmp/auto-events.jsonl` から当該 issue の最新 `phase_start` の `ts` を読む。
   - Fallback B: いずれも無い場合、cutoff を空にして全 comment を best-effort で consume し、「cutoff undetermined」を注記。
2. **comment 取得**: `gh issue view "$ISSUE_NUMBER" --json comments --jq ".comments[] | select(.createdAt > \"$CUTOFF\")"` (CUTOFF が空なら全件)。ISO8601 UTC 文字列は辞書順比較可能なため `date` 不要。`COMMENT_SCOPE=issue+pr` の場合は対応する PR comment も `gh pr view` で取得。
3. **信頼境界で分類**: 各 comment の `authorAssociation` と `author.login` を見て Trust Boundary 表で分類。
4. **context へ inject**: first-class comment はプロンプト相当で current phase に inject。external は「外部入力」マーク付きで inject。bot はスキップ (例外あり)。
5. **記録**: `## Consumed Comments` セクション (Spec / retrospective) に各 consume した comment を列挙 (login / authorAssociation / trust tier / 1 行意図サマリ / url)。0 件なら "No new comments since last phase" と記録。
6. **イベント emit** (best-effort、`AUTO_EVENTS_LOG` がセットされている時のみ): `source "${CLAUDE_PLUGIN_ROOT}/scripts/emit-event.sh"` した上で `EMIT_ISSUE_NUMBER=$ISSUE_NUMBER emit_event "comments_consumed" "phase=$PHASE_NAME" "count=$N" "authors=$AUTHORS" "trust_breakdown=$BREAKDOWN"`。`AUTO_EVENTS_LOG` 未設定時 (通常の in-session 実行) はスキップ。

Output: inject 済み context + `## Consumed Comments` 記録 + (条件付き) `comments_consumed` イベント。

## Alternatives Considered

- **cutoff を `gh issue view --json labels` から取る**: 却下。`labels` 配列は name/color/description のみで付与時刻 (`created_at`) を持たない。ラベル付与時刻は timeline (`labeled` イベント) にしか無いため timeline API を採用 (Issue body の "labels.created_at" 表現は実態と齟齬。Notes 参照)。
- **comment 消費を新規の番号付き Step として挿入**: 却下。各 SKILL.md の後続 Step 全番号繰り上げが発生し churn が大きい。Issue body の "Step 1〜2 付近" 指針にも合致するため、既存の早期 issue-fetch Step 内のサブセクションとして追加する。
- **イベントを SKILL.md で inline JSON 出力 (verify SKILL.md L451-453 方式)**: 検討。verify は `date:*`/`printf:*` を allowed-tools に持つため inline で書けるが、spec/code は持たない。emit-event.sh を source する方式なら locking/JSON 組み立てを再利用でき、追加ツールが不要 (source は `AUTO_EVENTS_LOG` セット時=非対話=permission skip 環境でのみ実行)。後者を採用。
- **cutoff 取得用の専用スクリプト `scripts/get-phase-transition-time.sh` を新設**: 却下。bats テスト + structure.md エントリ + `WHOLEWORK_SCRIPT_DIR` mock 追加が必要で Simplicity を超える。timeline API をモジュール内 inline で呼ぶ方式にする。

## Verification

### Pre-merge

- <!-- verify: file_exists "modules/l0-surfaces.md" --> `modules/l0-surfaces.md` が新規作成され、L0 surface 表が記述されている
- <!-- verify: file_contains "modules/l0-surfaces.md" "Issue comments" --> Issue / PR comments が consumable (一級入力) として宣言されている
- <!-- verify: file_contains "modules/l0-surfaces.md" "author.association" --> 信頼境界 (OWNER / COLLABORATOR / CONTRIBUTOR / bot) の判定ルールが明記されている
- <!-- verify: file_contains "modules/l0-surfaces.md" "wholework-event:" --> 機械可読 marker のフォーマットが定義されている
- <!-- verify: file_contains "scripts/emit-event.sh" "comments_consumed" --> `comments_consumed` イベント型が `emit-event.sh` に追加されている
- <!-- verify: grep "modules/l0-surfaces.md" "skills/spec/SKILL.md" --> `/spec` SKILL.md が l0-surfaces を Read and follow する
- <!-- verify: grep "modules/l0-surfaces.md" "skills/code/SKILL.md" --> `/code` SKILL.md が l0-surfaces を Read and follow する
- <!-- verify: grep "modules/l0-surfaces.md" "skills/verify/SKILL.md" --> `/verify` SKILL.md が l0-surfaces を Read and follow する
- <!-- verify: section_contains "docs/workflow.md" "## Related Documents" "l0-surfaces.md" --> `docs/workflow.md` の `## Related Documents` セクションに `modules/l0-surfaces.md` への link が追加されている
- <!-- verify: file_contains "docs/structure.md" "(37 files)" --> `docs/structure.md` の `modules/` ファイルカウントが新モジュール追加に合わせ `(37 files)` に更新されている

### Post-merge

- 試験 Issue に user comment を追加した状態で `/spec N` を実行し、Spec の "Consumed Comments" セクションに当該 comment が記録されることを手動確認する <!-- verify-type: manual -->
- `auto-events.jsonl` に `comments_consumed` イベントが phase 遷移ごとに記録されることを観察 <!-- verify-type: observation event=auto-run -->

## Tool Dependencies

### Bash Command Patterns
- `gh api:*` — `/spec` と `/code` の `allowed-tools` に追加が必要 (timeline API で phase ラベル付与時刻を取得)。`/verify` は既存。base tool 名は `Bash` (KNOWN_TOOLS 登録済) のため `scripts/validate-skill-syntax.py` の更新は不要。
- `gh issue view --json comments:*` / `gh pr view:*` — comment 取得。`/spec` `/code` `/verify` いずれも `gh issue view:*` を既存で保持。`/code` は `gh pr ...` は不要 (resume 時のみ; 既存 allowed-tools の範囲で対応可、PR comment 取得が必要なら follow-up)。
- `${CLAUDE_PLUGIN_ROOT}/scripts/emit-event.sh` (source) — `comments_consumed` emit。`AUTO_EVENTS_LOG` セット時 (非対話) のみ実行されるため permission prompt は実務上発生しない。

### Built-in Tools
- `Read` — モジュール / SKILL.md / docs の読み取り (既存)。
- `Edit` / `Write` — ファイル編集・新規作成 (既存)。

### MCP Tools
- none

## Uncertainty

- **`gh api .../timeline` の event volume / pagination**: コメント・ラベルが多い Issue で timeline が長大になる可能性。
  - **Verification method**: `--paginate` + `--jq '... | last'` で最新の `phase/*` `labeled` のみ抽出 (Spec 作成時に issue #705 で動作確認済: triaged / phase/issue / phase/spec が created_at 付きで返ることを確認)。
  - **Impact scope**: Comment Consumption Procedure step 1 (cutoff 決定)。Fallback A/B で degrade 可能。
- **`AUTO_EVENTS_LOG` の /spec 子プロセスへの伝播**: run-spec.sh は現状 `AUTO_EVENTS_LOG` を export していない (run-code/merge/review は export 済)。Implementation Step 8 で run-spec.sh に export を追加して埋める。
  - **Verification method**: /code 実装時に run-spec.sh 経由の /spec で `.tmp/auto-events.jsonl` に `comments_consumed` が書かれるか確認。worktree CWD と相対パス `.tmp/auto-events.jsonl` の解決差異が残る場合は親 /auto が export する絶対パスに従う。
  - **Impact scope**: post-merge AC #11 (observation; soft、merge gate ではない)。emit は best-effort で、未伝播でも graceful にスキップする。
- **`COMMENT_SCOPE=issue+pr` (/code resume) の PR comment 取得**: `/code` allowed-tools は `gh pr create:*` `gh pr comment:*` を持つが `gh pr view:*` は未登録。
  - **Verification method**: resume 経路で PR comment を read する場合 `gh pr view --json comments` が必要かを /code 実装時に確認。必要なら `gh pr view:*` 追加を follow-up。本 Issue の pre-merge AC は issue comment のみで満たされるため scope 外として degrade 可。
  - **Impact scope**: `/code` の resume 時 PR comment 取り込み (任意機能)。

## Notes

### Conflict with implementation (Issue body 前提 vs 実態)

- **`author.association` フィールド名の齟齬**: Issue body は「`gh issue view --json comments` の `author.association` フィールド」とするが、実際の gh JSON は各 comment の **トップレベル `authorAssociation`** フィールド (`author` 配下ではない)。AC3 は文字列 `author.association` の存在を要求するため、モジュールには「conceptually `author.association`」という記述で AC を満たしつつ、実装で参照する実フィールド名 `authorAssociation` を併記する。
- **`labels.created_at` の不在**: Issue body は cutoff 取得元として「`labels.created_at` または events.jsonl」を挙げるが、`gh issue view --json labels` のラベルオブジェクトは付与時刻を持たない。ラベル付与時刻は timeline (`labeled` イベント) に存在するため、Comment Consumption Procedure は timeline API を primary、events.jsonl を fallback とする。
- **`OWNER` vs `MEMBER`**: 本リポジトリのオーナー (saito) の comment は `authorAssociation=MEMBER` を返す (Spec 作成時に issue #699 で確認)。Issue body の trust bullet は OWNER / COLLABORATOR を一級として挙げるが、association enum 注記には MEMBER も含まれる。Trust Boundary 表では **OWNER / MEMBER / COLLABORATOR をすべて first-class** とする。

### 設計メモ

- `trust_breakdown` は emit_event() の value サニタイズ (`"` のエスケープ) で JSON が壊れるのを避けるため、`OWNER:n,MEMBER:n,COLLABORATOR:n,CONTRIBUTOR:n,NONE:n` の flat 文字列形式とする。
- bot 検出は `author.login` 末尾 `[bot]` で判定 (Issue body の "`[bot]` suffix の actor")。`gh issue view --json comments` の `author` は `login` のみを返すため、`__typename` 等は使わない。
- machine-readable marker `<!-- wholework-event: -->` は既存の HTML comment marker 規約 (`<!-- review-summary -->`, `<!-- verify-type: ... -->`, `<!-- verify-iteration: N -->`) と整合する新 namespace。
- post-merge AC #10 (manual): 試験 Issue への手動 comment 追加という前提作業が必要なため、自動化不可。`<!-- verify-type: manual -->` を維持 (Issue 側の Auto-Resolved Ambiguity で `observation event=skill-run` → `manual` に解決済。`skill-run` は有効 event-name 一覧に不在)。
- post-merge AC #11 (observation): `auto-run` は有効 event-name (pr-review-full / pr-review-light / auto-run / watchdog-kill / fix-cycle) に含まれるため `observation event=auto-run` を維持。
- ja mirror (`docs/ja/*`) は本 Issue の pre-merge AC (英語ファイル対象) とは別に同期する。verify command は英語ファイルにのみ付与し、ja 側は実装ステップで日本語フォーマットを維持する (verify command の format 影響を避ける)。

## issue retrospective

### 自動解決ログ (非対話モード)

**P1: `observation event=skill-run` → `manual` に変更**

- **判断**: `verify-classifier.md` の有効 event-name 一覧 (`pr-review-full` / `pr-review-light` / `auto-run` / `watchdog-kill` / `fix-cycle`) に `skill-run` は存在しない。未知イベントのフォールバックは `opportunistic` だが、当該 AC は「試験 Issue に user comment を追加する」という手動前提作業を必要とするため、`manual` が最適と判断
- **変更**: Post-merge AC #1: `<!-- verify-type: observation event=skill-run -->` → `<!-- verify-type: manual -->`
- **代替候補**: `opportunistic` (verify-classifier.md 未知イベントのフォールバック)
- **採用理由**: 手動セットアップ (試験 Issue への comment 追加) が必要な観察条件は `manual` が SSoT に従った分類

**P2: AC #9 の verify command を `section_contains` に変更**

- **判断**: `file_contains "docs/workflow.md" "L0 surfaces"` では、L0 surfaces という文字列がファイル内のどこにでも存在すれば PASS になる。実装意図は `## Related Documents` セクションへのリンク追加であるため、`section_contains "docs/workflow.md" "## Related Documents" "l0-surfaces.md"` に変更することで検証精度を向上
- **変更**: `file_contains "docs/workflow.md" "L0 surfaces"` → `section_contains "docs/workflow.md" "## Related Documents" "l0-surfaces.md"`
- **代替候補**: 元の `file_contains` を保持 (ドキュメント内のどこかに文字列があればよい)
- **採用理由**: 実装意図 (Related Documents セクションへのリンク) との整合性を高め、誤 PASS のリスクを低減

## Code Retrospective

### Deviations from Design
- Spec の実装ステップには `emit-event.sh:*` を allowed-tools に追加する記述がなかったが、`scripts/validate-skill-syntax.py` の cross-file validation で spec/code/verify の 3 SKILL.md に `emit-event.sh` を allowed-tools 追加することが必要と判明。追加コミットを作成した。

### Design Gaps/Ambiguities
- Spec Notes に「`gh api:*` は Bash サブパターンのため validate-skill-syntax.py 更新は不要」と明記されていたが、`emit-event.sh` の cross-file validation については言及がなかった。モジュールが `source` するスクリプトも cross-file validation の対象になることは、実装時に validate-skill-syntax.py を実行して初めて確認できた。

### Rework
- SKILL.md の allowed-tools 追加を 2 段階 (gh api:* → emit-event.sh:*) に分けて commit した。emit-event.sh の必要性が validate-skill-syntax.py 実行後に判明したため。

## spec retrospective

### Minor observations
- Issue body の前提記述に 2 件の実態齟齬があった: (1) `gh issue view --json comments` の実フィールドは `authorAssociation` (`author` 配下の `author.association` ではない)、(2) `labels.created_at` は存在せず phase ラベル付与時刻は timeline 由来。いずれも /spec の codebase 調査で検出し Notes に吸収。AC3 の文字列 `author.association` は維持しつつ実装は実フィールド名を使う形で両立させた。

### Judgment rationale
- comment 取り込みステップを「新規番号付き Step」ではなく「既存の早期 Step 内サブセクション」として追加する判断。理由: 3 つの SKILL.md で後続 Step 全番号の繰り上げ churn を避け、Issue body の "Step 1〜2 付近" 指針にも合致するため。
- structure.md の `(37 files)` カウント AC を 10 件目として追加し Issue body にも同期した。理由: structure.md maintenance rule がモジュール追加時のカウント verify を要求しているため (/audit drift の検出対象)。
- `comments_consumed` の emit を emit-event.sh の source 方式に統一 (verify SKILL.md の inline JSON 方式は採らない)。理由: spec/code は `date:*`/`printf:*` を allowed-tools に持たず、source 方式なら追加ツール不要で locking も再利用できるため。

### Uncertainty resolution
- `gh api repos/{owner}/{repo}/issues/N/timeline` が `phase/*` の `labeled` イベントを `created_at` 付きで返すことを issue #705 の実データで確認 → cutoff 取得の primary 経路として確定。
- `authorAssociation` の実値を確認: リポジトリオーナー saito の comment が `MEMBER` を返す (issue #699 で確認) → Trust Boundary は OWNER / MEMBER / COLLABORATOR を first-class とした。
- run-spec.sh が `AUTO_EVENTS_LOG` を export していないことを確認 → Implementation Step 8 で補完。worktree CWD と相対パス `.tmp/auto-events.jsonl` の解決差異は /code で要確認として Uncertainty に残置。

## review retrospective

### Spec vs. implementation divergence patterns
- `modules/l0-surfaces.md` の bot exception 検出文字列が empty form `<!-- wholework-event: -->` で定義されており、実際のマーカーフォーマット (attributes 必須) と一致しない論理エラーが発見された。これは Spec/Code のフェーズでは気付きにくい「プロトコル整合性ギャップ」の典型例。ドキュメントとして定義した形式と、条件文で照合するリテラル文字列を別々に書くと齟齬が生じやすい。
- jq の `| last` がゼロ件時に `null` を文字列として出力する点も、LLM が実行する手順書として記述した prose の論理エラー。prose ドキュメント内の shell コマンド例でも fallback 分岐との整合性確認が必要。

### Recurring issues
- 今回の 2 件の bug 指摘は互いに独立しており、同種の繰り返しパターンとは言えない。一方、「prose 定義と照合文字列の不整合」と「jq の edge case」は、今後 comment consumption procedure を実装する際にも同様のリスクがある。verify command でカバーしにくい領域 (prose 内コード例の論理的正確性) として認識する。

### Acceptance criteria verification difficulty
- 全 10 件が file_exists / file_contains / grep / section_contains で verify 可能な形式になっており、UNCERTAIN は 0 件。verify command の設計品質が高く、機械検証の困難さは特になかった。
- post-merge AC 2 件 (manual + observation) は /verify フェーズで対応予定。

## Phase Handoff
<!-- phase: review -->

### Key Decisions
- iteration 2 (PR #786) の MUST issue を検出・修正: `_emit_comments_consumed()` を `phase_start` emit の前に移動し、backfill 検出を修復。
- `modules/l0-surfaces.md` Step 6 のドキュメントを実装に合わせて更新 (「before `phase_start` emit」を明示)。
- AC10 (`(37 files)`) は stale AC と判断 (PR #786 は structure.md を変更しない)。次 phase (merge) ではこの FAIL を無視して良い。

### Deferred Items
- bats tests 11-15 (`append-loop-state-heartbeat.bats`) は pre-existing failures on main、本 PR と無関係。merge 後も継続して別途対処が必要。
- post-merge AC #11/#12 は /verify フェーズで引き続き対応が必要。

### Notes for Next Phase (/merge)
- PR #786 の CI: test #98 regression は修正済み (commit 55b0986)。push 後の CI 結果が SUCCESS になることを confirm してから merge を実行すること。
- tests 11-15 の pre-existing failures は merge ブロッカーではない (main でも失敗している)。
- AC10 stale FAIL は regression ではないため merge ブロッカーではない。

## Verify Retrospective

### Phase-by-Phase Review

#### issue
- Auto-Resolve Log で 2 件の ambiguity を解決 (verify-type observation→manual、AC #9 file_contains→section_contains)。両者とも実装意図と SSoT に基づいた合理的選択。決定の質は高い。

#### spec
- codebase 調査で Issue body の 2 件の事実齟齬を検出 (`authorAssociation` 実フィールド名、`labels.created_at` 不在 → timeline API)。spec が "issue は SSoT" の規約を守りつつ実態に合わせる形で吸収した。Issue body を直接書き換えずに spec/Auto-Resolve Log で記録という処理は適切。
- `(37 files)` カウント verify を 10 件目として追加し structure.md maintenance rule との整合を確保。

#### code
- `validate-skill-syntax.py` 実行で `emit-event.sh` cross-file validation の必要性が判明、2 段階 commit にリワーク。spec 段階で `emit-event.sh` source 元への影響を予見できなかった。

#### review
- 2 件の MUST issue を発見・解決:
  1. `modules/l0-surfaces.md` の bot exception 検出文字列 `<!-- wholework-event: -->` が、ドキュメント本文で定義されたマーカー仕様 (attributes 必須) と齟齬。**prose 定義と検出 literal の不整合** という典型パターン。
  2. jq `| last` のゼロ件時 `null` 出力 — prose 内の shell 例の論理エラー。
- いずれも pre-merge verify command では捕捉困難 (file_contains の対象外)。adversarial review が機能した実例。

#### merge
- squash + delete-branch、`closes #705` で auto-close。CI 全 SUCCESS、conflict resolution スキップ。問題なし。

#### verify
- Pre-merge 10件は idempotent 再検証で全 PASS。Post-merge 2件 (manual + observation) は本セッションで実機観察できないため deferred (phase/verify 維持)。
- verify command 設計品質が高く UNCERTAIN 0件。

### Improvement Proposals

**1. Prose 定義 vs 検出 literal の整合性チェック (Tier 1 候補)**

review で発見された bot exception marker の bug は、Markdown 本文で「マーカー仕様」を定義しながら検出条件文ではそれと異なる literal を書いていたために生じた典型パターン。pre-merge verify command (file_contains, grep) はこの種の論理整合性を捉えられない。

提案: `/triage` AC audit または `/review` の review-spec エージェントに「prose で定義された例 (e.g., code fence 内の YAML/HTML) と、それを検出する条件文 literal の一致をチェックする」パターンを追加。少なくとも `modules/*.md` 内で同じ文字列を 2 箇所以上書く構造 (定義 + 検出) を持つ場合は両者を突き合わせる rubric を導入。

影響範囲: `modules/l0-surfaces.md` 以外にも、`modules/verify-patterns.md`、`modules/orchestration-fallbacks.md` 等で同種パターンが将来発生する可能性。再発性: 中-高。

**2. `AUTO_EVENTS_LOG` export の一貫性 (Tier 2 / 規約)**

run-spec.sh で `AUTO_EVENTS_LOG` export が欠けていた。他の run-*.sh wrapper (run-code.sh、run-review.sh、run-merge.sh) も同様の状態か未検証。

提案: 全 run-*.sh wrapper 起動時に `AUTO_EVENTS_LOG` を `.tmp/auto-events.jsonl` で export する規約を `scripts/run-*.sh` の共通テンプレートに昇格 (もしくは `scripts/emit-event.sh` の preamble で auto-detect)。

**3. emit-event.sh cross-file validation の spec 反映 (Tier 3 / 一回限り)**

spec 段階で `validate-skill-syntax.py` の cross-file validation 要件 (emit-event.sh source 元への allowed-tools 追加) を予見できなかった点は今後の spec 作成時に意識する。Tier 3 (Spec retro 記録のみ、Issue 起票不要)。

## review retrospective (iteration 2)

### Spec vs. implementation divergence patterns

- `_emit_comments_consumed()` が `emit_event "phase_start"` の*後*に置かれた構造エラー。`_maybe_emit_phase_complete()` の backfill 検出条件 (`_last_event == "phase_start"`) を暗黙的に前提とするコードが既存しており、新たに追加した emit 呼び出しがその前提を破壊した。設計書 (l0-surfaces.md Step 6) には「before each phase runner script」と書かれていたが、実装は `phase_start` の後に配置されており spec と実装の齟齬が生じていた。
- 同パターン教訓: イベントロギングの順序は明示的な順序制約として spec に記述する必要がある。「phase runner の前」という記述では `phase_start` emit の前後どちらなのかが曖昧。

### Recurring issues

- test #98 (backfill) は bats テストが既存の挙動 (`phase_start` が最後のイベント) を前提に書かれており、新規 emit 追加で自動的に失敗した。新しいイベント emit を追加する際は、テストで前提とされているイベント順序への影響を必ず確認すること。これは iteration 1 でも類似の順序問題 (jq `| last` の null 出力) が発生した再発例。

### Acceptance criteria verification difficulty

- AC10 (`file_contains "docs/structure.md" "(37 files)"`) が iteration 1 マージ後の後続開発で stale になっていた。iteration 2 のレビューでは PR 変更非対象ファイルの AC が FAIL となり、regression との区別に調査コストが発生。iteration 単位での PR レビュー時には、前 iteration の AC が stale になっていないかを最初に確認するか、iteration 2 用の新 AC セットを明示的に定義すべき。
