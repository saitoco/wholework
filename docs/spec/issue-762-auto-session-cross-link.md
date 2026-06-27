# Issue #762: audit: get-auto-session-report.sh に L3 session retrospective への cross-link footer を追加

## Overview

`/audit auto-session` が生成するデータ層レポート (`docs/reports/auto-session-{session-id}-{date}.md`) と、`/auto` Step 5 が生成する L3 session retrospective (`docs/sessions/{session-id}-{date}/session.md`) は同一 session を別角度で記録するが相互参照がない。

本 Issue は、`scripts/get-auto-session-report.sh` がデータ層レポート生成後に `docs/sessions/{session-id}-*/session.md` の存在を確認し、存在する場合はレポート末尾に "See also:" フッターを追記する機能を追加する。また `skills/auto/SKILL.md` Step 5 に逆方向 (session.md → データ層レポート) の cross-link 手順または運用注記を追加する。

## Changed Files

- `scripts/get-auto-session-report.sh`: report 生成後に `docs/sessions/${SESSION_ID}-*/session.md` を glob 検索し、存在すれば `## See also` footer を `$OUTPUT_PATH` に追記する — bash 3.2+ compatible
- `skills/auto/SKILL.md`: Step 5 L3 auto-retrospective の step 3 (Create session files) の後に、データ層レポート (`docs/reports/auto-session-${AUTO_SESSION_ID}-*.md`) が存在する場合に session.md 末尾へ cross-link を追記するステップを追加
- `tests/get-auto-session-report.bats`: cross-link 動作のテストを追加 (session.md 存在時にフッターが出力される、session.md 不在時はフッターなし)

## Implementation Steps

1. `scripts/get-auto-session-report.sh` のレポート書き込み (`cat > "$OUTPUT_PATH" << REPORT_EOF` ... `REPORT_EOF`) の直後 (line 835 付近、`# Apply narrative draft` ブロックの前) に以下を追記する (→ AC1, AC2, AC3):

   ```bash
   # Cross-link to L3 session retrospective if it exists
   _l3_session_found=""
   for _l3_dir in "docs/sessions/${SESSION_ID}-"*/; do
     if [[ -f "${_l3_dir}session.md" ]]; then
       _l3_session_found="${_l3_dir}session.md"
       break
     fi
   done
   if [[ -n "$_l3_session_found" ]]; then
     printf '\n---\n\n## See also\n\n- [L3 Session Retrospective](%s)\n' "$_l3_session_found" >> "$OUTPUT_PATH"
   fi
   ```

2. `skills/auto/SKILL.md` Step 5 L3 auto-retrospective の step 3 (Create session files) の直後に、以下の step 3a を追加する (→ AC4):

   ```
   3a. **Cross-link to data layer report**: `docs/reports/auto-session-${AUTO_SESSION_ID}-*.md` が存在すれば、Write ツールで `$SESSION_DIR/session.md` の末尾に以下を追記する:
       ```
       ---

       ## See also

       - [Data layer report](docs/reports/auto-session-{AUTO_SESSION_ID}-{DATE}.md)
       ```
       ファイルが存在しない場合はスキップする。
   ```

3. `tests/get-auto-session-report.bats` に 2 つのテストを追加する (→ AC1):

   ```
   @test "cross-link: See also footer appended when L3 session.md exists" {
     # setup: create docs/sessions/{SESSION_ID}-{date}/session.md in tmpdir
     # run report script
     # assert output contains "## See also" and "session.md"
   }

   @test "cross-link: no footer when L3 session.md absent" {
     # setup: no docs/sessions/ directory
     # run report script
     # assert output does not contain "## See also"
   }
   ```

## Verification

### Pre-merge

- <!-- verify: rubric "scripts/get-auto-session-report.sh が、当該 session-id に対応する L3 session retrospective ファイル (docs/sessions/{session-id}-{date}/session.md) の存在を確認し、存在する場合は生成されるデータ層レポートの末尾に See also: パターンの footer を追記する" --> get-auto-session-report.sh が L3 retrospective への cross-link を追記
- <!-- verify: grep "See also" "scripts/get-auto-session-report.sh" --> get-auto-session-report.sh に "See also:" フッター文字列の実装が追加されている
- <!-- verify: grep "session\.md" "scripts/get-auto-session-report.sh" --> スクリプトに L3 session.md ファイルパスへの参照が追加されている
- <!-- verify: rubric "skills/auto/SKILL.md § Step 5 L3 auto-retrospective に、L3 session.md 生成時にデータ層レポートが存在すれば cross-link を session.md の末尾に追記する手順、または運用注記が追加されている" --> SKILL.md にも逆方向の cross-link 手順または運用注記が追加されている (片方向だけでも合格)

