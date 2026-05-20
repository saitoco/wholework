# Issue #458: auto: --batch List mode で triage 直後の Size 取得が空になり run-auto-sub が中断

## Overview

`/auto --batch` の List mode で triage 未実施 Issue を含むと、triage 直後の `run-auto-sub.sh` が `Error: Size is not set` で exit 1 中断する。原因 1（GitHub eventual consistency / mutation skip）と原因 2（`get-issue-size.sh` Phase 1 の `gh-graphql.sh --cache` 鮮度問題）の複合。SSoT は Project field 単一を維持しつつ、局所改修 D（triage 側 verify-after-write + retry）と B'（`get-issue-size.sh --no-cache` フラグ）で構造的に解消する。

## Reproduction Steps

1. triage 未実施の Issue を用意（`phase/*` ラベルなし・Size 未設定）
2. `/auto --batch <該当 Issue 番号>` を実行
3. `run-issue.sh` 内の triage は exit 0 で Size 判定（completion report に XS 等表示）
4. 続く `run-auto-sub.sh` 117–138 行が `get-issue-size.sh` を呼び出し、空応答により `Error: Size is not set for issue #N` で exit 1
5. batch が当該 Issue を fail 分類してスキップ

## Root Cause

**原因 1: triage の Size 永続化が確実でない**
- GraphQL mutation `update-field-value` は exit 0 を返すが GitHub 側 eventual consistency により数秒間反映遅延が発生し得る
- LLM が mutation 自体を skip する病的ケースでも label fallback（Step 5）が走らないため Size 不明のまま

**原因 2: `get-issue-size.sh` Phase 1 が cache TTL 300s 経由**
- `scripts/get-issue-size.sh` 39–43 行が `gh-graphql.sh --cache` を呼ぶ
- triage 開始前にキャッシュされた「Size 未設定時点」のレスポンスを triage 直後に読みに行く
- Phase 2 ラベル fallback も triage が GraphQL 成功時はラベルを付けないため空

**修正方針の妥当性**
- D（verify-after-write）: mutation 直後に cache bypass で再読み取り → eventual consistency と mutation skip の両方を検知し、retry で吸収、最終的に failed なら既存の label fallback パスへ流す。triage 内で完結
- B'（`--no-cache` フラグ）: triage 直後の caller に限定して cache bypass。デフォルト挙動は無変更
- 現行の「ラベル＝GraphQL 失敗時のみの fallback」原則を維持、SSoT 二重化なし

## Changed Files

- `scripts/get-issue-size.sh`: `--no-cache` フラグを追加。フラグ指定時は `gh-graphql.sh` 呼び出しから `--cache` を除外 — bash 3.2+ 互換
- `scripts/run-auto-sub.sh`: `get-issue-size.sh` 呼び出し箇所（118 行・133 行付近）を `--no-cache` 付きに変更 — bash 3.2+ 互換
- `skills/triage/SKILL.md`: Step 6（Size Assignment）に verify-after-write 手順を追記（GraphQL success 直後の `get-issue-size.sh --no-cache` 再読み取り + 1s/2s/3s × 最大 3 回 retry、失敗時は既存 Step 5 label fallback へ流す）
- `tests/get-issue-size.bats`: `--no-cache` フラグが cache を bypass することを検証するテストケース追加
- `modules/project-field-update.md`: 変更なし（既存「Label fallback (only if steps 1-4 failed)」記述を維持して後方互換性を確保）

## Implementation Steps

1. `scripts/get-issue-size.sh` を改修: 先頭の引数パースで `--no-cache` フラグを受理し、`gh-graphql.sh` 呼び出し直前の cache 制御変数（例: `CACHE_FLAG=--cache` をデフォルト、フラグ指定時 `CACHE_FLAG=""`）を導入。Phase 1 の `"$SCRIPT_DIR/gh-graphql.sh" --cache ...` を `"$SCRIPT_DIR/gh-graphql.sh" $CACHE_FLAG ...` に置換 — bash 3.2+ 互換（→ AC #2）
2. `skills/triage/SKILL.md` Step 6 に verify-after-write 手順を追加: `modules/project-field-update.md` Steps 1→4 完了後、`scripts/get-issue-size.sh --no-cache $NUMBER` を呼び、設定値と一致しなければ 1s/2s/3s の順で待機して最大 3 回 retry。全 retry 失敗時は同モジュール Step 5 の label fallback を手動実行（`gh issue edit ... --add-label "size/$SIZE"`）。手順末尾に「失敗時 label fallback」旨を明示（→ AC #1）
3. `scripts/run-auto-sub.sh` の `get-issue-size.sh` 呼び出し（118 行と 133 行付近）を `"$SCRIPT_DIR/get-issue-size.sh" --no-cache "$SUB_NUMBER"` 形式に変更 — bash 3.2+ 互換（→ AC #3）
4. `tests/get-issue-size.bats` に `--no-cache` 動作テスト追加: (a) cache を pre-populate → mock 応答を変更 → `--no-cache` 付き呼び出しで新しい値が返ることを検証、(b) `--no-cache` フラグ未指定時は既存の cache 経路が維持されることを補強（→ AC #2 補強）

