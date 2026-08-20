# Issue #1418: config: permission-mode の bypass オプション (--dangerously-skip-permissions) を完全撤去

## Consumed Comments

No new comments since last phase. (cutoff: 2026-08-20T02:13:21Z — 直近の `phase/issue` label 付与時刻)

## Overview

`.wholework.yml` の `permission-mode` 設定キーと、その `bypass` 値が発行する `--dangerously-skip-permissions` 経路を完全撤去する。撤去後、全 `run-*.sh` (`run-code.sh` / `run-spec.sh` / `run-issue.sh` / `run-review.sh` / `run-merge.sh`) と `scripts/spawn-recovery-subagent.sh` は分岐なしに `--permission-mode auto` のみを使用する。

`scripts/handle-permission-mode-failure.sh` は `permission-mode: auto` 自体の失敗診断スクリプトとして維持するが、診断メッセージが `permission-mode: bypass` へのフォールバックを推奨している (現行 16-18 行目) ため、これは「bypass 分岐を前提にした記述」に該当し書き換える。

撤去は Claude Code 側の `bypassPermissions` mode を消すものではない (公式ドキュメント上も引き続き提供されている)。wholework が独自に維持していた opt-out 経路をやめ、単一経路に固定するという範囲の変更である。

## Changed Files

### scripts (bash 3.2+ 互換)

- `scripts/run-code.sh`: `PERMISSION_MODE`/`PERMISSION_FLAG`/`_PERM_LABEL` 分岐 (121-128 行目) を削除し `PERMISSION_FLAG="--permission-mode auto"` を直書き。`echo "Permissions: ..."` (237 行目) は固定文字列化。280 行目の**コメント** `# --dangerously-skip-permissions from propagating to the fork sub-agent (#284)` も文言変更が必須 (AC の `file_not_contains` はコメントも検出する)。369 行目の `handle-permission-mode-failure.sh` 呼び出しを 2 引数化 — bash 3.2+ 互換
- `scripts/run-spec.sh`: 同様 (113-120 / 228 / 304 行目)。コメント該当なし — bash 3.2+ 互換
- `scripts/run-issue.sh`: 同様 (61-68 / 76 / 143 行目) — bash 3.2+ 互換
- `scripts/run-review.sh`: 同様 (93-100 / 108 / 410 行目)。342 行目の**コメント**も文言変更が必須 — bash 3.2+ 互換
- `scripts/run-merge.sh`: 同様 (84-91 / 99 / 173 行目) — bash 3.2+ 互換
- `scripts/spawn-recovery-subagent.sh`: 142-147 行目の分岐を削除し直書き (`_PERM_LABEL`/`handle-permission-mode-failure.sh` 呼び出しはこのスクリプトには無い) — bash 3.2+ 互換
- `scripts/handle-permission-mode-failure.sh`: 第 3 引数 `permission_mode` を削除して 2 引数 (`exit_code` `elapsed`) 化。ヒューリスティックを `exit_code != 0 AND elapsed <= 30` に単純化。診断メッセージから `permission-mode: bypass` 誘導を削除し、allow rules テンプレート適用と SECURITY.md 参照に差し替える。ヘッダコメント (2-6 行目) も同期 — bash 3.2+ 互換

### config / modules

- `.wholework.yml`: 3 行目 `permission-mode: auto` を削除 (**Issue 本文 Scope 未記載 / Purpose 記載に基づき追加**)
- `modules/detect-config-markers.md`: Marker Definition Table の `permission-mode` 行 (57 行目) と Output セクションの `PERMISSION_MODE:` 行 (140 行目) を削除
- `modules/ambiguity-detector.md`: 42 行目 `claude -p --dangerously-skip-permissions` → `claude -p --permission-mode auto`
- `modules/autonomy-tier.md`: 25 行目 ``Under `permission-mode: auto`, ...`` を、設定可能なモードを含意しない表現 (例: `Under Claude Code auto mode`) に変更
- `modules/verify-patterns.md`: 38 行目の例が `get-config-value.sh permission-mode auto` を引用しているが、この呼び出しは本 Issue で全消滅する。現存する同形の呼び出し (`scripts/run-code.sh` の `"$SCRIPT_DIR/get-config-value.sh" autonomy L1`) に差し替える