### Post-merge

- 次回 batch/XL session で両レポートが生成される際、データ層レポート末尾に L3 retrospective への See also: リンクが出力されることを観察

## Notes

- **glob 検索パターン**: session_id は `3480-1782440098` のような形式で session dir は `docs/sessions/3480-1782440098-2026-06-26/` (実行日付付き)、レポートは `docs/reports/auto-session-3480-1782440098-2026-06-27.md` (生成日付付き)。日付が異なる場合があるため、`docs/sessions/${SESSION_ID}-*/session.md` の glob で検索する
- **bash 3.2+ 互換**: `for _l3_dir in "docs/sessions/${SESSION_ID}-"*/; do` パターンは bash 3.2+ で動作する (配列不使用)
- **PERIOD_MODE では追加しない**: period モード (`--day`, `--since-days`, `--range`) は複数 session を集計するため session.md cross-link は不適用。report mode (single session) のみに適用する
- **--no-github 非依存**: L3 session.md はローカルファイルのため `--no-github` フラグの影響を受けない
- **SKILL.md の step 3a**: session.md へのデータ層レポート cross-link は、実行時点でレポートが未生成の場合もある (`/audit auto-session` は事後生成)。そのため「存在すれば追記、なければスキップ」とする

## Consumed Comments

- saito (MEMBER, first-class): Issue Retrospective — AC2 verify コマンドを `grep "docs/sessions/"` → `grep "session\.md"` に修正 (false positive 回避)、AC1 に supplementary `grep "See also"` を追加。これらは Issue 本文の Auto-Resolved Ambiguity Points に反映済み。(2026-06-27)

## Code Retrospective

### Deviations from Design

- None. 実装は Spec の Implementation Steps と完全に一致した。

### Design Gaps/Ambiguities

- PERIOD_MODE での cross-link 不要の理由が Spec Notes に記載されていたため、コード上で `PERIOD_MODE` チェックを追加する必要がなかった (line 124 での早期 exit により report mode block は single session のみ実行される)。判断確認が不要で実装がシンプルになった。
- bats テストの `cross-link: See also footer appended` は `cd "$BATS_TEST_TMPDIR"` でサブシェル実行が必要だった。スクリプトが CWD 相対パスで `docs/sessions/` を glob するため、テスト tmpdir を CWD にして session dir を作成した。

### Rework

- None. 1 パスで実装完了。全 8 テスト一発 PASS。

## Phase Handoff
<!-- phase: code -->

### Key Decisions
- `REPORT_EOF` 直後に cross-link ブロックを追加した。PERIOD_MODE 分岐は不要 (line 124 の早期 exit が既に分離している)。
- `printf '\n---\n\n## See also\n\n- [L3 Session Retrospective](%s)\n'` で `>>` append にした。heredoc より printf の方が安全 (シェル変数展開が限定的)。
- `skills/auto/SKILL.md` の追記は step 3a 形式で、既存の step 3 (Create session files) と step 4 (retro-proposals) の間に挿入した。

### Deferred Items
- 逆方向 cross-link (session.md → データ層レポート) は step 3a で手順を追加したが、実際の `/auto` 実行時に `docs/reports/auto-session-*.md` が未生成の場合は skip となる。これは意図的な設計 (`/audit auto-session` は事後生成のため)。
- bats テストの `cross-link: See also footer appended` はサブシェル実行で CWD を BATS_TEST_TMPDIR に切り替える形だが、SESSION_DIR の glob マッチに `docs/sessions/session-xlink-2026-06-14/` を使用している。日付依存のテストではないが、固定日付であることに留意。

### Notes for Next Phase
- 変更ファイル: `scripts/get-auto-session-report.sh` (cross-link 追加)、`skills/auto/SKILL.md` (step 3a 追加)、`tests/get-auto-session-report.bats` (2 テスト追加)。
- /verify では rubric AC が 2 個あるため、実装内容を git diff で grader に渡して判定させること。
- 全テスト PASS (8/8)、forbidden expressions 違反なし (変更ファイル限定)。
