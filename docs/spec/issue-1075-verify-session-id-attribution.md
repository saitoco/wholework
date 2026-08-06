# Issue #1075: auto/verify: in-session /verify の event が並行セッションの session_id に誤帰属するのを防ぐ

## Consumed Comments

cutoff: `2026-08-06T17:49:24Z` (最新の `phase/*` label 付与時刻、timeline API より)

- `saito` / `MEMBER` / first-class / `/issue` フェーズの Issue Retrospective。Background の技術的主張を grep で検証済み・差分なしと報告、案 C (文書化のみ) 不採用の判定と AC3 スコープ確認を記録 / https://github.com/saitoco/wholework/issues/1075#issuecomment-5207991133

cutoff 以前のコメント 2 件 (2026-07-31 の追加観測、2026-08-06 の双方向誤帰属実測) は Comment Consumption の対象外だが、Issue body の Background に統合済みの内容であり、本 Spec の設計根拠として参照した。

## Overview

`/auto` が in-session `Skill(skill="wholework:verify")` として起動する `/verify` は、wrapper script を持たないため `AUTO_SESSION_ID` を環境変数として継承できない。`scripts/emit-event.sh` の `restore_auto_session_pointer()` がポインタファイルから復元する設計だが、探索順が `.tmp/auto-session-${PGID}` → `.tmp/auto-session-current` であり、Bash tool 呼び出しごとに PGID が変わる `/verify` では前者に決してヒットせず、PGID 非依存のグローバル単一ファイル `auto-session-current` に常時フォールバックする。並行 `/auto` セッションが同ファイルを相互に上書きするため、event の `session_id` が誤ったセッションに帰属する。

本 Issue では、`/auto` が dispatch 時に `AUTO_SESSION_ID` を **引数で in-band に引き渡し** (案 A)、`/verify` がそれを **Issue 番号スコープのポインタファイル** に永続化して以降の全 emit で読む (案 B) というハイブリッド方式を採用する。加えて `run-auto-sub.sh --write-manual-recovery` 経路のポインタ再生成規律を `skills/auto/SKILL.md` に明記する (案 D)。案 C (文書化のみ、修正なし) は AC1 を満たせないため `/issue` フェーズで不採用が確定済み。

## Reproduction Steps

1. `/auto --batch A B ...` を起動する (セッション S1: `.tmp/auto-session-current` に S1 の ID を書き込む)
2. 別ターミナルで並行して `/auto --batch C D ...` を起動する (セッション S2: 同ファイルを S2 の ID で上書き)
3. S1 の batch が Issue A の verify に到達し、親セッションで `Skill(skill="wholework:verify", args="A")` を呼ぶ
4. `/verify` の各 emit 箇所で `restore_auto_session_pointer` が実行される。Bash tool 呼び出しごとに新しい PGID になるため `.tmp/auto-session-${PGID}` は存在せず、`.tmp/auto-session-current` にフォールバックする
5. `.tmp/auto-events.jsonl` を確認すると、Issue A の `phase_start` / `phase_complete` / `retro_proposal_classified` が **S2 の `session_id`** で記録されている

実測 (Issue body より、いずれも再現済みの実データ):

- 2026-07-29 セッション `46196-1785292524`: #1051 の in-session `/verify` event が `74736-1785294462` に帰属
- 2026-08-06 セッション `11623-1785995193`: `retro_proposal_classified` が双方向に誤帰属 (自セッション → 他セッション、他セッション → 自セッション)
- 2026-08-05 セッション `56516-1785934632`: `--write-manual-recovery` の `manual_intervention` 2 件が `65022-1785935372` に帰属し、Metrics に `Parent session manual interventions: 0` と表示

## Root Cause

根本原因は 2 層ある。

**(1) 解決キーが呼び出し元セッションを一意に識別できない**

`restore_auto_session_pointer()` (`scripts/emit-event.sh:161-174`) の探索順は次の 2 段のみ:

