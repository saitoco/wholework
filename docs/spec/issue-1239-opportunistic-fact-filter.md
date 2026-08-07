# Issue #1239: opportunistic-search: run-fact token 絞り込みを opportunistic mode に導入

## Overview

`scripts/opportunistic-search.sh` の opportunistic mode (`--event` なしで skill 名指定時) には絞り込みゲートが実質存在せず、`/verify` 完了時の実測 (session `33233-1786023637`) では 6 回の実行すべてで同じ 14 件が候補として列挙され全て SKIP と判定された (84 回判定 / PASS 0 件)。

既存の `keyword=` ゲートは match loop 内で mode 非依存に実装済みだが、呼び出し元 `modules/opportunistic-verify.md` が `--context-file` を渡していないため到達不能になっている。また `keyword=` 属性自体も既存 AC の大半に付いていない (`/verify` 向け候補 14 件中主要 8 件が `keyword=0`)。

一方 `scripts/scan-pending-ac.sh --facts <path>` は AC 側の属性を必要としない run-fact token 照合を実装済みで、実測 (session `3340-1786079730`) で 418 件 → 186 件 (55.5% 除外) の効果が確認されている。本 Issue はこの同じロジックを `opportunistic-search.sh` の opportunistic mode に横展開し、属性付与を待たずに即座に効く絞り込みを導入する。あわせて `--context-file` 伝播で `keyword=` ゲートの到達不能な穴も塞ぐ。

## Changed Files

- `scripts/opportunistic-search.sh`: change — `--facts <path>` オプション追加 (既存の `--facts-file <path>` とは別物)。opportunistic mode (`--event` なし) の per-line match loop に fact-token フィルタを追加。header usage コメント更新。bash 3.2+ 互換 (macOS system bash) — `mapfile`/`${VAR,,}` は使わず、`scripts/scan-pending-ac.sh` と同じ `while read` ベースのトークン照合パターンに合わせる
- `modules/opportunistic-verify.md`: change — Step 1 に、`restore_auto_session_pointer` による session id 解決 → `collect-run-facts.sh` 呼び出し → `--facts`/`--context-file` を `opportunistic-search.sh` へ伝播する手順を追加
- `modules/verify-patterns.md`: change — §10 (Opportunistic Post-Merge Conditions) に `keyword=` の既存 AC 一括付与スコープ外方針を追記
- `tests/opportunistic-search.bats`: change — `--facts` トークンフィルタの新規テストケース追加 (`fact gate: ...` 命名規則)
- `docs/structure.md`: [Steering Docs sync candidate] `scripts/opportunistic-search.sh` の説明 ("opportunistic skill search and observation event scan", line 206) が `--facts` 追加後も正確か確認。役割自体は変わらないため変更不要見込みだが `/code` で最終判断 (`docs/ja/structure.md` の対応行も同様)
- `skills/code/SKILL.md`, `skills/issue/SKILL.md`, `skills/review/SKILL.md`, `skills/spec/SKILL.md`, `skills/verify/SKILL.md`: change — `modules/opportunistic-verify.md` Step 1 が新たに `collect-run-facts.sh` を呼ぶため、この 5 skill の `allowed-tools` に `${CLAUDE_PLUGIN_ROOT}/scripts/collect-run-facts.sh:*` を追加 (`scripts/validate-skill-syntax.py` のクロスファイル検証で検出。Code Retrospective 参照)

## Implementation Steps

1. `scripts/opportunistic-search.sh` に `--facts <path>` オプションと fact-token フィルタを追加する (→ acceptance criteria AC1, AC2)
   - 引数パースに `--facts <path>` を追加 (既存の `--facts-file <path>` とは別のケース分岐。文字列前方一致ではなく `case` の完全一致なので衝突しない)
   - パース後、`scripts/scan-pending-ac.sh` と同じロジック (`jq -r '[.issues[].fact_tokens[]?] | unique | .[]'` → lowercase) で `FACT_TOKENS_LOWER` を解決する。ファイル不在・parse 失敗時は stderr に warning を出してフィルタを無効化 (fail-open — `scan-pending-ac.sh` のような hard error ではなく、本スクリプトの既存 `--context-file`/`--facts-file` と同じ規約に合わせる)
   - 共有 per-line match loop 内に `[ -z "$EVENT_NAME" ]` (opportunistic mode のみ) でガードした新規ゲートを追加: `FACT_TOKENS_LOWER` が非空かつ行の小文字化テキストがどのトークンも部分文字列として含まない場合はスキップ。event mode 側の `--facts-file`/`when=` ゲートは変更しない
   - header usage コメントに `--facts <path>` (この文字列そのもの。`--facts PATH` 等の別表記にしない) を `--facts-file <path>` と並べて追記し、両者の違い (`--facts`: condition text へのトークン部分文字列照合・AC 属性不要・opportunistic mode 限定 / `--facts-file`: 構造化 `when=` 節照合・event mode) を一行で説明する

