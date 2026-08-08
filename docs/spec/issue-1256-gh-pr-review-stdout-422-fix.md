# Issue #1256: gh-pr-review: 自己 PR 422 fallback の判定対象を stdout のレスポンスボディへ修正

## Overview

`scripts/gh-pr-review.sh` の self-review 422 → COMMENT フォールバック (#1102 で導入) を修正する。導入時からリダイレクト順序のバグにより一度も発火しておらず、`/auto` の完全自律実行 (PR 作成者 = reviewer) で MUST 指摘を含むレビュー投稿が構造的に必ず hard-fail する。判定対象を `gh api` 呼び出しの stdout (API レスポンスボディ) を含む捕捉内容へ変更する。

## Reproduction Steps

1. PR 作成者とレビュー実行アカウントが同一 (自己レビュー。`/auto` の完全自律実行では常態) の PR に対し `/review` (または `/auto`) を実行する。
2. レビュー内容に MUST 指摘を1件以上含める → `scripts/gh-pr-review.sh` が `EVENT=REQUEST_CHANGES` を選択する。
3. `gh api repos/$REPO/pulls/$PR_NUMBER/reviews --method POST --input -` が呼ばれ、GitHub は「PR 作成者は自分の PR に REQUEST_CHANGES できない」ため HTTP 422 を返す。
4. 期待動作: 自己 PR 422 を検知し、同一ペイロードを `event: COMMENT` に変更して再 POST する。
5. 実際の動作: フォールバックが発火せず `Error: failed to post review for PR #$PR_NUMBER` で `exit 1`。2026-08-07 の `/review 1252` 実行で直接再現確認済み (Issue 本文 Background 参照)。

## Root Cause

`scripts/gh-pr-review.sh:184` の POST 呼び出しは `API_STDERR=$(... 2>&1 >/dev/null)` という形でレスポンスを捕捉している。bash のリダイレクトは左から右に評価されるため、`2>&1` が stderr を「その時点の stdout」= コマンド置換のキャプチャ先へ複製し、その後の `>/dev/null` は stdout 自体を向け変えるだけで既に複製済みの stderr コピーには影響しない。結果として `API_STDERR` には stderr のみが入り、POST 呼び出しの stdout (実際の API レスポンスボディ) は捨てられる。

GitHub がこのケースで返す判別可能なエラー文言 ("...can not request changes on your own pull request...") は **レスポンスボディ (stdout) 側**にあり、`gh` 自身が stderr に出すのは汎用の `gh: Unprocessable Entity (HTTP 422)` 行のみである。フォールバック条件は `grep -q "422"` (stderr 上にあるためマッチする) **かつ** `grep -qi "request changes on your own pull request"` (stdout と共に捨てられているため永久にマッチしない) の AND 条件のため、フォールバック分岐には到達できない。

このバグは #1102 (本フォールバックの導入 Issue) の時点から一度も機能しないまま存在していた。検出が遅れた一因は `tests/gh-pr-review.bats` の既存回帰テスト (`success: REQUEST_CHANGES 422 self-review error falls back to COMMENT`) のモックが、判別文言を実際の GitHub 挙動と異なり stdout ではなく stderr に直接置いていたこと — この不正確なモックにより、リダイレクトバグを持つ現行コードでもテストが (誤って) パスしていた。本スクリプトにおける 422 系不具合はこれで3件目 (`#945`, `#1102`, 本 Issue)。

## Changed Files

- `scripts/gh-pr-review.sh`: reviews POST 呼び出しの捕捉を `API_STDERR=$(... 2>&1 >/dev/null)` から `API_OUT=$(... 2>&1)` へ変更 (`>/dev/null` を除去し変数名を変更)。直後の2つの `grep` 判定 (422 / 自己レビュー文言) の参照先を `$API_STDERR` から `$API_OUT` へ更新。bash 3.2+ 互換 (新規の bash4 専用構文なし)
- `tests/gh-pr-review.bats`: `success: REQUEST_CHANGES 422 self-review error falls back to COMMENT` テストのモックを修正 — 1回目の `gh api` 呼び出しで、判別文言を含む JSON 相当のボディを stdout に出力し、stderr には汎用の `gh: Unprocessable Entity (HTTP 422)` のみを出力してから `exit 1` する形へ変更 (実際の `gh api` 挙動に合わせる)。新規テスト追加ではなく既存テストの修正 — 現行のモックはリダイレクトバグを再現しない不正確なものだったため

## Implementation Steps

1. `scripts/gh-pr-review.sh` の line comments 分岐内、reviews POST 呼び出し (`if ! API_STDERR=$(echo "$REVIEW_PAYLOAD" | gh api ... --input - 2>&1 >/dev/null); then` の行) から ` >/dev/null` を除去し、`API_STDERR` を `API_OUT` にリネームする (→ acceptance criteria 1, 2)
2. (after 1) 直後の2つの `grep` 判定 (`echo "$API_STDERR" | grep -q "422"` と `echo "$API_STDERR" | grep -qi "request changes on your own pull request"`) の参照先を `$API_OUT` に更新する (→ acceptance criteria 1, 2)
3. (after 2) `scripts/gh-pr-review.sh` 内の他の箇所が `$API_STDERR`/`$API_OUT` を参照していないことを確認する (成功パスおよび line comments なし分岐は元々参照していない) — 追加変更不要であることの確認のみ (→ acceptance criteria 3)
4. (parallel with 1-3) `tests/gh-pr-review.bats` の `success: REQUEST_CHANGES 422 self-review error falls back to COMMENT` テストのモックを修正する: 1回目の `gh api ... reviews ... --input -` 呼び出しで、自己レビュー文言を含む JSON 相当のボディ (例: `{"message":"Review cannot request changes on your own pull request","documentation_url":"..."}`) を stdout に出力し、stderr には `gh: Unprocessable Entity (HTTP 422)` のみを出力して `exit 1`。2回目呼び出し (`$GH_API_STDIN` へ書き込み、`exit 0`) と既存のアサーションは変更しない (→ acceptance criteria 4)
5. `bats tests/gh-pr-review.bats` をローカル実行し、修正した 422 フォールバックケースを含む全ケースが pass することを確認する (→ acceptance criteria 4, 5)

## Verification

### Pre-merge

- <!-- verify: rubric "scripts/gh-pr-review.sh の reviews POST 呼び出しが、stdout を /dev/null へ捨てずにレスポンスボディを変数へ捕捉しており、self-review 422 の判別文言照合がその捕捉内容に対して行われている" --> `scripts/gh-pr-review.sh` の `gh api` 呼び出しが API レスポンスボディ (stdout) を含めて捕捉している
- <!-- verify: rubric "scripts/gh-pr-review.sh の reviews POST 呼び出しに 2>&1 >/dev/null の順序が残っていない" --> `2>&1 >/dev/null` 形式が該当箇所から除去されている
- <!-- verify: rubric "変更後の捕捉変数について、gh api 成功時の挙動が壊れていないことがコード上またはテストで確認できる" --> 成功パスで捕捉変数の内容に依存する箇所がないこと、または依存箇所が新しい捕捉内容に合わせて更新されていることが確認されている
- <!-- verify: command "bats tests/gh-pr-review.bats" --> `tests/gh-pr-review.bats` に、self-review 422 のレスポンスボディを模したケースでフォールバックが COMMENT として発火することを検証するテストが追加されている
- <!-- verify: github_check "gh run list --workflow=test.yml --branch=main --limit=1 --json conclusion --jq '.[0].conclusion'" "success" --> CI (bats テスト) が PR で pass する

### Post-merge

- 次回 `/auto` の `/review` フェーズで MUST 指摘が発生した際、自己 PR でも COMMENT フォールバックが発火しレビューが投稿されることを観察する <!-- verify-type: observation event=auto-run -->

## Notes

- **[Auto-Resolve Log — 非対話モード]** Issue 本文の「対応方針 (案)」は line comments 分岐 (フォールバックが壊れている箇所) のみを対象としている。line comments なし分岐 (review body のみを POST する `else` 分岐、`scripts/gh-pr-review.sh` 末尾) には元々 (#1102 の設計時点から) self-review 422 フォールバックが存在しない。この分岐へのフォールバック拡張は本 Issue のスコープ外と判断した — 理由: 最小リスク (Issue が明示するスコープに一致)、かつこの codebase の実際の `/review` 運用では MUST 指摘は常に line comment を伴うため実害がない。他候補: フォールバックを両分岐に拡張する (不採用— Issue 本文のスコープを超える)。必要であれば follow-up Issue として起票する。
- **[Auto-Resolve Log — 非対話モード]** AC4 (`tests/gh-pr-review.bats` へのテスト追加) は、新規テストを並列追加するのではなく既存の `success: REQUEST_CHANGES 422 self-review error falls back to COMMENT` テストのモックを修正する形で満たすと判断した。理由: 既存テストは AC4 が要求するシナリオそのもの (self-review 422 フォールバックの検証) を既にターゲットにしており、問題はモックが不正確だった点のみ。修正することでカバレッジギャップを直接解消でき、ほぼ同一の近接重複テストを新設せずに済む。他候補: 既存テストはそのままにして新規テストを追加する (不採用 — 不正確なモックのテストが将来にわたり残存し続ける)。
- **bats モック仕様 (実装者向け)**: 修正後の `success: REQUEST_CHANGES 422 self-review error falls back to COMMENT` テストで、1回目の `gh api` 呼び出しのモック応答は「stdout に自己レビュー判別文言を含む JSON 相当のボディ」「stderr に `gh: Unprocessable Entity (HTTP 422)` の汎用行のみ」「`exit 1`」の3点を満たすこと。既存の `api_call_count` カウンタ機構・2回目呼び出し (成功、`$GH_API_STDIN` 書き込み) はそのまま維持する。
- 外部仕様確認 (`skills/spec/external-spec.md` 該当): `gh --version` (2.96.0) 上で `gh api --help` を確認したが、4xx 応答時の stdout/stderr 分離に関する明文化された記述は見つからなかった。Issue 本文が記す「2026-08-07 の `/review 1252` 実行での実測確認」を本挙動の一次情報として採用した。
- 関連する既存 Spec: `docs/spec/issue-1102-gh-pr-review-422-fallback.md` (本フォールバックの元設計。提案diff自体に同じバグが含まれていた)、`docs/spec/issue-1236-opportunistic-verify-events.md` (本不具合が最初に言及された箇所。当時は Issue スコープ外として未修正のまま記録された)
- Steering Docs sync candidate 確認: `docs/structure.md` の `scripts/gh-pr-review.sh` — post PR reviews という記述はスクリプトの目的を変えないため更新不要。`docs/migration-notes.md` の `gh-pr-review.sh` セクションは private→public 移行時の英語化記録であり本変更とは無関係のため更新不要。他に `scripts/gh-pr-review.sh` を参照する docs/tests/scripts ファイルは `tests/gh-pr-review.bats` のみ (Changed Files に含む)。

## Consumed Comments

No new comments since last phase.

- saito / MEMBER / first-class / ## Acceptance Test Results / https://github.com/saitoco/wholework/issues/1256#issuecomment-5226562801
- saito / MEMBER / first-class / <!-- wholework-event: type=observation-trigger phase=observation-trigger issue=1 / https://github.com/saitoco/wholework/issues/1256#issuecomment-5226962836
- saito / MEMBER / first-class / ## Post-merge observation の証拠を観測しました (PR #1291) / https://github.com/saitoco/wholework/issues/1256#issuecomment-5227663647
## Code Retrospective

### Deviations from Design
- N/A — Implementation Steps 1-5 were followed as written; no reordering, omission, or approach change.

### Design Gaps/Ambiguities
- Issue Pre-merge AC #5 used `github_check "gh pr checks" "Run bats tests"`, which is incompatible with patch route (no PR exists on this route). Auto-fixed to the canonical `github_check "gh run list --workflow=test.yml --branch=main --limit=1 --json conclusion --jq '.[0].conclusion'" "success"` form per `modules/verify-classifier.md` § "Patch Route CI Verification Note", and synced to both the Issue body and this Spec's Verification section. This gap was not called out in the Spec's own Notes section — worth flagging in future Spec review for patch-route Issues that the CI AC form should be pre-validated against route.

### Rework
- N/A — no rework occurred.

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- Renamed `API_STDERR` to `API_OUT` and removed `>/dev/null` so the reviews POST call captures combined stdout+stderr; both discriminator `grep` checks (422 code, self-review message) now match against this capture.
- Fixed the existing `success: REQUEST_CHANGES 422 self-review error falls back to COMMENT` bats test's mock rather than adding a new test — the existing test already targeted this exact scenario, and its mock was the inaccurate part (it put the discriminator text on stderr; real `gh api` puts it in the stdout response body).
- Left the no-line-comments (`else`) branch of `gh-pr-review.sh` without a self-review 422 fallback, per Spec Notes — out of scope for this Issue.

### Deferred Items
- Post-merge observation AC (next `/auto` `/review` run with a MUST finding on a self-authored PR should show the COMMENT fallback actually firing) — cannot be verified pre-merge.
- None else.

### Notes for Next Phase
- All 4 pre-merge rubric/command AC are checked `[x]`; the CI AC (`github_check "gh run list" ...`) is intentionally left `[ ]` — patch route has no PR-scoped run yet at code-phase time, `/verify` evaluates it post-merge.
- `/verify` should confirm the `gh run list --workflow=test.yml --branch=main --limit=1` run picked up by this Issue's push (implementation + retrospective commits) actually reflects `Run bats tests` success, not an unrelated concurrent session's run — see the Residual risk note in `modules/verify-classifier.md` § Patch Route CI Verification Note.

## Verify Retrospective

### Phase-by-Phase Review

#### issue

- Issue 本文が根本原因 (リダイレクト評価順序)・修正方針・AC を具体的に記述しており、`/issue` は本文変更不要と判断した。以降のフェーズで要件の解釈揺れは発生しておらず、この判断は妥当だった
- 一方 Pre-merge AC #5 の `github_check` は `gh pr checks` 形式で書かれていた。`/issue` 実行時点の Size は M (pr route) のためこの形式は正しく、Step 15 の AC 監査 (Pattern 4: patch route × `gh pr checks`) も問題なしと判定している。非互換になったのは後続フェーズでの Size 降格の結果であり、`/issue` 時点の判定に誤りはない

#### spec

- Changed Files 2 件・root cause 明確な bug fix と判定し Size を M → XS へ降格 (Projects Size フィールドの read-back 確認済み)。pr route を通していれば review→merge の 2 フェーズが冗長だったため、この降格自体は妥当
- 降格が AC #5 の route 依存性に波及する点は Spec の Notes に記録されなかった。結果として検出は `/code` フェーズまでずれ込んでいる

#### code

- Implementation Steps 1-5 を逸脱なく実行、rework ゼロ
- AC #5 の patch route 非互換を検出し、`modules/verify-classifier.md` § "Patch Route CI Verification Note" の正準形へ自動修正のうえ Issue 本文と Spec の双方へ同期した。フェーズ間の補償が実際に機能した事例
- 既存の `success: REQUEST_CHANGES 422 self-review error falls back to COMMENT` テストのモックが判別文言を stderr 側に置く不正確な作りだったことを発見し、新規テストを並列追加せず既存テストの修正で AC4 を満たした。このモックの不正確さは #1102 の修正が「テスト緑のまま一度も発火しない」状態で main に残存した直接の原因でもあり、症状ではなく原因側を潰している

#### review

- patch route のため `/review` フェーズは実行されていない

#### merge

- patch route の直コミット。コンフリクト・CI 失敗なし

#### verify

- Pre-merge 4 件は `/code` フェーズで既に `[x]`、CI の 1 件のみを実測して PASS。CI run (`31261875018`) の headSha は `b5a2ca18` で本 Issue 自身の commit であり、Phase Handoff が求めた「無関係な並行セッションの run を拾っていないこと」の確認要件を満たしている
- 本 Issue は自己 PR への `REQUEST_CHANGES` 422 フォールバックを修正するものだが、patch route で着地したため修正コードは本 Issue 自身の workflow では一度も実行されていない。実発火の確認は post-merge の observation 条件 (`event=auto-run`) に依存する。#1102 が「修正が一度も発火しないまま close された」経緯を踏まえると、この observation が評価されるまでは同じ失敗形が再現していないと断言できない

### Improvement Proposals

### Addendum: post-merge observation の判定 (re-verify, session `23043-1786197225`)

初回 verify 時点では `auto-run` 未発火のため SKIPPED としていた post-merge 条件を、同一セッションの `/auto --batch` 完走後に再評価して **PASS** と判定した。

条件が求めた「自己 PR で MUST 指摘が発生した際の COMMENT フォールバック発火」は、同一 batch の **#1257 / PR #1291** で成立した。証拠: review body 先頭に `scripts/gh-pr-review.sh` のフォールバック分岐が生成する固有の注記 (`Note: posted as COMMENT instead of REQUEST_CHANGES — ...`) が付与され、`MUST: 1` かつ author/reviewer とも同一アカウント、review state は `COMMENTED`、review→merge が hard-fail せず完走している。

修正前は判別文言がレスポンスボディ (stdout) 側にあり `2>&1 >/dev/null` で捨てられていたため、この注記が付くこと自体がありえなかった。フォールバックの発火が、`API_OUT=$(... 2>&1)` への変更が stdout を捕捉していることの直接の証拠になる。

本セッションの先行 2 件は条件を満たさなかった — #1266 は patch route で `/review` が実行されず、#1279 (PR #1286) は MUST 0 件で `REQUEST_CHANGES` が試行されなかった。#1102 が「修正が一度も発火しないまま close された」経緯を踏まえると、本 Issue は**実発火まで確認したうえで close された**点で先行事例と異なる。

全受入条件がチェック済みとなり `phase/done` へ遷移した。

- **route 依存の verify command が Size 再評価で非互換になりうる (Tier 2 — 記録のみ)**: `github_check "gh pr checks"` と `gh run list` の使い分けは route に依存するが、AC 監査は `/issue` Step 15 で、route を決める Size 再評価は `/spec` で行われる。今回は `/spec` が M → XS へ降格した結果 AC #5 が非互換になり、`/code` が検出・自動修正した。`modules/verify-classifier.md` の正準形記述という補償が効いており実害ゼロだったため単独起票は見送る。Size 降格由来の AC 非互換が `/code` の自動修正を素通りする、あるいは `/code` を経ない経路で顕在化した場合は Tier 1 へ引き上げる
