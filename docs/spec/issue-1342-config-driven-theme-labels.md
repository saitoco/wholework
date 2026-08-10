# Issue #1342: setup-labels: theme label カタログを .wholework.yml 駆動でプロジェクト固有化

## Consumed Comments

- saito / MEMBER / first-class / ⚠️ Triage AC audit: verify command に問題があります / https://github.com/saitoco/wholework/issues/1342#issuecomment-5245554676
- saito / MEMBER / first-class / ## Issue Retrospective / https://github.com/saitoco/wholework/issues/1342#issuecomment-5245573333

反映内容:

- 1件目 (Triage AC audit): AC4 の `command "bats tests/setup-labels.bats"` 単独形は、実装前の `main` でも既存20件が全 pass するため常時 PASS になるという指摘。指示どおり「新規テスト名の存在確認 (`file_contains` × 2) + 全テスト pass の回帰保護 (`command`)」の2段構えに Issue 本文 AC4 を更新済み。新規テスト名は実装前に0件一致であることを確認済み (`grep -c themes tests/setup-labels.bats` → 0)。
- 2件目 (Issue Retrospective): `themes:` 未定義時にフォールバック作成しないというポリシー決定と、wholework 自身の5テーマを特別扱いせず同じ経路で移行する方針を確認。本 Spec はこの決定をそのまま前提としている。

## Overview

`scripts/setup-labels.sh` の `ALWAYS_LABELS` にハードコードされている wholework 自身のドッグフーディング用 theme label 5件 (`theme/observability`, `theme/ac-quality`, `theme/concurrency`, `theme/verify-backlog`, `theme/batch-orchestration`) を、`.wholework.yml` の `themes:` キー駆動に置き換える。

- `themes:` が定義されていれば、そこから `theme/{name}` ラベルを description 付きで作成する
- `themes:` が未定義なら theme label を一切作成しない (既定のフォールバック作成は廃止)
- wholework 自身の5テーマは本リポジトリの `.wholework.yml` に明示移行し、他プロジェクトと同じ経路を通す
- `/triage` Step 6a の分類ロジック (`gh label list` による動的取得 + `description` マッチング) は無改修

## Changed Files

- `.wholework.yml`: `themes:` block mapping を新規追加し、既存5テーマ (name + description) を移行
- `scripts/setup-labels.sh`: `ALWAYS_LABELS` から `theme/*` 5エントリを削除 / `themes:` パーサ (`THEME_LABELS` 構築) と theme label 作成ループを追加 / ヘッダコメントの Always-group 件数を 22 → 17 に更新し `theme/*` を config 駆動として記述 — bash 3.2+ 互換 (`mapfile`・連想配列を使わず、`sed -E` / `case` / 通常配列のみ)
- `tests/setup-labels.bats`: `setup()` に `export WHOLEWORK_CONFIG_PATH=/dev/null` を追加 (既存テストがリポジトリ自身の `.wholework.yml` を読み込まないようにする) / `themes:` 定義あり・なしの新規テスト2件を追加
- `docs/guide/customization.md`: [Steering Docs sync candidate] `.wholework.yml` サンプル YAML と Available Keys 表 (SSoT) に `themes:` 行を追加
- `docs/ja/guide/customization.md`: [Steering Docs sync candidate] 上記の日本語ミラー同期 (`scripts/check-translation-sync.sh` が `docs/guide/*.md` を同期対象に含む)
- `docs/tech.md`: [Steering Docs sync candidate] Wholework Label Management の Label Groups 表 (Always 22 → 17、`theme/*` を行から除外し config 駆動の行/注記を追加)、SSoT 記述と Modification Rules に `theme/*` の例外を追記
- `docs/ja/tech.md`: [Steering Docs sync candidate] 上記の日本語ミラー同期
- `docs/product.md`: [Steering Docs sync candidate] Theme-driven backlog consumption の「theme カタログの実体は GitHub label 側が SSoT」記述を、seed カタログは `.wholework.yml` `themes:` 側である旨に更新
- `docs/ja/product.md`: [Steering Docs sync candidate] 上記の日本語ミラー同期
- `modules/label-conventions.md`: [Steering Docs sync candidate] `theme/*` 行および "Relation to setup-labels.sh" 節に、`theme/*` の定義元が `.wholework.yml` `themes:` (project-dependent) である旨を追記
- `skills/triage/SKILL.md`: [Steering Docs sync candidate] Step 6a の「分類基準は `description` (see `scripts/setup-labels.sh`)」の出所参照を `.wholework.yml` の `themes:` に更新

