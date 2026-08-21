# Issue #1421: auto: run-auto-sub.sh の operate route 誤判定を修正 (Changed Files の ### サブ見出しで空判定)

## Overview

`scripts/run-auto-sub.sh` の `_spec_is_diffless()` (638-655行目) の awk セクション抽出パターンを修正し、`## Changed Files` セクション配下を `### ` サブ見出しでファイル分類した Spec でも正しく非 diff-less (実ファイル変更あり) と判定されるようにする。回帰テストを `tests/run-auto-sub.bats` に追加する。

## Reproduction Steps

1. `## Changed Files` セクション配下を `### scripts (bash 3.2+ 互換)` のような `### ` サブ見出しでファイル分類した Spec を用意する (実例: `docs/spec/issue-1418-remove-permission-bypass.md`)。
2. 現行の awk パターンを手動実行して確認する:
   ```bash
   awk '/^## Changed Files/{flag=1; next} /^#/{flag=0} flag' docs/spec/issue-1418-remove-permission-bypass.md
   ```
   → 空文字列が返る (実際には 40 以上のファイルが `### ` サブ見出し配下に列挙されているにもかかわらず。修正後パターンでは 59 行分のセクション本文が抽出される)。
3. `changed_files` が空になるため `_spec_is_diffless()` は `true` (diff-less) を返し、`run-auto-sub.sh` は本来 `code-pr` を dispatch すべきところ `code-patch` を dispatch する。

## Root Cause

`_spec_is_diffless()` (`scripts/run-auto-sub.sh:638-655`) の awk セクション抽出パターン `/^#/{flag=0}` が、`## Changed Files` セクションの終端を「任意レベルの `#` 見出し行」で判定している。`### scripts (bash 3.2+ 互換)` のような `### ` サブ見出し行に最初にヒットした時点で即座に `flag=0` となり、実際のファイルパス列挙 (`` - `scripts/run-code.sh`: ... `` 等) に到達する前にセクション抽出が終了する。結果、`changed_files` 変数が空文字列になり `_spec_is_diffless()` が `true` を返し、operate route (diff-less) と誤判定される。

#1418 (Size L、`permission-mode: bypass` 撤去、43 ファイル変更) がこの誤判定を受け、本来 pr route + full review が必須なところ `/code --patch` で直接 main にコミットされ、`/review`・`/merge` を完全にスキップした (`/verify 1418` で発見)。

## Changed Files

- `scripts/run-auto-sub.sh`: `_spec_is_diffless()` (638-655行目) 内、652行目の awk パターンを `/^#/{flag=0}` から `/^## /{flag=0}` に変更 (`## Changed Files` と同格以上の見出しでのみ終端) — bash 3.2+ 互換 (既存同様 `awk`/`sed -nE` のみ使用、`mapfile` 等は不使用)
- `tests/run-auto-sub.bats`: `### ` サブ見出しでファイルを分類した `## Changed Files` セクションを持つ Spec fixture に対する回帰テストを追加 (284行目 "Size M + diff-less Spec" テストの直後、306行目 "Size M + Spec with real Changed Files" テストと同型の positive テストとして挿入)

## Implementation Steps

1. `scripts/run-auto-sub.sh` の `_spec_is_diffless()` 内、652行目の awk パターン `/^#/{flag=0}` を `/^## /{flag=0}` に変更する (→ acceptance criteria 1)。
   **Fail-safe critical 判定**: この関数は `code-patch`/`code-pr` の dispatch (review/merge 実行有無) を左右するゲートに該当するため fail-safe critical と判定する。本修正のスコープは awk 終端パターンの変更のみに限定し (Issue Proposal 記載の通り)、以下の既存境界動作は変更しない:
   - `## Changed Files` の内容が `なし` 等の説明文のみ (バッククォート付きファイルパスの列挙が無い) の場合 → 引き続き diff-less=true (意図通りの動作、影響なし)。
   - `## Changed Files` 見出し自体が存在しない場合 → 649行目の早期 `return 1` (非 diff-less) で fail-closed、影響なし。
   - `grep`/`awk` 依存コマンドが失敗した場合 → `grep -q '^## Changed Files' ... || return 1` は fail-closed (判定不能時は非 diff-less = pr route + full review を強制する安全側の既存動作)。`awk`/`sed` パイプライン自体が失敗した場合は `changed_files` が空文字列となり fail-open (diff-less=true) になる既存動作は本 Issue のスコープ外であり変更しない。
   - ファイルパスに `>` / `"` / 改行 / マルチバイト文字が含まれる場合 → `sed -nE` によるバッククォート内抽出はこれらの文字と非干渉であり、今回の修正 (`^## ` と `^#` の判別) の影響を受けない。
2. `tests/run-auto-sub.bats` に新規 `@test` を追加する (284行目テストの直後、306行目テストと同型の fixture 構成を用いる): `## Changed Files` セクション配下を `### scripts` のような `### ` サブ見出しでグルーピングした Spec fixture を用意し、`_spec_is_diffless()` が `false` (非 diff-less) を返すこと — `bash "$SCRIPT" 42` 実行後 `42 --pr` が `$RUN_CODE_LOG` に記録され、`$RUN_REVIEW_LOG`/`$RUN_MERGE_LOG` が両方生成されることをアサートする (→ acceptance criteria 2)。
3. `bats tests/run-auto-sub.bats` を実行し、既存テストと新規テストを含め全て pass することを確認する (→ acceptance criteria 3)。

