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