変更不要 (grep で確認済み):

- `docs/structure.md:261` / `docs/ja/structure.md:253`: `scripts/setup-labels.sh — create GitHub labels for workflow` の一行説明のみで、記述は変更後も正確
- `docs/workflow.md:186`: 「ラベルを再作成するには `scripts/setup-labels.sh` を手動実行」の記述で、挙動は不変
- `docs/guide/workflow.md:189` / `docs/ja/guide/workflow.md:185`: `/auto --batch --until "label:theme/*"` の利用例で、label 名前空間自体は不変
- `skills/auto/SKILL.md:1211`: bulk `/triage` が `theme/*` を付与する記述で、付与ロジックは無改修
- `skills/triage/SKILL.md:344,346,386,400`: theme カタログを `gh label list` で取得する記述で、取得方法は無改修
- `README.md` / `README.ja.md` / `CLAUDE.md`: `theme` / `setup-labels` の grep ヒット 0件
- `docs/migration-notes.md:417` / `docs/ja/migration-notes.md:412`: 日本語→英語移行時の履歴記録のため除外

## Implementation Steps

1. `.wholework.yml` に `themes:` block mapping を追加し、既存5テーマを `{theme-name}: "{description}"` 形式で移行する。description は `scripts/setup-labels.sh` の現行エントリの文字列をそのまま転記する (→ 受け入れ条件 5)
2. `scripts/setup-labels.sh` の `ALWAYS_LABELS` から `theme/*` 5エントリを削除し、ファイル先頭のヘッダコメントの `Always-group (22 labels): ... , theme/*` を `Always-group (17 labels): ...` (`theme/*` を除去) に更新したうえで、theme label は `.wholework.yml` の `themes:` から作成される旨をヘッダに追記する (→ 受け入れ条件 6)
3. (2 の後) `scripts/setup-labels.sh` に `themes:` パーサを追加する。`FALLBACK_LABELS` 定義の直後、`detect_issue_types()` の直前に配置する (→ 受け入れ条件 2, 3)
   - `THEME_COLOR="006B75"` を定数として定義する
   - `CONFIG_FILE="${WHOLEWORK_CONFIG_PATH:-.wholework.yml}"` で設定ファイルを解決する (`scripts/get-config-value.sh` と同一の解決規則)
   - `THEME_LABELS=()` を初期化し、`[ -f "$CONFIG_FILE" ]` のときのみ `while IFS= read -r line || [ -n "$line" ]` でパースする
   - セクション開始判定は `echo "$line" | grep -qE "^themes[[:space:]]*:[[:space:]]*(#.*)?$"`、セクション終了判定は `case "$line" in [[:space:]]*) ... ;; *) IN_THEMES=false ;; esac` (非インデント行で終了)。空行はスキップして継続する
   - 子要素行は `^[[:space:]]+[A-Za-z0-9._-]+[[:space:]]*:` にマッチする行のみ採用する (インデントされたコメント行・不正行を自然に除外する)
   - name は `sed -E "s/^[[:space:]]+([A-Za-z0-9._-]+)[[:space:]]*:.*$/\1/"`、description は最初のコロン以降を取り出したうえで inline コメント除去・末尾空白除去・前後クォート除去を行う (`get-config-value.sh` と同じ sed チェーン)
   - 結果は `THEME_LABELS+=("theme/${name}|${THEME_COLOR}|${desc}")` の形で、`ALWAYS_LABELS` と同じ `name|color|description` 形式で保持する