1. `.tmp/auto-session-${PGID}` — 各 Bash tool 呼び出しが新しいプロセスグループを得るため、in-session `/verify` では**構造上ヒットしない**
2. `.tmp/auto-session-current` — PGID 非依存の**グローバル単一ファイル**。`skills/auto/SKILL.md` Step 1 が `/auto` 起動時に無条件で上書きする

つまり実質的に常に (2) が使われ、並行セッション数が 2 以上なら誰の ID が入っているかはタイミング依存になる。「どのセッションが呼んだか」という情報が呼び出し経路のどこにも乗っていないことが本質で、ファイル名を変えるだけでは解決しない — **呼び出し元が自分の ID を明示的に渡す経路** (案 A) が必要。

なお 2026-07-31 の追加観測で「より古いセッション ID が新しいものを上書きした」現象が報告されており、`/auto` Step 1 の起動時上書き以外にも `auto-session-current` への書き込み経路が存在する可能性がある。in-band 引き渡し (案 A) はこの未知の書き込み経路にも耐える点で、ファイル名スコープ化のみ (案 B 単独) より優れる。

**(2) 単発 Bash 呼び出しがポインタ再生成規律から外れている**

`skills/auto/SKILL.md` Step 1 は「`run-code.sh` / `run-review.sh` / `run-merge.sh` / `run-auto-sub.sh` を呼ぶ直前に同じ Bash 呼び出しの中で `.tmp/auto-session-${PGID}` を再生成すること」を求めているが、Step 6 の Manual recovery hand-off (`--write-manual-recovery`) の記述にはこの言及がない。単独の Bash 呼び出しで実行すると PGID ポインタが存在せず `auto-session-current` にフォールバックする — 実測 2 の直接原因。

**修正方針の位置づけ (案 A/B/C/D の判断)**

| 案 | 採否 | 理由 |
|---|---|---|
| 案 A (引数で明示引き渡し) | **採用 (主)** | 呼び出し元の ID が in-band で伝わるため、ポインタファイルの競合・未知の上書き経路の双方に耐える |
| 案 B (Issue 番号スコープのポインタ) | **採用 (transport)** | 案 A で受け取った ID を `/verify` 内の後続 Bash 呼び出しへ運ぶ手段として使う。1 回書いて N 回読む形になり、11 箇所の emit で ID リテラルを引き回す必要がなくなる |
| 案 C (文書化のみ) | 不採用 | AC1 が「仕組みが実装されている」ことを要求。`/issue` フェーズで確定済み |
| 案 D (Step 6 のポインタ再生成明記) | **採用 (併用)** | 案 A/B が届かない `--write-manual-recovery` 経路を塞ぐ。AC3 が直接要求 |

案 A を「権威ある出所」、案 B を「セッション内の運搬手段」として組み合わせるのが本 Spec の設計である。案 B を単独採用しなかったのは (1) の未知の書き込み経路に耐えられないため、案 A を単独採用しなかったのは `/verify` の 11 箇所の emit ブロックすべてに session_id リテラルを LLM が引き回す必要があり、Step 1 のポインタ再生成規律と同じ「LLM の記憶に依存した規律」を新たに増やすことになるため。

## Changed Files

