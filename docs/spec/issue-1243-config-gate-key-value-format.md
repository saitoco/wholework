# Issue #1243: observation-trigger: config= 条件ゲートを key:value 形式へ拡張し enum 設定キーに対応

## Overview

`modules/observation-trigger.md` § "Condition Check Gate (`config=`)" が定義する observation AC の `config=<key>` ゲートは、現状 boolean 専用 (`get-config-value.sh` の戻り値が `"true"` に解決する場合のみマッチ) であり、`auto-stop-at` (enum: `spec`/`code`/`review`/`merge`/`verify`) のような enum 値を取る設定キーに依存する条件を表現できない。この制約が実害として #1165 で #783 の再型付けを断念させ retire に倒す決め手になった。

本 Issue は `config=` 属性値にコロンが含まれる場合を新形式 `config=<key>:<value>` として解釈し、`get-config-value.sh` の戻り値と `<value>` を比較してマッチ判定するよう `scripts/opportunistic-search.sh` を拡張する。既存の `config=<key>` (値なし) 形式は完全に後方互換を維持する。姉妹機構 `when=<axis>:<value>` ゲート (同スクリプト内) と同じ「最初の `:` で分割」パターンを踏襲し、value 側には `get-config-value.sh` の KEY 制約と同じ `[A-Za-z0-9._-]` サニタイズを適用、不正入力は fail-closed (マッチ除外) とする。

## Changed Files

- `modules/observation-trigger.md`: § "Condition Check Gate (`config=`)" に `config=<key>:<value>` 形式のマッチング仕様 (分割方法・サニタイズ・比較方法・fail-closed 挙動) を追記し、既存 `config=<key>` 形式との後方互換セマンティクスを明記。末尾の「comparison is boolean-only; enum-valued keys ... are out of scope. Both are candidates for a `config=key:value` extension」という記述を、拡張が実装済みであることを反映した文言に更新する。
- `scripts/opportunistic-search.sh`: Config check gate ブロックとファイル冒頭のヘッダーコメントを拡張 (詳細は Implementation Steps 参照)。bash 3.2+ 互換 (`case`/パラメータ展開のみ使用)。
- `tests/opportunistic-search.bats`: `config=auto-stop-at:verify` 形式のマッチ / 非マッチ、value サニタイズ不適合時の fail-closed、を検証する新規 `@test` を追加。既存の `config gate: *` 3 テスト (L350-388) は変更なしで green を維持することを確認。
- `modules/verify-classifier.md`: § "observation Type: Event Values and Syntax" の `config=<key>` 段落 (L53-70 付近) に `config=<key>:<value>` 形式を追記し、「enum-valued keys ... are out of scope for `config=`」という now-inaccurate な一文を改訂する。

## Implementation Steps

1. `modules/observation-trigger.md` § "Condition Check Gate (`config=`)" を更新する。「Matching specification」箇条書きに `config=<key>:<value>` 形式の分割方法 (属性値中の最初の `:` でキー部分と値部分を分割)、value 側のサニタイズ (`[A-Za-z0-9._-]`、`get-config-value.sh` の KEY 制約と同一)、比較方法 (解決値と value の大小文字を無視した文字列比較)、フェイルモード (value サニタイズ不適合または key/value いずれかが空になる記法不正の場合はマッチ除外・fail-closed) を追加する。既存の `config=<key>` (値なし) 形式は「解決値が `"true"` の場合のみマッチ」という現行セマンティクスのまま変更しないことを明記する。末尾の「Scope」箇条書きの「comparison is boolean-only; enum-valued keys ... are out of scope. Both are candidates for a `config=key:value` extension if a future Issue needs them.」という一文を、拡張が実装済みであることを反映するよう改訂する。 (→ 受け入れ条件 1)
2. `scripts/opportunistic-search.sh` の Config check gate ブロック (`# Config check gate: skip lines whose config= attribute names a` から始まるコメントと、既存の `CONFIG_KEY=$(echo "$line" | grep -oE 'config=[^ >]+' | ...)` 抽出行) を拡張する。抽出した属性値全体 (`CONFIG_ATTR`) を保持し、`:` を含むかどうかで分岐する (`case "$CONFIG_ATTR" in *:*) ... ;; *) ... ;; esac` — 同ファイル内の既存 `when=<axis>:<value>` ゲートが使う `${VAR%%:*}` / `${VAR#*:}` という最初の `:` 分割パターンを踏襲する):
   - **コロンを含む場合 (拡張形式)**: `${CONFIG_ATTR%%:*}` を key、`${CONFIG_ATTR#*:}` を value とする。key・value の両方を `case` の glob パターン `""|*[!A-Za-z0-9._-]*)` (`get-config-value.sh` 自身の KEY サニタイズと同一の文字集合・同一の実装方式 — glob マッチであり正規表現として解釈しない) で検証し、いずれか一方でも空または許可文字集合外の文字を含む場合は `continue` でその AC 行を除外する (fail-closed)。両方が有効な場合のみ既存と同じ `"${SCRIPT_DIR}/get-config-value.sh" "$CONFIG_KEY" "false"` 呼び出しで key を解決し、小文字化した戻り値と小文字化した value を文字列比較する。一致すれば残し、不一致なら `continue` で除外する。
   - **コロンを含まない場合 (既存形式)**: 現行の実装 (`get-config-value.sh` の戻り値が `"true"` と一致する場合のみ残す) を完全に維持し、分岐や比較ロジックを変更しない。
   併せてファイル冒頭のヘッダーコメント (`` `config=<key>` gates event-mode matches on .wholework.yml validity: when a `` から始まる段落) に新形式の説明を追記する。 (→ 受け入れ条件 2, 3, 4, 5)