### skills

- `skills/auto/SKILL.md`: 10 / 311 行目の `claude -p --dangerously-skip-permissions` および「full permission bypass」表現を `--permission-mode auto` ベースに変更
- `skills/verify/SKILL.md`: 267 行目 ``**Non-interactive mode** (`--dangerously-skip-permissions` environment)`` を `--permission-mode auto` 環境に変更
- `skills/spec/SKILL.md`: 789 行目の挿入位置の**例示**が `--dangerously-skip-permissions` を使っている。現存する別のコード断片を例示に差し替える
- `skills/review/SKILL.md`: 306 行目の `get-config-value.sh permission-mode auto` 例を `modules/verify-patterns.md` と同じ差し替え先に揃える (両者は同一例文の複製)

### docs (英語ソース)

- `SECURITY.md`: 「Permission Modes (`/auto`)」節 (38-101 行目) を単一モード前提に再構成。`### bypass mode (legacy)` / `### Security comparison` / `### Migration` を削除し、auto mode の説明・allow rules テンプレート適用手順・**auto mode 利用要件** (公式ドキュメント実査に基づく: Plan は全プラン対応、Team/Enterprise は管理者が `permissions.disableAutoMode` で無効化可能、モデルは Sonnet 4.6+ / Opus 4.6+ / Fable 5) に置き換える
- `README.md`: 55 行目から `--dangerously-skip-permissions` 記述を削除。59 行目の「permission-bypass behavior」も表現を更新
- `docs/workflow.md`: 56 行目 operate route の逃げ道記述からの ``or set `permission-mode: bypass``` 削除 (allowed-tools 拡張のみを唯一の手段として記述)、109 行目の `/auto` 説明を単一経路化
- `docs/tech.md`: 54 行目「configurable permission mode」を単一経路の記述に変更、73 行目の autonomy tier 直交性説明から `permission-mode` 参照を整理
- `docs/product.md`: 79 / 171 行目の autonomy tier 直交性説明、180 行目 § Terms「Non-interactive mode」定義中の `--dangerously-skip-permissions` を更新
- `docs/structure.md`: 197 行目 `handle-permission-mode-failure.sh` の説明をシグネチャ変更後の内容に同期
- `docs/environment-adaptation.md`: 32 行目のサンプル YAML から `permission-mode` 行を削除
- `docs/guide/customization.md`: 68-70 行目 (サンプル YAML + コメント 2 行)、151 行目 (Available Keys 表の行) を削除。加えて **134 / 135 行目** (`preview-url-command` / `preview-basic-auth-command` の「the same trust level as `permission-mode`」)、**166 行目** (`themes` のキー衝突例 ``(e.g. `autonomy`, `permission-mode`)``) も別キーへの言い換えが必須 — AC の `file_not_contains` は全出現を検出する (**Issue 本文 Scope の記述より広い**)
- `docs/guide/autonomy.md`: 44 行目の `permission-mode: auto` 言及、71-73 行目「How the tier relates to `permission-mode`」節を撤去後の状態に書き換え
- `docs/guide/auto-mode-template.json`: 3 行目 `description` 中の「before using permission-mode: auto」を設定キー非依存の表現に変更 (**Issue 本文 Scope 未記載 / 追加**)

### tests

- `tests/run-code.bats`: bypass 専用テスト (406 行目 `@test "permission-mode: bypass in .wholework.yml uses --dangerously-skip-permissions"`) を削除。378 行目の auto テストは `get-config-value.sh` 上書きを外して常時経路の検証に改め、`! grep -q "FLAG_SKIP_PERMS=1"` の回帰ガードを維持。setup / fixture 内の `permission-mode: bypass` 行と mock の `permission-mode)` 分岐を全削除
- `tests/run-spec.bats`: 同様 (302 行目の bypass テスト削除 / 218・274 行目の auto テスト整理 / fixture・mock 掃除)
- `tests/run-issue.bats`: 同様 (242 行目の bypass テスト削除)
- `tests/run-review.bats`: 同様 (1135 行目の bypass テスト削除。fixture の `permission-mode: bypass` 行が約 20 箇所ある)
- `tests/run-merge.bats`: 同様 (421 行目の bypass テスト削除)
- `tests/run-code-mergeability.bats`: setup の fixture・mock から `permission-mode` を削除
- `tests/run-auto-sub.bats`: 19 行目 fixture の `permission-mode: bypass` 行を削除
- `tests/handle-permission-mode-failure.bats`: `@test "permission-mode bypass: elapsed=5 exit=1 no diagnostic"` を削除し、残る 3 ケースを 2 引数呼び出しに更新