4. (3 の後) `scripts/setup-labels.sh` の Always-group 作成ループ直後、Fallback-group ブロックの直前に theme label 作成ループを追加する。`set -u` 下で空配列展開が失敗しないよう `for entry in "${THEME_LABELS[@]+"${THEME_LABELS[@]}"}"` の形を使い、既存の `create_label()` と `CREATED_COUNT` インクリメントをそのまま再利用する (→ 受け入れ条件 2, 3)
5. `tests/setup-labels.bats` の `setup()` に `export WHOLEWORK_CONFIG_PATH=/dev/null` を追加する。これがないと既存テストが実行時 CWD (リポジトリルート) の `.wholework.yml` を読み、Step 1 で追加した5テーマ分だけ `count_label_creates` が `count_always_labels` を超えて既存アサーションが壊れる (→ 受け入れ条件 4)
6. (5 の後) `tests/setup-labels.bats` に新規テスト2件を追加する (→ 受け入れ条件 3, 4)
   - `@test "themes: config-driven theme labels created from .wholework.yml"` — `BATS_TEST_TMPDIR` に `themes:` を含む設定ファイルを作成して `WHOLEWORK_CONFIG_PATH` で指し、`theme/{name}` が作成されること・作成総数が `count_always_labels + N` になること・description が `gh label create` 呼び出しに渡ることを検証する
   - `@test "themes: no theme labels created when themes key is absent"` — `themes:` を含まない設定ファイルを指し、`label create theme/` が1件も現れないこと・作成総数が `count_always_labels` に一致することを検証する
7. `docs/guide/customization.md` の `.wholework.yml` サンプル YAML と Available Keys 表 (SSoT) に `themes:` 行を追加し、block mapping 形状・未定義時は theme label を作成しないこと・色は固定であることを記述する。あわせて `docs/ja/guide/customization.md` を同期する (→ 受け入れ条件 1)
8. `docs/tech.md` の Wholework Label Management 節を更新する: Label Groups 表の Always 行を 17 にして `theme/*` を除き、`theme/*` を `.wholework.yml` の `themes:` 駆動 (project-dependent) として記述する行/注記を追加、SSoT 記述と Modification Rules に `theme/*` が `setup-labels.sh` ハードコードの例外である旨を追記する。あわせて `docs/ja/tech.md` を同期する (→ 受け入れ条件 7)
9. `docs/product.md` の Theme-driven backlog consumption 項の「theme カタログの実体は GitHub label 側を SSoT とする」記述を、seed カタログは `.wholework.yml` の `themes:` で宣言し、`/triage` が読む実行時カタログは引き続き GitHub label である、という二層構造の記述に更新する。あわせて `docs/ja/product.md` を同期する (→ 受け入れ条件 7)
10. `modules/label-conventions.md` の `theme/*` 行と "Relation to setup-labels.sh" 節に、`theme/*` の定義元が `.wholework.yml` の `themes:` (project-dependent) であり `setup-labels.sh` の定義 SSoT の唯一の例外である旨を追記する。あわせて `skills/triage/SKILL.md` Step 6a の分類基準の出所参照を `scripts/setup-labels.sh` から `.wholework.yml` の `themes:` に更新する (→ 受け入れ条件 7)

## Alternatives Considered

| 案 | 内容 | 採否 |
|----|------|------|
| A. block mapping (`themes:` 配下に `{name}: {description}`) | 1テーマ1行。`capabilities:` / `auto-retry-on-fail:` / `recoveries-auto-fire:` と同じ形状 | **採用** |
| B. list of mappings (`- name: x` / `description: y`) | Issue 本文の「name + description のリスト」という表現に最も近い | 不採用 — `.wholework.yml` に list-of-mappings の先例がなく、エントリ境界のフラッシュ処理を伴う専用パーサが必要になる。表現力の差 (将来の追加フィールド) は現時点の要件にない |
| C. `themes:` 未定義時に wholework 自身の5テーマをフォールバック作成 | 後方互換を優先 | 不採用 — Issue の Q&A で明示的に却下済み。他プロジェクトに wholework 固有テーマが混入するため |
| D. テーマごとに色を config 指定可能にする | `{name}: {description}` を `{name}: {description, color}` に拡張 | 不採用 — Issue の Proposal は name + description のみ。namespace 単位の色一貫性 (`modules/label-conventions.md`) を保つため `006B75` 固定とする |
| E. `themes:` パースを `scripts/get-config-value.sh` に汎用リスト読み出しとして追加 | 共通化 | 不採用 — `get-config-value.sh` は単一キー→単一値の契約 (ヘッダの Supported/Unsupported Input Shapes 表が SSoT) で、キー列挙は契約外。消費者が `setup-labels.sh` 1箇所のため、`scripts/check-verify-dirty.sh` の `verify-ignore-paths` と同じくスクリプト内ローカルパーサを採る |

