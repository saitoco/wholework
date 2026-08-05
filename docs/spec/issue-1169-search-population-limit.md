# Issue #1169: opportunistic-search: observation AC 検索の母集団が --limit 50 で無言に切り捨てられる状態を解消

## Overview

`scripts/opportunistic-search.sh` の母集団取得 (`gh issue list --label "phase/verify" --state closed --json number --limit 50`) が固定 `--limit 50` かつページネーションなしのため、`phase/verify` ラベル付き closed Issue の総数 (実測 316 件、2026-08-05) がこれを超えると、古い Issue が無言で検索対象から脱落する。#843 / #841 / #839 はこの窓の外に落ちており、未解決の `verify-type: observation` AC を持つにもかかわらず恒久的に発火しない。

本 Issue では、`gh issue list` の `--search` フラグ (本文テキスト検索。`--label`/`--state` と AND 結合できることを実測で確認済み) を用いてモード別 (`verify-type: observation` / `verify-type: opportunistic`) に母集団を事前絞り込みし (実測: 316 件 → 54 件 / 132 件)、あわせて `POPULATION_LIMIT` を 50 から 300 に引き上げ、取得件数が上限に達した場合は stderr に警告を出す。Issue 本文が提示する 4 案のうち「案 2 (事前絞り込み) + 案 3 (切り捨ての可視化)」の組み合わせを採用する (判断根拠は Notes 参照)。

## Reproduction Steps

1. `phase/verify` ラベル付き closed Issue が 50 件を超えているリポジトリで `scripts/opportunistic-search.sh --event auto-run` (または任意の skill 名) を実行する
2. `gh issue list --label "phase/verify" --state closed --json number --limit 50` (`scripts/opportunistic-search.sh:180`) が直近 50 件のみを返し、それより古い Issue 番号は `ISSUE_NUMBERS` に一切含まれない
3. 母集団から外れた Issue が未解決の `verify-type: observation` / `verify-type: opportunistic` AC を持っていても、その Issue に対して `gh issue view` が呼ばれることは二度とないため恒久的にマッチしない。エラーも警告も出力されないため、出力される JSON 配列だけを見て取りこぼしに気づくことはできない
4. 実測 (2026-08-05): `--limit 50` の母集団の最古は #861。一方で `phase/verify` かつ closed の総数は 316 件あり、#843 / #841 / #839 はこの母集団の外に落ちている

## Root Cause

`scripts/opportunistic-search.sh:180` の母集団取得が固定 `--limit 50` かつページネーションなしで実装されているため、`phase/verify` ラベル付き closed Issue の総数が 50 件を超えると、更新日時順で古い Issue から無言で検索対象外になる。母集団の定義自体 (「`phase/verify` ラベル + closed」) は妥当だが、取得件数を絞る手段が単純な `--limit` のみで、(a) 母集団を意味的に絞り込む事前フィルタ、(b) 取りこぼしの可視化、のいずれも欠けている。

