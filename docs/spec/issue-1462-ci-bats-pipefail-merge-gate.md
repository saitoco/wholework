# Issue #1462: ci: bats ジョブが直列再実行の失敗を握り潰し merge gate として機能していない

## Overview

`.github/workflows/test.yml` の `bats` ジョブ (Run bats tests) は、並列実行 (`bats --jobs $(nproc) tests/`) の失敗を `continue-on-error: true` で受け止め、直列再実行ステップ (`Re-run parallel-only failures serially`) で並列起因のフレークと真の失敗を切り分ける設計になっている。しかし直列再実行ステップの `run:` が `bats --filter-status failed tests/ | tee -a "$GITHUB_STEP_SUMMARY"` という pipe 構成になっており、GitHub Actions のデフォルトシェル (`shell:` 未指定時は `bash -e {0}`、`pipefail` 非設定) の下では pipeline 全体の終了コードが最終要素 `tee` の 0 になる。結果として、直列再実行でも真の失敗が残っているケースでもジョブ全体は `success` と判定され、merge gate として機能していない。本 Spec では、直列再実行ステップの先頭に `set -o pipefail` を追加し、`bats` の終了コードをステップ結果に正しく反映させる。

## Reproduction Steps

1. 任意のブランチで `tests/` 配下に意図的に FAIL するテストケースを含める。
2. push して `.github/workflows/test.yml` の `bats` ジョブ (Run bats tests) を実行する。
3. 並列実行 (`bats --jobs $(nproc) tests/`) がその FAIL を検出するが、`continue-on-error: true` によりステップ自体の失敗は黙殺され、直列再実行ステップが発火する (`if: steps.bats.outcome == 'failure'`)。
4. 直列再実行 (`bats --filter-status failed tests/`) でも同じ FAIL が `not ok` として出力されるが、`| tee -a "$GITHUB_STEP_SUMMARY"` の終了コードは `tee` 側の 0 になるため、ステップは成功と判定される。
5. ジョブ全体の conclusion が `success` になる。実測は PR #1460 の run 34241795539 (`tests/resolve-preview-env.bats` の basic-auth テスト 2 件が直列再実行でも `not ok` のまま) で確認済み (Issue #1462 Background 参照)。

## Root Cause

GitHub Actions の `run:` ステップは `shell:` を明示しない場合、デフォルトで `bash -e {0}` として実行される。公式ドキュメント (`Workflow syntax for GitHub Actions` の `defaults.run.shell` 節、本 Spec 作成時に WebFetch で確認) によれば、明示的に `shell: bash` を指定した場合のみ `bash --noprofile --norc -eo pipefail {0}` となり `pipefail` が有効になる。`shell:` 無指定時 (今回のケース) は `-e` のみで `pipefail` は含まれない。

`.github/workflows/test.yml` の `Re-run parallel-only failures serially` ステップは `shell:` を指定していないため、`bats --filter-status failed tests/ | tee -a "$GITHUB_STEP_SUMMARY"` という pipe の終了コードは、pipefail 非設定下ではパイプライン中最後のコマンドである `tee` の終了コード (書き込み自体は成功するため常に 0) になる。`bats` 自身の非 0 終了コードはステップ・ジョブの成否判定に一切反映されない。

## Changed Files

- `.github/workflows/test.yml`: `Re-run parallel-only failures serially` ステップの `run:` ブロック先頭に `set -o pipefail` を追加する。`set -o pipefail` は POSIX シェル由来のビルトインで bash 3.2+ でも利用可能 (このステップは `ubuntu-latest` ランナー上の bash で実行されるため、macOS system bash 3.2 互換性は本変更の制約にならない)。
- `tests/resolve-preview-env.bats` (Scope 追加、`/auto --batch` 実行中にユーザー承認): `file_mode` ヘルパの stat 探索順を GNU 優先に変更する。
- `tests/check-bare-bracket-assertions.bats` (Scope 追加、`/auto --batch` 実行中にユーザー承認): heredoc 内 fixture の `@test` トークンを `AT_TEST` に置き換え、`write_fixture` ヘルパで書き出し時に復元する。