- `scripts/emit-event.sh`: `persist_auto_session_pointer()` を新規追加 (Issue 番号スコープのポインタ書き込み・空 session-id 時は削除)。`restore_auto_session_pointer()` に optional な issue-number 引数を追加し、解決順序を `AUTO_EVENTS_LOG` 既設 → `AUTO_SESSION_ID` env → issue-scoped → PGID → current の 5 段に変更 — bash 3.2+ 互換 (`mapfile` / 連想配列を使わない)
- `skills/verify/SKILL.md`: Step 1 に `--session-id=<SID>` の parse と `persist_auto_session_pointer` 呼び出しを追加。`restore_auto_session_pointer` の全 11 箇所を `restore_auto_session_pointer $NUMBER` に変更 (計測範囲: `skills/verify/SKILL.md` 単一ファイルに対する `grep -c "restore_auto_session_pointer"` = 11)
- `skills/auto/SKILL.md`: `Skill(skill="wholework:verify", ...)` の全 6 箇所の `args` に `--session-id=<literal SESSION_ID>` を追加 (計測範囲: `skills/auto/SKILL.md` 単一ファイルに対する `grep -c "wholework:verify"` = 6、frontmatter を除く本文のみ)。Step 1 に in-band 引き渡し規約を追記。Step 6 の `--write-manual-recovery` 呼び出し 2 箇所にポインタ再生成手順を追加
- `modules/retro-proposals.md`: Tier classification persistence の emit ブロックで `restore_auto_session_pointer` に `NUMBER` (numeric 時) を渡すよう変更。`/auto` 親セッションからの呼び出しでは `AUTO_SESSION_ID` をリテラルで前置する旨を追記
- `modules/event-emission.md`: `restore_auto_session_pointer()` 節を新しい解決順序 (exhaustive) に更新し、`persist_auto_session_pointer()` と `--session-id` in-band 引き渡しの説明を追加
- `tests/emit-event.bats`: 並行セッション下の解決順序テストを追加 (issue-scoped が `auto-session-current` に優先すること、`AUTO_SESSION_ID` env が最優先であること、`persist_auto_session_pointer` の書き込み/削除)
- `skills/audit/SKILL.md`: Session Boundary Identification のポインタファイル一覧に `.tmp/auto-session-issue-${ISSUE}` の行を追加
- `docs/structure.md`: `scripts/emit-event.sh` の説明に `persist_auto_session_pointer()` を追記
- `docs/ja/structure.md`: [translation sync] 上記 `docs/structure.md` の変更を日本語ミラーに反映 (`docs/translation-workflow.md` の Sync Procedure に従う)

**Steering Docs sync candidate (要確認、`/code` が最終判断):**

- `docs/migration-notes.md` / `docs/ja/migration-notes.md`: [Steering Docs sync candidate] `Skill(skill="wholework:verify", args="$NUMBER --base release/v1")` の対応表がある。`--session-id` を追記するか、run-verify.sh 廃止時点の履歴記録として据え置くかを確認。**除外推奨** — 当該表は移行時の対応関係を記録した履歴であり、現行の引数仕様の SSoT ではない
- `docs/reports/external-kill-investigation.md`: [Steering Docs sync candidate] L378 が本 Issue の failure mode を「#1075's known failure mode」として記述。**除外推奨** — 調査時点の観測を記録した report であり、修正後も当時の観測事実は変わらない
- `tests/auto-batch.bats`: [Steering Docs sync candidate] L19-20 が List mode 節に `wholework:verify` が含まれることを検査。`grep -q 'wholework:verify'` は部分一致のため `--session-id` 追加後も PASS する見込み。変更不要かを `/code` で確認すること

**"変更不要" の検証済み判断:**

- `scripts/run-spec.sh` / `run-code.sh` / `run-review.sh` / `run-merge.sh` / `run-issue.sh` / `run-auto-sub.sh`: いずれも `restore_auto_session_pointer` ではなく `AUTO_SESSION_ID="${AUTO_SESSION_ID:-$(cat ".tmp/auto-session-${PGID}" ...)}"` の直接展開で解決しており、wrapper は環境変数を子プロセスに export するため本 Issue の誤帰属経路に該当しない (grep 確認済み: `run-auto-sub.sh:384` の `restore_auto_session_pointer` のみが該当し、これは案 D で対処)
- `scripts/collect-run-facts.sh` / `filter-session-verified-issues.sh`: `auto-session-current` を読むが、これは「現在のセッション ID を解決する」用途であり emit 時の帰属とは別問題 (grep 確認済み)。本 Issue のスコープ外

## Implementation Steps

