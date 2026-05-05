# Issue #385: config: permission-mode のデフォルトを auto に変更

## Overview

`.wholework.yml` の `permission-mode` のデフォルト値を `bypass`（`--dangerously-skip-permissions`）から `auto`（`--permission-mode auto`）へ反転する。コード側の fallback 値（`modules/detect-config-markers.md` と 7 つの `scripts/*.sh`）と関連ドキュメント（SECURITY.md / README.md / docs/workflow.md / docs/tech.md / docs/guide/customization.md / docs/environment-adaptation.md）および日本語 mirror（docs/ja/*）を一括で新デフォルトに合わせる。SECURITY.md には migration note を追加し、Pro 等 auto 非対応プランのユーザーに対しては #397 で merged 済みの lazy-catch 診断ヘルパー（`scripts/handle-permission-mode-failure.sh`）が runtime で remediation を案内することを明示する。

## Changed Files

- `modules/detect-config-markers.md`: line 46 の marker definition table セルを `\`"bypass"\`` → `\`"auto"\``、line 89 の Output Format ブロックの `(default: "bypass")` → `(default: "auto")` に変更
- `scripts/run-code.sh` (line 49): `get-config-value.sh permission-mode bypass` → `permission-mode auto`、トレーリング `|| echo bypass` → `|| echo auto`。bash 3.2+ 互換（既存パターン値差し替えのみ）
- `scripts/run-spec.sh` (line 40): 同上のパターン。bash 3.2+ 互換
- `scripts/run-review.sh` (line 18): 同上のパターン。bash 3.2+ 互換
- `scripts/run-merge.sh` (line 16): 同上のパターン。bash 3.2+ 互換
- `scripts/run-verify.sh` (line 37): 同上のパターン。bash 3.2+ 互換
- `scripts/run-issue.sh` (line 24): 同上のパターン。bash 3.2+ 互換
- `scripts/spawn-recovery-subagent.sh` (line 133): 同上のパターン。bash 3.2+ 互換（`run-*.sh` と同じ permission-mode consumer）
- `SECURITY.md`: §"Permission Modes" を再構成。`### Choosing a Mode` の YAML 例で auto を default に並べ替え、`### bypass mode (default)` 見出しを `### bypass mode (legacy)` 等に変更（auto セクションに `(default)` を移す）。新規 `### Migration` 見出しを `## Permission Modes` セクション内に追加し、(a) `bypass` を継続したいユーザー向けの `.wholework.yml` 設定方法、(b) auto 非対応プラン（Pro 等）ユーザー向けに #397 の `scripts/handle-permission-mode-failure.sh` が stderr 診断と remediation を runtime で表示することを記述
- `README.md` (line 55): security description を flip。"uses `--dangerously-skip-permissions` by default, or `--permission-mode auto` when ..." → "uses `--permission-mode auto` by default, or `--dangerously-skip-permissions` when `permission-mode: bypass` is set in `.wholework.yml`"
- `docs/workflow.md` (line 101): `/auto` 説明を flip。"By default uses `--dangerously-skip-permissions`; set `permission-mode: auto` ..." → "By default uses `--permission-mode auto`; set `permission-mode: bypass` in `.wholework.yml` to use `--dangerously-skip-permissions` instead"
- `docs/tech.md` (line 50): `/auto` skill 説明の括弧書きを flip。"(`--dangerously-skip-permissions` by default; `--permission-mode auto` when ...)" → "(`--permission-mode auto` by default; `--dangerously-skip-permissions` when `permission-mode: bypass` is set in `.wholework.yml`)"
- `docs/guide/customization.md`:
  - lines 49-52 の YAML 例コメントを書き換え。"# Permission mode for /auto subprocess (default: bypass)" → "(default: auto)"。続くコメント行（auto / bypass の説明順）を auto-first に並べ替え、`bypass` には "legacy / opt-out" 等の表現を追加
  - line 86 の Available Keys 表の Default 列セル `\`"bypass"\`` → `\`"auto"\``、Description 列の説明順（auto / bypass）も整合
- `docs/environment-adaptation.md` (line 32): `.wholework.yml` 例の `permission-mode: bypass` → `permission-mode: auto`、コメントは `# Permission mode for /auto subprocess (default: auto, legacy bypass)` 等
- `docs/ja/workflow.md` (line 94): docs/workflow.md の変更を日本語訳して反映（`permission-mode: auto` をデフォルトとした記述に変更）
- `docs/ja/tech.md` (line 40): docs/tech.md の `/auto` skill 説明を日本語で flip
- `docs/ja/guide/customization.md` (lines 44-46, 80): docs/guide/customization.md の YAML 例コメント＋表セル更新を日本語版に同期

## Implementation Steps

**Step recording rules:** 整数 Step、依存関係（"after N" / "parallel with N"）、acceptance criteria への mapping を併記。挿入位置は近接コード文脈で指定。

1. `modules/detect-config-markers.md` の marker definition table（line 46）と Output Format ブロック（line 89）の 2 箇所で `bypass` → `auto` を置換（→ acceptance criteria: `modules/detect-config-markers.md` 関連 2 件）
2. (parallel with 1) 7 scripts の `get-config-value.sh permission-mode bypass`（および `|| echo bypass`）を `permission-mode auto`（および `|| echo auto`）に置換: `scripts/run-{code,spec,review,merge,verify,issue}.sh` および `scripts/spawn-recovery-subagent.sh`。各 script の `permission-mode` を読む 1 行のみが対象、それ以外（`PERMISSION_FLAG` 分岐ロジックや `_PERM_LABEL` の文字列など）は変更しない（→ acceptance criteria: scripts 関連 7 件）
3. (after 1, 2) `SECURITY.md` の `## Permission Modes (\`/auto\`)` セクションを再構成: (a) `### Choosing a Mode` の YAML サンプルで auto-first・default 表記を移動、(b) `### bypass mode (default)` 見出しを `### bypass mode (legacy)` 系に変更、auto 側を `### auto mode (default)` に昇格、(c) 新規サブ見出し `### Migration` を追加し、`bypass` 維持手順と #397 の lazy-catch helper（`scripts/handle-permission-mode-failure.sh`）による Pro プラン runtime 診断への言及を含める（→ acceptance criteria: SECURITY.md 関連 4 件）
4. (after 3) `README.md` line 55 の security description を flip。"uses `--dangerously-skip-permissions` by default, or `--permission-mode auto` when ..." を auto-first に書き換え、bypass を opt-in として表現（→ acceptance criteria: `README.md` 関連 1 件）
5. (parallel with 4) `docs/workflow.md` line 101 と `docs/tech.md` line 50 の `/auto` skill 説明を auto-first へ書き換え（→ acceptance criteria: workflow.md / tech.md 各 1 件）
6. (parallel with 4, 5) `docs/guide/customization.md` の YAML 例コメント（lines 49-52）と Available Keys 表（line 86）を更新。表のセル値は `\`"auto"\``、コメントは `(default: auto)`（→ acceptance criteria: customization.md 関連 2 件）
7. (parallel with 4, 5, 6) `docs/environment-adaptation.md` line 32 の `.wholework.yml` 例の値を `permission-mode: auto` に変更し、コメントを auto-first に整合（→ acceptance criteria: environment-adaptation.md 関連 1 件）
8. (after 4, 5, 6, 7) 日本語 mirror を同期: `docs/ja/workflow.md`, `docs/ja/tech.md`, `docs/ja/guide/customization.md` の該当箇所（permission-mode 記述）を日本語訳で flip。translation-workflow.md に従い、`docs/*.md` を更新したら同 PR 内で `docs/ja/` を sync する（→ acceptance criteria: rubric "docs/ja/ 配下の該当翻訳が新デフォルトを反映している"）
9. (after 1-8) `bats tests/` を実行し、全テストが PASS することを確認。setup() で `permission-mode: bypass` を明示する既存テスト（`run-{code,spec,review,merge,verify,issue}.bats`）はテスト fixture が明示設定のため、default 反転で挙動変化しない見込み。`tests/handle-permission-mode-failure.bats` も diagnostic message を変更しないため影響なし（→ acceptance criteria: `bats tests/` 1 件）

## Verification

### Pre-merge

- <!-- verify: file_contains "modules/detect-config-markers.md" "default: \"auto\"" --> `modules/detect-config-markers.md` のマーカー定義表で `permission-mode` のデフォルトが `"auto"` に更新されている
- <!-- verify: file_contains "modules/detect-config-markers.md" "default: \"auto\")" --> `modules/detect-config-markers.md` の Output Format 説明でも `PERMISSION_MODE` のデフォルトが `"auto"` に更新されている
- <!-- verify: file_contains "scripts/run-code.sh" "get-config-value.sh permission-mode auto" --> `scripts/run-code.sh` の `get-config-value.sh` 呼び出しで fallback 値が `auto` に更新されている
- <!-- verify: file_contains "scripts/run-spec.sh" "get-config-value.sh permission-mode auto" --> `scripts/run-spec.sh` の fallback 値が `auto` に更新されている
- <!-- verify: file_contains "scripts/run-review.sh" "get-config-value.sh permission-mode auto" --> `scripts/run-review.sh` の fallback 値が `auto` に更新されている
- <!-- verify: file_contains "scripts/run-merge.sh" "get-config-value.sh permission-mode auto" --> `scripts/run-merge.sh` の fallback 値が `auto` に更新されている
- <!-- verify: file_contains "scripts/run-verify.sh" "get-config-value.sh permission-mode auto" --> `scripts/run-verify.sh` の fallback 値が `auto` に更新されている
- <!-- verify: file_contains "scripts/run-issue.sh" "get-config-value.sh permission-mode auto" --> `scripts/run-issue.sh` の fallback 値が `auto` に更新されている
- <!-- verify: file_contains "scripts/spawn-recovery-subagent.sh" "get-config-value.sh permission-mode auto" --> `scripts/spawn-recovery-subagent.sh` の fallback 値が `auto` に更新されている
- <!-- verify: section_contains "SECURITY.md" "### Choosing a Mode" "permission-mode: auto" --> `SECURITY.md` §Choosing a Mode で `auto` が default として提示されている
- <!-- verify: section_contains "SECURITY.md" "### Choosing a Mode" "default" --> `SECURITY.md` §Choosing a Mode の default 表記が `auto` 側に移っている
- <!-- verify: section_contains "SECURITY.md" "## Permission" "Migration" --> `SECURITY.md` の Permission セクションに既存ユーザー向け migration note が追加されている
- <!-- verify: rubric "SECURITY.md の migration note セクションが、auto 非対応プラン（Pro 等）ユーザーに対して #397 で導入された scripts/handle-permission-mode-failure.sh による runtime 診断が remediation を自動表示することに言及している" --> migration note が #397 の lazy-catch 診断との関係を説明している
- <!-- verify: file_contains "README.md" "--permission-mode auto" --> `README.md` の security description が新デフォルト（auto）を反映している
- <!-- verify: file_contains "docs/workflow.md" "permission-mode auto" --> `docs/workflow.md` の `/auto` 説明が新デフォルトを反映している
- <!-- verify: file_contains "docs/tech.md" "permission-mode auto" --> `docs/tech.md` の `/auto` skill 説明が新デフォルトを反映している
- <!-- verify: file_contains "docs/guide/customization.md" "default: auto" --> `docs/guide/customization.md` の YAML 例コメントのデフォルト値が `auto` に更新されている
- <!-- verify: rubric "docs/guide/customization.md の Available Keys 表で permission-mode 行の Default 列の値が \"auto\" に更新されている" --> Available Keys 表の Default 列が `auto` に更新されている（表のセル値）
- <!-- verify: file_contains "docs/environment-adaptation.md" "permission-mode: auto" --> `docs/environment-adaptation.md` の `.wholework.yml` 例で `permission-mode: auto` がデフォルト想定として記載されている
- <!-- verify: rubric "docs/ja/ 配下の該当翻訳（workflow.md / tech.md / guide/customization.md）が新デフォルトを反映している、もしくは followup Issue に切り出されている旨が PR 本文に明記されている" --> 日本語翻訳ドキュメントの整合が確保されている
- <!-- verify: command "bats tests/" --> 全 bats テストが PASS する

### Post-merge

- `permission-mode` 未設定の `.wholework.yml` で `/auto` を起動し、subprocess コマンドラインに `--permission-mode auto` が渡ることを確認する
- 既存ユーザーが `bypass` を継続利用したい場合の明示設定手順（`.wholework.yml` に `permission-mode: bypass` を追記）が SECURITY.md / README.md を読んで理解できることを確認する
- Pro プラン環境（または `permission-mode: auto` を直接呼ぶ mock）で `permission-mode` 未設定のまま `/auto N` を実行し、#397 の lazy-catch 診断が stderr に表示され、`permission-mode: bypass` への切り替え手順が案内されることを確認する

## Tool Dependencies

allowed-tools 追加は不要（既存の `Edit` / `Read` / `Bash` のみで完結）。

### Bash Command Patterns
- なし（テスト実行は既存の `bats tests/` を `command` verify hint 経由で行うのみ）

### Built-in Tools
- `Read`, `Edit`: ファイル読み書き
- `Bash`: bats 実行・git 操作

### MCP Tools
- なし

## Notes

### translation-workflow.md との conflict 解決（Step 6 conflict detection）

Issue body の Auto-Resolved Ambiguity Points には「本 Issue では英語原文のみを更新対象とし、`docs/ja/*` の該当翻訳は `/doc translate` の定常フローで処理する」と auto-resolve されていたが、`docs/translation-workflow.md` は「skills が top-level `docs/*.md` を変更したら同 PR 内で `docs/ja/` mirror を sync する」と義務付けている。本 Spec では translation-workflow.md を優先し、`docs/ja/workflow.md` / `docs/ja/tech.md` / `docs/ja/guide/customization.md` を同 PR で sync する方針に変更した。

- `docs/ja/environment-adaptation.md` には `permission-mode` への言及が無いため content 変更なし
- `README.ja.md` は `README.{lang}.md` として `/doc translate {lang}` で再生成される運用（structure.md line 70）のため、本 PR の対象外とし、後続の `/doc translate ja` で同期させる
- 既存 Issue body の rubric "docs/ja/ 配下の該当翻訳... もしくは followup Issue に切り出されている旨が PR 本文に明記されている" は permissive で、本方針でも PASS する。Spec 側で具体ファイルを Changed Files に明示することで実装上の見落としを防ぐ

## review retrospective

### Spec vs. 実装の乖離パターン

特筆なし。全 accept criteria はテスト失敗を除いてすべて PASS。実装変更はシンプルなフォールバック値の差し替えのみで、乖離は発生していない。

### 繰り返し問題

`WHOLEWORK_SCRIPT_DIR` をモック化するテスト（`run-spec.bats`）が `get-config-value.sh` をモックしておらず、フォールバック値に依存していた。フォールバック値変更時に直ちに壊れるテストパターン。同パターンが他の `run-*.bats` に存在しないことを確認済み（他のテストは `WHOLEWORK_SCRIPT_DIR` を上書きしていないか、`.wholework.yml` に実 `get-config-value.sh` からアクセスできる）。今後スクリプトのフォールバック値を変更する場合は `WHOLEWORK_SCRIPT_DIR` モック利用テストの `get-config-value.sh` モック有無を確認すること。

### verify command 品質

verify commands はすべて適切に定義されており、UNCERTAIN は 1 件（`command "bats tests/"` → safe mode, CI reference fallback）のみで CI で FAIL が検出できた。`bats tests/` の CI fallback は有効に機能した。

### `handle-permission-mode-failure.sh` の診断メッセージは変更不要

既存の remediation 文言（`switch to bypass by adding to .wholework.yml: permission-mode: bypass`）は default 反転後も正しい案内のまま。helper の trigger 条件（`PERMISSION_MODE == "auto"` AND `exit_code != 0` AND `elapsed <= 30`）は default 値とは独立で、本 Issue でメッセージ変更は不要。

### 既存 bats テストへの影響

`tests/run-{code,spec,review,merge,verify,issue}.bats` は `setup()` で `echo "permission-mode: bypass" > "$BATS_TEST_TMPDIR/.wholework.yml"` と明示設定するため、default 反転の影響を受けない。`tests/handle-permission-mode-failure.bats` は helper 単体テストで diagnostic message を直接 assert しているため、メッセージ未変更により影響なし。`tests/spawn-recovery-subagent.bats` は `get-config-value.sh` を mock で hardcode `bypass` 返却にしているため、script 側の fallback 値変更とは独立で影響なし。

なお `@test "success: --dangerously-skip-permissions is passed"` 等の test name は「default 動作」を示唆しないため reframe 不要（test 内で permission-mode を bypass に明示設定しており、test name は output flag を示している）。

### 弱い verify check の保留

Issue body から verbatim copy した `section_contains "SECURITY.md" "### Choosing a Mode" "default"` は default 反転前後どちらの状態でも word "default" が当該セクションに登場するため、flip 方向の検証としては弱い。同様に `section_contains "### Choosing a Mode" "permission-mode: auto"` も flip 前から auto 例示が含まれており弱い。Spec の verify command sync rule（Issue body から verbatim copy）に従い変更しない。実装側は SECURITY.md restructure 時に default 表記が auto セクションに移動することを Step 3 の手順で担保する。

### 反転対象 fallback 値の網羅性

`grep -rn "PERMISSION_MODE\|permission-mode" scripts/` で `permission-mode bypass` パターンの fallback を持つ script を全数列挙し、`scripts/run-*.sh` 6 ファイル + `scripts/spawn-recovery-subagent.sh` の計 7 ファイルが対象であることを確認済み。Issue body 旧版で抜けていた `spawn-recovery-subagent.sh` も Acceptance Criteria に含めた。

### Auto-Resolved Ambiguity Points (in spec phase)

Spec 作成時の自動解決:

1. **SECURITY.md の `### Migration` 配置**: `## Permission Modes` 直下のサブ見出しとして配置（top-level `## Migration` ではなく）。理由: migration はモード選択の一部であり、上位コンテキストを保つ方が読み手の流れが自然。
2. **`### bypass mode` 見出しの新表記**: `### bypass mode (legacy)` を採用。alternative の `(opt-out)` よりも legacy が「過去 default だった」歴史性を伝えやすく、product.md vision との整合性も高い。
3. **README.md の 1 行 description における auto / bypass の語順**: auto を先頭に配置し、bypass を opt-in として後置。`(line 55: 1 sentence)` 単一行のため副節として処理。

## spec retrospective

### Minor observations

- Issue body の auto-resolved 「翻訳ドキュメントは `/doc translate` に委ねる」と `docs/translation-workflow.md`「skill 実行時に `docs/ja/` を sync する義務」が衝突していた。Spec 段階で conflict detection が機能し、translation-workflow.md 優先に解決して Changed Files に ja mirror を追加した。Issue refinement 段階でこの conflict が拾えていれば手戻りが無かった点は学び。
- `section_contains "SECURITY.md" "### Choosing a Mode" "default"` 等の verify command は flip 前後で word "default" がどちらにも登場するため、flip 方向の検証としては弱い。verbatim copy ルール優先で本 Spec では維持したが、より厳密な検証が必要な場合は rubric への置き換えを検討する余地がある。

### Judgment rationale

- **`scripts/spawn-recovery-subagent.sh` を反転対象に含める**: `run-*.sh` と同じ `get-config-value.sh permission-mode <fallback>` パターンで permission-mode を読む consumer として動作整合上含めるべきと判断。Issue body 旧版で抜けていたが、Issue refinement round 2 で Acceptance Criteria に明示追加済み。
- **`handle-permission-mode-failure.sh` のメッセージは未変更**: helper の trigger 条件（`PERMISSION_MODE == "auto"` AND `exit_code != 0` AND `elapsed <= 30`）は default 値とは独立で、remediation 文言「switch to bypass」は default 反転後も正しい案内のまま。touch しないことで bats test（`tests/handle-permission-mode-failure.bats`）への影響もゼロ。
- **`docs/ja/environment-adaptation.md` を Changed Files から除外**: `permission-mode` への言及が無いため content 変更不要と判定（grep で確認済み）。translation-workflow.md の sync 義務は「内容変更があれば」が前提で、無変更ファイルまで touch は不要。
- **`README.ja.md` を本 PR 対象外**: structure.md line 70 で `README.{lang}.md` は `/doc translate {lang}` 生成物と定義されており、英語原文に追随する hand-maintenance 対象では無い。本 PR merge 後に `/doc translate ja` で同期させる運用に従う。

### Uncertainty resolution

- **`SECURITY.md` 新 `### Migration` サブ見出しの位置**: `## Permission Modes` 直下に配置（top-level `## Migration` ではなく）。`section_contains "SECURITY.md" "## Permission" "Migration"` の verify が PASS するためには `## Permission Modes` セクション内に "Migration" 文字列が含まれる必要があり、これを満たす配置として確定。
- **`docs/guide/customization.md` 表のセル値検証**: 既存の `file_contains "default: auto"` は YAML 例コメント（line 49）のみを捕捉し、Available Keys 表（line 86）の `\`"auto"\`` セル値は捕捉できない。Issue body 側で rubric を追加済みのため、この弱点は補完されている。
- **bats テストへの影響**: `tests/run-*.bats` は setup() で permission-mode を明示設定するため default 反転に非依存。`tests/handle-permission-mode-failure.bats` は diagnostic message を assert するため helper を touch しない方針で影響ゼロ。`tests/spawn-recovery-subagent.bats` は get-config-value.sh モックで bypass 返却を hardcode しており影響ゼロ。Step 9 の `bats tests/` で全数確認する。