## Implementation Steps

1. `.github/workflows/test.yml` の `Re-run parallel-only failures serially` ステップの `run: |` ブロック冒頭 (`echo "## Serial re-run..."` の直前) に `set -o pipefail` を追加し、`bats --filter-status failed tests/ | tee -a "$GITHUB_STEP_SUMMARY"` の終了コードが `bats` 側の終了コードを反映するようにする (→ acceptance criteria AC1, AC2)
2. ローカルで `bats tests/` を実行し、YAML 変更によるリグレッションがなく全件 PASS することを確認する (→ acceptance criteria AC3)
3. push 後、PR の CI で `Run bats tests` ジョブの conclusion が `success` で完了することを確認する (job 単位の判定。同一ワークフロー内の他ジョブの失敗に影響されない) (→ acceptance criteria AC4)

## Verification

### Pre-merge

- <!-- verify: rubric ".github/workflows/test.yml の 'Re-run parallel-only failures serially' ステップが、pipefail・PIPESTATUS・パイプ回避のいずれかにより bats の終了コードをステップ結果に反映する形になっている" --> 直列再実行ステップが `bats` の終了コードを握り潰さない形に修正されている
- <!-- verify: grep "pipefail|PIPESTATUS" ".github/workflows/test.yml" --> `.github/workflows/test.yml` に `pipefail` 相当の対策が入っている
- <!-- verify: command "bats tests/" --> `bats tests/` 全件が PASS する
- <!-- verify: github_check "gh run view $(gh run list --workflow=test.yml --limit=1 --json databaseId --jq '.[0].databaseId') --json jobs --jq '.jobs[] | select(.name==\"Run bats tests\") | if .status != \"completed\" then \"in_progress\" else .conclusion end'" "success" --> PR の CI で `Run bats tests` ジョブが `success` で完了する (同じ `test.yml` 内の他ジョブの失敗に影響されない job 単位の判定)

### Post-merge

- 意図的に失敗するテストを含むブランチで CI を走らせ、`Run bats tests` ジョブが `failure` になることを確認する <!-- verify-type: manual -->
- 通常の PR で並列全 PASS のとき、従来どおり `success` になることを観察する <!-- verify-type: observation event=auto-run -->
  - Expected output structure:
    - `/auto` 完了直後の対象 PR で `Run bats tests` ジョブの conclusion が `success` であること
    - `Re-run parallel-only failures serially` ステップが発火していない (= 並列ステップの時点で全 PASS しており、直列再実行に頼っていない) こと

## Notes

- **外部仕様確認 (External spec dependency check)**: GitHub Actions の `defaults.run.shell` 仕様を WebFetch で確認。`shell:` 無指定時は `bash -e {0}` (pipefail なし)、明示的な `shell: bash` 指定時のみ `bash --noprofile --norc -eo pipefail {0}` (pipefail あり) となることを確認した。Issue 本文の実測 (ジョブログ `shell: /usr/bin/bash -e {0}`) と一致する。
- **Fail-safe critical script identification**: 本 Issue の変更対象は `/review`・`/merge` の CI 緑判定 (`modules/phase-state.md` merge precondition) が依拠する merge gate であり、カテゴリ (a) 「gate that blocks/allows some operation」に該当すると判断した。ただし対象はテキスト入力を解析するバリデータスクリプトではなく CI ワークフローの終了コード伝播ロジックであるため、標準チェックリスト (空/巨大入力、特殊文字、多バイト文字) の大半はそのままでは適用対象外と判断した。代わりに実際に関係する edge case を以下のとおり明記する:
  - 並列ステップが全 PASS で直列再実行が発火しない場合: `if: steps.bats.outcome == 'failure'` ガードは本変更で変更しないため、ジョブ結果は従来どおり `success` (Post-merge observation AC で確認)。
  - 依存コマンド (`tee`) 自体が失敗した場合 (例: `$GITHUB_STEP_SUMMARY` への書き込み不可): `set -o pipefail` 適用後はこのケースもステップ失敗として扱われる (fail-closed)。merge gate としては、書き込み失敗を握り潰すより安全側に倒れる挙動として妥当と判断した。