1. `scripts/emit-event.sh` に `persist_auto_session_pointer()` を追加する。挿入位置は `restore_auto_session_pointer()` 定義の直前。引数は `$1`=session id、`$2`=issue number。`git worktree list --porcelain` で main repo root を解決して `${root}/.tmp/auto-session-issue-${issue}` に `printf '%s\n'` で書き込む (root 解決ロジックは `restore_auto_session_pointer()` の既存実装と同一の idiom を使う)。`$1` が空文字列のときは同ファイルを `rm -f` して return 0 (standalone `/verify` が stale ポインタを自己修復するため)。`$2` が空なら何もせず return 0。bash 3.2+ 互換 (→ 受け入れ条件 1)

2. `scripts/emit-event.sh` の `restore_auto_session_pointer()` を optional な第 1 引数 (issue number) 受け取りに変更し、解決順序を以下の 5 段 (exhaustive) にする (after 1) (→ 受け入れ条件 1, 2):
   - `AUTO_EVENTS_LOG` が既に設定済み → 何もせず return 0 (既存挙動を維持)
   - `AUTO_SESSION_ID` が既に設定済み → その値を採用 (案 A の直接経路。従来は `_sid` が空だと `AUTO_EVENTS_LOG` が設定されず emit がスキップされていた不具合も同時に解消)
   - 引数で issue number が渡され `${root}/.tmp/auto-session-issue-${issue}` が存在 → その値を採用
   - `${root}/.tmp/auto-session-${PGID}` が存在 → その値を採用
   - `${root}/.tmp/auto-session-current` が存在 → その値を採用
   - いずれも該当なし → no-op (standalone `/verify` が uninstrumented のままであるという既存ポリシーを維持)

   issue-scoped を PGID より前に置くのは、in-session `/verify` では PGID が構造上ヒットせず、かつ OS が PGID を再利用した場合に他セッションの stale ポインタを誤って拾う潜在的ハザードがあるため。

3. `skills/verify/SKILL.md` の Step 1、phase banner 表示の直後・`phase_start` emit ブロックの直前に、`--session-id=<SID>` の parse とポインタ永続化の手順を追加する。ARGUMENTS に `--session-id=<SID>` があればその値を、なければ空文字列を第 1 引数として `persist_auto_session_pointer` を呼ぶ (`source "${CLAUDE_PLUGIN_ROOT}/scripts/emit-event.sh"` に続けて実行)。`--session-id` は `/verify` の新しいオプションとして冒頭の ARGUMENTS 説明にも追記する (after 2) (→ 受け入れ条件 1, 2)

4. `skills/verify/SKILL.md` の `restore_auto_session_pointer` 全 11 箇所を `restore_auto_session_pointer $NUMBER` に変更する。各箇所は直後に `EMIT_ISSUE_NUMBER=$NUMBER emit_event ...` を持つため `$NUMBER` は同一ブロック内で利用可能 (`verify_reopen_cycle` の printf 直書きブロックも同様) (after 3) (→ 受け入れ条件 1, 2)

5. `skills/auto/SKILL.md` の `Skill(skill="wholework:verify", ...)` 全 6 箇所の `args` に `--session-id=<literal SESSION_ID value from Step 1>` を追加する。対象は patch route の verify phase、pr route の verify phase、XL sub-issue fan-out、Step 5 の observation dispatch (single-issue path)、`--batch` List mode の Verify orchestration、`--batch` Step 5 の observation dispatch。あわせて Step 1 の「Pointer file regeneration required before every `run-*.sh` / `run-auto-sub.sh` call」段落の直後に、in-session `Skill(wholework:verify)` dispatch では PGID ポインタ再生成ではなく `--session-id` による in-band 引き渡しを使う旨の規約段落を追加する (parallel with 3, 4) (→ 受け入れ条件 1, 2)