## Verification

### Pre-merge

- <!-- verify: rubric "docs/guide/customization.md に、.wholework.yml の themes: キーでプロジェクト固有の theme label カタログを定義する方法が説明されている" --> <!-- verify: file_contains "docs/guide/customization.md" "themes:" --> `.wholework.yml` の `themes:` キーの使い方が `docs/guide/customization.md` に文書化されている
- <!-- verify: rubric "scripts/setup-labels.sh が .wholework.yml の themes: キーを読み込み、定義されたテーマそれぞれについて theme/{name} ラベルを description 付きで作成する処理を実装している" --> <!-- verify: grep "themes" "scripts/setup-labels.sh" --> `setup-labels.sh` が `.wholework.yml` の `themes:` からプロジェクト固有の `theme/{name}` ラベルを作成する
- <!-- verify: rubric ".wholework.yml に themes: が定義されていない場合、setup-labels.sh は theme label を一切作成しない (wholework 自身の5テーマを含むデフォルトの theme label 作成は行われない)" --> `themes:` 未定義時に theme label が作成されないことが実装・テストで確認できる
- <!-- verify: file_contains "tests/setup-labels.bats" "themes: config-driven theme labels created from .wholework.yml" --> <!-- verify: file_contains "tests/setup-labels.bats" "themes: no theme labels created when themes key is absent" --> <!-- verify: command "bats tests/setup-labels.bats" --> `themes:` 定義あり/なし双方のケースをカバーする新規テスト2件が `tests/setup-labels.bats` に追加され、全テストが pass する
- <!-- verify: file_contains ".wholework.yml" "themes:" --> <!-- verify: file_contains ".wholework.yml" "batch-orchestration" --> wholework 自身の既存5テーマ (`theme/observability`, `theme/ac-quality`, `theme/concurrency`, `theme/verify-backlog`, `theme/batch-orchestration`) が本リポジトリの `.wholework.yml` に `themes:` として明示移行されている
- <!-- verify: rubric "scripts/setup-labels.sh の ALWAYS_LABELS からハードコードされた theme/* エントリ5件が削除され、themes: 駆動のロジックに置き換わっている" --> <!-- verify: file_not_contains "scripts/setup-labels.sh" "theme/observability" --> `scripts/setup-labels.sh` のハードコードされた theme エントリが削除されている
- <!-- verify: rubric "docs/tech.md と docs/ja/tech.md の Label Groups 表の Always 行が 17 に更新され theme/* が除かれており、theme/* が .wholework.yml の themes: 駆動である旨が記載されている。あわせて docs/product.md / docs/ja/product.md の Theme-driven backlog consumption 記述、modules/label-conventions.md の theme/* 定義元、skills/triage/SKILL.md Step 6a の分類基準の出所参照も .wholework.yml 駆動に更新されている" --> <!-- verify: file_contains "docs/tech.md" "themes:" --> <!-- verify: file_contains "modules/label-conventions.md" "themes:" --> theme label の定義元がドキュメント側 (`docs/tech.md`, `docs/product.md` と各日本語ミラー, `modules/label-conventions.md`, `skills/triage/SKILL.md`) にも反映されている

### Post-merge

なし

## Tool Dependencies

### Bash Command Patterns

なし (実装で使うのは既存の `bats` 実行と通常のファイル編集のみ。`scripts/setup-labels.sh` は既存スクリプトで、新規スクリプト追加はない)

### Built-in Tools

なし (`Read` / `Edit` / `Write` / `Grep` はいずれも `/code` の `allowed-tools` に登録済み)

### MCP Tools

なし

## Uncertainty

なし。設計時点で残っていた3点はいずれも `/spec` 中に実機検証で解消済み (詳細は Notes の「不確実性の解消」を参照)。

## Notes

### 自動解決ログ (非対話モード)

`--non-interactive` のため、以下3点を model 判断で自動解決した。いずれも Issue 本文の `## Design Decisions` 節にも反映済み。