2. `modules/opportunistic-verify.md` Step 1 で `--facts`/`--context-file` を生成・伝播する (→ acceptance criteria AC3, AC4, AC5, AC6) (parallel with 1)
   - `opportunistic-search.sh` 呼び出し前に `source scripts/emit-event.sh` して `restore_auto_session_pointer <呼び出し元スキル自身の Issue/PR 番号>` を呼ぶ (Step 3 が既に行っている呼び出しと同一 — 新しい session-id 受け渡しフラグは導入しない)
   - `AUTO_SESSION_ID` が解決できた場合: `collect-run-facts.sh` を `--session` 明示なしで呼ぶ (今設定された `AUTO_SESSION_ID` 環境変数を既存のフォールバック順で自動的に拾う) → `.tmp/facts-<session>.json` へ出力 → `--facts .tmp/facts-<session>.json` を付与。解決できない場合 (standalone 実行等) は `--facts` を省略し、現行と同じ無絞り込み動作を維持する
   - Write ツールで `.tmp/context-<呼び出し元 Issue 番号>.md` を生成する (内容: 現在処理中の Issue の body。`$SPEC_PATH/issue-<番号>-*.md` に Spec が存在する場合はその `## Changed Files` セクションも含める) → `--context-file .tmp/context-<番号>.md` を付与
   - session id 解決方式が `restore_auto_session_pointer()` の再利用であり新規フラグを要しないことをモジュール本文に明記する (AC3 の「session id の解決方法が明記されていること」を満たす)

3. `modules/verify-patterns.md` §10 に `keyword=` 一括付与スコープ外方針を記録する (→ acceptance criteria AC7) (parallel with 1, 2)
   - 「既存の opportunistic AC への `keyword=` 一括付与は本 Issue のスコープ外とし、新規 AC から適用する」という方針を一文で追記する。#1172 が `when=` について同じ判断をした前例に合わせる (`docs/spec/issue-1169-search-population-limit.md` 134行目に前例の引用あり — Spec は disposable のため一次情報としては残らず、本追記が耐久的な記録になる)

4. `tests/opportunistic-search.bats` に `--facts` フィルタのテストケースを追加する (after 1) (→ acceptance criteria AC9, AC10)
   - 既存の `"context gate: ..."` / `"config gate: ..."` / `"when gate: ..."`命名規則に倣い `"fact gate: ..."` を新設
   - カバー範囲: トークン一致で該当 Issue を含む / トークン不一致で除外する / `--facts` 未指定時は無条件マッチ (後方互換) / 存在しない `--facts` パスは warning 付きでゲート無効化 / event mode (`--event`) では `--facts` が効かない (`--facts-file`/`when=` のみ有効) ことの確認
   - fixture JSON は `collect-run-facts.sh` の出力形式に合わせる: `{"session_id":"s1","issues":[{"number":1,"fact_tokens":["token"]}]}` (`tests/run-fact-matching.bats` の `scan-pending-ac.sh --facts` テストと同じ形)

5. 絞り込み効果を実測し Spec に記録する (after 1, 2) (→ acceptance criteria AC8)
   - Step 1, 2 実装後、`scripts/opportunistic-search.sh /verify --facts <実際または代表的な run-facts JSON>` を実行し、Issue #1239 本文記載のベースライン 14 件 (計測 scope: `phase/verify` ラベル付き closed Issue のうち `verify-type: opportunistic` タグ + skill `/verify` を含むもの。session `33233-1786023637` で計測) と比較する
   - 前後の件数・facts のソース (session id またはファイル)・計測日を本 Spec の `## Verification` セクション (Pre-merge リスト直下のプレースホルダ行) に追記する

## Verification

### Pre-merge