6. `skills/auto/SKILL.md` Step 6 の `--write-manual-recovery` 呼び出し 2 箇所 (external-kill pre-check の Recording (mandatory) ブロックと、Manual recovery hand-off の段落) に、同じ Bash 呼び出しの中で `.tmp/auto-session-${PGID}` を再生成してから subcommand を呼ぶ手順を追加する。Step 1 の再生成規律と同じ形 (`PGID=$(ps -o pgid= -p $$ | tr -d ' ')` → `printf` → subcommand) を使い、Step 1 の規律の適用対象であることを明示する (parallel with 5) (→ 受け入れ条件 3)

7. `modules/retro-proposals.md` の Tier classification persistence の emit ブロックを `restore_auto_session_pointer <NUMBER が numeric のときのみ NUMBER、非 numeric なら引数なし>` に変更し、`/auto` 親セッション (Step 4a step 6 / Step 5 L3 step 6) から呼ばれる場合は emit ブロックの先頭で `AUTO_SESSION_ID="<literal SESSION_ID>"` を明示的に設定する旨を Numeric guard の直後に追記する (after 2) (→ 受け入れ条件 1, 2)

8. `tests/emit-event.bats` に並行セッション下の解決順序テストを追加する。既存の `restore_auto_session_pointer` テスト群の直後に配置し、最低限次の 4 ケースを含める: (a) `auto-session-current` に別セッション ID がある状態で issue-scoped ポインタが優先されること、(b) `AUTO_SESSION_ID` env が issue-scoped/current より優先され `AUTO_EVENTS_LOG` も導出されること、(c) `persist_auto_session_pointer` が issue-scoped ファイルを書くこと、(d) 空 session-id で呼ぶと既存の issue-scoped ファイルが削除されること。既存 4 テストが引き続き PASS することも確認する (after 2) (→ 受け入れ条件 4)

9. `modules/event-emission.md` の `restore_auto_session_pointer()` 節を新しい解決順序 (exhaustive マーカー付き) に書き換え、`persist_auto_session_pointer()` と `--session-id` in-band 引き渡しの説明を追加する。あわせて `skills/audit/SKILL.md` の Session Boundary Identification のポインタファイル一覧に `.tmp/auto-session-issue-${ISSUE}` の行を追加する (after 2) (→ 受け入れ条件 5)

10. `docs/structure.md` の `scripts/emit-event.sh` の説明行に `persist_auto_session_pointer()` を追記し、`docs/translation-workflow.md` の Sync Procedure に従って `docs/ja/structure.md` の対応行を日本語で同期する。コードフェンス数の一致確認まで実施する (after 1) (→ 受け入れ条件 5)

## Verification

### Pre-merge

- <!-- verify: rubric "in-session Skill() 呼び出しで起動された /verify が emit する event の session_id が、呼び出し元の /auto セッションの AUTO_SESSION_ID と一致することを保証する仕組み (引数での明示引き渡し、Issue 番号スコープのポインタ、または同等の方式) が実装されている" --> in-session `/verify` の event が呼び出し元セッションに正しく帰属する
- <!-- verify: rubric "並行する複数の /auto セッションが同時に存在する状況で、後発セッションの起動が先行セッションの in-session /verify の session_id 解決を壊さないことが、実装またはテストで担保されている" --> 並行 `/auto` セッションが互いの session_id 解決を壊さない
- <!-- verify: rubric "run-auto-sub.sh --write-manual-recovery のようなサブコマンド呼び出しについても、pointer ファイル再生成の指示または同等の session_id 解決保証が skills/auto/SKILL.md に記述されている" --> サブコマンド呼び出し経路の session_id 解決が担保されている
- <!-- verify: rubric "tests/emit-event.bats もしくは同等のテストに、並行セッション下での session_id 解決を検証するケースが追加されている" --> 並行セッションのケースがテストで保護されている
- <!-- verify: rubric "modules/event-emission.md の restore_auto_session_pointer に関する記述が、変更後の解決順序・並行セッション時の挙動と一致している" --> ドキュメントが実装と整合している

### Post-merge