### 翻訳ミラー (個別 verify command は付与しない)

- `README.ja.md`, `docs/ja/workflow.md`, `docs/ja/tech.md`, `docs/ja/product.md`, `docs/ja/structure.md`, `docs/ja/environment-adaptation.md`, `docs/ja/guide/customization.md`, `docs/ja/guide/autonomy.md`: `/doc translate ja` により英語ソースと同期。`SECURITY.md` に ja ミラーは存在しない

### 対象外 (Non-Goals — 変更しない)

- `docs/spec/*.md` / `docs/reports/*.md` / `docs/ja/reports/*.md` / `docs/stats/*.md` — 履歴記録
- `modules/worktree-lifecycle.md` — worktree 内の `mv`/`cp` 挙動差に関する Tips であり PERMISSION_FLAG 分岐とは無関係

## Implementation Steps

受入条件の記号は `## Verification > Pre-merge` の上から順に A-K を割り当てたもの (A: run-code.sh / B: run-spec.sh / C: run-issue.sh / D: run-review.sh / E: run-merge.sh / F: spawn-recovery-subagent.sh / G: detect-config-markers.md / H: customization.md / I: SECURITY.md / J: README.md / K: bats テスト)。

1. 6 スクリプト (`run-code.sh` / `run-spec.sh` / `run-issue.sh` / `run-review.sh` / `run-merge.sh` / `spawn-recovery-subagent.sh`) の `PERMISSION_MODE` 取得・`PERMISSION_FLAG` 分岐・`_PERM_LABEL` 分岐を削除し `PERMISSION_FLAG="--permission-mode auto"` を直書き。`run-code.sh` 280 行目・`run-review.sh` 342 行目の**コメント内の `--dangerously-skip-permissions`** も同時に文言変更する (→ 受入条件 A-F)
2. `scripts/handle-permission-mode-failure.sh` を 2 引数化 (`exit_code` `elapsed`) し、判定を `exit_code != 0 AND elapsed <= 30` に単純化。診断メッセージから bypass 誘導を削除し、allow rules テンプレート適用 (`docs/guide/auto-mode-template.json`) と SECURITY.md 参照に差し替える。ヘッダコメントも同期。5 箇所の呼び出し側を 2 引数に更新 (1 の後) (→ 受入条件 K、および A-E: 呼び出し行の更新は各 runner 内)
3. `.wholework.yml` から `permission-mode: auto` 行を削除し、`modules/detect-config-markers.md` の表行 (57 行目) と Output 行 (140 行目) を削除 (1, 2 と並行可) (→ 受入条件 G)
4. `modules/ambiguity-detector.md` / `modules/autonomy-tier.md` の文言更新と、`modules/verify-patterns.md` 38 行目・`skills/review/SKILL.md` 306 行目の例文を現存する `get-config-value.sh autonomy L1` 呼び出しに差し替え (両ファイルは同一例文なので同時に更新) (1 の後) (→ 対応する pre-merge AC なし。「AC が捕捉しない残留リスク」参照)
5. `skills/auto/SKILL.md` (10 / 311 行目)、`skills/verify/SKILL.md` (267 行目)、`skills/spec/SKILL.md` (789 行目) の言及を更新。SKILL.md 編集時は半角感嘆符・三連バッククォートを本文に持ち込まないこと (3, 4 と並行可) (→ 対応する pre-merge AC なし。「AC が捕捉しない残留リスク」参照)
6. `SECURITY.md`「Permission Modes (`/auto`)」節を単一モード前提に再構成し、bypass 節・比較節・Migration 節を削除。auto mode 利用要件は公式ドキュメント実査結果 (全プラン対応 / 管理者による `permissions.disableAutoMode` / モデル要件) を反映する (1 の後) (→ 受入条件 I)
7. `README.md` (55 / 59 行目)、`docs/workflow.md` (56 / 109 行目)、`docs/tech.md` (54 / 73 行目)、`docs/product.md` (79 / 171 / 180 行目)、`docs/structure.md` (197 行目)、`docs/environment-adaptation.md` (32 行目) を更新 (6 の後) (→ 受入条件 J)
8. `docs/guide/customization.md` の 68-70 / 151 行目を削除し、134 / 135 / 166 行目の `permission-mode` 言及を別表現・別キーに言い換える。`docs/guide/autonomy.md` (44 / 71-73 行目)、`docs/guide/auto-mode-template.json` (3 行目) を更新 (7 と並行可) (→ 受入条件 H)
9. `tests/*.bats` 8 ファイルを更新: bypass 専用テストケースを削除し、fixture の `permission-mode: bypass` 行と mock の `permission-mode)` 分岐を掃除。各 runner の auto テストは `get-config-value.sh` 上書きを外した「常に `--permission-mode auto` を渡す」形に改め、`! grep -q "FLAG_SKIP_PERMS=1"` の否定アサーションを回帰ガードとして必ず残す。`tests/handle-permission-mode-failure.bats` は bypass ケースを削除し残り 3 ケースを 2 引数呼び出しに更新。`bats --jobs $(nproc) tests/` が PASS することを確認 (1, 2 の後) (→ 受入条件 K)
10. `/doc translate ja` で `README.ja.md` と `docs/ja/*` の対応ミラーを再生成し、`bash scripts/check-translation-sync.sh` で同期状態を確認 (3-8 の後) (→ post-merge 受入条件)