3. (after 2) `tests/opportunistic-search.bats` に新規 `@test` を追加する。既存の `config gate: enabled config key includes the issue` (L350) と同じパターン — `MOCK_ISSUE_BODY_<N>` に observation AC 行、`WHOLEWORK_CONFIG_PATH` で一時 `.wholework.yml` を指す — を踏襲し、(a) `.wholework.yml` に `auto-stop-at: verify` を書いた状態で AC 行 `config=auto-stop-at:verify` がマッチすること、(b) `.wholework.yml` に `auto-stop-at: merge` を書いた状態で同じ AC 行がマッチしない (除外される) こと、(c) value 部分が許可文字集合外の文字を含む場合 (例: `config=auto-stop-at:foo/bar`) にマッチが除外される (fail-closed) ことを検証する。既存の `config gate: *` 3 テスト (L350-388、`config=some-flag` 形式) は無変更のまま green を維持することを確認する。`bats tests/opportunistic-search.bats` を実行し、既存 + 新規テストすべてが green であることを確認する。 (→ 受け入れ条件 6, 7)
4. `modules/verify-classifier.md` § "observation Type: Event Values and Syntax" の `config=<key>` 段落 (`` **`config=<key>` for setting-dependent observation conditions**`` から始まる段落、L53-70 付近) に `config=<key>:<value>` 形式を追記する。「`<key>` must be a flat kebab-case key or a single-level nested key in block format ... the comparison is boolean-only (`true`/`false`); enum-valued keys (e.g. `auto-stop-at`) are out of scope for `config=`.」という一文を、enum キーが `config=<key>:<value>` 形式でサポートされるようになったことを反映して改訂する。 (→ 受け入れ条件 8)

## Verification

### Pre-merge

- <!-- verify: grep -n "config=<key>:<value>" modules/observation-trigger.md --> `modules/observation-trigger.md` § "Condition Check Gate (`config=`)" が `config=<key>:<value>` 形式のマッチング仕様 (キーと値への分割方法、比較方法) を定義し、既存の `config=<key>` (値なし) 形式との後方互換セマンティクスを明記している
- <!-- verify: rubric "scripts/opportunistic-search.sh の config= 処理が config=<key>:<value> 形式 (コロンを含む場合) を key と value に分割し、get-config-value.sh で解決した値と value 部分を比較してマッチ判定していることがコード上確認できる" --> `scripts/opportunistic-search.sh` が `config=<key>:<value>` 形式 (コロンを含む `config=` 属性値) を key 部分と value 部分に分割し、`get-config-value.sh` の戻り値と value 部分を比較してマッチ判定している
- <!-- verify: rubric "config=key (値なし) 形式が従来どおり get-config-value.sh の戻り値が \"true\" に解決する場合のみマッチするという後方互換セマンティクスが、実装とテストの双方で保証されている" --> 既存の `config=key` (値なし) 形式が従来どおり「`true` に解決する場合のみマッチ」として動作することが保たれている
- <!-- verify: rubric "config= の value 部分に get-config-value.sh のキー制約 ([A-Za-z0-9._-]) と同等のサニタイズが適用され、free-text が正規表現メタ文字として解釈されないことがコード上確認できる" --> `value` 側に `get-config-value.sh` のキー制約と同等のサニタイズ (`[A-Za-z0-9._-]`) が適用され、free-text が正規表現として解釈されない
- <!-- verify: rubric "config=key:value の value がサニタイズ不適合または記法不正の場合、opportunistic-search.sh がそのAC行を除外 (fail-closed) することがコード上確認できる" --> サニタイズ不適合の value や記法不正 (コロンの位置不正など) を検出した場合、マッチを除外する (fail-closed) 挙動になっている
- <!-- verify: grep -n "auto-stop-at" tests/opportunistic-search.bats --> `tests/opportunistic-search.bats` に `config=auto-stop-at:verify` 形式のマッチ / 非マッチと、既存 `config=always-pr` 形式の後方互換を検証する新規テストケースが追加されている
- <!-- verify: command "bats tests/opportunistic-search.bats" --> `tests/opportunistic-search.bats` の全テスト (既存 + 新規) が green である
- <!-- verify: grep -rn "config=<key>:<value>" docs/guide/ modules/verify-classifier.md --> `docs/guide/customization.md` または `modules/verify-classifier.md` の observation AC 記法説明が新形式を反映している