1. **YAML 形状: block mapping を採用 (list of mappings ではなく)**
   Issue 本文は「name + description のリスト」と書きつつ「具体的な入れ子形式は `/spec` で決定する」と明示的に委譲している。`.wholework.yml` の既存構造は `capabilities:` / `auto-retry-on-fail:` / `recoveries-auto-fire:` がすべて block mapping であり、list-of-mappings の先例は存在しない。block mapping なら `scripts/get-config-value.sh` の section-scan ループと同型のパーサで済み、エントリ境界のフラッシュ処理が不要になる。theme name は label suffix (kebab-case) なので YAML キーとして安全であり、キーの一意性がそのままテーマ名の一意性を保証する。

2. **色は `006B75` 固定 (config 指定不可)**
   Issue の Proposal は name + description のみを挙げており、色の設定要求はない。`modules/label-conventions.md` は `theme/*` を1つの namespace として定義しており、namespace 単位で色を揃えるのが既存の全ラベル群の慣習。将来必要になれば `{name}: {description}` を mapping 値に拡張する余地は残る。

3. **設定ファイル解決は CWD 基準 + `WHOLEWORK_CONFIG_PATH` 上書き**
   `scripts/get-config-value.sh` と同じ規則 (`CONFIG_FILE="${WHOLEWORK_CONFIG_PATH:-.wholework.yml}"`)。`scripts/gh-label-transition.sh` の auto-bootstrap は CWD を変更せずに `setup-labels.sh` を呼ぶため、リポジトリルート/worktree ルートのいずれからでも当該ツリーの `.wholework.yml` が読まれる。`WHOLEWORK_CONFIG_PATH` 上書きは `tests/setup-labels.bats` の決定性確保に必須 (Implementation Step 5)。

### 不確実性の解消 (プロトタイプ実機検証)

`/spec` 中に Implementation Step 3 のパーサをプロトタイプとして実装し、macOS システム bash (GNU bash 3.2.57) で以下を確認した。設計上の未検証点は残っていない。

- 5テーマすべてを `name` / `color` / `description` に正しく分解できる。description に含まれる `:` (`Theme: observability ...`)、`—` (em dash)、`/` (`batch/until`)、`,` がいずれも欠落しない
- ブロック内のインデントされたコメント行 (`  # ...`) と空行を正しくスキップする
- クォートあり (`"..."`) / クォートなしの両方の description を扱える
- 非インデント行 (`capabilities:`) でセクションが正しく終了し、後続キーが theme として誤取得されない
- `themes:` 未定義の設定ファイル、および設定ファイル不在 (`WHOLEWORK_CONFIG_PATH=/dev/null`) のいずれでも `count=0` になる
- `set -euo pipefail` 下で空配列を展開するため、作成ループでは `"${THEME_LABELS[@]+"${THEME_LABELS[@]}"}"` 形式が必須 (bash 3.2 は空配列を unset 扱いにする)

既知の制限: description から inline コメント (` #` 以降) を除去する挙動は `scripts/get-config-value.sh` の sed チェーンをそのまま踏襲する。そのため description 中の ` #` は保持されない。既存5テーマに該当文字列はなく、YAML のクォートなしスカラーの解釈とも整合するため、先例一致を優先して許容する。

### 既存実装との矛盾

Issue 本文の前提記述 (`/triage` Step 6a が `gh label list` で動的取得している / `setup-labels.sh` の Always-group に5テーマがハードコードされている) はいずれも現行実装と一致しており、矛盾は検出されなかった。

### allowed-tools 影響連鎖チェック

- Case 1 (新規 `scripts/*.sh`): 該当なし — 新規スクリプトの追加はない
- Case 2 (`modules/*.md` 変更): `modules/label-conventions.md` が Changed Files に含まれる。lightweight gate は既存の `scripts/setup-labels.sh` 参照文字列にヒットするが、`grep -rl "modules/label-conventions\.md" skills/*/SKILL.md` の結果は0件 (この module を "Read and follow" する SKILL.md は存在しない)。よって `allowed-tools` の追加要否は発生しない

### skill-dev 設計時チェック

- settings.json 追加: 新規 skill なし → 該当なし
- 共通モジュール抽出: `themes:` パーサの消費者は `scripts/setup-labels.sh` 1箇所のみ。`scripts/check-verify-dirty.sh` の `verify-ignore-paths` パーサと同じくスクリプト内ローカル実装とし、`modules/` への抽出は行わない (2箇所以上での再利用が発生した時点で再検討)
- SKILL.md validation 制約: `skills/triage/SKILL.md` の変更は Step 6a の1文のみ。半角感嘆符・三連バッククォート・YAML block scalar のいずれも新たに導入しない
- 網羅マーカー: `modules/label-conventions.md` に追記する `theme/*` の定義元の記述には **(project-dependent)** マーカーを付す (テーマ集合がプロジェクト設定依存であるため)