## Verification

### Pre-merge

- <!-- verify: file_not_contains "scripts/run-code.sh" "dangerously-skip-permissions" --> `scripts/run-code.sh` から `--dangerously-skip-permissions` 分岐が削除され、常に `--permission-mode auto` を使用する
- <!-- verify: file_not_contains "scripts/run-spec.sh" "dangerously-skip-permissions" --> `scripts/run-spec.sh` から `--dangerously-skip-permissions` 分岐が削除され、常に `--permission-mode auto` を使用する
- <!-- verify: file_not_contains "scripts/run-issue.sh" "dangerously-skip-permissions" --> `scripts/run-issue.sh` から `--dangerously-skip-permissions` 分岐が削除され、常に `--permission-mode auto` を使用する
- <!-- verify: file_not_contains "scripts/run-review.sh" "dangerously-skip-permissions" --> `scripts/run-review.sh` から `--dangerously-skip-permissions` 分岐が削除され、常に `--permission-mode auto` を使用する
- <!-- verify: file_not_contains "scripts/run-merge.sh" "dangerously-skip-permissions" --> `scripts/run-merge.sh` から `--dangerously-skip-permissions` 分岐が削除され、常に `--permission-mode auto` を使用する
- <!-- verify: file_not_contains "scripts/spawn-recovery-subagent.sh" "dangerously-skip-permissions" --> `scripts/spawn-recovery-subagent.sh` から `--dangerously-skip-permissions` 分岐が削除され、常に `--permission-mode auto` を使用する
- <!-- verify: file_not_contains "modules/detect-config-markers.md" "permission-mode" --> `modules/detect-config-markers.md` から `permission-mode` のフォールバック値解決ロジックの記述が削除される
- <!-- verify: file_not_contains "docs/guide/customization.md" "permission-mode" --> `docs/guide/customization.md` の Available Keys 表とサンプル YAML から `.wholework.yml` の `permission-mode` キーの説明が削除される
- <!-- verify: file_not_contains "SECURITY.md" "dangerously-skip-permissions" --> `SECURITY.md` から `--dangerously-skip-permissions` の記述が削除され、`--permission-mode auto` の単一経路のみが記載される
- <!-- verify: file_not_contains "README.md" "dangerously-skip-permissions" --> `README.md` から `--dangerously-skip-permissions` の記述が削除される
- <!-- verify: github_check "gh run list --workflow=test.yml --branch=main --limit=1 --json conclusion --jq '.[0].conclusion'" "success" --> 全 bats テストが pass する (更新後の `tests/run-*.bats` を含む、patch route)

### Post-merge

