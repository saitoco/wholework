# Issue #1051: lighthouse-adapter: Basic Auth (Authorization ヘッダ) 注入オプションを追加

## Overview

`modules/lighthouse-adapter.md` の `lighthouse_check` verify command は、実行コマンドが `lighthouse "URL" --output=json --quiet --chrome-flags="--headless --no-sandbox" --only-categories="category"` 固定であり、`--extra-headers` による Authorization ヘッダ注入手段がない。このため対象サイトが Basic Auth 保護下 (PR preview / 公開前本番) だと `lighthouse_check` が認証を通せず機械検証できない。本 Issue では、`modules/browser-adapter.md` Step 3 (Basic Authentication Setup) と同一の規約 (`PREVIEW_BASIC_USER` / `PREVIEW_BASIC_PASS` 環境変数、認証情報のマスキング方針) で `lighthouse-adapter` に Basic Auth 対応を追加し、Lighthouse CLI 公式仕様の `--extra-headers` (JSON 文字列 or JSON ファイルパス) を用いて Authorization ヘッダを注入できるようにする。スコープは `lighthouse-adapter` (Lighthouse CLI) に限定し、curl 系 verify command (`html_check` 等) の同種の Basic Auth 障壁は Issue 本文の Auto-Resolved Ambiguity Points により本 Issue のスコープ外 (別 Issue 起票を推奨)。

## Changed Files

- `modules/lighthouse-adapter.md`: change — Step 1 (CLI Detection) の後に新しい「Step 2: Basic Authentication Setup」を挿入し、既存の Step 2 (Lighthouse Execution) を Step 3、Step 3 (Score Evaluation) を Step 4 に繰り下げる。新 Step 2 で `PREVIEW_BASIC_USER` / `PREVIEW_BASIC_PASS` から一時 JSON ヘッダファイルを組み立て、新 Step 3 の実行コマンドに `--extra-headers` を条件付きで追加する。
- `modules/verify-executor.md`: change — 「### Basic Authentication Support」節 (現状 `browser_check` / `browser_screenshot` に限定した記述、L256-258 付近) に、`lighthouse_check` も同じ環境変数で Basic Auth をサポートするようになった旨を追記する。本 Issue の実装後、この節の記述が実態と乖離する (lighthouse-adapter も対応済みなのに未記載のまま) ため、Changed Files に含めた。

## Implementation Steps

1. `modules/lighthouse-adapter.md` の Step 1 (CLI Detection) の直後に、新しい見出し「### Step 2: Basic Authentication Setup」を挿入する (既存 Step 2/Step 3 はそれぞれ Step 3/Step 4 に繰り下げ)。挿入する本文の要点:
   - `modules/browser-adapter.md` Step 3 と同一の規約で、環境変数 `PREVIEW_BASIC_USER` (username) / `PREVIEW_BASIC_PASS` (password) から Basic Auth 情報を取得する旨を記載する。
   - 両方が設定されている場合、認証情報をコマンドライン文字列に直接埋め込まず、一時 JSON ヘッダファイルを組み立てる手順として、次のシェルスニペットを記載する:
     ```bash
     mkdir -p .tmp
     header_file="$(mktemp .tmp/lighthouse-headers-XXXXXX.json)"
     printf '{"Authorization":"Basic %s"}' "$(printf '%s:%s' "$PREVIEW_BASIC_USER" "$PREVIEW_BASIC_PASS" | base64 | tr -d '\n')" > "$header_file"
     ```
     (`tr -d '\n'` は GNU coreutils の `base64` がデフォルトで 76 文字ごとに挿入する折り返し改行を除去する。折り返しが残ると JSON 文字列値が壊れるため。)
   - 新 Step 3 の実行コマンドで `--extra-headers="$header_file"` を渡す旨を記載する。どちらか一方でも環境変数が未設定の場合はヘッダ注入をスキップし、`--extra-headers` なしで新 Step 3 を実行する (現行の無認証動作を維持) 旨を記載する。
   - `PREVIEW_BASIC_USER` / `PREVIEW_BASIC_PASS` の値・base64 エンコード後の値・ヘッダファイルの内容を、ログや検証結果詳細に出力しない (`****` としてマスク) 旨を、`modules/browser-adapter.md` Step 3 と同じマスキング方針として明記する。
   - 新 Step 4 完了後 (成功・失敗を問わず) に `rm -f "$header_file"` で一時ヘッダファイルを削除する後始末を明記する。
   (→ Pre-merge AC1)