## Verification

### Pre-merge

- <!-- verify: grep "## /\{flag=0\}" "scripts/run-auto-sub.sh" --> `_spec_is_diffless()` の awk パターンが `## ` (レベル2見出し) でのみ終端するよう修正されている (`/^## /{flag=0}` という連続した部分文字列が存在する)
- <!-- verify: rubric "tests/run-auto-sub.bats contains a regression test verifying that _spec_is_diffless() returns false (non-diffless) for a Spec whose ## Changed Files section is organized with ### subheadings grouping file entries by category" --> `### ` サブ見出しを含む Changed Files セクションに対する回帰テストが追加されている
- <!-- verify: command "bats tests/run-auto-sub.bats" --> 既存テストを含め全て pass する

### Post-merge

なし

## Notes

- **Consumed Comments 反映**: `/issue` retrospective コメント (2026-08-21T00:47:02Z, saito, MEMBER) にて、Pre-merge AC 1 の verify command が `grep "flag=0.*## " ...` (修正前後を判別できない誤ったパターン) から `grep "## /\{flag=0\}" ...` (修正後コードに一意に出現する連続部分文字列を anchor とする、`modules/verify-patterns.md` §23 準拠) へ修正済み。現行 Issue body は既にこの修正を反映しており、本 Spec の Verification セクションもそのまま転記した。Background の行番号 (638-655行目、起票時点記載の 628-651行目から訂正) も同コメントで修正済み。実際に `rg` で手元検証し、現行 (バグあり) コードでは不一致 (exit 1)、修正後コードのシミュレーションでは一致 (exit 0) することを確認済み。
- **既出の類似バグ**: `_spec_is_diffless()` は `docs/spec/issue-1240-run-auto-sub-operate-route.md` (導入時 Spec) のレビュー時点で、既に一度この awk/sed 境界条件の不備を指摘され2箇所修正されている (先頭トークン限定の緩和、セクションクローズ条件の拡張)。同 Spec の Code Retrospective は「既存コードからの『そのまま再利用』判断は、再利用元がカバーしていない境界条件まで無条件に引き継ぐリスクがある」と総括しており、本 Issue (#1421) は同じ関数の別の境界条件 (セクション終端判定) が実運用 (#1418) で顕在化した3件目の事例にあたる。
- **BRE metacharacter チェック**: AC1 の verify command パターン `## /\{flag=0\}` に含まれる `\{`/`\}` は BRE metacharacter 検出対象リスト (`\|`, `\(`, `\)`, `\+`, `\?`) に該当しないためスキップ対象。ripgrep (ERE) では `\{`/`\}` はリテラルの `{`/`}` にマッチするエスケープであり、意図通り動作することを実際に `rg` で検証済み (上記 Consumed Comments 反映の項を参照)。
- **Steering Docs sync candidate check**: `scripts/run-auto-sub.sh` をキーワードに `docs/`, `tests/`, `scripts/`, `modules/` を再帰的に grep した (`docs/structure.md`, `docs/workflow.md`, `docs/tech.md` にヒットあり)。いずれも `--batch`/`--resume`/external kill respawn/`WHOLEWORK_SPAWN_DETACH` 等の高レベルな挙動説明であり、`_spec_is_diffless()` の awk 抽出内部ロジックを記述したものは無いため、sync candidate なし。
- **新規テストケース要件チェック**: 本修正は既存 awk パターンの終端条件を厳密化するものであり、新しい `case`/`if` 分岐や新イベント種別を追加するものではないため、`modules/spec/SKILL.md` の「新規分岐ロジックへの新規テストケース要求」チェックには厳密には該当しない。ただし Issue 自身の Proposal で回帰テスト追加が明示的に要求されており、Implementation Step 2 で対応する。
- **Doc-checker Impact Assessment**: ワークフローフェーズ変更・プロジェクト構造変更のいずれにも該当しない内部バグ修正のため、doc-checker 対象文書 (README.md/CLAUDE.md/docs/workflow.md/`$STEERING_DOCS_PATH/structure.md`) の変更は不要と判断した。
- **Patch route verify command check**: 本 Issue の Verification > Pre-merge に `github_check "gh pr checks"` 系の verify command は含まれていない (grep/rubric/command のみ) ため、patch route (Size S, ALWAYS_PR=false, PR無し) への自動置換対象なし。

## Consumed Comments

- login: saito / authorAssociation: MEMBER / trust tier: first-class / intent: `/issue` retrospective — corrected Pre-merge AC 1's verify command (from an undiscriminating pattern to `grep "## /\{flag=0\}" ...`, anchored on a contiguous substring unique to the fixed code per `modules/verify-patterns.md` §23) and the Background line numbers (628-651 → 638-655); already reflected in the current Issue body, which this Spec's Verification section transcribes verbatim / url: https://github.com/saitoco/wholework/issues/1421#issuecomment-5363823935
