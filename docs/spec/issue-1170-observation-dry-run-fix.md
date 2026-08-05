# Issue #1170: observation-trigger: --dry-run を検索実行 + 副作用抑止のセマンティクスに修正

## Overview

`scripts/opportunistic-search.sh` と `scripts/observation-trigger.sh` の `--dry-run` は、現状いずれも**検索そのものを実行せず**に早期 `exit` するため、マッチ集合を副作用なしに観測する手段が存在しない (親 Issue #1118 の Post-merge AC が検証不能だった実害あり)。

本 Issue では `--dry-run` の意味を「検索は実行し、副作用 (Issue へのコメント投稿) のみを抑止する」に修正する。`opportunistic-search.sh` はもともと read-only (`gh issue list` / `gh issue view` のみ) であるため、抑止すべき副作用自体が存在せず、同スクリプトの `--dry-run` は実質「短絡を撤去して常に実行する no-op フラグ」になる。`observation-trigger.sh` は `gh issue comment` という実際の副作用を持つため、こちらは「検索は実行しコメント投稿のみ抑止」という本来の dry-run 挙動になる。

## Changed Files

- `scripts/opportunistic-search.sh`: `--dry-run` の短絡ブロック (`# dry-run mode: skip actual API calls and exit successfully` コメントと `if [ "$DRY_RUN" = true ]; then echo "[]"; exit 0; fi`、`# 1. Fetch closed Issues with phase/verify label` の直前に位置) を削除 — bash 3.2+ 互換
- `scripts/observation-trigger.sh`: 引数パース直後の early-exit ブロック (`if [ "$DRY_RUN" = true ]; then exit 0; fi`) を削除し、コメント投稿呼び出しの条件のみ `$DRY_RUN` でガード — bash 3.2+ 互換
- `modules/observation-trigger.md`: Arguments テーブルの `--dry-run` 行 (「Optional. Skip API calls; return empty array (for testing)」) を新セマンティクスの説明に更新
- `tests/opportunistic-search.bats`: 旧挙動 (`--dry-run` は常に空配列) を前提とした既存テスト3件を、非空マッチデータで実データが返ることを検証する内容に書き換え
- `tests/observation-trigger.bats`: 旧挙動 (`--dry-run` は `opportunistic-search.sh` を呼ばない) を前提とした既存テスト1件を書き換え、コメント投稿抑止を検証する negative case テストを追加

## Implementation Steps

1. `scripts/opportunistic-search.sh` から dry-run 短絡ブロックを削除する。`--dry-run` フラグ自体のパース (`DRY_RUN=true` 代入、L46) は CLI 後方互換のため残すが、削除後は参照されない no-op フラグになる。これにより `--dry-run` 指定時も無指定時と同じ経路で `gh issue list` / `gh issue view` を実行し、実際のマッチ結果 JSON 配列を stdout に出力する (→ 受入条件1)
2. `scripts/observation-trigger.sh` の early-exit ブロック (`if [ "$DRY_RUN" = true ]; then exit 0; fi`、引数パース直後) を削除し、`opportunistic-search.sh` 呼び出し (L71/L73) に dry-run 時も到達させる。for ループ内のコメント投稿箇所 (現行: `if [ "$SKIP" = false ]; then` に続けて `BODY=$(printf ...)` → `gh issue comment` を実行) の条件を `if [ "$SKIP" = false ] && [ "$DRY_RUN" = false ]; then` に変更し、コメント投稿のみを抑止する。冪等性マーカーチェック (`gh issue view` によるマーカー検索、SKIP 判定) と末尾の `echo "$NUMBERS"` は dry-run 有無に関わらず変更しない — Issue Purpose が抑止対象とするのは「コメント投稿という副作用」のみであり、read-only なマーカーチェックはその対象ではないため (after 1) (→ 受入条件2)
3. `modules/observation-trigger.md` の `### Caller → opportunistic-search.sh --event` 直下の Arguments テーブルにある `--dry-run` 行を、「検索は通常どおり実行され API 呼び出しはスキップされない (`opportunistic-search.sh` は元々 read-only で抑止すべき副作用がないため)。CLI 後方互換のため引数としては受理されるが、挙動に影響しない no-op フラグ」という趣旨の説明に更新する (parallel with 1, 2) (→ ドキュメント整合)
4. `tests/opportunistic-search.bats` の既存テスト3件 (`"dry-run: outputs empty array and exits 0"` / `"dry-run: works with --dry-run before skill name"` / `"event filter: --event with dry-run returns empty array"`) を、`MOCK_ISSUE_LIST='[{"number": N}]'` + `MOCK_ISSUE_BODY_N='- [ ] ... <!-- verify-type: opportunistic --> '` (または `event=<name>` 付き observation 形式) の非空フィクスチャを設定したうえで、`--dry-run` 付きの呼び出しが `--dry-run` なしの呼び出しと同一の非空 JSON 結果を返すことを検証する内容に書き換える。「`--dry-run` 指定時は常に空配列」という旧セマンティクスを前提としたアサーションは残さない (after 1) (→ 受入条件3)
5. `tests/observation-trigger.bats` の `"dry-run: exits 0 without calling opportunistic-search.sh"` を、`MOCK_SEARCH_OUTPUT='[{"number": 42, "condition": "..."}]'` を設定したうえで `--dry-run` 指定時に `opportunistic-search.sh` が呼び出され (`search-calls.log` に記録される)、マッチした Issue 番号 (`42`) が stdout に出力されることを検証する内容に書き換える。さらに、同じマッチデータで `--dry-run` 実行時は `gh-calls.log` に `issue comment` 呼び出しが記録されないことを検証する negative case テストを新規追加する (after 2) (→ 受入条件4)

## Verification

### Pre-merge

- <!-- verify: rubric "scripts/opportunistic-search.sh の --dry-run が、API 呼び出しをスキップする短絡をやめ、検索を実行した結果の JSON 配列を stdout に出力する" --> `opportunistic-search.sh --dry-run` が検索結果を返す
- <!-- verify: rubric "scripts/observation-trigger.sh の --dry-run が、検索を実行してマッチした Issue 番号を stdout に出力し、Issue へのコメント投稿のみを抑止する。stdout contract (マッチした Issue 番号を 1 行 1 件・昇順) は --dry-run なしの場合と同一であること" --> `observation-trigger.sh --dry-run` がコメント投稿なしでマッチ集合を返す
- <!-- verify: rubric "tests/opportunistic-search.bats に、--dry-run が検索結果を返すことを検証するテストが追加されている。--dry-run 指定時に空配列が返る旧挙動を前提としたテストが残っていないこと" --> `--dry-run` の新セマンティクスがテストで担保されている
- <!-- verify: rubric "tests/ 配下に、observation-trigger.sh --dry-run が Issue コメントを投稿しないことを検証する negative case のテストが存在する" --> 副作用が発生しないことを検証する negative case が存在する
- <!-- verify: command "bats tests/opportunistic-search.bats" --> `tests/opportunistic-search.bats` が PASS する
- <!-- verify: github_check "gh pr checks" "Run bats tests" --> bats テスト全件が CI で PASS する (pr route)

### Post-merge

- `scripts/observation-trigger.sh --event auto-run --dry-run` を実行し、マッチした Issue 番号が出力され、かつ対象 Issue に新規コメントが投稿されていないことを確認する <!-- verify-type: manual -->

## Notes

- **別フラグ切り出しの判断 (Issue本文で /spec への判断委任あり)**: `scripts/`, `skills/`, `modules/`, `tests/` を横断 grep した結果、本番コード経路で `opportunistic-search.sh` を `--dry-run` 付きで呼び出す既存呼び出し元は確認されなかった (`modules/opportunistic-verify.md`, `modules/verify-classifier.md`, `skills/review/SKILL.md`, `skills/verify/SKILL.md`, `skills/auto/SKILL.md`, `scripts/claude-watchdog.sh`, `scripts/observation-trigger.sh` はいずれも `--event <name>` のみで呼び出し、`--dry-run` を付与しない)。「呼び出しコストを避けたい呼び出し元」は現状存在しないため、新規フラグは追加しない。将来的にコスト回避ニーズが生じた場合は別 Issue で対応する
- **`observation-trigger.sh` の冪等性マーカーチェックは dry-run でも維持**: Issue の Purpose が抑止対象とするのは「コメント投稿という副作用」のみであり、`gh issue view` によるマーカー読み取り (read-only) は対象外と解釈した。この解釈でも AC2 の stdout contract 要件 (`echo "$NUMBERS"` は marker チェック結果に依存しない) は満たされる
- **Pre-merge 検証項目数について**: 本 Spec の Pre-merge 検証は6件で、light テンプレートの目安 (5件) をわずかに超えるが、Verify command sync rule (Issue body の `## Acceptance Criteria > Pre-merge` を逐語コピーし独自に書き換えない) を優先し、件数を変更していない
- **Issue本文の実装箇所引用との整合確認**: Issue本文が引用する行番号 (opportunistic-search.sh L115-120、observation-trigger.sh L66-68) はコードベース調査の結果 (実際の該当行: opportunistic-search.sh L115-120 のコメント+117-120 の if ブロック、observation-trigger.sh L66-68 の if ブロック) とほぼ一致しており、Issue body と実装の間に conflict は検出されなかった
- `--dry-run` なしの経路 (実際にコメントを投稿する経路) の挙動は変更しない。冪等性ガード (#1099) もそのまま維持する (Issue本文 Notes を踏襲)

## Consumed Comments

前回フェーズ (triage → spec) 以降の新規コメントなし。Issue #1170 には現時点でコメントが1件も存在しない (cutoff: 直近の `phase/*` ラベル付与時刻 2026-08-05T03:03:25Z、および全件走査でも 0 件を確認)。

### code フェーズ

前回フェーズ (spec → code) 以降の新規コメントなし (cutoff: 直近の `phase/*` ラベル付与時刻 2026-08-05T05:33:30Z)。cross-phase marker (`type=verify-fail` / `type=preview-ac-unverified`) の全件走査でも該当なし。

## Code Retrospective

### Deviations from Design
- N/A — Implementation Steps 1〜5 を Spec 記載順どおりに実装した。逸脱なし

### Design Gaps/Ambiguities
- N/A — Notes セクションで既に判断済みの論点 (別フラグ切り出し不要、冪等性マーカーチェックは dry-run でも維持) 以外に、実装中に新たな曖昧点は生じなかった

### Rework
- N/A — 各 Implementation Step は一度の Edit で完了し、手戻りは発生しなかった

## review retrospective

### Spec vs. implementation divergence patterns
- N/A — 実装 (PR #1176 diff) は Spec の Implementation Steps 1〜5 と 1:1 で対応しており、構造的な逸脱は検出されなかった (review-light エージェントの Perspective 1 確認結果)

### Recurring issues
- N/A — review-light の4観点 (Spec乖離・エッジケース/堅牢性・セキュリティ/安全性・ドキュメント整合性) いずれも指摘なし。同種issueの再発パターンは見られなかった

### Acceptance criteria verification difficulty
- 6件の Pre-merge AC (rubric×4、command×1、github_check×1) は全て safe mode で自動判定可能だった。`command "bats tests/opportunistic-search.bats"` は safe mode では直接実行できないが、CI job `Run bats tests` への CI reference fallback で代替確認できた — verify command 設計として機能した
- Spec Notes に記載の通り、本 Issue の Pre-merge 検証項目数 (6件) は light テンプレートの目安 (5件) をわずかに超えていたが、UNCERTAIN や verify command の不備は発生せず、実務上の支障はなかった

## Phase Handoff
<!-- phase: review -->

### Key Decisions
- Step 8 静的検証で Pre-merge AC 6件すべてを PASS 判定 (AC1〜5 は code フェーズで既に `[x]` 化済み、AC6 `github_check "gh pr checks" "Run bats tests"` は CI 完了後の本レビューで `[x]` 化)
- Step 10.0 軽量統合レビュー (review-light エージェント) で4観点とも指摘なし。MUST/SHOULD/CONSIDER いずれもゼロ件のため Step 12 (issue resolution) は実施せず
- Base branch conflict pre-check (`git merge-tree`) で `changed in both` ブロックなしを確認、base 側との衝突コンテキストは記録不要と判断

### Deferred Items
- Post-merge AC (`observation-trigger.sh --event auto-run --dry-run` の実環境確認、`verify-type: manual`) は未実施 — `/verify` フェーズでの手動確認に委ねる (code フェーズからの引き継ぎを継続)

### Notes for Next Phase
- MUST issue なしのため `/merge 1176` にそのまま進行可能
- Post-merge AC は手動確認 (`verify-type: manual`) のため、`/verify` 実行時に人手での実環境確認が必要
