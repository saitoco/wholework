# Issue #1475: orchestration: merge phase auto-retry の deferral 解除条件に回避可能性の判定を加える

## Overview

`modules/orchestration-fallbacks.md` § "auto-retry-on-fail (code_retry_fire)" の Phase Scope Decision は、merge phase への auto-retry 拡張を「実際の merge phase の silent no-op インシデントが、追加の設計・実装コストを正当化するまで」保留している。#1462 / PR #1465 でこの条件を形式上満たすインシデントが発生したが、真因は merge gate が pre-merge AC 未チェックで設計どおり停止したことで、auto-retry が実装されていても同じ地点で再停止したはずだった。件数だけを解除条件にすると、救えないインシデントを根拠に不可逆操作 (`gh pr merge ... --delete-branch`) のリトライ機構を実装してしまう。

この Issue はドキュメントのみの変更で、次の 3 点を行う。

1. merge phase の deferral 解除条件を、「インシデントが発生したか」から「silent no-op シグネチャが実測され、かつ auto-retry で回避可能 (avoidable) だったか」へ改訂する。gate による正常停止・AC 未充足・CI 恒久失敗などの回避不能なインシデントは解除根拠に数えない旨を明記する
2. 判定の記録規約を定める。`docs/reports/orchestration-recoveries.md` のエントリの `### Diagnosis` に専用行 `- avoidable: <yes|no|unknown> — <one-line reason>` を置く。`run-auto-sub.sh --write-manual-recovery --diagnosis` の自由記述で書けるので、スクリプト変更は要らない
3. #1462 を回避不能な実例として記録し、既存の merge phase エントリ (#1180 / #1181 / #1227 / #1410) を分類例として添える

コード・スクリプト・SKILL.md は変更しない。

## Changed Files