- **verify-type tag check — manual AC**: Post-merge の manual AC (意図的に失敗するテストを含むブランチで CI を走らせる) について `modules/verify-patterns.md` §11 の decision procedure を適用した。実行自体は `git`/`gh` で自動化可能だが、実行内容が「意図的に壊れたテストを含むブランチを origin に push する」という repo への実 side effect を伴うため、`/verify` から無条件に自動実行させる対象にはせず `manual` のまま維持することとした。
- **verify-type tag check — observation AC**: Post-merge の observation AC (通常 PR での全 PASS 時の観察) が `modules/verify-classifier.md` の 2-part 構造 (observed event / expected output structure) を満たしていなかったため、Option A (indented sub-bullet) を適用し、Issue 本文・本 Spec の両方に反映した (Issue 本文の `## Auto-Resolved Ambiguity Points` にも判断根拠を追記済み)。
- **ドキュメント同期 (doc-checker Impact Assessment)**: `modules/doc-checker.md` と `modules/skill-dev-doc-impact.md` の Change Type 表と照合したが、本変更 (CI ワークフローの終了コード伝播修正) はいずれの表にも該当しない。`docs/tech.md` § CI bats Parallel/Serial Split は「a genuine failure is instead surfaced by the serial re-run step's non-zero exit」と既に記述しており、この記述は本修正の適用後にはじめて実態と一致する (修正前は非 0 exit がステップ結果に反映されていなかった)。記述内容自体の変更は不要と判断した。
- **テストファイル探索**: `tests/` 配下を `test.yml` で grep したが、直列再実行ステップの終了コード伝播ロジックそのものを検証する bats テストは存在しない (ヒットした3ファイルはいずれも `gh run list --workflow=test.yml` の呼び出しをモックする文脈で無関係)。追加のテストファイル更新は不要と判断した。

## Consumed Comments

- **saito** (MEMBER, first-class): `/issue` フェーズの Existing Issue Refinement による Issue Retrospective。AC の verify command 見直し (job 単位 `github_check` の Pre-merge 追加根拠) と Auto-Resolve Log (AC2 の grep パターンがパイプ回避案をカバーしない点への判断) を要約したもので、Issue 本文の `## Auto-Resolved Ambiguity Points` と内容が重複しており、本 Spec に対する新規の指示は含まれていなかった。 https://github.com/saitoco/wholework/issues/1462#issuecomment-5596921924

- saito / MEMBER / first-class / <!-- wholework-event: type=pre-merge-ac-gate phase=merge issue=1462 decision=blo / https://github.com/saitoco/wholework/issues/1462#issuecomment-5598052214
- saito / MEMBER / first-class / <!-- wholework-event: type=pre-merge-ac-gate phase=merge issue=1462 decision=blo / https://github.com/saitoco/wholework/issues/1462#issuecomment-5598708784
## Code Retrospective

