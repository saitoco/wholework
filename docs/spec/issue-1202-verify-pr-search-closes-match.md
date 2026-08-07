# Issue #1202: verify: Step 2 の PR 検索結果を closes 突き合わせで検証し無関係な PR の採用を防ぐ

## Overview

`skills/verify/SKILL.md` Step 2 は Issue に紐づく merged PR を `gh pr list --search "closes #$ISSUE_NUMBER" --state merged --json number --jq ".[0].number"` で検索し、その先頭 1 件を無条件に `PR_NUMBER` として採用している。`gh pr list --search` は GitHub の全文検索であり、検索語 `closes #N` は「その PR が Issue #N を closes する」ことを保証しない。実測 (2026-08-06、#1197) では、PR を持たない patch 経路の Issue に対して無関係な PR #1018 (実際は `closes #1015`) が検索結果の先頭に返った。

`PR_NUMBER` が誤って非空になると、Step 5 の patch route detection (`PR_NUMBER` が空であることを判定条件にする) が働かず、`github_check "gh pr checks"` 型 AC が無関係な PR のチェック結果を参照して PASS/FAIL 判定されうる。

本 Issue は、検索結果を採用する前に `scripts/gh-extract-issue-from-pr.sh` が返す `issue_number` (PR body/title から `closes #N` を抽出済み) と `$ISSUE_NUMBER` を突き合わせ、一致する PR のみを `PR_NUMBER` として採用するよう Step 2 を修正する。

## Reproduction Steps

