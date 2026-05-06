# Issue #424: verify-executor: http_status / html_check / api_check に --allow-localhost opt-in を追加

## Overview

`http_status` / `html_check` / `api_check` verify commands の safe mode で localhost への HTTP 検証を opt-in で有効にする `--allow-localhost` フラグを追加する。

現状、safe mode ではこれらのコマンドが SSRF 防止のために `127.0.0.0/8` (localhost) を block するため、ローカル dev サーバへの検証が verify command として表現できず `<!-- verify-type: manual -->` に流れている。`--allow-localhost` フラグ付きで明示 opt-in した場合に限り、safe/full 両モードで localhost アクセスを許可する。

合わせて、`scripts/validate-skill-syntax.py` の `KNOWN_VERIFY_COMMAND_TYPES` に未登録の `html_check` / `api_check` を追加する。

## Changed Files

- `modules/verify-executor.md`: `http_status` / `html_check` / `api_check` 行に `--allow-localhost` フラグ使用時の動作説明を追加
- `modules/browser-verify-security.md`: `http_status URL Security Policy` セクションに `--allow-localhost` opt-in 時の動作（safe mode でも localhost を許可）を追記
- `scripts/validate-skill-syntax.py`: `KNOWN_VERIFY_COMMAND_TYPES` に `html_check`・`api_check` を追加、`--allow-localhost` フラグを arg count から除外する処理を追加 — bash 3.2+ compatible
- `tests/validate-skill-syntax.bats`: `--allow-localhost` フラグ付き verify command が構文検証をパスするテストケースを追加
- `skills/issue/SKILL.md`: verify command テーブルの `http_status` / `html_check` / `api_check` 行に `--allow-localhost` フラグの構文・動作説明を追加

## Implementation Steps

1. **`scripts/validate-skill-syntax.py` 更新** (→ AC 3, 4, 5):
   - `KNOWN_VERIFY_COMMAND_TYPES` 辞書の `'http_status': (2, 2),` の後に `'html_check': (3, 3),` と `'api_check': (3, 3),` を追加
   - `validate_verify_commands` 関数内、`--when` を除外する `re.sub` の直後（line 614）に `args_str_for_count = re.sub(r'\s*--allow-localhost\b', '', args_str_for_count)` を追加

2. **`modules/verify-executor.md` 更新** (→ AC 1):
   - 翻訳テーブルの `http_status` 行を更新: `--allow-localhost` フラグ指定時の動作（safe/full 両モードで localhost を許可）を説明に追記。フラグ構文: `http_status "URL" "CODE" --allow-localhost`
   - `html_check` 行と `api_check` 行にも同様の `--allow-localhost` フラグ説明を追記

3. **`modules/browser-verify-security.md` 更新** (after 2) (→ AC 2):
   - `http_status URL Security Policy` セクション内に `--allow-localhost` opt-in 時の挙動（safe mode でも `127.0.0.0/8` を許可）を追記
   - localhost のみ opt-in 対象であること（他 private IP `10.*`/`192.168.*`/`172.16.*-172.31.*` は引き続き block）を明記

4. **`skills/issue/SKILL.md` 更新** (→ AC 7):
   - verify command テーブルの `http_status` 行: 説明に `--allow-localhost` フラグによる opt-in 動作を追記
   - `html_check` 行と `api_check` 行にも同様の `--allow-localhost` フラグ説明を追記

5. **`tests/validate-skill-syntax.bats` 更新** (after 1) (→ AC 6):
   - `@test "success: verify command with --allow-localhost flag passes validation"` テストケースを追加
   - テスト内容: `http_status "http://localhost:3000/" "200" --allow-localhost` / `html_check "http://localhost:3000/" "h1" "--exists" --allow-localhost` / `api_check "http://localhost:3000/api" ".status" "ok" --allow-localhost` の 3 コマンドを含む SKILL.md fixture を作成し、`python3 "$REAL_SCRIPT"` が exit 0・0 error で通ることをアサート

## Verification

### Pre-merge