2. (after 1) 新 Step 3 (旧 Step 2: Lighthouse Execution) の実行コマンド記述を、Basic Auth なし (現行、変更なし) の場合とありの場合を併記する形に更新する。

   Basic Auth なし (デフォルト、変更なし):
   ```
   lighthouse "URL" --output=json --quiet --chrome-flags="--headless --no-sandbox" --only-categories="category"
   ```

   Basic Auth あり (Step 2 で `$header_file` が作成された場合):
   ```
   lighthouse "URL" --output=json --quiet --chrome-flags="--headless --no-sandbox" --only-categories="category" --extra-headers="$header_file"
   ```
   (→ Pre-merge AC2)

3. (after 2) 新 Step 4 (旧 Step 3: Score Evaluation) は内容変更不要 (スコア判定ロジックは `--extra-headers` の有無に依存しない)。Step 2 のマスキング方針の記述 (ステップ1 で追加済み) により AC3 を満たすことを確認する。
   (→ Pre-merge AC3)

4. (parallel with 1-3) `modules/verify-executor.md` の「### Basic Authentication Support」節に以下の 1 文を追記する: 「`lighthouse_check` supports the same environment variables via the lighthouse adapter's own Basic Authentication Setup step (`--extra-headers` Authorization injection); see `modules/lighthouse-adapter.md`.」

## Verification

### Pre-merge

- <!-- verify: grep "PREVIEW_BASIC_USER" "modules/lighthouse-adapter.md" --> lighthouse-adapter が Basic Auth 認証情報 (環境変数 `PREVIEW_BASIC_USER` / `PREVIEW_BASIC_PASS`、`modules/browser-adapter.md` と同一の規約) から `--extra-headers` の Authorization ヘッダを組み立てて実行できる
- <!-- verify: grep "extra-headers" "modules/lighthouse-adapter.md" --> 実行コマンドに `--extra-headers` 注入手順が記載されている
- <!-- verify: rubric "認証情報がコマンドライン文字列・ログに平文で残らない方式 (環境変数参照または一時ファイル) が採用されている" --> 認証情報がプロセスリストやログに露出しない

### Post-merge

- Basic Auth 保護下の URL に対する `lighthouse_check` AC を含む Issue の `/review` または `/verify` 実行で、PASS/FAIL が機械判定される

## Notes

