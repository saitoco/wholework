# Issue #783: auto: project-level always-pr と auto-stop-at (enum) config を追加

## Overview

`.wholework.yml` に 2 つの project-level config を追加する。

**`always-pr` (boolean)**: Size に関わらず PR route を強制する。website 系プロジェクト (main = 公開) では main への直接 commit が即公開につながるため、XS/S Issues でも PR が必須になる。このキーで Size ベースの patch route を無効化する。

**`auto-stop-at` (enum: `spec|code|review|merge|verify`)**: `/auto` pipeline を指定 phase 完了後に停止させる。デフォルト `verify` (= 現状の full pipeline)。per-invocation override として `--stop-at=<phase>` フラグも追加。停止後は次の人間アクションを出力する。

組み合わせにより、website 系プロジェクトで `/auto` の orchestration 恩恵 (issue/spec/code/review の連続実行) を受けつつ、merge=公開のリスクを人間が gate できるワークフローを実現する。

## Consumed Comments

No new comments since last phase.

## Changed Files

- `modules/detect-config-markers.md`: マーカー定義表に `always-pr` → `ALWAYS_PR` (boolean, default: false) と `auto-stop-at` → `AUTO_STOP_AT` (string, default: `"verify"`) の 2 行を追加。Output Format セクションにも対応する変数説明を追加 — bash 3.2+ 互換
- `skills/code/SKILL.md`: Step 0 Route Detection に `detect-config-markers.md` 読み込みと `ALWAYS_PR` チェックを追加 — ALWAYS_PR=true 時は `--patch` フラグがあっても警告して pr route を強制 (案 A: 無視して警告)
- `skills/auto/SKILL.md`: (a) Step 2 に `detect-config-markers.md` 読み込みを追加し `AUTO_STOP_AT` / `ALWAYS_PR` を取得、`--stop-at=<phase>` フラグ解析を追加。(b) Step 4 pr route・patch route の各フェーズ完了後に stop-at チェックを追加。(c) Step 5 Completion Report に stop-at 停止時の next-action ガイダンス出力を追加
- `docs/guide/customization.md`: `always-pr` / `auto-stop-at` を YAML 例・Available Keys 表に追加。website 系プロジェクト推奨設定例を追記
- `docs/ja/guide/customization.md`: 上記の日本語 mirror を更新
- `tests/auto.bats` (update): `stop-at` 各 enum 値のテストケースを追加 — bash 3.2+ 互換
- `tests/code.bats` (new): `always-pr` 強制の structural test を追加 — bash 3.2+ 互換

## Implementation Steps

1. `modules/detect-config-markers.md` を更新: マーカー定義表 (Marker Definition Table) に以下の 2 行を追加。また Output Format セクションにも対応する変数説明を追記する。(→ AC1、AC2、AC3)
   - `| always-pr | ALWAYS_PR | true | false |` — boolean、XS/S の patch route を pr route に昇格
   - `| auto-stop-at | AUTO_STOP_AT | string value as-is | "verify" |` — enum string、未設定 / 空文字列は `"verify"` として扱う

2. `skills/code/SKILL.md` Step 0 Route Detection を更新: Step 0 の冒頭 (Size fetch の前) に以下を挿入する。(→ AC4)
   - `detect-config-markers.md` を読み込み `ALWAYS_PR` を取得
   - フラグ優先順位のテーブルに `ALWAYS_PR=true` 行を追加 (優先度: `--pr` > `ALWAYS_PR=true` > `--patch` 無視 + 警告 > Size auto-detect):
     - `ALWAYS_PR=true` かつ `--patch` フラグあり → 警告 "Warning: always-pr: true is set in .wholework.yml. The --patch flag is ignored; pr route is forced." を出力し pr route を選択
     - `ALWAYS_PR=true` かつ フラグなし → Size に関わらず pr route を選択
   - Size auto-detection セクションの前に `ALWAYS_PR=true` チェックを挿入し、条件が満たされた場合は auto-detection をスキップして pr route に設定