`gh issue list` は `--search` フラグで本文テキスト検索を `--label` / `--state` と AND 結合できる (実測: 絞り込みなし 316 件 → `--search "verify-type: observation in:body"` 追加で 54 件、`--search "verify-type: opportunistic in:body"` 追加で 132 件。いずれも #843/#841/#839 を含む)。GitHub Search はトークン単位の一致であり厳密な部分文字列一致ではないため取りこぼし (false negative) のリスクはなく、事前フィルタとして安全に使える — 最終的な厳密一致はループ内の既存 `grep "verify-type: ..."` が引き続き担う。これを使って母集団を事前に絞り込むことで、取りこぼしの解消と `gh issue view` 呼び出し回数の削減 (316 回 → 54〜132 回) を両立できる。

## Changed Files

- `scripts/opportunistic-search.sh`: 母集団取得 (`# 1. Fetch closed Issues with phase/verify label` 直下、L179-181) をモード別 `--search` テキスト絞り込み + `POPULATION_LIMIT=300` 定数 + limit 到達時の stderr 警告に置き換える — bash 3.2+ 互換 (`mapfile` 等は使わない)
- `tests/opportunistic-search.bats`: `setup()` の `gh` モックに呼び出し引数キャプチャ (`export MOCK_DIR` を追加し、`issue list` 分岐で `$MOCK_DIR/gh-list-args.txt` に書き出す) を追加。新規 `@test` を 3 件追加 (limit 到達時の stderr 警告、event モードの `--search` テキスト検証、skill モードの `--search` テキスト検証)
- `docs/structure.md` (L202-203) / `docs/ja/structure.md` (L194-195): [Steering Docs sync candidate] `opportunistic-search.sh` の 1 行説明を確認済み。CLI インターフェース (引数・出力形式) は変更しないため変更不要と判断
- `docs/migration-notes.md` (L486) / `docs/ja/migration-notes.md`: [Steering Docs sync candidate] `opportunistic-search.sh` 項は英語化移行時の履歴記録 (`Interface changes: None` は当時の移行内容についての記述) であり、本 Issue のスコープ外。変更不要と判断 (grep で内容確認済み)

## Implementation Steps

1. `scripts/opportunistic-search.sh` の母集団取得部分 (`# 1. Fetch closed Issues with phase/verify label` 直下) を書き換える。`POPULATION_LIMIT=300` を定義し、unknown event fallback 適用後の最終的な `EVENT_NAME` の有無に応じて `SEARCH_TEXT` を `"verify-type: observation in:body"` (event モード) / `"verify-type: opportunistic in:body"` (skill モード) に設定、`ISSUES_JSON=$(gh issue list --label "phase/verify" --state closed --search "$SEARCH_TEXT" --json number --limit "$POPULATION_LIMIT")` に置き換える。取得件数 (`jq 'length'`) が `POPULATION_LIMIT` 以上の場合は stderr に "Warning: population fetch reached --limit ${POPULATION_LIMIT}; results may be truncated. Consider raising POPULATION_LIMIT in scripts/opportunistic-search.sh or narrowing the --search filter." を出力する (→ 受け入れ条件 1, 2)
2. `tests/opportunistic-search.bats` の `setup()` に `export MOCK_DIR` を追加し、`gh` モックの `issue list` 分岐の先頭に `printf '%s\n' "$@" >> "$MOCK_DIR/gh-list-args.txt"` を追加して呼び出し引数をキャプチャできるようにする (→ 受け入れ条件 3 の前提)
3. (2 の後) `tests/opportunistic-search.bats` に、`MOCK_ISSUE_LIST` を `POPULATION_LIMIT` と同数 (300件、`jq -n '[range(1;301) | {number: .}]'` で生成) にしたケースで stderr に limit 到達の警告が出力されることを検証する `@test` を追加する (→ 受け入れ条件 3)
4. (2 の後、3 と並行可) `tests/opportunistic-search.bats` に、`--event auto-run` 実行時は `$MOCK_DIR/gh-list-args.txt` に `verify-type: observation in:body` が、skill 名実行時 (例: `/issue`) は `verify-type: opportunistic in:body` が記録されることを検証する `@test` を 2 件追加する (→ 受け入れ条件 2)
5. (1, 3, 4 の後) `bats tests/opportunistic-search.bats` をローカル実行し、既存テストを含む全件が PASS することを確認する (→ 受け入れ条件 4)

## Verification

### Pre-merge

- <!-- verify: rubric "scripts/opportunistic-search.sh の observation AC 検索において、母集団が固定 --limit 50 で無言に切り捨てられる状態が解消されている。全件取得・事前絞り込み・切り捨ての警告出力のいずれの方式でもよいが、採用方式と他案を採らなかった判断根拠が記録されている" --> 母集団の無言切り捨てが解消され、方式選定の根拠が記録されている
- <!-- verify: rubric "母集団の窓から外れていた #843 / #841 / #839 が、変更後の検索で observation AC のマッチ対象に含まれるようになることが、実装またはテストから確認できる" --> 窓外に落ちていた Issue が再びマッチ対象になる
- <!-- verify: rubric "tests/opportunistic-search.bats に、母集団が limit を超える場合の挙動 (全件取得されるか、または警告が出力されるか) を検証するテストが追加されている" --> 母集団超過時の挙動を検証するテストが存在する
- <!-- verify: command "bats tests/opportunistic-search.bats" --> `tests/opportunistic-search.bats` が PASS する
- <!-- verify: github_check "gh pr checks" "Run bats tests" --> bats テスト全件が CI で PASS する (pr route)

### Post-merge

- 変更後に `scripts/opportunistic-search.sh --event auto-run` を実行し、マッチ件数が変更前の 12 件から増加している (または母集団超過の警告が出力される) ことを確認する

## Notes

### 対応方針の採用根拠 (非対話モードでの自動解決)

Issue 本文は 4 案を提示し「案 2 + 3 の組み合わせが有力」としていた。codebase investigation で以下を実測し、案 2+3 を採用した:

- 現在の母集団 (`--label phase/verify --state closed`、絞り込みなし): 316 件
- `--search "verify-type: observation in:body"` を追加した場合: 54 件 (#843 / #841 / #839 を含む)
- `--search "verify-type: opportunistic in:body"` を追加した場合: 132 件
- `--search` は `--label` / `--state` と AND 結合される (実測で確認: label+state のみ 316 件 → label+state+text で真部分集合の 54/132 件になる。text のみ・state+text のみで試した中間結果も、label を外すと単調に増加し、AND 結合と矛盾しない)

**不採用とした案:**
- **案 1 (`--limit` 撤廃・全件取得)**: 母集団 316 件を毎回全走査することになり、Issue 本文が懸念する「`gh issue view` の呼び出しが線形に増える」問題をむしろ悪化させる。案 2 で母集団を 54〜132 件に絞ればこの懸念自体が解消するため、全件取得は不要と判断した
- **案 4 (retire との接続)**: `/audit stats --retention` の escalation 経路との統合は、本 Issue が報告する「無言切り捨て」自体の解決には必須ではなく、「どの observation AC を retire すべきか」という別軸の判断を伴うスコープの大きい改善である。本 Issue のスコープ外とする

`POPULATION_LIMIT=300` は実測した現在の最大母集団 (132 件、opportunistic モード) の約 2.3 倍の余裕を持たせた値。将来この値に到達した場合は stderr 警告が出力され (案 3)、無言での取りこぼしには戻らない。

### 残存する制約

GitHub Search API は検索結果を最大 1000 件までしか返さない既知の制約がある。現在の絞り込み後母集団 (54〜132 件) はこの上限から十分離れているため今回のスコープでは対応不要だが、将来 `POPULATION_LIMIT` を 1000 に近づける必要が生じた場合は別途検討が必要。

## Consumed Comments

No new comments since last phase.

## Code Retrospective

### Deviations from Design
- N/A — implementation followed the Spec's Implementation Steps as written.

### Design Gaps/Ambiguities
- `rubric` verify commands are graded from Issue body + git diff only, not the Spec (Issue=WHAT/Spec=HOW separation per `docs/tech.md`). AC1 requires the rejected-alternatives rationale to be "記録されている" (recorded), but this Issue's Notes section — where that rationale actually lives — is invisible to the grader. Addressed by duplicating the rationale (adopted approach + both rejected alternatives) into a code comment directly above `POPULATION_LIMIT` in `scripts/opportunistic-search.sh`, so it appears in the git diff the grader reads. Future Issues with a rubric AC that references "judged/recorded rationale" should place that rationale where the grader's input scope (Issue body / git diff / rubric-named files) can actually see it, not only in Spec Notes.

### Rework
- N/A — no rework occurred.

## Phase Handoff
<!-- phase: merge -->

### Key Decisions
- Merged PR #1182 (squash) into `main` with no conflicts (mergeable=true, reason=clean; CI 9/9 SUCCESS, review approved) — no rebase/conflict resolution was needed.
- Pre-merge AC gate re-checked at merge time: all 5 Pre-merge AC on Issue #1169 already `[x]`, so the gate passed without requiring an override.

### Deferred Items
- Post-merge AC: re-run `scripts/opportunistic-search.sh --event auto-run` after merge and confirm the match count increased from the pre-change baseline of 12 (or that the limit-reached warning fires) — `verify-type: manual`, left for `/verify`.
- GitHub Search API's 1000-result cap (noted in Spec "残存する制約") is not a concern at the current filtered population size (54–132) but would need reconsideration if `POPULATION_LIMIT` is ever raised toward 1000.

### Notes for Next Phase
- Issue #1169 will auto-close on merge (`closes #1169`, base branch is `main`); label transition to `phase/verify` follows in Step 5.
- `/verify` should focus on the single remaining Post-merge AC item above.

## review retrospective

### Spec vs. implementation divergence patterns
Nothing to note — review-light confirmed the implementation matches the Spec's Implementation Steps 1-5 exactly (mode-scoped `SEARCH_TEXT`, `POPULATION_LIMIT=300`, stderr warning wording, bats test additions).

### Recurring issues
Nothing to note — review-light found no issues across all 4 perspectives (spec deviation, edge cases, security, documentation consistency), and Step 8 static AC verification found no FAIL among the 5 Pre-merge conditions.

### Acceptance criteria verification difficulty
Nothing to note, but worth recording why: AC1's `rubric` grader reads only the Issue body and git diff, not the Spec (Issue=WHAT / Spec=HOW separation), so a rationale recorded only in Spec Notes would have been invisible to the grader. The `/code` phase pre-empted this by duplicating the rejected-alternatives rationale into a code comment directly above `POPULATION_LIMIT` in `scripts/opportunistic-search.sh` (see Code Retrospective above), so the rationale appeared in the diff the grader reads and all 3 rubric AC passed cleanly with no UNCERTAIN. This pattern — duplicating Spec-only rationale into diff-visible code comments when a rubric AC references "recorded rationale" — worked as designed here and required no follow-up from `/review`.

## Verify Retrospective

### Phase-by-Phase Review

#### issue
- AC 設計は良好。特に条件 2 が「#843 / #841 / #839 が再びマッチ対象になる」と**具体的な Issue 番号**で書かれていたため、実測で一意に判定できた。抽象的な「母集団が広がる」ではなく検証可能な形になっていた

#### spec
- N/A — spec 側の記述と実装に乖離なし

#### code
- rubric grader が Spec を読まない (Issue=WHAT / Spec=HOW 分離) 点を先回りし、rejected-alternatives の根拠をコード コメントに複製した判断が有効に働いた件は review retrospective に記録済み

#### review
- N/A — 指摘なし

#### merge
- N/A

#### verify
- **母集団の盲点は想定より大きかった**。AC が名指ししていたのは 3 件 (#843 / #841 / #839) だが、実測ではマッチが 12 件 → **25 件**に増え、旧カットオフ (#861) より下から **#667 / #626 / #624 / #590 / #589 / #562 / #514 の 7 件**も新たに浮上した。合計 10 件が「未チェックの observation AC を持ちながら恒久的に発火しない」状態だったことになる
- **二次的な影響 — dispatch 母集団が増える**: 新たに浮上した 7 件は古い Issue で、その observation AC には `when=` 注釈が付いていない (#1172 が「既存 AC の一括付与はスコープ外」としたため)。したがって実行文脈に関係なく無条件マッチし、L3 の observation dispatch 対象に入る。#1118 / #1172 が減らそうとしていた「観察不能な AC への無駄 dispatch」を、母集団拡大が押し戻す方向に働く。[この相互作用は #1163〜#1167 (滞留 manual/observation AC の再型付け) と #1162 (セッション内 verify 済みの除外) が扱う領域であり、新規起票は不要]
- **worktree からの実行で `when=` ゲートが fail-open する**現象を再び確認 (#1170 / #1171 / #1172 に続き 4 回目)。本 verify では「12 件」のベースラインもゲート実装前の測定なので、条件が揃っており比較としては妥当だった。ただし測定条件を明示しないと誤読を招くため、Issue コメントに注記を入れた
- **Arm 4a (外部 kill 調査) の並行条件下での実行**: 本 Issue は別セッションの `/auto --batch 1179 1181 1180` と並行して処理された。wrapper (`run-auto-sub.sh 1169`, 稼働約 46 分) は `Exit code: 0` トレーラ付きで正常終了し、**external kill は発生しなかった**

### Improvement Proposals
- N/A — 上記の観察はいずれも既存 Issue (#1163〜#1167 / #1162 / #1141) が追跡済み。Arm 4a の観測結果は `docs/reports/external-kill-investigation.md` と #1146 に集約する