- **外部仕様確認 (`--extra-headers`)**: Lighthouse CLI 公式ドキュメント ([CLI reference](https://googlechrome-lighthouse.mintlify.app/api/cli-reference)) で `--extra-headers` は「JSON string or path to a JSON file of additional HTTP headers to send with requests」であることを確認した。インライン JSON 文字列形式 (`--extra-headers '{"Authorization":"..."}'`) ではなく JSON ファイルパス形式 (`--extra-headers="$header_file"`) を採用した理由: 認証情報の生値をコマンドライン文字列に直接埋め込まない (AC3 のマスキング要件) ため。
- **`modules/browser-adapter.md` との整合性**: `PREVIEW_BASIC_USER` / `PREVIEW_BASIC_PASS` の環境変数名、マスキング方針 (ログ・検証結果詳細への非出力)、「コマンドライン文字列に生値を書かない」制約は、Issue 本文の指定通り `modules/browser-adapter.md` Step 3 と同一の規約を踏襲した。
- **クレデンシャル/セキュリティポリシー確認 (確認済み、矛盾なし)**: `SECURITY.md` および `grep -rl "credential\|security" docs/ SECURITY.md` (repo ルート) でヒットしたポリシー文書を確認したが、`PREVIEW_BASIC_USER` / `PREVIEW_BASIC_PASS` の取り扱いを制約する明示的な記述はなく、`SECURITY.md` の「Wholework does not store or transmit credentials」は GitHub CLI 認証に関する記述で本件とは別スコープ。既存の適用規約は `modules/browser-adapter.md` Step 3 のみであり、本 Issue はそれを踏襲するため矛盾はない。
- **他ファイルへの影響なし (確認済み)**: `grep -rln "lighthouse" docs/ tests/ modules/ scripts/ skills/` (repo ルート、`.git/` 除く) で lighthouse 言及ファイルを網羅的に確認した。`docs/guide/adapter-guide.md` (bundled adapter 一覧)、`docs/environment-adaptation.md` (capability 検出方式一覧・adapter pattern 適用例)、`docs/guide/customization.md` (pre-merge-preview tier 対象コマンド一覧)、`skills/verify/lighthouse-guidance.md` (Domain file) はいずれも lighthouse を高レベルに言及するのみで Basic Auth 有無を主張する記述がないため、更新不要と判断した。`modules/verify-executor.md` の「Basic Authentication Support」節のみ `browser_check`/`browser_screenshot` に限定した記述があり、本 Issue の実装後に不整合となるため Changed Files に含めた (`grep -rln "extra-headers"` は本 Issue 実装前の repo 全体で 0 件)。
- **Issue 本文と実装の整合性チェック (確認済み、矛盾なし)**: Issue 本文が主張する現行実装 (`lighthouse-adapter.md` の実行コマンドが `--extra-headers` を持たない固定コマンドである点) は `modules/lighthouse-adapter.md` の Step 2 の記述と完全に一致することを確認した。
- **アダプタパターン調査**: 本 Issue の verify command (`grep`, `rubric`) はいずれも `modules/verify-executor.md` の built-in translation table に既存の command type であり、新規 command type を導入しないため `docs/environment-adaptation.md` Extension Guide Step 0 の対象外と判断した。
- **スコープ境界**: Issue 本文の Auto-Resolved Ambiguity Points に記載の通り、curl 系 verify command (`html_check` / `http_status` / `api_check` / `http_header` / `http_redirect`) への同種の Basic Auth 対応は本 Issue のスコープ外。本 Spec でもこの境界を変更しない。
- **Smoke Test セクション不採用**: 本 Issue の verify command は `mcp_call` を含まず `capabilities.mcp` も無関係のため、Smoke Test セクションの採用条件に該当しない。また wholework 自身のリポジトリには Basic Auth 保護下の preview URL が存在しないため、pre-merge での実地スモークテストは対象読者環境でのみ可能 (Post-merge AC で opportunistic に確認する設計)。

## Consumed Comments

- saito (MEMBER, first-class): `/issue` フェーズの Issue Retrospective コメント (2026-07-29T02:39:22Z)。curl 系 verify command への同種対応をスコープ外とした Auto-Resolve 判断の理由、Related Issues (#1056, #1059) を追加した経緯を記録したもので、内容は本 Issue 本文の Background / Auto-Resolved Ambiguity Points に既に反映済みのため、Spec 作成上の追加対応は不要と判断した。 (https://github.com/saitoco/wholework/issues/1051#issuecomment-5112167503)

## Code Retrospective

### Deviations from Design
- N/A (Implementation Steps 1-4 をそのまま実装した)

### Design Gaps/Ambiguities
- N/A

### Rework
- N/A

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- Spec の Implementation Steps 通り、`modules/lighthouse-adapter.md` に Step 2 (Basic Authentication Setup) を新設し、既存 Step 2/3 を Step 3/4 に繰り下げた。`modules/browser-adapter.md` Step 3 と同一の環境変数名・マスキング方針を踏襲。
- `--extra-headers` はインライン JSON 文字列ではなく一時 JSON ヘッダファイルパス形式を採用 (認証情報の生値をコマンドライン文字列に残さないため)。

### Deferred Items
- Post-merge AC (opportunistic): Basic Auth 保護下の URL に対する `lighthouse_check` AC を含む Issue の `/review` または `/verify` 実行で PASS/FAIL が機械判定されることの確認。wholework 自身のリポジトリには Basic Auth 保護下の preview URL が存在しないため、対象読者環境でのみ確認可能。
- curl 系 verify command (`html_check` 等) への同種の Basic Auth 対応は本 Issue のスコープ外 (Issue 本文の Auto-Resolved Ambiguity Points により別 Issue 起票を推奨)。

### Notes for Next Phase
- 全 pre-merge AC (grep×2, rubric×1) はローカルで PASS 確認済み、Issue チェックボックスも更新済み。
- テストスイート (`bats tests/`, 1246 tests) 全 PASS、`check-forbidden-expressions.sh` / `validate-skill-syntax.py` も問題なし。
- 本 Issue はドキュメント (Markdown モジュール) のみの変更で、bats/CI 実行系コードへの機能追加はない。

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- AC は `grep` × 2 + `rubric` × 1 の構成で、いずれも実装の核心 (環境変数名 / `--extra-headers` / 認証情報の非露出) を判定できる形になっていた。実装前の main では `grep -rln "extra-headers"` が 0 件だったことが Spec Notes に記録されており、常時 PASS な verify command は含まれていない。
- Lighthouse CLI 公式仕様 (`--extra-headers` が JSON 文字列とファイルパスの両方を受け付ける) を外部ドキュメントで確認したうえでファイルパス形式を選定しており、選定理由 (AC3 のマスキング要件) が追跡可能な形で残っている。

#### design
- `modules/browser-adapter.md` Step 3 の既存規約 (環境変数名・マスキング方針) を踏襲する判断により、認証情報の扱いを再発明せずに済んだ。
- Spec 作成時の副次的発見として `modules/verify-executor.md` の「Basic Authentication Support」節が `browser_check`/`browser_screenshot` 限定の記述のままだと実装後に不整合になる点を先回りで検出し、Changed Files に含めている。drift の作り込みを未然に防いだ good case。

#### code
- Code Retrospective は Deviations / Design Gaps / Rework すべて N/A。fixup/amend パターンなし、実装は 1 コミット (`c794c8a6`) で完結。

#### review
- patch route (Size S) のため review フェーズなし。

#### merge
- patch route のため merge フェーズなし (main 直コミット)。

#### verify
- pre-merge AC 3 件すべて初回 PASS。FAIL / UNCERTAIN なし、auto-retry 発火なし。
- post-merge AC 1 件は `verify-type: opportunistic` のため未チェックのまま `phase/verify` に留置。wholework 自身のリポジトリに Basic Auth 保護下の preview URL が存在しないため、これは設計どおりの状態。
- 本実行中に event の `session_id` 誤帰属と、Worktree Exit の merge 失敗を検出した (下記 Improvement Proposals)。
- Worktree Exit (Step 13) で `worktree-merge-push.sh` が FF merge に失敗し、手動 rebase による介入が必要になった。並行セッションが verify 実行中に main を 2 コミット進めたことが引き金。

### Improvement Proposals

- **in-session `/verify` の event が並行 `/auto` セッションの `session_id` に誤帰属する**: `restore_auto_session_pointer()` は `.tmp/auto-session-${PGID}` → `.tmp/auto-session-current` の順にポインタを探すが、`/verify` は wrapper を持たず Bash 呼び出しごとに新しい PGID を得るため、実質的に常に後者 (PGID 非依存の単一グローバルファイル) にフォールバックする。このファイルは `/auto` Step 1 が起動時に無条件で上書きするため、**並行して別の `/auto` セッションが起動すると、先行セッションの in-session `/verify` が emit する event が後発セッションの ID で記録される**。本実行で実証: batch セッション `46196-1785292524` の `/verify 1051` が emit した `phase_start` / `phase_complete` が `.tmp/auto-events.jsonl` 上で `session_id=74736-1785294462` (#1059/#1069 を処理していた並行セッション) として記録された。一方 `run-auto-sub.sh` 経由の #1051 の event は PGID ポインタ経由で正しく `46196-...` を記録できており、誤帰属は in-session emit 経路にのみ現れる。影響範囲は batch/XL の L3 retrospective の event 抽出 (`jq 'select(.session_id == ...)'`)、`/audit auto-session` のメトリクス、および L3 notable 判定で、いずれも並行セッション運用下で件数を取りこぼす / 他セッション分を混入させる。`.tmp/auto-session-current` は #791 iter B / #902 fix cycle で in-session `/verify` 救済のために導入されたものだが、並行 `/auto` セッションを想定していない。対策候補: (a) `/auto` が `Skill(wholework:verify)` を呼ぶ際に `AUTO_SESSION_ID` を引数として明示的に引き渡し、`/verify` 側がそれを最優先で使う、(b) ポインタファイルを Issue 番号でスコープする (`.tmp/auto-session-issue-N`) ことで並行セッション間の衝突を構造的に排除する、(c) `auto-session-current` を「単一 `/auto` セッション運用時のみ有効」と明示し、並行運用時は誤帰属しうる旨を `modules/event-emission.md` に既知の制約として記載する。(a) が最も確実だが、(b) は既存の呼び出し規約を変えずに済む。

- **`worktree-merge-push.sh` の "base が current branch" 経路に rebase fallback が欠落している**: `scripts/worktree-merge-push.sh` L88 の `git fetch . "${FROM_BRANCH}:${BASE_BRANCH}"` は 2 つの異なる理由で失敗しうる — (a) `BASE_BRANCH` がいずれかの worktree で checkout 済み (exit 128)、(b) fast-forward にならない (exit 1)。しかし L89-117 の分岐は `current_branch == BASE_BRANCH` かどうかだけで経路を選んでおり、失敗理由を区別していない。結果として **true 側 (L90-95) は失敗理由を (a) だけと仮定して `git merge --ff-only` を試み、それが失敗したら ancestry チェックも rebase も試さずに `exit 1`** する。一方 false 側 (L96-116) は `merge-base --is-ancestor` 判定 → worktree での `git rebase origin/BASE` → ref-fetch 再試行、という fallback を完備している。`/verify` は Step 2 で main リポジトリに対して `git checkout "$BASE_BRANCH"` を実行するため、Step 13 の Worktree Exit では**必ず true 側を通る**。そこに並行セッションによる main への commit が重なると (a) と (b) が同時に成立し、fallback を持たない経路で確定的に失敗する。本実行で再現: verify 実行中に並行セッションが main を 2 コミット進めた (`b678c0c9`, `a4d8f28d`) 結果 `Error: FF merge failed even though main is checked out locally. Resolve manually.` で停止し、`git -C <worktree> rebase main` を手動実行してから再実行することで解決した。並行セッション運用 (docs/sessions の記録上、常態) では `/verify` の Worktree Exit が高頻度で失敗する。対策: true 側の FF merge 失敗時に false 側と同じ ancestry チェック + worktree rebase + 再試行を実行する (両経路で共通の関数に切り出すのが素直)。なお false 側は `origin/${BASE_BRANCH}` に rebase するが、true 側は手元の `${BASE_BRANCH}` が既に origin と同期している前提が置けるため、どちらの ref を使うかは実装時に確認が必要。