- 並行 `/auto` セッションを 2 本以上走らせた状態で `--batch` を実行し、`.tmp/auto-events.jsonl` 上で in-session `/verify` の event が正しい `session_id` を持つことを確認する

## Tool Dependencies

### Bash Command Patterns

- 追加なし。`skills/verify/SKILL.md` の `allowed-tools` は既に `${CLAUDE_PLUGIN_ROOT}/scripts/emit-event.sh:*` を含んでおり、新規追加する `persist_auto_session_pointer` は同ファイルを `source` した上での関数呼び出しであるため、既存の `restore_auto_session_pointer` 呼び出しと同じ形になる。`skills/auto/SKILL.md` 側も `${CLAUDE_PLUGIN_ROOT}/scripts/emit-event.sh:*` と `${CLAUDE_PLUGIN_ROOT}/scripts/run-auto-sub.sh:*` を既に保持している

### Built-in Tools

- 追加なし (`Read` / `Edit` / `Grep` はいずれも既存の `allowed-tools` に含まれる)

### MCP Tools

- なし

## Uncertainty

- **`Skill()` の `args` 文字列が `/verify` の ARGUMENTS に素通しで届くか**: `--session-id=<SID>` を `args` に載せる設計は、`/verify` が既に `--base {branch}` を ARGUMENTS 経由で受け取っている実績 (`skills/verify/SKILL.md` Step 2、`docs/migration-notes.md` の `args="$NUMBER --base release/v1"` 対応表) に依拠している
  - **検証方法**: `/code` フェーズで `skills/verify/SKILL.md` の `--base` パース記述を確認し、同じ書式で `--session-id` を記述する。実挙動の確認は post-merge の並行セッション実測 AC に委ねる
  - **影響範囲**: Implementation Steps 3, 5

- **standalone `/verify` による stale ポインタ自己修復の十分性**: `--session-id` なしの `/verify` が `.tmp/auto-session-issue-<N>` を削除する設計にしたが、`/auto` セッションが verify 到達前に異常終了した場合、当該 Issue の issue-scoped ポインタが残存する。次に同 Issue を扱う `/auto` セッションが dispatch 時に上書きするため実害は限定的だが、その間に standalone `/verify` が走ると削除されるまでの 1 回だけ古いセッションに帰属しうる
  - **検証方法**: `tests/emit-event.bats` の削除ケース (Implementation Step 8 の (d)) で削除動作自体は担保する。残存シナリオ自体はテストせず、既知の制約として Notes に記録する
  - **影響範囲**: Implementation Steps 1, 3

## Notes

**自動解決した曖昧点 (non-interactive mode)**

1. **対応方針として案 A + 案 B + 案 D のハイブリッドを採用** — 理由: 案 A 単独では `/verify` の 11 箇所の emit ブロックすべてに session_id リテラルを LLM が引き回す必要があり、Step 1 のポインタ再生成規律と同種の「LLM の記憶に依存した規律」を新設することになる。案 B 単独では 2026-07-31 に観測された未知の `auto-session-current` 上書き経路に耐えられない。A を権威ある出所、B をセッション内の運搬手段として組み合わせると、`/auto` 側は既存の 1 行に flag を足すだけ・`/verify` 側は Step 1 で 1 回書いて N 回読む形に収まる
   - Other candidates: 案 A 単独 / 案 B 単独 — 上記理由により見送り。案 C は `/issue` フェーズで不採用確定済み

2. **`restore_auto_session_pointer()` の解決順序で issue-scoped を PGID より前に置く** — 理由: in-session `/verify` では PGID ポインタが構造上ヒットせず、OS が PGID を再利用した場合に他セッションの stale ポインタを誤って拾う潜在的ハザードがある。issue-scoped の方が呼び出し元をより特異に識別できる。wrapper script 群はこの関数を使わず直接展開で解決しているため、順序変更の影響を受けない
   - Other candidates: PGID を先に置く (既存順序を最大限保つ) — stale PGID ハザードが残るため見送り