- マージ後の `README.ja.md`・`docs/ja/*` が `/doc translate ja` により撤去後の英語ソースと同期している
- マージ後の `/auto` 実行 (任意の Issue) で `run-*.sh` が `--permission-mode auto` のみで正常完走し、classifier ブロックに起因する hang が発生しないことを確認する

## Tool Dependencies

### Bash Command Patterns
- なし (既存の `git` / `gh` / `bats` パターンで充足)

### Built-in Tools
- なし (`Read` / `Edit` / `Write` / `Grep` はすべて `/code` の `allowed-tools` に登録済み)

### MCP Tools
- なし

## Notes

### Issue 本文と実装の食い違い (Conflict with implementation)

1. **`.wholework.yml` が Scope 未記載** — Issue 本文の Purpose は「`.wholework.yml` の `permission-mode` 設定キー自体を削除し」と述べているが、`## Scope` のファイル一覧に `.wholework.yml` が無い。実装確認: 本リポジトリ自身の `.wholework.yml` 3 行目に `permission-mode: auto` が存在する。**解決 (auto-resolve)**: Purpose の記述を優先し Changed Files に追加した。
2. **`docs/guide/auto-mode-template.json` が Scope 未記載** — 実装確認: 3 行目 `description` に「before using permission-mode: auto」がある。**解決**: Changed Files に追加。
3. **`docs/guide/customization.md` の変更範囲が Issue 本文の記述より広い** — 本文は「Available Keys 表とサンプル YAML から削除」と書いているが、AC は `file_not_contains "docs/guide/customization.md" "permission-mode"` であり全出現の除去を要求する。実装確認: 134 / 135 行目 (`preview-url-command` / `preview-basic-auth-command` の信頼レベル類比) と 166 行目 (`themes` のキー衝突例) にも出現する。**解決**: AC を満たすため 3 箇所とも言い換える。134 / 135 行目は「`.wholework.yml` を checked-out branch 上で信頼済みとして扱う必要がある」という趣旨を `permission-mode` 参照抜きで保つ。166 行目の例は現存する別キー (例: `autonomy`, `spec-path`) に差し替える。
4. **`SECURITY.md` の「Non-Max plan users」記述が事実として陳腐化** — 現行 101 行目は「`--permission-mode auto` requires the Claude Code Max plan」と述べる。公式ドキュメント実査 (下記) では **Plan: All plans** であり、この前提は既に誤り。**解決**: bypass 誘導の削除と同時にプラン要件記述も実査結果へ更新する。
5. **`docs/workflow.md` 56 行目の逃げ道が消える** — operate route で任意の外部 CLI が必要なプロジェクトに対し「`/code` の allowed-tools を拡張するか `permission-mode: bypass` を設定する」と案内している。bypass 撤去により後者は選択肢でなくなる。**解決**: allowed-tools 拡張のみを唯一の手段として記述する (機能的な選択肢の縮小であり、Issue の意図した帰結)。

### 外部仕様の実査結果 (Claude Code 公式ドキュメント)

`https://code.claude.com/docs/en/permission-modes` および `.../permissions` を確認:

- `--permission-mode` の値として `auto` と `bypassPermissions` は**いずれも Claude Code 側では引き続き有効**。本 Issue は wholework が提供していた opt-out を消すだけで、Claude Code の機能を消すものではない
- auto mode の利用要件 — **Plan: All plans**。Team/Enterprise では管理者が managed settings の `permissions.disableAutoMode` で無効化可能。モデルは Anthropic API 上で Opus 4.6 以降 / Sonnet 4.6 以降 / Fable 5
- 「Pro, Max, Team プランでは auto mode が組み込みの起動時 permission mode」— Issue 本文の 2026-08-14 の記述と整合
- 影響確認: `run-*.sh` は `--model sonnet` (Sonnet 5)、`spawn-recovery-subagent.sh` は `ANTHROPIC_MODEL="claude-sonnet-4-6"` を使用しており、いずれも auto mode 対応モデル要件を満たす

### fail-safe critical script の判定

