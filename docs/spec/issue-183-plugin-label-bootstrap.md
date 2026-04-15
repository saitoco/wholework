# Issue #183: Wholework ユーザーが setup-labels.sh を自分のリポジトリで実行できる

## Overview

Plugin インストール（`/plugin install wholework@saitoco-wholework`）のみで Wholework を導入したユーザーが、リポジトリ clone 無しでラベル初期化を完了できるようにする。具体的には (1) `scripts/setup-labels.sh` を Wholework 管理ラベルの SSoT として拡張（不足ラベル追加 + Projects/Issue Types 環境検出による条件付きフォールバック）、(2) `scripts/gh-label-transition.sh` からの auto-bootstrap 起動、(3) `docs/tech.md` へのドリフト防止ガイド追加を行う。

## Changed Files

- `scripts/setup-labels.sh`: ラベル定義拡張（`phase/done` / `retro/verify` / `audit/drift` / `audit/fragility` を常時作成群に追加）、Projects/Issue Types 環境検出ロジック、冪等（check-then-create）実装への切り替え
- `scripts/gh-label-transition.sh`: 対象 `phase/*` ラベル未作成を検出した場合に `setup-labels.sh` を自動実行するブートストラップ呼び出しを追加
- `tests/setup-labels.bats`: 新ラベル群 + 環境検出分岐 + idempotent 挙動に合わせてテスト更新
- `tests/gh-label-transition.bats`: auto-bootstrap 呼び出し挙動の追加テスト
- `docs/tech.md` + `docs/ja/tech.md`: `ssot_for` frontmatter に `labels` 追加、`## Wholework Label Management` 節を追加（SSoT 宣言 + 追加・変更・削除ルール + fallback label 検出条件併記ルール）
- `docs/workflow.md` + `docs/ja/workflow.md`: Label Transition Map に `phase/done` および常時作成ラベル群を記載、setup-labels.sh の役割を更新（Plugin ユーザーは明示実行不要の旨を追記）
- `docs/guide/quick-start.md` + `docs/ja/guide/quick-start.md`: Plugin install 手順直下に「ラベルは Wholework が初回実行時に自動作成する」の 1 段落を追加

## Implementation Steps