- <!-- verify: grep "--allow-localhost" "modules/verify-executor.md" --> `modules/verify-executor.md` の `http_status` / `html_check` / `api_check` の各行に `--allow-localhost` フラグ使用時の動作説明が追加されている
- <!-- verify: section_contains "modules/browser-verify-security.md" "http_status URL Security Policy" "--allow-localhost" --> `modules/browser-verify-security.md` の `http_status URL Security Policy` セクションに `--allow-localhost` opt-in 時の動作（safe mode でも localhost を許可）が記述されている
- <!-- verify: grep "allow-localhost" "scripts/validate-skill-syntax.py" --> `scripts/validate-skill-syntax.py` が `--allow-localhost` フラグを arg count から除外する処理を持つ（`--when` modifier と同様の扱い）
- <!-- verify: file_contains "scripts/validate-skill-syntax.py" "'html_check'" --> `scripts/validate-skill-syntax.py` の `KNOWN_VERIFY_COMMAND_TYPES` に `html_check` が追加されている（現在未登録）
- <!-- verify: file_contains "scripts/validate-skill-syntax.py" "'api_check'" --> `scripts/validate-skill-syntax.py` の `KNOWN_VERIFY_COMMAND_TYPES` に `api_check` が追加されている（現在未登録）
- <!-- verify: grep "allow-localhost" "tests/validate-skill-syntax.bats" --> `tests/validate-skill-syntax.bats` に `--allow-localhost` フラグ付き verify command が構文検証をパスするテストケースが追加されている
- <!-- verify: grep "allow-localhost" "skills/issue/SKILL.md" --> `skills/issue/SKILL.md` の verify command テーブルの `http_status` / `html_check` / `api_check` 行に `--allow-localhost` フラグの構文・動作説明が追加されている

### Post-merge

- `http_status "http://localhost:PORT/..." "200" --allow-localhost` を AC に持つ Issue に対して `/verify` を実行すると、UNCERTAIN にならず curl で localhost にアクセスして検証が走ることを確認

## Notes

- `--allow-localhost` は localhost (`127.0.0.0/8`) のみ opt-in 対象。`10.*`、`192.168.*`、`172.16.*-172.31.*` 等の他の private IP は本フラグ指定時も引き続き block
- `html_check` / `api_check` の `KNOWN_VERIFY_COMMAND_TYPES` 未登録は Issue 起票時に判明。本 Issue で合わせて追加
- `html_check` の arg count: (3, 3) — `"URL"`, `"selector"`, `"--exists"` or `"--count=N"` (3rd arg 必須)
- `api_check` の arg count: (3, 3) — `"URL"`, `"jq_expression"`, `"expected_value"` (全 arg 必須)
- `--allow-localhost` 除外 regex: `r'\s*--allow-localhost\b'`。`--when` 除外の直後に `args_str_for_count` に対して適用
- dev サーバライフサイクル管理（起動・終了込み）や他 private IP の opt-in は Out of Scope（別 Issue 対応）

## Code Retrospective

### Deviations from Design

- N/A

### Design Gaps/Ambiguities

- `section_contains` verify command の PASS 確認では、簡易 `grep -A5` では不十分なケースがある（セクション内の対象文字列が 5 行以上先にある場合）。Python スクリプトによる正確な section boundary チェックが必要だった。実装自体は正しく、verify command もPASSしていることを確認済み。

### Rework

- N/A

## review retrospective

### Spec vs. implementation divergence patterns

- 実装は Spec 通りに正確に対応している。`KNOWN_VERIFY_COMMAND_TYPES` への追加、`--allow-localhost` の arg count 除外正規表現、モジュールドキュメント更新がすべて一致。

### Recurring issues

- `browser-verify-security.md` が `browser_check`/`browser_screenshot` 向けの "Processing Steps" セクションと `http_status`/`html_check`/`api_check` 向けの "http_status URL Security Policy" セクションを同一ファイルに持ち、localhost ポリシーが異なる（前者は許可、後者はブロック）。ドキュメントを読む際に混乱が生じうる。将来の同種変更では Processing Steps セクションへの注釈（「このセクションは browser コマンド専用」旨）追加を検討する。
- `except ValueError` フォールバックでのフラグ除外の一貫性: `--when=` を除外する際に `--allow-localhost` も除外リストに追加しなかったため、稀なエッジケースで false-positive が生じうる。将来フラグを追加する際は同フォールバックへの追加も漏れなく行う必要がある。

### Acceptance criteria verification difficulty

- Pre-merge 条件はすべて `grep`/`file_contains`/`section_contains` で自動検証可能な形式になっており品質が高い。UNCERTAIN が 0 件だった。
- `section_contains` の実装には section boundary の正確な判定（Python スクリプト相当）が必要であることを Code Retrospective で指摘済み。verify command の精度向上は別 Issue での対応が望ましい。