3. **stale な issue-scoped ポインタは standalone `/verify` が自己修復する** — 理由: TTL や mtime 判定を導入すると解決ロジックが時刻依存になりテストが不安定化する。`--session-id` の有無という決定的な条件で書き込み/削除を分岐させれば、追加の呼び出し箇所を増やさずに済む
   - Other candidates: `/verify` 終端で明示的に削除する / mtime による staleness 判定 — 前者は呼び出し箇所と LLM 規律が増え、後者は時刻依存になるため見送り

4. **`/auto` 親セッションからの `retro-proposals.md` 呼び出しは `AUTO_SESSION_ID` リテラル前置で対処** — 理由: `/auto` Step 4a / Step 5 L3 の呼び出しは `BRIDGE_NUMBER="batch-<session-id>"` のような非 numeric な NUMBER を取りうるため issue-scoped ポインタが使えない。親セッションは自身の SESSION_ID リテラルを保持しているので、Implementation Step 2 で新設する「`AUTO_SESSION_ID` env が最優先」分岐をそのまま使える
   - Other candidates: `/auto` 側で PGID ポインタを再生成してから retro-proposals を呼ぶ — Bash 呼び出しを 1 段増やす割に得られる保証が同等のため見送り

5. **既存の `.tmp/auto-session-current` は廃止せず維持する** — 理由: `run-spec.sh` / `run-code.sh` / `run-review.sh` / `run-merge.sh` / `run-issue.sh` / `collect-run-facts.sh` / `filter-session-verified-issues.sh` が読んでおり、廃止すると影響範囲が本 Issue のスコープを大きく超える。最終フォールバックとして残し、`modules/event-emission.md` に「並行運用時は最終手段であり帰属精度を保証しない」旨を記載する
   - Other candidates: `auto-session-current` の廃止 — blast radius が過大なため見送り

**実装上の注意**

- `scripts/emit-event.sh` は macOS system bash (3.2) 上で動作するため、`mapfile` / 連想配列 / `${var^^}` 等の bash 4+ 構文を使わないこと
- `persist_auto_session_pointer()` の main repo root 解決は `restore_auto_session_pointer()` と同一の `git worktree list --porcelain | awk '/^worktree /{print $2; exit}'` idiom を使うこと。git repo 外 (bats の tmpdir fixture 等) では prefix が空になり CWD 相対にフォールバックする既存挙動を維持する
- `restore_auto_session_pointer()` の既存テスト 4 件 (`tests/emit-event.bats` の `auto-session-current` 復元 / no-op / `AUTO_EVENTS_LOG` 既設時の非上書き / linked worktree からの解決) はいずれも `AUTO_SESSION_ID` を unset した状態で実行しているため、新設する「`AUTO_SESSION_ID` env 最優先」分岐の影響を受けず、そのまま PASS するはず。実装後に確認すること
- `tests/auto-batch.bats` の L19-20 は List mode 節に `wholework:verify` が含まれることを `grep -q` で検査しており部分一致のため、`args` への `--session-id` 追加では壊れない見込み
- `skills/auto/SKILL.md` / `skills/verify/SKILL.md` の編集では `validate-skill-syntax.py` の既知制約 (本文中の半角感嘆符禁止、本文中のトリプルバックティック禁止、frontmatter の YAML block scalar 不可) に抵触しないこと

**AC と Out of Scope の整合性**

Issue body に `## Out of Scope` セクションは存在せず、Pre-merge / Post-merge の AC と矛盾する記述もない。

**Issue body と既存実装の conflict**

`/issue` フェーズの Issue Retrospective が Background の技術的主張 (探索順、Step 6 の pointer 再生成言及の欠如) を grep で検証済みと報告しており、本 Spec でも `scripts/emit-event.sh:161-174` と `skills/auto/SKILL.md` Step 1 / Step 6 を再確認した。conflict は検出されなかった。