現行の 6 スクリプトは `get-config-value.sh permission-mode auto 2>/dev/null || echo auto` という fail-open (取得失敗時は `auto` にフォールバック) パターンを持つため、判定基準 (c) に該当する。本 Issue はこの読み取り自体を削除するため、撤去後は設定入力が存在せず fail-open 経路も消滅する (`PERMISSION_FLAG` が定数化)。したがって空入力・特大入力・特殊文字入力に関する追加のエッジケース規定は不要 — 入力面が無くなることが解である。この判断根拠を実装時に失わないため、コメント等で「設定由来ではなく固定」であることが読み取れる形にする。

`scripts/handle-permission-mode-failure.sh` は常に exit 0 の診断出力専用スクリプトでありゲート/バリデータではないため、判定基準 (a)(b) には該当しない。第 3 引数削除は後方互換上も安全 (bash は余分な位置引数を黙って無視する) だが、本 Issue 内で 5 箇所の呼び出し側をすべて 2 引数に揃える。

### audit/investigation-type Issue の判定

**該当しない**。本 Issue の目的は既存項目の調査・分類ではなく、単一の一貫した機能撤去である。判断根拠となる per-item の分類表を成果物として残す要件もない。したがって識別子の存在検証を要求する追加 Implementation Step は設けない (ただし Changed Files に記載した行番号は本 Spec 作成時点で grep 実査済み)。

### allowed-tools 影響連鎖チェックの判定

**新規 `scripts/*.sh` は追加しない** ため Case 1 は非該当。Changed Files に `modules/*.md` (4 ファイル) を含むため Case 2 の軽量ゲートを評価したが、いずれの変更も既存記述の削除・文言変更であり、モジュール内に**新規のスクリプト呼び出しを導入しない**。`modules/verify-patterns.md` の差し替え例文は verify command の書き方を示す**例示**であって、読み手 skill が実行する呼び出しではない。したがって reader SKILL.md の `allowed-tools` 追加は不要。

### 新規分岐ロジックに対する新規テストケース要件の判定

本 Issue は分岐を**削除**する変更であり、既存ファイルへ新規分岐ロジックを追加する Implementation Step は存在しないため、当該チェックは非該当。ただし Step 9 では、bypass テスト削除に伴って各 runner の auto テストを「常に `--permission-mode auto` を渡し、`--dangerously-skip-permissions` は決して渡さない」ことを検証する回帰ガード (`! grep -q "FLAG_SKIP_PERMS=1"`) として残すことを必須とする。mock `claude` の `--dangerously-skip-permissions)` 分岐は、この否定アサーションを成立させるために**削除せず維持**する。

### AC と Verification の項目数について

Issue 本文の `## Acceptance Criteria > Pre-merge` は 11 項目であり、`docs/tech.md`「Spec Simplicity Rules」の full 上限 (10) を 1 件超える。verify command 同期規則 (Issue 本文からの逐語コピー) と件数整合チェックを優先し、11 項目のまま維持する。意図的な逸脱。

### AC が捕捉しない残留リスク

`file_not_contains "SECURITY.md" "dangerously-skip-permissions"` はフラグ名のみを対象とするため、`SECURITY.md` 51 / 96 / 101 行目の `permission-mode: bypass` という**設定値表記**は AC 上素通りする。Step 6 で必ず併せて除去すること。同様に `README.md` 59 行目の「permission-bypass behavior」も AC 対象外なので Step 7 で明示的に扱う。

Issue 本文の pre-merge AC 11 項目は代表サンプルであり、Changed Files の全ファイルを覆っていない。特に **Step 4 (`modules/ambiguity-detector.md` / `modules/autonomy-tier.md` / `modules/verify-patterns.md` / `skills/review/SKILL.md`) と Step 5 (`skills/auto/SKILL.md` / `skills/verify/SKILL.md` / `skills/spec/SKILL.md`)、および Step 7 の `docs/*` 群 (README.md 以外)、Step 8 の `docs/guide/autonomy.md` / `auto-mode-template.json`、Step 3 の `.wholework.yml`** には対応する pre-merge AC が存在しない。AC 追加ではなく Spec の Changed Files / Implementation Steps 側で担保する方針を採ったため、`/review` は Spec 準拠チェックでこれらの未 AC 項目を明示的に照合すること。AC を追加しなかった理由は (a) verify command 同期規則が Issue 本文からの逐語コピーを求めており独自追加は規則外、(b) 既に simplicity 上限を超過しており更に 8 項目増やすと verify 面が肥大する、の 2 点。