### Post-merge

- 拡張後のコードを確認し、retire した #783 を `config=auto-stop-at:merge` 相当のゲート付き observation として再型付けし直せるかを判断する (`verify-type: manual`)

## Notes

- **Auto-Resolved Ambiguity Points**: 本 Issue は `/issue` フェーズ (非対話モード) で以下 3 件の曖昧性解決を完了済みで、Issue 本文の「Auto-Resolved Ambiguity Points」セクションに記録されている。SPEC_DEPTH=light のため Step 7 (Ambiguity Resolution) は実行せず、この決定をそのまま設計に採用した:
  - コロン分割方法 → 最初の `:` で分割 (`when=` ゲートと同じ方針)
  - value 側のサニタイズ文字集合 → `get-config-value.sh` の KEY 制約と同じ `[A-Za-z0-9._-]`
  - 不正な value のフェイルモード → fail-closed (既存の `config=<key>` 形式自体が fail-closed 設計であるため一貫性を優先。姉妹機構 `when=` の fail-open とは意図的に区別)
- **Post-merge AC の `verify-type: manual` 維持**: Consumed Comments (下記) に記載の Issue Retrospective で「マージ後のコードを読めば即座に判断できる」性質と判断され `observation` から `manual` へ再分類済み。`modules/verify-patterns.md` §11 (Manual AC Quick Reference) の置換候補表と照合したが、#783 への再型付け可否判断は別 Issue に対する横断的な判断であり、`rubric`/`file_exists` 等の機械的検証には馴染まないため `manual` のまま維持する。
- **Pre-merge Verification 項目数 (8件) について**: light depth のシンプリシティ・ガイドライン (目安 5 件) を超えるが、Issue 本文の Pre-merge AC は `/issue` フェーズの Triage AC audit で常時 PASS パターン (Pattern 2) 4 件の修正と追加 2 件の精査を経て既に絞り込まれたリストである (Consumed Comments 参照)。Verify command sync rule (Issue 本文からの verbatim コピー) を優先し、追加の圧縮は行っていない。Implementation Steps 側は 4 ステップに集約し目安の 5 件以内に収めた。
- **ドキュメント同期確認済み (変更不要)**: `docs/guide/customization.md`・`docs/workflow.md`・`README.md`/`README.ja.md` を `config=`/`observation-trigger` で grep し、いずれも本 Issue が拡張する記法を記述していないことを確認した (変更不要)。
- **Steering Docs sync candidate からの除外 (Exclusions)**: `docs/reports/observation-ac-audit-a.md`・`docs/reports/manual-ac-retype-a.md`・`docs/sessions/**/session.md` は `config=`/`observation-trigger.sh` を含むが、いずれも過去の監査・セッションの実行記録 (historical record) であり変更対象外。
- **文字列存在確認 (pre-implementation)**: Pre-merge AC の `grep` 系検証対象文字列 (`config=<key>:<value>` in `modules/observation-trigger.md` / `docs/guide/` / `modules/verify-classifier.md`、`auto-stop-at` in `tests/opportunistic-search.bats`) はいずれも実装前時点で対象ファイルに存在しないことを確認済み — 実装後に FAIL→PASS へ正しく遷移する (常時 PASS パターンではない)。
- **allowed-tools impact chain check**: `modules/observation-trigger.md`・`modules/verify-classifier.md` への変更は新規 `scripts/*.sh` 呼び出しを一切追加しない (既存の `get-config-value.sh` 参照のみ) ため、lightweight gate により allowed-tools 追従は不要と判定した。