### bats テストの入力データ形式

新規テストが `setup-labels.sh` に与える入力は `WHOLEWORK_CONFIG_PATH` が指す YAML ファイル。想定形式は以下 (block mapping、2スペースインデント):

```
themes:
  checkout: "Theme: checkout flow"
  payments: "Theme: payments and billing"
```

`gh` モックは `echo "$@" >> "$GH_CALL_LOG"` で引数を空白連結して記録するため、アサーションは `grep "label create theme/checkout"` および `grep "description Theme: checkout flow"` の形になる (既存の `label_created()` ヘルパーと同じ照合方式)。

### `WHOLEWORK_SCRIPT_DIR` モック追加チェック

`tests/setup-labels.bats` は `export WHOLEWORK_SCRIPT_DIR="$MOCK_DIR"` を設定しているが、本 Issue で新規スクリプトを追加しないため `$MOCK_DIR` への新規モックファイル追加は不要。

## issue retrospective

### 判断根拠

- **theme label カタログの二層構造の確認**: `/triage` Step 6a の分類ロジック (`gh label list` による動的取得 + description マッチング) は既にプロジェクト非依存だが、ラベルの種を実際に作成する `scripts/setup-labels.sh` が wholework 自身のドッグフーディング用5テーマをハードコードしていた。この Issue はラベル seeding のみを config 駆動化し、分類ロジックには手を入れない。

### Q&A での主要ポリシー決定

- **`.wholework.yml` の `themes:` が未定義の場合の挙動**: 「wholework 自身の5テーマを既定値としてフォールバック作成する」案と「`themes:` 未定義なら theme label を一切作成しない」案を提示し、後者を採用。理由: 既定フォールバックを残すと、他プロジェクトが `setup-labels.sh` を実行した際に wholework 自身のドッグフーディング用テーマ (observability, ac-quality 等) が意図せず混入してしまうため。この決定に伴い、wholework 自身の既存5テーマは本リポジトリ自身の `.wholework.yml` に `themes:` として明示移行する (特別扱いせず、他プロジェクトと同じ経路を使う)。

### Acceptance Criteria について

新規起票のため「変更」はないが、上記ポリシー決定を反映して AC5/AC6 (wholework 自身の5テーマ移行、`setup-labels.sh` のハードコード削除) を Pre-merge に含めている。

## spec retrospective

### Minor observations

- `tests/setup-labels.bats` の既存アサーションはスクリプト本体から件数を導出する (`count_always_labels()`) 設計になっており、ラベル追加に自動追従する。しかし「実行時の CWD にある `.wholework.yml`」という新しい外部入力が加わると、この自動追従は逆に破綻方向に働く (リポジトリ自身の設定を読んで件数がずれる)。設定ファイルを読むスクリプトのテストでは、件数の自動導出より先に入力の固定 (`WHOLEWORK_CONFIG_PATH`) を設計する必要がある。
- `docs/product.md` の Theme-driven backlog consumption 項に「theme カタログの実体は GitHub label 側を SSoT とし、本ドキュメントには記述しない」という設計判断が明文化されていた。この一文は Issue 本文・`setup-labels.sh` のどちらからも参照されておらず、`theme/` の全文 grep で初めて発見された。SSoT の所在を宣言する記述は、対象の実装を変える Issue から機械的にはたどれない。

### Judgment rationale