- `modules/orchestration-fallbacks.md`: 4 箇所を編集する (prose のみ。`.sh` ではないため bash 互換の考慮は不要)
  - `## auto-retry-on-fail (code_retry_fire)` > `### Phase Scope Decision`: merge の箇条書き (`- **merge**: ...`) の末尾文 `Deferred until a real merge-phase silent-no-op incident justifies the added design and implementation cost.` を置き換え、解除条件の入れ子箇条書き 3 件を追加する
  - 同節に新規サブセクション `### Avoidability Record` (h3) を追加する。位置は `### Phase Scope Decision` 末尾の Tier 2 段落 (「Tier 2」で始まり `apply-fallback.sh` に言及する段落) の直後、`### Fallback Steps` の直前
  - 同節の `### Rationale` の末尾に 1 項目を追記する (Issue #1475 を判断記録として参照)
  - `## manual-recovery-spec-write` > `### Fallback Steps` の手順 1 の末尾に 1 文を追記する (merge phase の recovery では回避可能性を `--diagnosis` で記録する旨と、`### Avoidability Record` への参照)
- `docs/reports/orchestration-recoveries.md`: ヘッダ部のスキーマ記述だけを編集する (ログエントリは変更しない。先例: #1153 が `notification` を同じ 2 箇所に追加した、コミット `e667602e`)
  - `## Entry Format` の `### Diagnosis` ブロックに、`- notification:` の直後へ `- avoidable:` の任意行を追加する
  - `## Field Definitions` 表に、`notification` 行の直後へ `avoidable` 行を追加する
- [Steering Docs sync candidate] keyword "orchestration-fallbacks.md" skipped: matched 146 files (no discriminating power) (測定: `grep -rl "orchestration-fallbacks.md" docs/ tests/ scripts/ modules/ | wc -l`)
- [Steering Docs sync candidate] keyword "--diagnosis" skipped: matched 11 files (no discriminating power) (測定: `grep -rl -e "--diagnosis" docs/ tests/ scripts/ modules/ | wc -l`)
- [Steering Docs sync candidate] keyword `avoidable` (この Issue が導入する専用行のキー): 3 件 (測定: `grep -rl "avoidable" docs/ tests/ scripts/ modules/`)。`docs/spec/issue-875-abolish-data-layer-md.md`、`docs/spec/issue-1084-verify-patterns-section-heading-coupling.md`、`modules/verify-patterns.md` はいずれも別の語 "unavoidable" の一致で、関係なし (変更不要)
- [Steering Docs sync candidate] keyword `Avoidability Record` (この Issue が導入するサブセクション名): `docs/ tests/ scripts/ modules/` 内の該当は 0 件 (導入前の測定)
- [Listing-side sub-check] 発火しない: subcommand の追加・削除なし、ファイルの追加・削除・改名なし、ディレクトリ構造の変更なし (既存 2 ファイルの編集のみ)
- [Outbound pointer sync candidate] `auto-retry-on-fail` 節が指す `docs/reports/orchestration-recoveries.md` は Changed Files に含めた。同節が指す `modules/phase-state.md` (merge の完了シグネチャ) と `skills/merge/SKILL.md` Step 2 は、今回の変更の影響を受けない

## Implementation Steps

1. `modules/orchestration-fallbacks.md` の `### Phase Scope Decision` の merge 箇条書きを改訂する。末尾文 `Deferred until a real merge-phase silent-no-op incident justifies the added design and implementation cost.` (ファイル内で 1 件のみ) を次の文面に置き換える。箇条書き本体 (`not safely portable as-is` から `a materially different, not-yet-designed mechanism.` まで) は変更しない。入れ子箇条書きは親の `- **merge**:` 行の直下に、2 スペースのインデントで続ける (→ AC1, AC2, AC3)

   ````markdown
   Deferred until a real merge-phase silent-no-op incident that was **avoidable** by auto-retry — a plain re-run of the phase would have succeeded — justifies the added design and implementation cost. The release condition is not the incident count alone (refined by Issue #1475):
     - Counts as release evidence: a merge-phase incident that showed the silent-no-op signature (`claude` exited 0 but `reconcile-phase-state.sh merge --check-completion` returned `matches_expected:false`, i.e. the PR was not `MERGED`) **and** is recorded as `- avoidable: yes` (see "Avoidability Record" below)
     - Does not count: an incident that auto-retry could not have prevented — a gate stopping the phase as designed (e.g. the `/merge` pre-merge AC gate blocking on unchecked acceptance conditions), unmet AC, a persistent CI failure, a merge conflict needing manual resolution, or any other case where a change had to be made before a re-run could succeed. A re-run stops at the same gate again, so counting these would justify building a retry around an irreversible operation on grounds it cannot address. #1462 / PR #1465 is such a case: a measured merge-phase silent no-op that was a gate stop, not a re-runnable failure
     - Does not count either: a PR that was already `MERGED` when the incident was handled (#1410) — the reconciler reports `matches_expected:true`, so there is no signature, and a blind re-run is the second-merge risk described above
   ````

2. (after 1) 同じ節に新規サブセクション `### Avoidability Record` を追加する。見出しは必ず `###` (h3) にする。位置は `### Phase Scope Decision` 末尾の Tier 2 段落の直後、`### Fallback Steps` の直前 (理由は Notes の「section 系 AC の走査範囲」を参照)。本文は次のとおり (→ AC2, AC3, AC4)

   ````markdown
   ### Avoidability Record

   The release condition above is evaluated from `docs/reports/orchestration-recoveries.md`, so each merge-phase incident needs its judgment on record instead of being re-derived from the incident's story. An incident is **avoidable** when a plain re-run of the same phase wrapper — same arguments, with no change to the repository, PR, Issue, or CI state in between — would have completed the phase. For the code and spec phases, that re-run is exactly what this entry's `exec` self-restart performs.

   Record the judgment as a dedicated line in the entry's `### Diagnosis`, in the same style as `- cause:` and `- notification:`:

   ```
   - avoidable: <yes|no|unknown> — <one-line reason>
   ```

   - `yes`: a plain re-run would have succeeded. `no`: it would not have, including the case where a re-run was unnecessary because the phase had already completed. `unknown`: not determinable from the recorded evidence
   - An entry with no `- avoidable:` line is treated as `unknown`. Only `yes` counts as release evidence, so the deferral stays in place until an affirmative judgment is on record. The default is conservative on purpose: a wrong release builds a retry around an irreversible operation, while a wrong hold only delays one
   - No script change is needed: pass the line through `--diagnosis` of `run-auto-sub.sh --write-manual-recovery` (see `#manual-recovery-spec-write`). The value is written verbatim after `- ` and may contain newlines (#1123), so `--diagnosis "avoidable: no — <reason>"` yields the dedicated line, and a value made of a free-text diagnosis, a newline, and `- avoidable: no — <reason>` yields it as a second line. A dedicated flag is deliberately left to a separate Issue
   - The line does not take part in `collect-recovery-candidates.sh` grouping (only `- cause:` does). Whoever evaluates the release condition reads it directly: list the entries whose `### Context` says `phase: merge` and count those that carry `- avoidable: yes` together with the silent-no-op signature

   **Worked example — #1462 / PR #1465 (not avoidable).** `run-merge.sh` logged `claude exited 0 but merge phase did not complete (silent no-op)` (`matches_expected:false`, PR still `OPEN`) and exited 1; Tier 3 returned `action=abort`. The merge gate had stopped the phase as designed: two pre-merge acceptance conditions (AC 3 and 4) were unchecked, and they could not be checked while CI was red from two pre-existing failures that the Issue's own fix had surfaced. The parent session repaired CI, checked the conditions, and re-ran `run-merge.sh` (entry `manual-recovery-ci-fix-and-merge-rerun`). A plain re-run would have stopped at the same gate, so the judgment is `avoidable: no`: the incident matches the signature but is not release evidence.

   **Classification examples** (existing merge-phase entries in `docs/reports/orchestration-recoveries.md`; illustrative, not exhaustive):

   - #1180 / #1181 (`manual-recovery-merge-rerun`, `cause: pre-merge-ac-command-unverifiable`): a `command`-type pre-merge AC was left unexecuted by `/review`'s safe mode, so the pre-merge AC gate blocked until the parent session checked it directly. A re-run reaches the same gate: `no`. Whether the silent-no-op signature appeared was not confirmed
   - #1227 (`merge-tier3-recovery`): a silent hang during the merge wait ended in a watchdog kill (exit 143), and Tier 3 `action=retry` succeeded: `yes`. It is a kill rather than the exit-0 signature, so it is not release evidence by itself
   - #1410 (`manual-recovery-verified-already-complete`): the PR was already `MERGED` when the external kill was handled: `no` (a re-run was unnecessary, and a blind one risks a second merge attempt)
   ````

3. (after 2) 次の 2 点を追記する (→ AC4)
   - 同じ節の `### Rationale` の末尾 (`- Issue #1329 is the decision record for the original code-phase-only scope; ...` の行の直後) に、次の項目を足す。`#N` 形式の Issue 参照を含むこと (`tests/orchestration-fallbacks.bats` の Rationale 検査)

     ````markdown
     - Issue #1475 refined the merge-phase release condition from incident count to avoidability: #1462 / PR #1465 formally met the original count-based wording (#1329), yet it was a gate stopping as designed that auto-retry could not have prevented. Counting it would have justified a retry mechanism for an irreversible operation on grounds the mechanism cannot address — see Phase Scope Decision and Avoidability Record above
     ````

   - `## manual-recovery-spec-write` の `### Fallback Steps` の手順 1 は、文 ``is distinct from omitting the flag entirely, which records as `unspecified` `` (ファイル内で 1 件のみ) で終わる。この直後に、次の文を足す。元の文は末尾にピリオドを持たないので、足す文も先頭のピリオドから始め、末尾にはピリオドを付けない

     ````markdown
     . For a merge-phase recovery, also state whether a plain re-run would have succeeded by passing an `avoidable: <yes|no|unknown> — <reason>` line through `--diagnosis` — the merge auto-retry deferral release condition reads it (see `#auto-retry-on-fail-code_retry_fire`, "Avoidability Record", Issue #1475)
     ````

4. (parallel with 1, 2, 3) `docs/reports/orchestration-recoveries.md` のヘッダ部を編集する。ログエントリ (`<!-- Log entries appear below, newest first. -->` より後) は変更しない (→ AC4)
   - `## Entry Format` の `### Diagnosis` ブロック (コードフェンス内) の `- notification:` 項目 (`participate in frequency grouping)` で終わる) と `- <observed state inspection result and root cause hypothesis>` の間に、次の項目を挿入する

     ````markdown
     - avoidable: <yes|no|unknown> — <one-line reason> (optional; merge-phase entries — whether a
       plain re-run of the phase wrapper would have completed the phase, the evidence for the
       merge auto-retry deferral release condition in
       `modules/orchestration-fallbacks.md#auto-retry-on-fail-code_retry_fire`. Written by hand,
       e.g. via `run-auto-sub.sh --write-manual-recovery --diagnosis`. Absent is treated as
       `unknown`. Does not participate in frequency grouping)
     ````

   - `## Field Definitions` 表の `notification` 行の直後に、次の行を挿入する

     ````markdown
     | `avoidable` | Judgment in `### Diagnosis` of whether a plain re-run of the phase wrapper would have completed the phase (Issue #1475): `yes`/`no`/`unknown`, followed by ` — <one-line reason>`. Intended for merge-phase entries, where only `yes` counts as release evidence for the merge auto-retry deferral (see `modules/orchestration-fallbacks.md#auto-retry-on-fail-code_retry_fire`, "Avoidability Record"). Written by hand — there is no dedicated script flag; pass it through `run-auto-sub.sh --write-manual-recovery --diagnosis`. Absent is treated as `unknown`. Does not participate in `/audit recoveries` frequency grouping — `cause` is the only grouping key |
     ````

5. (after 1, 2, 3, 4) 検証する (→ AC1-AC5 全体)
   - 追記文に書いた識別子が現行コードベースに存在することを grep で再確認する (`/spec` 時点で確認済みだが、main が進んでいる場合に備える): `docs/reports/orchestration-recoveries.md` の `manual-recovery-ci-fix-and-merge-rerun` / `manual-recovery-merge-rerun` / `pre-merge-ac-command-unverifiable` / `merge-tier3-recovery` / `manual-recovery-verified-already-complete`、`scripts/` の `run-merge.sh` / `reconcile-phase-state.sh` / `collect-recovery-candidates.sh`、モジュール内のアンカー `manual-recovery-spec-write` と `auto-retry-on-fail-code_retry_fire`
   - 構造を確認する。必須 5 見出し (`### Symptom` / `### Applicable Phases` / `### Fallback Steps` / `### Escalation` / `### Rationale`) の出現数が変更前と同じ 21 件ずつであること (`grep -c '^### Symptom' modules/orchestration-fallbacks.md` 等)。`### Avoidability Record` が `## auto-retry-on-fail (code_retry_fire)` と次の `## external-kill-parent-respawn` の間にあること。小文字の `avoidable` が当該節にあること (`section_contains` は固定文字列で大文字小文字を区別する)
   - `git diff -- modules/ | python3 scripts/check-language-convention.py` が違反なしで終わること (モジュールへの追記は英語のみ。em dash `—` は CJK 文字ではない)。追記文に二重スペースと全角括弧が入っていないこと
   - `bats tests/orchestration-fallbacks.bats` を実行し、続けて全件 `bats tests/` (AC5) を実行する。全件は 135 ファイル / 2120 テストあるので、明示的な timeout を付けて foreground で実行する。`/spec` 時点の実行環境には `bats` が無かった (`which bats` で確認)。`bats` が使えない環境では、`tests/orchestration-fallbacks.bats` が見る観点 (必須 5 見出しの出現数の一致、`### Entry Retention Criterion` の存在、各 Rationale の `#N` 参照) を grep / awk で同等に確認し、全件実行は CI に委ねたことを記録する

## Verification

### Pre-merge

- <!-- verify: rubric "modules/orchestration-fallbacks.md の Phase Scope Decision における merge phase の deferral 解除条件が、インシデント件数だけでなく『そのインシデントが auto-retry で回避可能だったか』の判定を含む形に改訂されており、gate による正常停止や AC 未充足のような回避不能なインシデントは解除根拠に数えないと明記されている" --> merge phase の deferral 解除条件に回避可能性の判定が含まれている
- <!-- verify: section_contains "modules/orchestration-fallbacks.md" "auto-retry-on-fail" "avoidable" --> 当該節に回避可能性に関する記述が存在する (module は英語記述のため英語表記 `avoidable` で判定)
- <!-- verify: grep "1462" "modules/orchestration-fallbacks.md" --> #1462 の事例が回避不能な実例として記録されている
- <!-- verify: rubric "modules/orchestration-fallbacks.md の auto-retry-on-fail 節が、merge phase の recovery エントリに『auto-retry で回避可能だったか』の判定を記録する場所と書式 (例: ### Diagnosis 内の専用行) を定めている" --> 回避可能性の判定結果を `docs/reports/orchestration-recoveries.md` のエントリへ記録する規約 (記録先と書式) が当該節に定められている
- <!-- verify: command "bats tests/" --> `bats tests/` 全件が PASS する

### Post-merge

- 次に merge phase の silent no-op が発生した際、回避可能性の判定が記録され解除条件の充足判断に使われることを観察する <!-- verify-type: observation event=auto-run session=next -->
  - Expected output structure:
    - `docs/reports/orchestration-recoveries.md` の該当エントリに、当該インシデントが auto-retry で回避可能だったかの判定が記録されていること
    - 回避不能と判定された場合、deferral 解除の根拠には数えられていないこと

## Notes

### 計測値

- recoveries log の merge phase エントリ: 9 件 (スコープ: live file `docs/reports/orchestration-recoveries.md` の `### Context` 内 `phase: merge` 行のみ、1142 行時点。コマンド: `grep -c "phase: merge" docs/reports/orchestration-recoveries.md`)。内訳は #1462 / #1410 / #1273 / #1275 / #1227 / #939 / #1180 / #1181 / #1123
- モジュールの必須 5 見出しの出現数: 各 21 件、`## ` 見出し 26 件 (スコープ: `modules/orchestration-fallbacks.md` のみ。コマンド: `grep -c '^### Symptom' modules/orchestration-fallbacks.md` 等、`grep -c '^## ' modules/orchestration-fallbacks.md`)
- bats スイート: 135 ファイル / 2120 テスト (スコープ: `tests/*.bats` 直下のみ。コマンド: `ls tests/*.bats | wc -l`、`cat tests/*.bats | grep -c "^@test"`)

### 事実確認 (Issue 本文と既存実装の突き合わせ)

- `scripts/run-merge.sh:169-179`: `claude` が exit 0 のあと `reconcile-phase-state.sh merge ... --check-completion` が `matches_expected:false` なら `Warning: claude exited 0 but merge phase did not complete (silent no-op)` を出して `EXIT_CODE=1` にする。`exec` による自己再起動は無い。Issue 本文の「auto-retry せず exit 1」と一致する
- `modules/phase-state.md` の merge 行: 完了シグネチャは `gh pr view --json state == MERGED`。PR が `MERGED` なら `matches_expected:true` になるため、#1410 型 (kill 時点で既に MERGED) は silent no-op シグネチャを持たない
- `docs/product.md` § Terms の "Silent no-op" は「`claude -p` が exit 0 で観測可能な効果を残さず、`matches_expected: false` で検出される」と定義している。この Spec が解除条件に書くシグネチャ (`claude` exit 0 かつ `matches_expected:false`) はその定義と一致する
- Issue 本文は #1462 の真因を「pre-merge AC 未チェック」とし、recoveries エントリは「既存 CI 失敗 2 件を自身の修正が顕在化」と記録している。Issue Retrospective が、AC 3 / 4 (bats 全件 PASS) は CI が緑になるまでチェックできないため連続した因果だと整理済み。モジュールの実例も両方を連鎖として書く
- Issue 本文は /issue で「初のインシデント」を中立表現に直している (#1180 / #1181 に同系統の gate 停止があり、「初」は検証できないため)。モジュールにも「初」とは書かず、「a measured merge-phase silent no-op」と書く
- merge phase のエントリ 9 件のうち、Issue の補足表が扱うのは 4 系統 (#1462 / #1180・#1181 / #1227 / #1410)。#1273 (watchdog kill と PR の競合、親セッションが手動で競合を解消)、#1275 (`wrapper-retry-on-kill` が自動再試行して成功)、#939 (external kill)、#1123 (原因の記載なし) はモジュールの分類例に含めない。Issue の範囲に沿う判断で、モジュール側も「illustrative, not exhaustive」と明記して網羅性を主張しない
- 矛盾検出の結果: Issue 本文の Background の事実主張と既存実装・既存記録に、設計に影響する矛盾は無い

### 設計判断 (非対話モード。light 深度のため Step 7 の曖昧点解決は対象外だが、判断は記録する)

- **キー名は `avoidable`**: 将来、専用フラグ (`--avoidable`) を足す場合に、既存の `--cause` → `- cause:` / `--notification` → `- notification:` と同じ「フラグ名 = 行のキー」に揃う。「何で回避可能か」はモジュールの定義 (plain re-run) で補う。AC2 の検索語 `avoidable` とも一致する
- **値は `yes|no|unknown`、解除根拠に数えるのは `yes` のみ**: #1410 (再実行不要) は `no` に含める。`n/a` を 4 つ目の値にしても集計上は `no` と同じ扱いになるため増やさない
- **記録なし = `unknown` = 数えない (fail-closed)**: 誤った解除は不可逆操作のリトライ機構を作らせる。誤った保留は着手を遅らせるだけ。非対称なので保留側に倒す。スクリプトは変更しないので、ここでの fail-closed は文書上の既定値のこと
- **解除条件は「silent no-op シグネチャ」かつ「avoidable: yes」の 2 条件**: 元の文言 (silent-no-op incident) を保ったまま回避可能性を足した。#1227 は avoidable だが kill (exit 143) でシグネチャが無く、単独では解除根拠にならない
- **配置**: 解除条件の本体は Phase Scope Decision の merge 箇条書きに置く (AC1 が「Phase Scope Decision における」と明記している)。記録規約・実例・分類例は新設の `### Avoidability Record` に置く
- **`manual-recovery-spec-write` に 1 文の導線を足す**: 親セッションが実際に参照する記録手順の SSoT がこの節で、`skills/auto/SKILL.md` の Manual recovery hand-off も `modules/orchestration-fallbacks.md#manual-recovery-spec-write` を指している。導線が無いと、Post-merge の observation AC (次の発生時に判定が記録される) が、規約を知らない親セッションでは満たされない。`skills/auto/SKILL.md` は変更しない (allowed-tools や validator への影響を避け、モジュールを SSoT に保つ)
- **bats テストは追加しない**: ドキュメントのみの変更で、新規の分岐ロジックは無い (新規テストケースの要否: 該当なし)。AC5 は既存の `tests/orchestration-fallbacks.bats` (必須 5 見出しの出現数の一致、各 Rationale の Issue 参照) が壊れていないことの回帰保護

### section 系 AC の走査範囲 (verify-patterns §29)

AC2 の `section_contains "modules/orchestration-fallbacks.md" "auto-retry-on-fail" "avoidable"` は、`## auto-retry-on-fail (code_retry_fire)` (h2。この語を含む見出しはファイル内でこの 1 件のみ) から、次の同レベル以上の見出し `## external-kill-parent-respawn` の直前までを走査する。新設する `### Avoidability Record` は h3 なので走査範囲に入る。`##` で作ると範囲外になり AC2 が評価できなくなるため、見出しレベルは `###` で固定する。`avoidable` は小文字で書くこと (固定文字列の一致で大文字小文字を区別する。`Avoidability` の大文字始まりだけでは一致しない)。AC2 の対象文字列は実装前の時点でファイル内に 0 件 (`grep -ic "avoidable" modules/orchestration-fallbacks.md`)、AC3 の `1462` も 0 件で、どちらもこの実装で初めて現れる。

### bats の構造制約 (`tests/orchestration-fallbacks.bats`)

- 新規の `##` エントリを足さない。必須 5 見出しを持たない `##` エントリが増えると、「5 必須見出しの出現数が一致する」検査が壊れる (#1329 の Spec Notes にも同じ制約がある)。今回追加する `### Avoidability Record` は 5 必須見出しのどれでもないので、出現数に影響しない
- 各エントリの `### Rationale` に `#N` 形式の Issue 参照が必要。今回追記する Rationale 項目は `#1475` / `#1462` / `#1329` を含む

### 同期候補・除外・影響確認

- 除外: `docs/spec/issue-1329-auto-retry-scope-decision.md` は旧文言を引用する過去の Spec (歴史記録) なので変更しない
- `docs/tech.md:138` と `docs/ja/tech.md:129` は `auto-retry-on-fail` 節の Phase Scope Decision を spec phase の Tier 2 の文脈で参照するだけで、merge phase の解除条件には触れない。`sed -n 138p docs/tech.md | grep -o "merge[^.]*"` が 0 件なので変更不要 (確認済み)
- `docs/structure.md:145` のモジュール説明は汎用的な一行で、merge の解除条件に触れない (変更不要、確認済み)
- `scripts/collect-recovery-candidates.sh` が `### Diagnosis` から読むのは `- cause:` 行だけ (`:225` の `grep -qE '^- cause: .+'`)。`- avoidable:` 行はどのパターン (`## <date> UTC:` / `- 起票済み` / `- cause:` / `- N/A`) にも一致せず、集計に影響しない (変更不要、確認済み)
- `tests/` にレポートの実ファイルを読むテストは無い (`grep -rn "orchestration-recoveries" tests/*.bats` の該当は一時ファイル / fixture のみ)。スキーマ記述への追記でテストは壊れない
- `docs/ja/` の同期: `docs/translation-workflow.md` により `docs/reports/` は翻訳対象外、`modules/` は `docs/*.md` ではないため、いずれも `docs/ja/` の同期は不要
- allowed-tools の影響: 追記が触れる `scripts/run-auto-sub.sh` / `scripts/reconcile-phase-state.sh` / `scripts/collect-recovery-candidates.sh` は、いずれも既存の記述の延長で新規のスクリプト呼び出しを導入しない。このモジュールを読む `skills/auto/SKILL.md` / `skills/review/SKILL.md` / `skills/verify/SKILL.md` の `allowed-tools` は変更不要
- 変更しないファイル: `scripts/run-auto-sub.sh` (Out of scope: 専用フラグ化は別 Issue)、`skills/auto/SKILL.md`、`tests/orchestration-fallbacks.bats`

### その他のチェック結果

- fail-safe critical: 該当なし (スクリプト変更なし)
- audit / investigation 型: no。目的は解除条件の改訂と記録規約の策定で、分類例は説明用 (網羅しない)。ただし分類例に書く識別子 (エントリ名・cause slug・スクリプト名) は、予防として存在確認を Implementation Step 5 に入れた。`/spec` 時点では、5 つのエントリ名と `cause: pre-merge-ac-command-unverifiable`、3 つのスクリプトを `docs/reports/orchestration-recoveries.md` と `scripts/` で確認済み
- 外部仕様への依存: なし。必要な事実は、すべてローカルのスクリプト・テスト・ドキュメントの読み取りで確認した (`--diagnosis` の複数行の扱いは `scripts/run-auto-sub.sh:262-295` と `tests/run-auto-sub.bats:1942`)
- Patch route: Size S、`always-pr` 未設定のため patch route。Verification に `github_check "gh pr checks"` は含まれない
- AC と Out of scope の整合: Pre-merge / Post-merge のどの条件も、Issue の Out of scope (merge phase auto-retry の実装、code / spec phase の挙動、`--write-manual-recovery` へのフラグ追加) を要求しない
- Uncertainty: なし

## Consumed Comments

- saito / MEMBER / first-class / ## Issue Retrospective / https://github.com/saitoco/wholework/issues/1475#issuecomment-5965395129

## Code Retrospective

### Deviations from Design
- なし。Spec の Implementation Steps 1-4 のとおりに `modules/orchestration-fallbacks.md` (4 箇所) と `docs/reports/orchestration-recoveries.md` のヘッダ部 (2 箇所) を編集した

### Design Gaps/Ambiguities
- Spec Step 5 の「bats が使えない環境」の分岐に該当した (`which bats` で未検出)。`tests/orchestration-fallbacks.bats` が見る観点 (必須 5 見出しの出現数 21 件ずつ、各 Rationale の `#N` 参照、`### Entry Retention Criterion` の存在) を grep / awk で代替確認し、全件 `bats tests/` (AC5) は実行できなかった。CI に委ねる (Step 10 では UNCERTAIN 扱い、`/verify` で再判定)
- Behavioral Change Detection: 変更 2 ファイルを参照する他テスト (`tests/run-auto-sub.bats` ほか recoveries 系) は、追記した文言や見出しを検査していない (`Deferred until a real merge-phase` 等は tests/ に 0 件)。ヘッダ部のスキーマ記述追加がテストを壊す経路は見つからなかった

### Rework
- なし。新規テストは追加していないため pre-implementation FAIL の確認対象も無い (Confirmed pre-implementation FAIL for 0 new test(s))

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- Spec の文面をそのまま実装した。解除条件は「silent no-op シグネチャ」かつ「`- avoidable: yes`」の 2 条件で、記録なしは `unknown` 扱い (fail-closed)
- スクリプト・SKILL.md・テストは変更せず、`modules/orchestration-fallbacks.md` と `docs/reports/orchestration-recoveries.md` のヘッダ部だけを編集した

### Deferred Items
- 全件 `bats tests/` (AC5) はこの環境に `bats` が無く未実行。構造検査のみ grep / awk で代替確認した。CI または `/verify` で実行する
- `--write-manual-recovery` への専用フラグ追加 (`--avoidable`) は Issue の Out of scope で、別 Issue に残している

### Notes for Next Phase
- `/verify` は AC5 (`command "bats tests/"`) を実際に実行すること。bats が使えない場合は CI の結果で判定する
- Post-merge の observation AC (次の merge phase silent no-op 発生時に `- avoidable:` 行が記録されること) は、発生するまで未判定のまま残る