3. `skills/auto/SKILL.md` を更新: (→ AC5、AC6、AC7)
   - **Step 2 (Route Detection)** に以下を追加 (Step 2 冒頭の flag 検出の前):
     - `detect-config-markers.md` を読み込み `AUTO_STOP_AT` と `ALWAYS_PR` を取得
     - `--stop-at=<phase>` フラグ解析を追加 (per-invocation override; 有効値: `spec|code|review|merge|verify`)
     - `EFFECTIVE_STOP_AT` を決定: `--stop-at` フラグ > `AUTO_STOP_AT` > デフォルト `verify` の優先順位
     - `ALWAYS_PR=true` かつ ROUTE が patch → pr route に昇格 (警告メッセージ出力)
   - **Step 4 pr route** の各フェーズ完了後に stop-at チェックを追加:
     - code 完了後: `EFFECTIVE_STOP_AT == "code"` なら Completion Report へ (Step 5)
     - review 完了後: `EFFECTIVE_STOP_AT == "review"` なら Completion Report へ
     - merge 完了後: `EFFECTIVE_STOP_AT == "merge"` なら Completion Report へ
   - **Step 4 patch route** の code 完了後: `EFFECTIVE_STOP_AT == "code"` なら Completion Report へ
   - **Step 5 Completion Report** に stop-at 停止時の表示を追加:
     - 通常完了と区別するため "stopped at {phase}" バナーを出力
     - 停止 phase に応じた next-action メッセージを出力:

       | stop-at | next-action メッセージ |
       |---------|----------------------|
       | `spec` | "次は `/code $NUMBER` を実行してください" |
       | `code` | "次は `/review $PR_NUMBER` を実行してください" |
       | `review` | "次は `/merge $NUMBER` を実行してください (PR #N を確認後)" |
       | `merge` | "次は `/verify $NUMBER` を実行してください" |
       | `verify` | (通常完了 — next-action メッセージなし) |

4. `docs/guide/customization.md` を更新: (→ AC8)
   - YAML 例に `always-pr: true` と `auto-stop-at: review` をコメント付きで追加
   - Available Keys 表に以下の 2 行を追加:
     - `| always-pr | boolean | false | Size に関わらず PR route を強制する。XS/S Issues でも branch + PR を作成する。--patch フラグより優先 |`
     - `| auto-stop-at | string | "verify" | /auto pipeline の停止 phase を宣言。有効値: spec/code/review/merge/verify。--stop-at=<phase> で per-invocation override 可能 |`
   - "Website project example" セクションを追加:
     ```yaml
     # website 系プロジェクト向け推奨設定 (always-pr + auto-stop-at)
     always-pr: true
     auto-stop-at: review
     ```
   - `docs/ja/guide/customization.md` を同様に日本語で更新 (after all)

5. bats テストを追加: (→ AC9、AC10)
   - `tests/code.bats` (新規作成): `skills/code/SKILL.md` Step 0 に `always-pr` / `ALWAYS_PR` キーワードと pr route 強制の仕様が記述されていることを検証する structural test。`tests/auto.bats` と同様のパターン (awk で Step 0 セクション抽出 → keyword 存在確認)
   - `tests/auto.bats` (更新): `skills/auto/SKILL.md` に以下が存在することを検証するテストケースを追加:
     - `stop-at` キーワードが SKILL.md に存在する
     - `auto-stop-at` キーワードが SKILL.md に存在する
     - enum 値 `spec`、`code`、`review`、`merge` が SKILL.md の stop-at 仕様に存在する
     - next-action ガイダンスのキーワード (例: "/merge" または "next") が SKILL.md に存在する

## Verification

### Pre-merge