- Issue 本文は `themes:` を「name + description のリスト」と表現していたが、YAML 形状の決定を明示的に `/spec` に委譲していた。`.wholework.yml` の既存セクション (`capabilities:` / `auto-retry-on-fail:` / `recoveries-auto-fire:`) がすべて block mapping であり list-of-mappings の先例がないこと、および block mapping なら `get-config-value.sh` の section-scan ループと同型のパーサで済むことを根拠に、本文の字面より既存構造との一貫性を優先した。委譲が明示されている場合、本文の例示表現は制約ではなく出発点として扱う。
- `themes:` パーサを `scripts/get-config-value.sh` に汎用機能として追加せず、`setup-labels.sh` 内のローカル実装に留めた。`get-config-value.sh` は「単一キー → 単一値」の契約をヘッダの Supported/Unsupported Input Shapes 表で SSoT 化しており、キー列挙はその契約の外側にある。消費者が1箇所であることと、`scripts/check-verify-dirty.sh` が `verify-ignore-paths` で同じくローカルパーサを採っている先例が決め手になった。2箇所目の消費者が現れた時点が共通化の判断点になる。

### Uncertainty resolution

- 設計段階で残っていた「bash 3.2 でこのパーサが動くか」「description 中の `:` / em dash / `/` が欠落しないか」「インデントされたコメント行・空行・非インデント行境界を正しく扱えるか」の3点は、`/spec` 中にプロトタイプを書いて macOS システム bash (3.2.57) で実機検証し、すべて解消した。Uncertainty 節に「検証方法」を書いて `/code` に渡すより、`/spec` の中で20行のプロトタイプを回すほうが安く確実だった — パーサのように入出力が閉じている設計要素では、この前倒しが有効。
- 実機検証で `set -euo pipefail` 下の空配列展開 (`"${THEME_LABELS[@]+"${THEME_LABELS[@]}"}"`) が必須であることが判明した。これはプロトタイプを書かなければ `/code` 段階で `unbound variable` として初めて顕在化していた種類の制約で、Implementation Step 4 に明示的に書き込んだ。

## Code Retrospective

### Deviations from Design

なし。Implementation Steps 1-10 を Spec の指示どおりの順序・配置 (パーサは `FALLBACK_LABELS` 定義直後、`detect_issue_types()` 直前 / 作成ループは Always-group ループ直後、Fallback-group ブロック直前) で実装した。

### Design Gaps/Ambiguities

- 行動変化検知 (behavioral change detection) が `.wholework.yml` を「他テストが広く参照する既存ファイル」と判定し、フルテストスイート (1715件) の実行をトリガーした。実際には `.wholework.yml` を参照する既存テストの大半 (`run-spec.bats` 等) は `WHOLEWORK_CONFIG_PATH` のパス文字列としての言及であり、本 Issue の `themes:` 追加による挙動変化とは無関係だった。パス文字列ベースの参照検知は、設定ファイルパスのように汎用的に言及されるファイルに対して過検知気味になる。今回は誤検知でも実害はなかった (フルスイートは1715件全 PASS)ため、検知ロジック自体の変更は提案しない。

### Rework

なし。テスト・手動スモークテスト (themes あり2件・themes なし・実データ5テーマ) がいずれも初回実装で成功した。

## Phase Handoff
<!-- phase: code -->

### Key Decisions

- Spec の Implementation Steps 1-10 をそのままの順序・配置で実装した (逸脱なし)。パーサ配置・作成ループ配置・`WHOLEWORK_CONFIG_PATH` 対応・空配列展開の form はいずれも Spec 記載どおり。
- 全7件の Pre-merge AC を `/code` 内で機械チェック (`file_contains` / `grep` / `file_not_contains` / `command`) + rubric 相当の判断で PASS 判定し、Issue 本文のチェックボックスを更新済み。

### Deferred Items

- None (本 Issue のスコープはすべて Implementation Steps に含まれ、完了している)。

### Notes for Next Phase

- `bats tests/setup-labels.bats` 全22件 (既存20件 + 新規2件) が pass。実データの `.wholework.yml`(5テーマ) でも手動スモークテストし、`theme/observability` 等が正しく色 `006B75` ・description 付きで作成されることを確認済み。
- behavioral change detection が `.wholework.yml` / `docs/tech.md` を参照する既存テストの存在により発火し、bats フルスイート (1715件、`--jobs 18`) を実行して全 PASS を確認済み。`/review` で再度フルスイートを回す場合も同じ結果になるはず。
- ドキュメント同期は英語/`docs/ja/` の3ペア (`customization.md` / `tech.md` / `product.md`) + `modules/label-conventions.md` + `skills/triage/SKILL.md` の計8ファイルすべて更新済み。`scripts/check-translation-sync.sh` による OUTDATED 検出は想定していない。