1. `scripts/setup-labels.sh` を書き換え (→ 受入条件 #1 #2 #3 #4 #5):
   - `ALWAYS_LABELS` 配列に 11 種（`phase/*` 6 種 + `phase/done` + `triaged` + `retro/verify` + `audit/drift` + `audit/fragility`）を定義
   - `FALLBACK_LABELS` 配列に 15 種（`type/*` 3 種 + `priority/*` 4 種 + `size/*` 5 種 + `value/*` 5 種）を定義し、各エントリに検出条件コメントを併記
   - 環境検出関数 `detect_issue_types()` を追加: `"$SCRIPT_DIR/gh-graphql.sh" --query get-issue-types --jq '.data.repository.issueTypes.nodes | length'` の結果が 1 以上なら true。失敗時は false
   - 環境検出関数 `detect_projects_field(field_name)` を追加: `"$SCRIPT_DIR/gh-graphql.sh" --query get-projects-with-fields --jq '[.data.repository.projectsV2.nodes[].fields.nodes[] | select(.name=="<field>")] | length'` 結果が 1 以上なら true
   - 冪等化: 開始時に `gh label list --limit 200 --json name --jq '.[].name'` で既存ラベル名を 1 回取得し、各ラベル作成前に「未存在ならば作成」パターンに変更（`--force` は `--force` フラグ指定時のみ）
   - CLI: `scripts/setup-labels.sh [--force] [--no-fallback]` をサポート（`--force` は既存ラベルを上書き、`--no-fallback` は環境検出をスキップして always group のみ）

2. `scripts/gh-label-transition.sh` に auto-bootstrap トリガを追加 (→ 受入条件 #6):
   - `gh issue edit ... --add-label "phase/$TARGET_PHASE"` 実行前に `gh label list --limit 200 --json name --jq '.[].name' | grep -qx "phase/$TARGET_PHASE"` でラベル存在確認
   - 未存在の場合 `"$SCRIPT_DIR/setup-labels.sh" || echo "Warning: label bootstrap failed, continuing" >&2` を 1 回実行
   - 冪等性を保つためトリガは 1 呼び出しにつき最大 1 回（環境変数 `WHOLEWORK_LABEL_BOOTSTRAPPED=1` をセットし後続の子呼び出しでスキップも可だが、同一プロセス内でのみ扱うので単純な順次実行で十分）

3. テスト更新 (→ 受入条件 #7 #8) (parallel with 1, 2):
   - `tests/setup-labels.bats`: gh モックで `label list` / `gh-graphql.sh` 相当のレスポンスを切り替え、(a) Projects + Issue Types 共に利用可能 → always 11 種のみ作成、(b) 全て未構成 → always 11 + fallback 15 = 26 種作成、(c) 既存ラベルが一部存在 → 重複作成されない、(d) `--force` 指定時のみ `--force` フラグ付きで gh 呼び出し、の 4 ケースを追加。旧「10 labels」前提の既存テストは新挙動に合わせて更新
   - `tests/gh-label-transition.bats`: (a) `phase/*` ラベル未存在 → setup-labels.sh が 1 回起動される、(b) ラベル存在 → setup-labels.sh は起動されない、(c) setup-labels.sh 失敗時も gh-label-transition.sh は警告を出して継続、の 3 ケースを追加

4. `docs/tech.md` に `## Wholework Label Management` 節を追加 (→ 受入条件 #9 #10) (after 1):
   - Frontmatter `ssot_for:` に `- labels` を追記
   - 本文節で以下を明文化:
     - `scripts/setup-labels.sh` が Wholework 管理ラベルの SSoT である
     - skill / script / module で `gh label create` / `--add-label` / `--remove-label` / ラベル名を grep する pattern を追加・変更・削除する際は同 PR で `scripts/setup-labels.sh` を更新するルール
     - fallback label は検出条件を `setup-labels.sh` 内コメントに併記する規約
     - 将来的な `/audit drift` 相当の機械検出ポイント（ラベル参照 grep 集合と setup-labels.sh の集合一致）の方針言及
   - `docs/ja/tech.md` も同内容を日本語で追記（frontmatter 同期）

5. 追従ドキュメント更新 (→ 受入条件 #9 #11) (parallel with 4):
   - `docs/workflow.md` Label Transition Map に `phase/done` 行を追加、Setup 行を「Wholework が初回実行時に自動作成（手動実行は `scripts/setup-labels.sh`）」に差し替え
   - `docs/guide/quick-start.md` Step 1 直下に「Wholework will automatically create the labels it needs on first run — no manual setup required.」を追記
   - `docs/ja/workflow.md` / `docs/ja/guide/quick-start.md` を同内容で更新

## Alternatives Considered

- **新規 skill (`/wholework:bootstrap`) を追加する案**: `/issue` 時点でユーザー選択により却下（明示実行を求めると Plugin install ユーザーに認知負荷が発生）。auto-bootstrap 方式を採用
- **docs にキャッシュパスを明記するのみの案**: `/issue` 時点で却下（ユーザー手動操作が残る）
- **`gh-label-transition.sh` ではなく各 skill 側に個別追加する案**: 実装箇所が分散し SSoT 原則に反するため却下。ラベル付与の最下層 (`gh-label-transition.sh`) に 1 箇所で組み込む

## Verification

### Pre-merge

- <!-- verify: file_contains "scripts/setup-labels.sh" "retro/verify" --> `scripts/setup-labels.sh` に `retro/verify` ラベル定義が追加されている
- <!-- verify: file_contains "scripts/setup-labels.sh" "audit/drift" --> `scripts/setup-labels.sh` に `audit/drift` ラベル定義が追加されている
- <!-- verify: file_contains "scripts/setup-labels.sh" "audit/fragility" --> `scripts/setup-labels.sh` に `audit/fragility` ラベル定義が追加されている
- <!-- verify: file_contains "scripts/setup-labels.sh" "phase/done" --> `scripts/setup-labels.sh` に `phase/done` ラベル定義が追加されている（既存ドリフト解消）
- <!-- verify: file_contains "scripts/setup-labels.sh" "get-issue-types" --> `scripts/setup-labels.sh` に Issue Types/Projects 環境検出ロジック（`gh-graphql.sh --query get-issue-types` 呼び出し）が追加されている
- <!-- verify: file_contains "scripts/gh-label-transition.sh" "setup-labels.sh" --> `scripts/gh-label-transition.sh` が auto-bootstrap として `setup-labels.sh` を呼び出す処理を含む
- <!-- verify: file_exists "tests/setup-labels.bats" --> `tests/setup-labels.bats` が新ラベル・環境検出分岐に合わせて存在する
- <!-- verify: github_check "gh pr checks" "Run bats tests" --> bats テスト（`tests/setup-labels.bats` / `tests/gh-label-transition.bats` 含む）が CI で成功する
- <!-- verify: file_contains "docs/tech.md" "setup-labels.sh" --> `docs/tech.md` に `scripts/setup-labels.sh` を SSoT と位置づける節が追加されている
- <!-- verify: file_contains "docs/tech.md" "SSoT" --> `docs/tech.md` のラベル SSoT 節で、ラベル参照変更時に `setup-labels.sh` を同 PR で更新するルールが明文化されている

### Post-merge

- Plugin install のみ（repo clone 無し）のユーザーが Projects 未構成の新規 repo で `/issue` を実行した際、常時作成ラベル + フォールバックラベルがすべて自動作成され、`phase/issue` が付与されたことを GitHub 上で確認できる
- Projects（Priority/Size/Value field 構成済み）+ Issue Types 利用可能な repo で Wholework を実行した際、`type/*` / `priority/*` / `size/*` / `value/*` ラベルが不要に作成されないことを確認
- 既にラベルが手動作成済みのリポジトリで Wholework を実行しても、既存ラベルの色・description が意図せず上書きされない（`--force` 未指定時の挙動）

## Notes

- **`--force` と冪等性の関係（Issue AC との調整）**: Issue 本文の Pre-merge AC に「`gh label create --force` を利用した冪等実装を維持」と記載されていたが、Post-merge の「既存ラベルが壊れない」条件と矛盾するため、Spec では default を check-then-create（既存ラベルをスキップ）に変更し、明示的な `--force` フラグ指定時のみ上書きする設計を採用した。Issue 本文は Spec の Verification 項目に合わせて自動更新する（`file_exists "scripts/setup-labels.sh"` AC は Spec 側で削除）
- **既存ドリフトの同時解消**: 現行 `setup-labels.sh` は `phase/done` / `retro/verify` / `audit/drift` / `audit/fragility` を欠いている。本 Issue が「ラベル参照と setup-labels.sh の乖離」自体を構造的に解消する位置付けなので、既存ドリフトも併せて解消する
- **環境検出の失敗扱い**: `gh-graphql.sh` 呼び出しが失敗した場合（API 制限・権限不足等）は「未構成」扱いにフォールバックし、fallback label も作成する（過剰作成側に倒すことで workflow を先に進められる）。テストでこの挙動を固定
- **Auto-bootstrap のループ安全性**: `gh-label-transition.sh` → `setup-labels.sh` → 内部で `gh label list` を呼ぶが `gh-label-transition.sh` は再呼び出ししないので循環は発生しない
- **日本語ミラー同期**: `docs/ja/tech.md` / `docs/ja/workflow.md` / `docs/ja/guide/quick-start.md` の同期は `/code` 実装で同 PR 内に含める。verify コマンドは英語版のみを対象とし、日本語版の文字列一致は目視確認に委ねる
- **Size=S 維持根拠**: 変更ファイル数 8（script 2 + test 2 + docs 4; うち docs/ja ミラーは機械的追随）。Spec Simplicity Rules の light 上限（5 step / 10 verification）内に収まる

## Auto-Resolved Ambiguity Points

- **`phase/done` の扱い**: 既存 `gh-label-transition.sh` / opportunistic-verify.md で使用されているが setup-labels.sh に未定義 → 常時作成群に追加（ドリフト解消）
- **Auto-bootstrap の具体箇所**: `gh-label-transition.sh` の `--add-label` 直前に配置（全 phase 遷移で最下層の 1 箇所のみ）
- **冪等性の実装方法**: `gh label list` で既存ラベル集合を 1 回取得 → 未存在のみ作成。`--force` フラグでオプトイン上書き
- **ja ミラーファイルの verify command**: 英語版のみを verify 対象にし、ja 同期は Notes で明示（過剰な verify command 追加を避ける）