## Verification

### Pre-merge

- <!-- verify: rubric "skills/triage/SKILL.md Step 6 または modules/project-field-update.md に、Size の Project field (GraphQL) 更新成功直後に cache を bypass した再読み取りで永続化を確認する verify-after-write 手順（retry を含む）が記述されている。失敗時は既存の label fallback パスへ流す旨も明示されている" --> triage に verify-after-write 手順（retry + 失敗時 label fallback）が追加されている
- <!-- verify: file_contains "scripts/get-issue-size.sh" "--no-cache" --> `get-issue-size.sh` に `--no-cache` オプション（または同等の cache bypass フラグ）が追加されている
- <!-- verify: file_contains "scripts/run-auto-sub.sh" "--no-cache" --> `run-auto-sub.sh` が `get-issue-size.sh` を cache bypass で呼び出す
- <!-- verify: section_contains "modules/project-field-update.md" "Updating Priority / Size Fields" "Label fallback (only if steps 1-4 failed)" --> 既存の「GraphQL 失敗時のみ label fallback」記述が維持されている（後方互換性の確保）

### Post-merge

- triage 未実施の Issue（`phase/*` ラベルなし・Size 未設定）を含む `/auto --batch <Issue 番号>` を実行し、`run-auto-sub.sh` が `Error: Size is not set` で中断せず正常に処理が進むことを実環境で確認する <!-- verify-type: opportunistic -->

## Code Retrospective

### Deviations from Design

- Specの実装ステップ4では「`tests/get-issue-size.bats` に `--no-cache` 動作テスト追加」として mock を変更せずテストを追加することを想定していたが、実際には `--no-cache` 時に `gh-graphql.sh` の non-cache パスが `--jq` を `gh api graphql` に渡す挙動を mock が処理しないため、テスト失敗が発生した。mock の `gh api graphql` ハンドラに `--jq` 処理を追加する修正を行い、これを別コミットとした。

### Design Gaps/Ambiguities

- Spec の Notes §「bats テスト Mock 互換性」に「run-auto-sub.bats の Mock は引数を無視するため `--no-cache` 追加でも既存テストはそのまま通過する」と記載されていたが、`get-issue-size.bats` の mock における `gh api graphql` の `--jq` 引数処理については言及がなかった。`--no-cache` 時は non-cache パスが `--jq` を `gh` コマンドに渡すため、既存 mock が `--jq` を無視して生 JSON を返し、テストが失敗するケースが生じた。

### Rework

- `tests/get-issue-size.bats`: 1回目のコミットでテスト追加後、テスト失敗を確認して mock の `gh api graphql` ハンドラに `--jq` 処理を追加する修正を2回目のコミットとして実施。

## Notes

### 実装ファイル選択の確定

verify-after-write 手順は **`skills/triage/SKILL.md` Step 6** に追記する方針を採用（Issue body の Auto-Resolved Ambiguity Points で Spec 決定とした項目）。理由:

- Issue body の Auto-Resolved で「適用スコープ: Size のみ」と決定済み。`modules/project-field-update.md` は Priority/Size/Value 共有モジュールであり、ここに verify-after-write を入れると 3 種全てに波及する
- triage SKILL.md Step 6 配置は Size 特化で局所変更、Priority/Value への副作用なし
- shared module 配置のメリット（Priority/Value にも自然波及）は別 Issue（必要性が確認された段階）で実装可能

### verify-after-write の retry 戦略

Auto-Resolved「短い指数 backoff × 最大 3 回 + 失敗時 label fallback」を採用。

- 待機: 1 回目 1s、2 回目 2s、3 回目 3s（合計最大 6s）
- GitHub eventual consistency は通常 < 1s で解消するため初回 1s 待機で多くのケースを吸収
- 3 回 retry で読めなければ mutation 自体が反映されていない可能性が高く、`gh issue edit --add-label "size/$SIZE"` で手動 label 付与（既存 Step 5 のロジック）

### `--no-cache` フラグの実装

`gh-graphql.sh` 側に新フラグは追加せず、`get-issue-size.sh` 内で `--cache` 引数を条件付きで渡す/外す方式とする。Auto-Resolved「`get-issue-size.sh` のみ追加」に従い、`gh-graphql.sh` の汎用 API には触らない。

### bats テスト Mock 互換性

`tests/run-auto-sub.bats` の Mock `get-issue-size.sh`（38–39 行）は引数を無視して `echo "M"; exit 0` を返すため、`--no-cache` 引数が追加されても既存テストはそのまま通過する。Mock 側の更新は不要。

### 既存 label fallback の維持

`modules/project-field-update.md` の `### Updating Priority / Size Fields` セクション内「5. Label fallback (only if steps 1-4 failed)」記述は変更しない。triage 側 verify-after-write の最終フォールバックとして同ロジックを Step 6 から手動呼び出しする形のため、shared module の挙動は無変更で後方互換性が保たれる。