1. Patch 経路の Issue (自身の merged PR を持たない。例: #1197) を用意する。
2. `gh pr list --search "closes #1197" --state merged --json number --jq ".[0].number"` を実行する → `1018` が返る。
3. `gh pr view 1018 --json body -q '.body' | grep -ioE "closes #[0-9]+"` を実行する → `closes #1015` が返り、PR #1018 は #1197 を closes していないことが確認できる。
4. 現状の Step 2 は `.jq ".[0].number"` の結果をそのまま `PR_NUMBER` に採用するため、この誤マッチがそのまま `BASE_BRANCH` 解決と Step 5 の patch route detection に伝播する。

## Root Cause

`gh pr list --search` は GitHub の全文検索 API であり、`closes #N` という検索語は関連度スコアに基づく通常のテキスト検索として扱われる — 「PR body に文字列 `closes #N` が含まれる」ことを保証する構造化フィルタではない。そのため、無関係な PR が検索結果の先頭に来ることがある。

`scripts/gh-extract-issue-from-pr.sh` は既に PR body/title から `closes #N` 相当のパターンを正規表現で抽出し `issue_number` として返す実装を持つ (L51-71)。しかし Step 2 は現状この戻り値のうち `base_ref` フィールドしか読んでおらず (L99)、`issue_number` による突き合わせを一切行っていないため、検索結果の誤マッチがそのまま `PR_NUMBER` に採用される。

## Changed Files

- `skills/verify/SKILL.md`: Step 2 の merged PR 検索ブロック (L89-102 付近) を、候補 PR を複数取得し `issue_number` で突き合わせてから採用する形に置き換える — bash 3.2+ 互換 (配列/mapfile 不使用、単純な `for` ループ)

## Implementation Steps

1. `skills/verify/SKILL.md` Step 2 の `PR_NUMBER=$(gh pr list --search "closes #$ISSUE_NUMBER" --state merged --json number --jq ".[0].number")` を、先頭 1 件のみでなく候補を複数 (最大 10 件) 取得する形に置き換える: `CANDIDATE_PRS=$(gh pr list --search "closes #$ISSUE_NUMBER" --state merged --json number --jq '.[].number' | head -10)` (→ 受入条件 A)
2. (after 1) 取得した候補を順に `${CLAUDE_PLUGIN_ROOT}/scripts/gh-extract-issue-from-pr.sh` に渡し、返り値の `issue_number` が `$ISSUE_NUMBER` と一致する最初の候補を `PR_NUMBER`/`BASE_BRANCH` として採用するループを追加する。一致する候補がなければ (候補が 0 件の場合を含む) `PR_NUMBER` は空のまま — 「Default to `BASE_BRANCH=main` if no PR is found or base branch cannot be fetched.」の記述はこの空文字ケースをそのまま説明として維持する (→ 受入条件 A, B, C)

## Verification

### Pre-merge

- <!-- verify: rubric "skills/verify/SKILL.md Step 2 が、gh pr list --search の結果をそのまま採用せず、その PR が当該 Issue を実際に closes しているかを突き合わせてから PR_NUMBER に採用する手順になっている。一致しない場合は PR_NUMBER を空 (patch 経路) として扱うことが記述されている" --> Step 2 が PR の突き合わせを行う
- <!-- verify: section_contains "skills/verify/SKILL.md" "Step 2" "issue_number" --> Step 2 の記述に `issue_number` による突き合わせが含まれる
- <!-- verify: rubric "patch 経路の Issue (PR を持たない) に対して無関係な PR がマッチした場合に PR_NUMBER が空として扱われる negative case が、実装またはテストで確認できる" --> 誤マッチ時に patch 経路として扱われる

### Post-merge

- patch 経路の Issue で `/verify` を実行し、Step 2 が無関係な PR を採用しないことを観察する <!-- verify-type: observation event=auto-run session=next -->
  - 期待される出力構造:
    - PR を持たない Issue で `BASE_BRANCH` が `main` に解決される
    - `github_check "gh pr checks"` 型 AC を持つ patch 経路 Issue が UNCERTAIN 化される (Step 5 の patch route detection が働く)

## Consumed Comments

- saito (MEMBER, first-class) — `/issue` フェーズの Issue Retrospective。「本 Issue のスコープは merged PR 検索 (L92, `--state merged`) に限定し、同じ Step 2 内の OPEN PR 検索 (L107, `--state open`) は対象外」という判断を明記。本 Spec もこの境界を踏襲し、OPEN PR 検索ブロックには一切変更を加えない。https://github.com/saitoco/wholework/issues/1202#issuecomment-5210412336

- saito / MEMBER / first-class / ## Acceptance Test Results / https://github.com/saitoco/wholework/issues/1202#issuecomment-5210985885
## Notes

- **設計判断 (候補を複数取得する方式を採用)**: Issue 本文の対応方針 (案) は「検索結果を候補として扱う」と複数形で記述している。先頭 1 件のみを検証し不一致なら即 patch 経路とする設計も検討したが、GitHub 検索の関連度順で正しい PR が先頭に来ない場合に false negative (実際は PR 経路の Issue を patch 経路と誤判定) を生みうるため不採用。最大 10 件という上限は、本リポジトリに `gh pr list --limit` を使う既存慣行がなく、`head -N` で件数を絞る既存パターン (`skills/auto/SKILL.md` の類似箇所参照) に倣った控えめな値。
- **スコープ境界の再確認**: 直前の `/issue` フェーズの Issue Retrospective (Consumed Comments 参照) で、同じ Step 2 内の OPEN PR 検索 (`--state open`, L107) は本 Issue のスコープ外と既に判断済み。本 Spec もこれを踏襲する。
- **既存コードの `$ISSUE_NUMBER` 変数命名について (スコープ外の観察)**: Step 2 の該当ブロック (L92, L107, L114) は `$NUMBER` ではなく `$ISSUE_NUMBER` を参照しているが、このスキル内で `ISSUE_NUMBER` が実際に bash 変数として代入されている箇所はなく (他の出現箇所はすべて `l0-surfaces.md` 等へのパラメータ名としての記述)、本 Issue 導入前から存在する状態。本 Issue のスコープ (closes 突き合わせ) とは独立した観察のため変更せず、新規コードも既存ブロックの命名慣行 (`$ISSUE_NUMBER`) に合わせる。
- **Step 6 external spec check**: `gh pr list --search` の全文検索としての挙動は Issue 本文に実測 (2026-08-06, #1197) が既に記載されているため、追加の公式ドキュメント参照 (`skills/spec/external-spec.md` の手順) は行わなかった。`gh-extract-issue-from-pr.sh` の `issue_number` 抽出ロジックはコードベース調査で直接確認済み (該当スクリプト L51-71)。
- **Steering Docs sync candidate check**: `gh-extract-issue-from-pr.sh` / `closes #N` を参照する `docs/structure.md`, `docs/ja/structure.md`, `modules/l0-surfaces.md`, `modules/verify-classifier.md` を確認したが、いずれもスクリプト自体やフィールドの汎用的な説明であり、Step 2 の判定条件を記述したものではないため、同期不要と判断した。
- **`skills/review/SKILL.md` の類似パターンとの違い**: `skills/review/SKILL.md` (L61-64) も `gh-extract-issue-from-pr.sh` を呼ぶが、そこでは PR 番号が `/review` 呼び出し時点で既知 (`$NUMBER` = PR 番号) であり `gh pr list --search` を経由しない。本 Issue と同じ全文検索誤マッチのリスクがないため、変更対象に含めない。
- 本 Issue はテスト対象が SKILL.md のプローズ (LLM 実行) であり、対応する bats テストファイルは存在しない (`tests/verify.bats` 等に Step 2 の PR 検索ロジックへの参照なし)。検証は Issue 本文で定義済みの `rubric` / `section_contains` verify command による。

## Code Retrospective

### Deviations from Design
- N/A — Implementation Steps 1・2 の記述通りに実装した (`CANDIDATE_PRS` 取得 → `gh-extract-issue-from-pr.sh` による `issue_number` 突き合わせループ)。

### Design Gaps/Ambiguities
- N/A

### Rework
- N/A

### Autonomous Auto-Resolve Log
- Step 3 の `phase/ready` ラベルチェック時点で、Issue には既に `phase/ready` が外れ `phase/code` が付与されていた (ラベル遷移タイムライン: `phase/ready` 付与と `phase/code` 付与が同一タイムスタンプ `2026-08-07T00:58:08Z`)。Spec (`docs/spec/issue-1202-verify-pr-search-closes-match.md`) 自体は完成済みで `reconcile-phase-state.sh --check-precondition` も `spec_file` を検出しており、Spec 欠如ではなく前回セッションの中断跡と判断。non-interactive ポリシー (Spec 欠如時の auto-resolve) の主旨 — 実装続行を妨げない — に沿って、そのまま実装を続行した。

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- Spec Implementation Steps 1・2 通り、`gh pr list --search` の結果を単一採用せず最大 10 件の候補に対して `gh-extract-issue-from-pr.sh` の `issue_number` 突き合わせを行うループに置き換えた。bash 3.2+ 互換のため配列/mapfile を使わず単純な `for`/`break` で実装。
- OPEN PR 検索ブロック (`--state open`, L107 付近) は `/issue` フェーズの Issue Retrospective で確定済みのスコープ境界を踏襲し、変更対象に含めなかった。

### Deferred Items
- Post-merge AC (`verify-type: observation event=auto-run session=next`) — 次回の patch 経路 Issue での `/verify` 実行時に、Step 2 が無関係な PR を採用しないこと (`BASE_BRANCH=main` に解決され、`github_check "gh pr checks"` 型 AC が存在すれば UNCERTAIN 化されること) を実地観察する必要がある。

### Notes for Next Phase
- 本 Issue に対応する bats テストは存在しない (SKILL.md プローズが対象)。Pre-merge AC は `rubric` × 2 と `section_contains` × 1 で検証済み (すべて PASS)。
- `/review` は `skills/verify/SKILL.md` の diff (Step 2 のみ) をレビュー対象とする。OPEN PR 検索ブロックには変更がないことを確認済み。

## Verify Retrospective

### Phase-by-Phase Review

#### issue
- Background に **#1197 の実測 (PR #1018 が実際には `closes #1015`)** が具体的に記録されており、これが実装本文にもそのまま根拠として引き継がれた。**起票時の実測が最終成果物まで到達した好例**
- `#107` (数値部分一致の誤マッチを `closes #N` クエリで解消) との違い — 「クエリ文字列の改善では構造的に閉じない別経路」— も明記されており、同クラス 2 回目の発生であることが判断材料として機能した

#### spec
- post-spec で Size を M → S に降格し patch route に切り替えた判断は妥当。実変更は `skills/verify/SKILL.md` の 1 ファイル・14 挿入 7 削除に収まった
- 上位 1 件でなく**最大 10 件を候補として扱う**設計が良い。全文検索のランキングは不安定で、正解が 1 位に来る保証がないため

#### code
- Rework ゼロ、設計からの逸脱なし。bash 3.2+ 互換のため配列/`mapfile` を使わず単純な `for`/`break` で実装した点も既存方針と整合
- Auto-Resolve Log が `phase/ready` と `phase/code` の同一タイムスタンプ付与を「前回セッションの中断跡」と解釈しているが、実際には spec 完了直後に code が始まる**正常な遷移**である (本バッチの #1202 実行は 00:38 UTC 開始、当該タイムスタンプは 00:58 UTC で同一実行内)。続行という結論は正しかったが、診断はやや過剰だった

#### review / merge
- patch route のため該当なし

#### verify
- Pre-merge 3 件すべて PASS。実装記述が negative case (「候補ゼロを含め一致がなければ `PR_NUMBER` は空 = patch route」) を明示しており、AC3 の「実装またはテストで確認できる」を実装側で満たす
- **本 Issue が直した経路を、本 verify 自身が実行している**。Step 2 の PR 検索は今回 patch route (PR なし) で走り、候補なし → `PR_NUMBER` 空 → `BASE_BRANCH=main` に解決された。修正後の挙動が実地で 1 回通ったことになるが、post-merge observation AC が求める「無関係な PR がマッチする状況での観察」ではないため、AC の判定材料には使えない

### Improvement Proposals

- **skill 本体が会話単位でキャッシュされ、会話中の skill 更新が反映されない (#1206 とは別機構)** — 本 verify に渡された `skills/verify/SKILL.md` のテキストは「**Re-runs**: re-verify all conditions (idempotent). Re-verify even if already checked」という**旧版**だったが、ディスク上のファイルは #1186 の「チェック済み AC スキップ」を既に持っている (L337 / L368、`tests/verify.bats` の 3 テストが保護)。#1186 は 2026-08-06 12:54 JST 着地、本会話で最初の `/verify` invocation は同日 10:30 頃 — **最初の一度だけ読み込まれた skill 本体が、以降の全 invocation で使い回されている**。harness の再呼び出し注記 (「the skill instructions were previously loaded」) がこれを示す。
  - **#1206 の修正では救えない**。#1206 はローカル main の遅れ (ディスク上のファイルが古い) を扱うが、本件はディスク上のファイルが正しいまま、渡されるテキストだけが古い
  - **実害**: #1186 着地後も本会話の `/verify` はチェック済み AC を毎回再検証し続けた (フル bats スイートの再実行を含む)。#1186 が削減しようとしたコストがそのまま残っていた
  - 検出手段の候補: `/verify` 実行時に、渡された skill テキストの特徴的な一文とディスク上のファイルを照合する軽量チェック。あるいは会話をまたぐ長時間セッションでは skill を明示的に再読込する運用
- **新経路を守るテストがない (観察のみ、起票せず)** — 本 Issue の変更は SKILL.md プローズのみで、`tests/verify.bats` に Step 2 突き合わせ経路のテストは追加されていない。同ファイルには既に SKILL.md の構造テストが 21 件あり (Step 2 guard / Step 5 / Step 8c)、同じパターンで保護できる。将来の編集でこの経路が静かに失われても現状どのテストも落ちない。Phase Handoff が「bats テストは存在しない」と意識的に記録しているため、次に Step 2 を触る Issue で回収するのが自然