### 自律的 auto-resolve (非対話モード)

本 Spec は `--non-interactive` で作成されたため、`AskUserQuestion` を使わず全曖昧点をモデル判断で解決した。解決内容は Issue の retrospective コメントとして投稿する Auto-Resolve Log に記録する。

## Phase Handoff
<!-- phase: code -->

### Key Decisions

- `--patch --non-interactive` で明示実行されたため、Size L でも flag precedence により patch route を採用した (Spec は pr route を前提に AC #11 を書いていた)。`github_check "gh pr checks" "Run bats tests"` を `github_check "gh run list --workflow=test.yml --branch=main --limit=1 --json conclusion --jq '.[0].conclusion'" "success"` へ Step 10 のルールに従い自動修正し、Issue 本文と Spec の両方に同期した
- `--workflow=` の対象は `.github/workflows/` に複数ファイル (`dco.yml` / `kanban-automation.yml` / `test.yml`) があるため `test.yml` (bats を実行する workflow) を選択した
- Spec の Notes に列挙された「AC が捕捉しない残留リスク」(SECURITY.md の `permission-mode: bypass` 設定値表記、README.md の「permission-bypass behavior」表現) はすべて Notes 記載通りに対応した — 見落としなし
- `tests/*.bats` の一括置換は Edit ツールの `replace_all` で機械的に行った (`permission-mode) echo "bypass" ;;` 行の全削除、`permission-mode: bypass\nauto-retry-on-fail:...` フィクスチャブロックの全削除)。各ファイル編集後に個別 bats 実行 → 最終的に `bats --jobs 18 tests/` で全 1879 件 PASS を確認した

### Deferred Items

- `docs/ja/*` と `README.ja.md` の同期は本 Code フェーズ内で `/doc translate ja` 相当の手動同期として実施済み (Step 10 として)。`scripts/check-translation-sync.sh` で対象 8 ファイルすべて IN_SYNC を確認した (既存の無関係な `docs/guide/xl-decomposition.md` の drift は対象外のまま残存)
- `/auto` 実行時に classifier ブロック起因の hang が起きないことの確認は post-merge の opportunistic AC のまま — この Code フェーズでは検証していない
- `#398` (plan 別 `permission-mode: auto` 互換性の preflight probe、Icebox) は本 Issue の対象外のまま。再評価は別 Issue で

### Notes for Next Phase

- patch route のため PR は存在しない。`/verify` は post-merge に、この commit 群 (11 commits) の `gh run list` 結果を評価すること
- Issue 本文の AC #11 (旧 `gh pr checks`) は `gh run list` 形式に書き換え済み。`/verify` フェーズはこの新形式を前提に評価する
- チェックボックスは AC 1-10 のみ `[x]` 済み。AC #11 (CI) は CI verification AC exclusion ルールによりこの Code フェーズでは意図的に未チェックのまま — post-merge の `/verify` で評価される

## spec retrospective

### Minor observations

- Issue 本文の `## Scope` が `grep -rl` の結果と完全一致していなかった (`.wholework.yml` と `docs/guide/auto-mode-template.json` が欠落)。撤去系 Issue では起票時の grep 結果をそのまま Scope に貼るだけでは足りず、「設定キー自体を消す」という Purpose の帰結として自リポジトリの設定ファイルが対象に入ることを明示的に確認する必要がある
- 撤去対象シンボルが**例示**として使われている箇所 (`modules/verify-patterns.md` / `skills/review/SKILL.md` の shell quoting 例、`skills/spec/SKILL.md` の挿入位置の例) は、機能的な依存ではないため Scope 検討時に見落としやすい。ただし放置すると「実在しないコードを指す例文」になり、後続の Spec/review がその例を信じて誤った検索文字列を生成する二次被害が起きる
- AC の `file_not_contains` は**コメント行も対象**という性質が、本 Issue では 2 箇所 (run-code.sh / run-review.sh の #284 コメント) で効いてくる。「分岐の削除」という Issue の言葉から実装者がコメントまで想起するとは限らないので、Spec 側で行番号付きで明示した

### Judgment rationale

- `handle-permission-mode-failure.sh` を「維持するが引数を減らす」と解釈した。Issue 本文は「撤去対象ではない」と明言する一方で「bypass 分岐を前提にした記述が残っていないか確認する」と要求しており、恒真ガードになる第 3 引数はまさに後者に該当すると判断した。スクリプト自体の存在は保つのでどちらの指示にも反しない
- pre-merge AC を追加しない判断をした。Step 4 / 5 など AC 未カバーの実装ステップが残るが、verify command 同期規則 (Issue 本文からの逐語コピー) を破ってまで AC を増やすより、Spec の Changed Files と Implementation Steps で担保し `/review` の Spec 準拠チェックに載せるほうが規約整合的と判断した。この未カバー範囲は Notes に明示列挙してある
- `docs/workflow.md` の operate route の逃げ道 (`permission-mode: bypass` を設定して任意の外部 CLI を使う) が消えることを、機能縮小として受け入れた。Issue が意図した帰結そのものであり、代替手段 (`/code` の allowed-tools 拡張) が既に文書化されているため

### Uncertainty resolution

- 「auto mode は Max プラン必須か」— `SECURITY.md` の現行記述と Issue 本文の背景 (2026-08-14 に Pro/Max/Team でデフォルト化) が食い違っていた。Claude Code 公式ドキュメント (`code.claude.com/docs/en/permission-modes`) を実査し、**Plan: All plans** / Team・Enterprise は管理者が `permissions.disableAutoMode` で無効化可能 / モデルは Opus 4.6 以降・Sonnet 4.6 以降・Fable 5 と確定した。`SECURITY.md` の記述は事実誤りとして更新対象に含めた
- 「Claude Code 側の `bypassPermissions` mode 自体が廃止されたのか」— 廃止されていない。公式ドキュメントに `bypassPermissions` は現役のモードとして記載がある。本 Issue は wholework が提供していた opt-out 経路を消すだけ、という位置づけを Overview に明記した
- 「`spawn-recovery-subagent.sh` が使う `claude-sonnet-4-6` は auto mode 対応モデルか」— 対応する (Sonnet 4.6 以降が要件)。撤去によって recovery subagent が起動不能になるリスクはない
- 新規テストケース要件チェックは非該当と判定した (分岐の追加ではなく削除のため)。ただし bypass テスト削除後に「auto しか渡らない」ことを保証する否定アサーションが消えると回帰検知が空くため、`! grep -q "FLAG_SKIP_PERMS=1"` の維持を Step 9 の必須事項として明記した

## Code Retrospective

### Deviations from Design

- Issue 本文の `## Acceptance Criteria > Pre-merge` 最終項目は `github_check "gh pr checks" "Run bats tests"` (PR route 前提) だったが、本 Issue は Size L でも `/code 1418 --patch --non-interactive` として明示的に patch route で実行された。`--patch` フラグは Size ベースの自動判定より優先されるため (`skills/code/SKILL.md` Flag precedence)、PR は作られず `gh pr checks` は解決不能。Step 10 の「Patch route verify command check」ルールに従い `github_check "gh run list --workflow=test.yml --branch=main --limit=1 --json conclusion --jq '.[0].conclusion'" "success"` へ自動修正し、Issue 本文と Spec の両方に同期した。Spec 側は Size L → pr route を前提に書かれていたため、これは Spec の誤りではなく実行時のルート選択 (呼び出し引数) に起因する差分
- `--workflow=` の対象ファイルは Spec に明記されていなかった (複数 workflow file 環境での要否は `modules/verify-classifier.md` の一般規則のみ規定)。`.github/workflows/` に `dco.yml` / `kanban-automation.yml` / `test.yml` の 3 ファイルが存在するため `--workflow=test.yml` を採用した

### Design Gaps/Ambiguities

- N/A — Spec の行番号付き Changed Files が実装時点の実ファイルと完全に一致しており、Implementation Steps の記載通りに実装できた

### Rework

- N/A — 手戻りなし。Spec Notes に記載された「AC が捕捉しない残留リスク」(SECURITY.md の `permission-mode: bypass` 設定値表記、README.md の「permission-bypass behavior」表現) は事前に列挙されていたため、実装時に見落としなく一度で反映できた