- <!-- verify: rubric "modules/detect-config-markers.md のマーカー定義表に always-pr (boolean) と auto-stop-at (enum: spec/code/review/merge/verify) の 2 行が追加されており、それぞれ ALWAYS_PR / AUTO_STOP_AT 変数として展開される" --> `detect-config-markers.md` に `always-pr` / `auto-stop-at` 行が追加されている
- <!-- verify: grep "always-pr" "modules/detect-config-markers.md" --> `detect-config-markers.md` に `always-pr` キーが追加されている
- <!-- verify: grep "auto-stop-at" "modules/detect-config-markers.md" --> `detect-config-markers.md` に `auto-stop-at` キーが追加されている
- <!-- verify: rubric "skills/code/SKILL.md の routing logic に、ALWAYS_PR=true の場合は Size に関わらず pr route を選択する仕様が追加されている" --> `/code` skill が `always-pr` 設定を読んで pr route を強制する
- <!-- verify: rubric "skills/auto/SKILL.md に、AUTO_STOP_AT 設定 (および per-invocation --stop-at=<phase> override) を読んで指定 phase 完了時点で pipeline を停止する仕様が記述されている。enum 値は spec/code/review/merge/verify をサポート" --> `/auto` skill が `auto-stop-at` 設定と `--stop-at=<phase>` フラグをサポート
- <!-- verify: grep "stop-at|stop_at" "skills/auto/SKILL.md" --> `/auto` SKILL.md に `stop-at` キーワードが追加されている
- <!-- verify: rubric "skills/auto/SKILL.md の完了レポートセクションに、stop-at で停止した場合に次の人間アクション (例: '次は /merge $NUMBER を実行してください') を提示する仕様が記述されている" --> 停止後の next-action ガイダンスが SKILL.md に追加されている
- <!-- verify: rubric "docs/guide/customization.md または同等のユーザ向けドキュメントに、always-pr / auto-stop-at の説明と website 系プロジェクト向け推奨設定例 (always-pr: true + auto-stop-at: review) が追加されている" --> ユーザ向け docs に新キーの説明と website 推奨設定例が追加されている
- <!-- verify: command "bats tests/auto.bats" --> auto skill の bats テストが green (stop-at 各 enum 値のケース追加)
- <!-- verify: command "bats tests/code.bats" --> code skill の bats テストが green (always-pr 強制のケース追加)

### Post-merge

- `always-pr: true` を設定した実プロジェクトで `/code XS-issue` を実行し、Size XS でも PR route で実行されることを観察
- `auto-stop-at: review` を設定した実プロジェクトで `/auto N` を実行し、review phase 完了後に停止し merge が実行されないことを観察
- 停止後、`/merge N` で手動 merge できることを確認

## Notes

- **auto-resolve: `--patch` + `always-pr=true` 挙動 (案 A を採用)**: `--patch` フラグが指定された場合は警告を出力して無視し、pr route を強制する。`always-pr` の目的は website プロジェクトの誤 direct push 防止であり、`--patch` による override を許容すると設定が無効化される。案 B (override 許可) より安全側を選択。
- **auto-resolve: `auto-stop-at` + `--batch` 組み合わせ**: 各 Issue ごとに stop-at を適用する。batch 完了レポートで全 Issue の停止状態と次アクションを集約表示する。
- **auto-resolve: `auto-stop-at=review` 時の next-action メッセージ**: preview URL パターンは含めない (プロジェクト依存)。汎用メッセージを採用する。
- **auto-resolve: `--resume` + stop-at セマンティクス**: resume 時も stop-at 設定を適用する (再開後も同じ停止 phase で止まる)。
- **`auto-stop-at` デフォルト値**: `"verify"` (full pipeline = 現状動作)。未設定 / 空文字列は `"verify"` として扱う。
- **`tests/code.bats` は新規作成**: Issue 本文の verify command は `tests/code.bats` を参照するが、このファイルは現時点で存在しない。`tests/auto.bats` と同様の structural test パターンで新規作成する。
- **verify item 数は 10 件 (light mode 限度 5 を超過)**: Issue 本文の AC が 10 件あり、sync rule によりすべて verbatim コピー。実装ステップは 5 件に収まっている。
- **`docs/ja/guide/customization.md` sync**: `docs/guide/customization.md` は `docs/guide/` 配下のため translation-workflow.md の "top-level `docs/*.md`" 規定の厳密な対象外だが、`docs/ja/guide/` に対応する mirror ファイルが存在するため Changed Files に含める。
- **`autonomy:` との直交性**: `always-pr` / `auto-stop-at` は `autonomy:` tier (L1/L2/L3) と直交する軸。customization.md の関連セクションに明記する。
- **ERE grep verify command 確認**: Issue 本文の `grep "stop-at|stop_at" "skills/auto/SKILL.md"` は ripgrep (ERE) で `|` が alternation として機能する正しい ERE 形式。BRE 問題なし。