## Consumed Comments

| login | authorAssociation | trust tier | 意図 | URL |
|-------|-------------------|-----------|------|-----|
| saito | MEMBER | first-class | Issue Retrospective — Triage AC audit が指摘した常時 PASS パターン 4 件の修正、Auto-Resolve Log (曖昧性解決 3 件)、Post-merge AC の `manual` 再分類の判断根拠を記録 | https://github.com/saitoco/wholework/issues/1243#issuecomment-5305371884 |

No new comments since last phase (cutoff: 2026-08-16T02:57:29Z, `phase/ready` label assignment).

## Code Retrospective

### Deviations from Design
- N/A — Implementation Steps 1-4 を Spec の記述どおりに実施した。

### Design Gaps/Ambiguities
- N/A — Spec の Auto-Resolved Ambiguity Points (コロン分割方法、サニタイズ文字集合、フェイルモード) がそのまま実装に適用でき、追加の曖昧性は発生しなかった。

### Rework
- N/A — 手戻りなし。

### Test Results
- `bats tests/opportunistic-search.bats`: 61/61 green (既存58 + 新規3)。
- フルスイート `bats --jobs 18 tests/` (Behavioral Change Detection により起動 — `tests/check-known-events-firing.bats` が `scripts/opportunistic-search.sh` を参照): 1 件の pre-existing 不整合 (`tests/code.bats` "Step 10 Patch route branch-scoped CI AC exclusion covers both patch and operate route") を検出。`main` ブランチで再現確認済みで本 Issue の変更と無関係。フォローアップ #1377 を起票。

### Follow-up Issues
- #1377 — `tests/code.bats` の stale assertion 修正 (本 Issue のスコープ外、フルスイート実行時に検出)

## Phase Handoff
<!-- phase: merge -->

### Key Decisions
- Pre-merge AC gate: `check-pre-merge-ac.sh` で unchecked_count=0、review-incomplete-fallback チェックも該当なしのためゲート通過。
- PR #1378 は `mergeable=true, reason=clean` (CI success, review approved) だったため、Step 3 (Resolve Conflicts) はスキップし直接 Squash Merge を実行した。
- `--non-interactive` モードで実行 (自律実行フロー)。

### Deferred Items
- Post-merge AC (`verify-type: manual`) — #783 を `config=auto-stop-at:merge` 相当で再型付けできるかの判断は post-merge (`/verify`) に委ねる。

### Notes for Next Phase
- `/verify 1243` で post-merge AC (#783 再型付け判断) を実施すること。
- フォローアップ #1377 (`tests/code.bats` の pre-existing 不整合) は本 Issue のスコープ外のまま。

## review retrospective

### Spec vs. implementation divergence patterns
N/A — Spec の Implementation Steps 1-4 と PR diff (`modules/observation-trigger.md`・`scripts/opportunistic-search.sh`・`tests/opportunistic-search.bats`・`modules/verify-classifier.md`) の間に構造的な乖離は見られなかった。分割方法 (最初の `:`)・サニタイズ文字集合 (`[A-Za-z0-9._-]`)・フェイルモード (fail-closed) はいずれも Spec の Auto-Resolved Ambiguity Points どおりに実装されている。

### Recurring issues
N/A — Copilot/Claude Code Review/CodeRabbit いずれも未設定 (`.wholework.yml` に対応キーなし) のため Step 7 は全体スキップ。review-light の4観点および Parser/Validator Edge Case Pre-check (実コード実行によるエッジケース検証) のいずれからも指摘は無く、再発パターンと呼べる論点はなかった。

### Acceptance criteria verification difficulty
Pre-merge AC 8件中、`grep` 系3件は機械的に確定 (`command` および `grep` verify command が的確)。`rubric` 系4件 (config= 処理のkey/value分割・後方互換・サニタイズ・fail-closed) はコード上の実装確認で全てPASSと判定できたが、いずれも「コード上確認できる」という記述に留まり、実行時の振る舞いまでは rubric 自体は保証しない。本レビューでは Parser/Validator Edge Case Pre-check により実際にコードを実行して補完検証したため UNCERTAIN は発生しなかったが、rubric verify command の設計として実行検証を必須化しない限り、将来同種の PR では静的読解のみで PASS 判定されるリスクが残る点は留意事項として記録する。