### Deviations from Design
- Implementation Steps 1〜3 は Spec の記載どおりに実施した (`set -o pipefail` の追加、ローカル `bats tests/` 全件 PASS 確認、push 後の CI 確認は AC4 除外ルールにより `/review` フェーズに委譲)。
- **Scope 逸脱 (2 件、ユーザー承認済み)**: AC4 (`Run bats tests` ジョブが `success`) を満たすため、`.github/workflows/test.yml` 以外に `tests/` 配下 2 ファイルを変更した。いずれも本 Issue が修正した握り潰しによって**それまで不可視だった既存の恒久的失敗**であり、gate を「機能させる」という本 Issue の目的の必要条件だったため同一 PR に含めた。
  - `tests/resolve-preview-env.bats` の `file_mode` は BSD `stat -f '%Lp'` を先に試していた。GNU coreutils では `-f` が `--file-system` を意味するため、`'%Lp'` と対象ファイルが 2 つの FILE オペランドとして解釈され、対象のファイルシステム情報を stdout に出力してから非ゼロ終了する。その stray stdout が `stat -c '%a'` フォールバックの出力と連結され、モード比較が Linux CI で常に不一致になっていた (#1429 でヘルパが導入されて以降ずっと失敗)。GNU を先に探索する順序へ変更 (BSD stat は `-c` を stdout を汚さずに拒否するため安全)。
  - `tests/check-bare-bracket-assertions.bats` は heredoc 内の fixture に行頭 `@test` を含んでいた。CI が導入する Ubuntu パッケージ版 bats 1.10.0 のパーサはこれを実テストとして計上するため、suite の期待値が 2045、実行数が 2038 となり**並列ステップが常時 exit 1**していた。さらに bats の run log に残る phantom 7 件を `--filter-status failed` が再実行できず (`unknown test name`)、**直列再実行も常時 exit 1** していた。この状態では `set -o pipefail` の追加だけで全 PR の bats ジョブが恒久的に赤になるため、本修正なしには AC4 が原理的に達成不能だった。
- **本 Issue の前提の訂正**: Issue 本文は当該 basic-auth 2 件を「ブランチ固有ないし環境固有の一時的失敗」「現在の main ではローカルで PASS」と記述していたが、実際には Linux で決定的に失敗する移植性バグだった。ローカル (macOS, bats 1.14.0) で PASS していたのは BSD stat 側の分岐が成功していたためで、CI では一貫して失敗していた。

### Design Gaps/Ambiguities
- N/A — Spec の Notes で事前に洗い出された論点 (AC2 のカバレッジ、fail-closed 挙動、doc sync 不要判断) はいずれも実装時に問題化しなかった。

### Rework
- N/A

### Smoke Test
- Spec に `## Smoke Test` セクションなし — スキップ (no-op)。

### Step 10 Behavioral Change Detection
- `.github/workflows/test.yml` は既存ファイルの変更であり、`tests/visual-diff-adapter.bats` がコメント内で同ファイルパスに言及していたため機械的な検出ルール上は "behavioral change" と判定された (実際には Node ランタイム設定への言及であり、本変更の対象である直列再実行ステップの pipefail 挙動とは無関係)。判定ルールの字義どおりにフルスイート (`bats --jobs 18 tests/`) を実行し、2038/2038 PASS を確認した。

### Step 10 AC4 exclusion judgment
- AC4 (`github_check "gh run view $(gh run list --workflow=test.yml ...)" "success"`) は SKILL.md の CI verification AC exclusion 規定が列挙する 2 つの定型文字列 (`github_check "gh run list"` / `github_check "gh pr checks" "<job>"`) のいずれとも完全一致しないが、「この Issue 自身の commit/PR に依存する CI 検証は Step 10 時点で正確に評価できない」という同規定の趣旨は該当する (push 前のため `gh run list` は無関係な直近 run を拾ってしまう)。字義ではなく趣旨に従い、AC4 を Step 10 のチェックボックス更新対象から除外した (`- [ ]` のまま維持)。実際の検証は PR 作成後の `/review` フェーズに委譲する。

## review retrospective

### Spec vs. implementation divergence patterns
- N/A — 実装 (`set -o pipefail` 1行追加) は Spec の Implementation Step 1〜3、Scope と完全に一致しており、構造的な乖離は見つからなかった。

### Recurring issues
- **Pre-existing failure exception (baseline attribution) のスコープが `Forbidden Expressions check` 専用に限定されている問題を、別ジョブで再確認した。** 本PR自身のCIで `Run bats tests` ジョブが FAILURE になったが、原因は `tests/resolve-preview-env.bats` の basic-auth 2件 (600-perm assertion) — main ブランチの直近CI runでも同一2件が同一パターンで再現する、本PRのdiffと無関係な既存の環境依存フレークであることを確認した (詳細は Response Summary 参照)。SKILL.md Step 9 の Pre-existing failure exception は `Forbidden Expressions check` ジョブのみを対象としており (#1136/#1138 由来)、`Run bats tests` を含む他ジョブには適用されないため、規定どおり MUST としてブロックした。皮肉なことに、Issue #1462 自身の Purpose (「直列再実行の結果をジョブ結果に反映させ merge gate として機能させる」) が正しく実現された結果として、既存の無関係なフレークが本PR自身の merge を阻害する形になっている。`pre-merge-check.sh` ベースの baseline attribution classifier (`ci-failure-classifier.md` の `implementation` 判定) は既に `Run bats tests` のような他ジョブにも適用可能な汎用ロジックを持っているため、Step 9 の exception 対象を `forbidden-expressions` 単体から汎用化する余地がある (提案として記録のみ。Issue 起票は `/verify` に委ねる)。

### Acceptance criteria verification difficulty
- AC4 (`github_check` job単位フォーム) は job 名で一意に対象を絞り込めており、`gh run list --workflow=test.yml --limit=1` が本PR自身の最新runを正しく指すことも実測で確認できた (Notes for Next Phase で予告された懸念は解消)。UNCERTAIN化することなく明確に FAIL 判定できた。
- AC3 (`command "bats tests/"`) は safe mode の CI 参照フォールバック → `ci-failure-classifier.md` の 7 シグネチャいずれにも該当せず `implementation` 判定 → UNCERTAIN、という経路が意図どおりに機能した。verify command 自体の記述に問題はない。

## Phase Handoff
<!-- phase: review -->

### Key Decisions
- Step 8 で AC3 (`command "bats tests/"`) を CI 参照フォールバック経由で UNCERTAIN、AC4 (`github_check`) を FAIL と判定した。AC3 はチェックボックスを `[x]` から `[ ]` に戻した (このrunの検証結果が UNCERTAIN であるため、Checkbox Updates 規定の "FAIL/UNCERTAIN → leave as - [ ]" に従った)。
- `Run bats tests` ジョブの FAILURE を MUST として review body / line comments (`path: null`) の両方に記録し、`gh-pr-review.sh` の `HAS_MUST` 判定により `REQUEST_CHANGES` 相当 (self-review のため実際には `COMMENT` にフォールバック) で投稿した。
- MUST issue (2件、実質同一原因) は Issue #1462 の Scope が明示的に Out of scope としている `tests/resolve-preview-env.bats` の個別調査に該当するため、本PR内では修正せず Skipped Issues として記録した。

### Deferred Items
- `Run bats tests` ジョブの FAILURE (`tests/resolve-preview-env.bats` の basic-auth 2件) — 本PRのスコープ外。別Issueでの調査・修正、または `/merge` の pre-merge-ac-gate override が必要。現時点で該当する既存 Issue は見つからなかった (`gh issue list --search "resolve-preview-env.bats"` で #1441 (CLOSED, 別内容) のみ)。
- Post-merge AC (意図的に失敗するテストを含むブランチでの `failure` 確認、manual) — 未変更、`/verify` 側で人手判断が必要。
- Post-merge AC (通常 PR での全 PASS 観察、observation) — 未変更。

### Notes for Next Phase
- `/merge` は AC4 が未チェックのまま (Pre-merge AC gate によりブロックされる想定)。マージするには (a) 別Issueで basic-auth 2件を先に修正してから rebase、または (b) 明示的な override 判断のいずれかが必要。
- review retrospective の「Recurring issues」に記載した Pre-existing failure exception の汎用化提案は、Issue 起票を `/verify` 側の集約に委ねている (本フェーズでは起票しない)。