- <!-- verify: file_contains "scripts/opportunistic-search.sh" "--facts <path>" --> `opportunistic-search.sh` が `--facts` オプションを受け付ける
- <!-- verify: rubric "scripts/opportunistic-search.sh の opportunistic mode (--event なし) の match loop で、--facts で渡された run-fact token による condition text の絞り込みが適用されている。--facts 未指定時は全件通過する後方互換が維持されていること" --> opportunistic mode に token 絞り込みが適用され後方互換が維持されている
- <!-- verify: rubric "modules/opportunistic-verify.md の Processing Steps で、collect-run-facts.sh の出力を opportunistic-search.sh へ --facts で渡す手順が記述されている。session id の解決方法が明記されていること" --> `opportunistic-verify.md` が facts を渡す手順を持つ
- <!-- verify: file_contains "modules/opportunistic-verify.md" "--facts" --> `opportunistic-verify.md` に `--facts` の記述がある
- <!-- verify: rubric "modules/opportunistic-verify.md の Processing Steps で、opportunistic-search.sh 呼び出し時に --context-file を渡す手順が記述されており、渡す内容 (今回処理した Issue の body + Spec の Changed Files など) が明記されている" --> `opportunistic-verify.md` から `--context-file` を伝播する手順が記述されている
- <!-- verify: file_contains "modules/opportunistic-verify.md" "--context-file" --> `opportunistic-verify.md` に `--context-file` の記述がある
- <!-- verify: rubric "既存 AC への keyword= 一括付与を行わない方針と、新規 AC から適用する指針が modules/ 配下のいずれかに記録されている" --> `keyword=` の適用方針が記録されている
- <!-- verify: rubric "変更前後の候補件数の比較が Spec の Verification セクションに数値で記録されている。ベースラインは /verify skill で 14 件" --> 絞り込み効果が数値で記録されている
- <!-- verify: command "bats tests/opportunistic-search.bats" --> `tests/opportunistic-search.bats` が PASS する
- <!-- verify: github_check "gh pr checks" "Run bats tests" --> CI (bats テスト) が PR で pass する

**Effect measurement (baseline)**: 14 件 (opportunistic mode, skill `/verify`。scope: `phase/verify` ラベル付き closed Issue のうち `verify-type: opportunistic` タグ + skill 名 `/verify` を含む Pre-merge/Post-merge 条件。session `33233-1786023637` で計測、Issue #1239 本文記載)。Implementation Step 5 の実施後、`/code` はこの行の直下に実装後の件数・facts のソース・計測日を追記すること (AC8 の充足条件)。

**Effect measurement (after implementation, 2026-08-07)**: `scripts/opportunistic-search.sh /verify` (`--facts` なし) で同じ母集団を再計測したところ **13 件** (ベースライン計測時点 session `33233-1786023637` から2日経過し数件クローズ等で微減。14→13 は同一計測手法の自然変動であり、`--facts` 未指定時に絞り込みが効いていないこと自体はこの再計測で確認済み — 後述のバックワード互換性確認と同義)。同じ母集団に対して `--facts` を付与し、spec→code→review→merge を完了した pr route セッション (Size M) を想定した代表的な run-facts JSON (`fact_tokens: ["pr route","Size M","spec","code","review","merge","#1300"]`) で絞り込むと **5 件** (#1051, #1053, #231, #436, #781) まで減少した — **61.5% 除外 (13→5)**。facts のソース: 実行中の `/auto` セッションが存在しない単発実行環境のため、Implementation Step 5 の指示 (「実際または代表的な run-facts JSON」) に従い、実際の `collect-run-facts.sh` 出力形式に相当する代表的 JSON (`.tmp/facts-repr-1239.json`) を使用した。

### Post-merge

- 次回以降の skill 完了時の opportunistic verification で、候補件数が変更前 (14 件) より減少していることを観察する <!-- verify-type: observation event=auto-run session=next -->

## Notes

- **session id 解決方式の決定**: Issue 本文は「#1234 と同じ方式 (`observation-trigger.sh` への `--session` 追加) を採るか、#1234 着地後にその実装を流用するか」を設計時判断に委ねていた。調査の結果、`collect-run-facts.sh` は既に `--session` フラグ / `AUTO_SESSION_ID` 環境変数 / `.tmp/auto-session-current` ポインタファイルの3段フォールバックを持ち (#1075/#1224)、`modules/opportunistic-verify.md` Step 3 は既にこのフォールバックの一部である `restore_auto_session_pointer()` (`scripts/emit-event.sh`) を呼んでいる。したがって #1234 の `observation-trigger.sh --session` 拡張を待つ・流用する必要はなく、Step 1 で `restore_auto_session_pointer` を先出しして `AUTO_SESSION_ID` を解決させ、`collect-run-facts.sh` を `--session` 明示なしで呼ぶだけで済む。この関数は `[[ -n "${AUTO_EVENTS_LOG:-}" ]] && return 0` で冪等なため、Step 3 で再度呼ばれても副作用はない。#1234 への依存はなく、blocked-by も不要という Issue 本文の記載と整合する
- **`--facts` と `--facts-file` の役割分担**: 命名が近いため、実装時に両者を混同しないよう Implementation Step 1 で明示した。`--facts` (本 Issue で新規追加): condition text への生トークン部分文字列照合、AC 属性不要、opportunistic mode (`--event` なし) 限定。`--facts-file` (既存): `when=<axis>:<value>` 属性を run facts JSON の構造化フィールドと照合、event mode 用だが実装上は mode 非依存の共有ループ内にある。event mode で `--facts` を渡しても (ガードにより) 無視される — 誤用時に warning を出す等の追加防御は本 Issue の AC に含まれないため `/code` の裁量とする
- **`keyword=` ゲート自体の修正は不要**: `keyword=` ゲートの実装 (`opportunistic-search.sh` L255-266) は既に mode 非依存で、`--context-file` さえ渡されれば opportunistic mode でも正しく動作する。今回の変更は呼び出し元 (`modules/opportunistic-verify.md`) から `--context-file` を渡す配線のみで、ゲート実装自体への変更はない
- **BRE メタ文字チェック**: Issue 本文の verify command はいずれも `file_contains`/`rubric`/`command`/`github_check` で `grep` 形式の `\|` 等の BRE メタ文字は含まれない。該当なし
- **patch route 検証**: `ALWAYS_PR=false` かつ Size=M → pr route (PR が存在する) のため `github_check "gh pr checks" "Run bats tests"` はそのまま正しい形。実際に `.github/workflows/test.yml` のジョブ名が `Run bats tests` であることを確認済み。修正不要
- **Issue 本文との整合性確認**: Background の事実主張 (2 モード構成、`keyword=` ゲートの mode 非依存性、`modules/opportunistic-verify.md` の `--context-file` 未伝播、`scan-pending-ac.sh --facts` のロジック) はいずれもコードベース実測で確認済み。実装との矛盾なし

## Consumed Comments

- **saito** (MEMBER, first-class): Issue Retrospective。Auto-Resolved Ambiguity Points の根拠 (`--facts` 検索文字列を `--facts-file` との部分文字列衝突を避けて `--facts <path>` に変更した理由、`--context-file` 伝播検証 AC を追加した理由、session id 解決方式を設計時判断に据え置いた理由) を記録。Background の事実主張はコードベース実測で裏付け確認済みとのこと — 本 Spec の調査でも独立に同じ結論を確認した。https://github.com/saitoco/wholework/issues/1239#issuecomment-5216043099

## Code Retrospective

### Deviations from Design

- Spec の `## Changed Files` に含まれていなかった 5 つの `skills/*/SKILL.md` (code/issue/review/spec/verify) の `allowed-tools` に `${CLAUDE_PLUGIN_ROOT}/scripts/collect-run-facts.sh:*` を追加した。原因: `modules/opportunistic-verify.md` Step 1 が新規に `collect-run-facts.sh` を呼ぶようになったため、`scripts/validate-skill-syntax.py` のクロスファイル検証 (呼び出し元 skill の allowed-tools に呼び出し先スクリプトが宣言されているかを確認) が 5 件のエラーを検出した。Spec 作成時にこのクロスファイル依存が見落とされていた — `modules/opportunistic-verify.md` は 5 skill から共有されるモジュールであるため、このモジュールに新しいスクリプト呼び出しを追加する変更は常に全呼び出し元の allowed-tools 更新を伴う。今後同様のモジュール変更を計画する際は、Spec 作成段階で `grep -rl "modules/<name>\.md" skills/*/SKILL.md` によって呼び出し元一覧を洗い出し、Changed Files に含めることを検討する。

### Design Gaps/Ambiguities

- N/A (Spec の Notes セクションで事前に解決済みの論点以外に新規の設計上の疑問点はなかった)

### Rework

- N/A (上記の allowed-tools 追加以外に手戻りは発生しなかった)

## Phase Handoff
<!-- phase: merge -->

### Key Decisions
- Pre-merge AC gate re-confirmed clean (`check-pre-merge-ac.sh`: 0 unchecked of 10) and `review_incomplete_fallback` was not set, so the merge proceeded without any override marker
- `gh-pr-merge-status.sh` reported `mergeable=true reason=clean` — no rebase/conflict resolution was needed

### Deferred Items
- Existing opportunistic/observation AC still lack `keyword=` attributes (unchanged from code/review-phase handoffs — bulk backfill remains out of scope; see `modules/verify-patterns.md` §10)
- The effect measurement (13→5, 61.5%) still uses a representative run-facts JSON rather than a real `/auto` session's output — a real measurement is only available once `modules/opportunistic-verify.md`'s new Step 1 has actually run inside an `/auto` session (unchanged from code/review-phase handoffs)

### Notes for Next Phase
- `/verify` should expect the Post-merge observation condition (`event=auto-run session=next`) to remain unchecked until a real `/auto` session runs with the new Step 1 in place — this is by design, not a regression
- No other post-merge risks identified; all Pre-merge AC and CI were green at merge time

## review retrospective

### Spec vs. implementation divergence patterns

Nothing to note. All 10 Pre-merge acceptance conditions (4 `file_contains`, 4 `rubric`, 1 `command`, 1 `github_check`) verified PASS against the implementation as merged into the PR branch, with no structural divergence between the Spec's Implementation Steps and the actual diff beyond the already-self-disclosed `allowed-tools` addition (recorded in the Spec's own Code Retrospective).

### Recurring issues

Two independent SHOULD-severity findings landed in the same small `modules/opportunistic-verify.md` Step 1 section across this PR's two review passes: an earlier pass (12:56Z, prior to this `/review` invocation) found a Bash-redirect-vs-Write-tool inconsistency (already fixed in commit `acd4cfb0` before this review ran); this pass's `review-light` agent found a second, independent issue — `restore_auto_session_pointer` and the subsequent `collect-run-facts.sh` call were presented as separate, unfenced steps, which could reintroduce the exact session-misattribution class Issue #1224 fixed if an executing agent splits them into separate Bash tool calls (fixed in this pass, combining them into one fenced block per Step 3's existing pattern).

Both findings share a root cause: this module's Step 1 (`--facts` resolution) was newly added prose describing a multi-command procedure, and did not follow the two conventions this same file's Step 3 already established (Write tool for `.tmp/` output, single fenced Bash block for session-pointer-dependent command sequences). When a new Step is modeled after prose description rather than copying an existing Step's established fencing/tooling pattern, both issues recur. Worth flagging for future module edits that add new multi-command procedures near existing ones with established conventions: explicitly diff the new Step's presentation against the nearest existing Step with the same shape (here, Step 3) rather than composing it independently.

### Acceptance criteria verification difficulty

Nothing to note. No UNCERTAIN results, no missing or inaccurate verify commands. The 4 `rubric` conditions (session-id-resolution documentation, `--context-file` propagation documentation, `keyword=` policy recording, numeric effect-measurement recording) all resolved cleanly against the PR diff and Spec content, including the AC8 numeric-comparison condition, whose Spec text needed to explain a small baseline drift (14→13, attributed to natural population change over 2 days) before presenting the actual `--facts`-filtered comparison (13→5) — the explanation was judged sufficient to satisfy "baseline is 14" without requiring a strict re-measurement against the exact original 14.

## Verify Retrospective

### Phase-by-Phase Review

#### issue
- `/issue` フェーズが AC の致命的な欠陥を検出・修正した: `file_contains "scripts/opportunistic-search.sh" "--facts"` は既存の `--facts-file <path>` オプションを部分文字列として拾うため、実装 0 行で常時 PASS していた。`--facts <path>` (末尾に空白 + `<path>`) へ変更して解消。**先行する `/triage` の AC 監査はこれを見逃していた** — triage の常時 PASS 検出は grep/file_contains の検索文字列を main に対して空撃ちする手順だが、この AC は「実装前でも PASS する」ことを検出できたはずで、監査の実効性に穴があった可能性がある
- `## Purpose` に明記された「`--context-file` の穴を塞ぐ」副次対応を検証する AC が欠落していた点も検出し、rubric + file_contains のペアを追加した

#### spec
- **共有モジュールの呼び出し元 allowed-tools が Changed Files から漏れた**。`modules/opportunistic-verify.md` に `collect-run-facts.sh` 呼び出しを追加したことで、5 つの `skills/*/SKILL.md` の `allowed-tools` 更新が必要になったが、Spec の Changed Files には含まれていなかった
- session id 解決方式を `#1234` の着地待ちにせず、既に同モジュールが使っている `restore_auto_session_pointer()` を先出しする方式で独立実装可能と判断したのは適切だった (blocked-by 化を回避)

#### code
- 上記 allowed-tools 5 件の追加が設計逸脱として発生。`scripts/validate-skill-syntax.py` のクロスファイル検証が機械的に捕捉した
- それ以外の手戻りなし

#### review
- 2 回のレビューパスで、`modules/opportunistic-verify.md` の**同一の Step 1 セクション**に独立した SHOULD 指摘が 2 件着地した: (1) Bash リダイレクト vs Write ツールの不整合、(2) `restore_auto_session_pointer` と `collect-run-facts.sh` 呼び出しが別々の unfenced ステップとして提示され、#1224 が修正した session 誤帰属クラスを再導入しうる状態
- 両者の根本原因は同一 — 新規 Step を、同ファイルの Step 3 が既に確立していた規約 (`.tmp/` 出力には Write ツール、session pointer 依存のコマンド列は単一の fenced block) に照らさず、prose から独立に構成したこと

#### merge
- `mergeable=true reason=clean`、未チェック AC 0/10、`review_incomplete_fallback` なし。conflict 解決も不要

#### verify
- Pre-merge 10 件は全て `[x]` 済みで already-checked rule により SKIPPED。post-merge observation 1 件は `auto-run` 未発火 + `session=next` で SKIPPED。FAIL/UNCERTAIN 0 件
- **効果測定が代表 JSON ベースに留まる**点は Phase Handoff の Deferred Items にも記録済み。13→5 (61.5% 削減) は実 `/auto` セッション出力ではなく代表的な run-facts JSON による測定であり、実測は observation AC の発火待ち

### Improvement Proposals

- **共有モジュールへのスクリプト呼び出し追加時、呼び出し元 skill の `allowed-tools` 更新が Spec の Changed Files から系統的に漏れる**: 本 Issue で 5 ファイル (`skills/{code,issue,review,spec,verify}/SKILL.md`) が漏れ、**同一セッションの #1236 でも同型の漏れが 2 ファイル** (`skills/issue/SKILL.md` / `skills/review/SKILL.md` に `emit-event.sh`) 発生した。いずれも `/spec` 段階では検出されず、`scripts/validate-skill-syntax.py` のクロスファイル検証が code フェーズで初めて捕捉している。`modules/*.md` は複数 skill から "Read and follow" される共有面であり、**新しいスクリプト呼び出しの追加は常に全呼び出し元の `allowed-tools` 更新を伴う**という構造的性質がある。`/spec` に「変更対象が `modules/*.md` かつ新規スクリプト呼び出しを追加する場合、`grep -rl "modules/<name>\.md" skills/*/SKILL.md` で呼び出し元を洗い出し Changed Files に含める」チェックを入れれば機械的に防げる。#1236 の Code Retrospective と本 Issue の Code Retrospective の 2 件が独立に同じ再発防止策を提案している
- **新規 Step を既存 Step の確立された規約に照らさず prose から構成すると、同一セクションに同種の指摘が反復する**: 本 PR では 2 回のレビューパスで同じ Step 1 に 2 件の SHOULD 指摘が着地した。モジュールに複数コマンドから成る新規 Step を追加する際は、同ファイル内で同じ形をした最も近い既存 Step (本件では Step 3) と提示形式を明示的に diff する運用が有効
- **`/triage` の AC 監査が「既存オプションの部分文字列による常時 PASS」を検出できなかった**: `file_contains "scripts/opportunistic-search.sh" "--facts"` は既存の `--facts-file` にマッチするため実装前から PASS する欠陥だったが、triage の監査コメントには挙がらず `/issue` フェーズで初めて検出された。`skills/triage/skill-dev-verify-audit.md` Pattern 2 の検出手順は「main に対して空撃ちする」と定義されており、本来検出可能だったはず。監査の実行漏れか、検索文字列が短くオプション名の部分一致になるケースを想定していないかのいずれか

