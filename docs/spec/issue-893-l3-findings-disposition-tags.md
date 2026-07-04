# Issue #893: auto: L3 session retrospective の Findings を disposition タグ必須の単一セクションに統合

## Overview

`/auto` の L3 session retrospective (`skills/auto/SKILL.md` Step 5 が書き出す `docs/sessions/*/session.md`) は、現在 `## What worked` / `## Limits and gaps` / `## Improvement candidates` / `## Auto Retrospective > ### Improvement Proposals` という並行した複数セクションを持つ。`modules/retro-proposals.md` の自動 Issue 化パイプラインが実際に読むのは末尾の `### Improvement Proposals` のみで、`## Limits and gaps` に書いた改善観察を手動で `### Improvement Proposals` に転記しないとパイプラインを素通りする。この手動同期漏れが構造的な起票漏れ (#892, および遡及起票された #823/#824) を招いていた。

本 Issue は `## Limits and gaps` と `## Improvement candidates` を単一の `## Findings` リストに統合し、各項目に disposition タグ (`[Filed: #N]` / `[No action: <理由>]` / `[Resolved directly: <対応>]`) を必須化する。さらに `scripts/check-session-findings-disposition.sh` を新設し、タグ欠落を機械的に検出できるようにして「全部拾えたか」を意味判断ではなく決定的チェックで検証可能にする。`### Improvement Proposals` は `## Findings` のうち起票対象の項目を機械転記する形に変え、`modules/retro-proposals.md` の読み取りロジックは不変のまま維持する。

## Changed Files

- `scripts/check-session-findings-disposition.sh`: 新規作成。`session.md` の path を引数に取り `## Findings` の各 `- ` bullet に canonical disposition タグがあるか検査するチェックスクリプト — bash 3.2+ 互換
- `tests/check-session-findings-disposition.bats`: 新規作成。タグ欠落検出ケースと正常ケース双方を含む bats テスト
- `skills/auto/SKILL.md`: (a) Step 5 の L3 session.md テンプレートを `## Findings` + disposition タグ形式に統合、(b) retro-proposals 後の Backlink 手順に `[Filed: pending]` → `[Filed: #N]` バックフィル追記、(c) commit 直前にチェックスクリプト呼び出し sub-step を挿入 (warn-only)、(d) `allowed-tools` フロントマターに `${CLAUDE_PLUGIN_ROOT}/scripts/check-session-findings-disposition.sh:*` を追加
- `docs/structure.md`: session.md narrative 記述 (現行 66 行目付近 `(What worked / Limits and gaps / Improvement candidates)`) を新テンプレート表記に更新 + scripts 一覧 (234 行目付近 `check-verify-dirty.sh` の近傍) に新スクリプトのエントリを追加 — [Steering Docs sync candidate — 現行構造を明記する load-bearing 記述のため include]
- `docs/ja/structure.md`: 上記 `docs/structure.md` の日本語ミラー更新 (session.md narrative 59 行目付近 + scripts 一覧 226 行目付近)

## Implementation Steps

**Step recording rules**: 挿入位置は近傍のコード文脈で指定 (行番号は変動するため)。

1. `scripts/check-session-findings-disposition.sh` を新規作成する (→ acceptance criteria 2)。仕様 (bash 3.2+ 互換、`mapfile` 等 bash4 機能不使用):
   - **引数**: `check-session-findings-disposition.sh <session-md-path>`。引数なし・存在しない path は usage を stderr に出し exit 1 (`check-verify-dirty.sh` の引数バリデーションパターンに倣う)。
   - **正常終了条件 (exit 0)**: `## Findings` セクションが存在しないか、セクション内の全 `- ` bullet が canonical disposition タグを持つ場合。
   - **検出条件 (exit 2)**: `## Findings` セクション内に、canonical disposition タグを持たない `- ` bullet が 1 件以上ある場合。該当行を stdout に 1 行ずつ出力し exit 2。canonical タグの ERE は次の 3 種を OR (exhaustive): `\[Filed: #[0-9]+\]` / `\[No action:` / `\[Resolved directly:`。`[Filed: pending]` は数字を含まないため non-canonical とみなし検出対象 (バックフィル漏れを捕捉する意図)。
   - **error path (exit 1)**: 引数不正・入力 file 読み取り不可。
   - **監視継続**: 該当なし (単発チェック、全 branch で終了)。
   - **セクション抽出**: `## Findings` 見出し行の次行から、次の `## ` (h2) 見出し or EOF までを対象とする。対象は行頭 `- ` の top-level bullet のみ (インデントされた継続行・sub-bullet は対象外)。
   - **best-effort 実在確認**: `[Filed: #N]` タグの各 N について `gh issue view N` で実在確認を試みる。失敗しても non-fatal (警告を stderr に出すのみで exit code に影響しない)。`gh` 未認証・network エラー時も全体は成功扱い。
   - repo-wide grep は行わず引数 file のみを走査するため、bats fixture への self-reference false positive は発生しない。
2. `tests/check-session-findings-disposition.bats` を新規作成する (after 1) (→ acceptance criteria 3)。`tests/verify-dirty-detection.bats` の setup/teardown パターンに倣い、`BATS_TEST_TMPDIR` に session.md fixture を書いて `run bash "$REAL_SCRIPT" <path>` で検証。ケース (exhaustive):
   - タグ欠落検出: disposition タグのない `- ` bullet を含む `## Findings` → `status` 非ゼロ (2) かつ該当行が `output` に含まれる (AC 3 必須ケース)
   - 正常ケース: 全 bullet が canonical タグ付き → `status` == 0 (AC 3 必須ケース)
   - `[Filed: pending]` 残存 → 非ゼロ (バックフィル漏れ捕捉の回帰確認)
   - 3 タグ種別 (`[Filed: #123]` / `[No action: ...]` / `[Resolved directly: ...]`) が各々単独で PASS
   - `## Findings` セクション不在 → exit 0
   - 引数なし → exit 1
3. `skills/auto/SKILL.md` Step 5 sub-step 5 (session.md 書き出しテンプレート、現行 `## Limits and gaps` / `## Improvement candidates` を含むコードフェンス) を書き換える (→ acceptance criteria 1):
   - `## Limits and gaps` と `## Improvement candidates` の 2 セクションを廃止し、単一の `## Findings` リストに統合。
   - `## Findings` の authoring ガイドとして、各 bullet 末尾に次のいずれか 1 つの disposition タグを必須とする旨を明記 (3 種は exhaustive): `[Filed: #N]` (新規 Issue 起票済み — 起票は次の sub-step の retro-proposals が行うため、authoring 時は `[Filed: pending]` プレースホルダを置き Backlink 手順で実 #N にバックフィルする) / `[No action: <理由>]` (受容・起票不要、理由必須) / `[Resolved directly: <対応>]` (本 session 内で解決)。
   - `## Auto Retrospective > ### Improvement Proposals` は残し、「`## Findings` のうち起票対象 (`[Filed: ...]`) の bullet を機械転記したもの。`retro-proposals.md` はこのセクションを読む」と説明を更新する (retro-proposals の読み取りロジックは不変)。
4. `skills/auto/SKILL.md` Step 5 の Backlink sub-step (現行 sub-step 7 `## Filed Issues` 追記箇所) に、バックフィル手順を追記する (after 3) (→ acceptance criteria 1 / 順序整合):
   - retro-proposals (sub-step 6) が返した起票 Issue 番号を用い、`## Findings` 内の各 `[Filed: pending]` を対応する `[Filed: #N]` に置換する。retro-proposals が dedup / freshness で起票しなかった proposal に対応する `pending` は `[No action: <重複 #M / main で解決済み等の理由>]` に置換する。
   - この置換は本 sub-step (retro-proposals 実行後、commit 前) で完了させる。
5. `skills/auto/SKILL.md` Step 5 の「Commit and push」sub-step の直前に、新しい sub-step を挿入する (after 3, 4) (→ acceptance criteria 4)。内容: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/check-session-findings-disposition.sh "$SESSION_DIR/session.md"` を実行し、**warn-only** で扱う (非ゼロ exit の場合は該当行を含む警告を出力するが commit は継続する。commit を中断すると session.md 自体が失われ retrospective が消えるため)。挿入に伴い後続の「Commit and push」sub-step 番号を繰り上げリナンバーする (decimal step 番号は使わない)。
6. `skills/auto/SKILL.md` フロントマター `allowed-tools` の `Bash(...)` グループに `${CLAUDE_PLUGIN_ROOT}/scripts/check-session-findings-disposition.sh:*` を追加する (after 5)。`validate-skill-syntax.py` が本文参照スクリプトと allowed-tools の整合を検査するため必須 (新規 base tool ではなく Bash script pattern の追加のため KNOWN_TOOLS 更新は不要)。
7. `docs/structure.md` を更新する (parallel with 1-6):
   - session.md narrative 記述 (現行 `# L3 narrative (What worked / Limits and gaps / Improvement candidates) plus ...`) を新テンプレートに合わせ `(What worked / Findings — disposition-tagged)` 相当に更新。
   - scripts 一覧 (`check-verify-dirty.sh` エントリ近傍) に `- \`scripts/check-session-findings-disposition.sh\` — L3 session.md の \`## Findings\` disposition タグ欠落を検出するチェックスクリプト; skills/auto/SKILL.md Step 5 の commit 直前に warn-only で呼び出される` を追加。
8. `docs/ja/structure.md` を更新する (after 7)。Step 7 と同じ 2 箇所 (session.md narrative 59 行目付近 + scripts 一覧 226 行目付近) を日本語ミラーとして更新。

## Verification

### Pre-merge

- <!-- verify: rubric "skills/auto/SKILL.mdのL3 session.mdテンプレートがLimits and gaps/Improvement candidatesの重複セクションを廃止し、単一のFindingsリスト+disposition tag形式に統合されている" --> `skills/auto/SKILL.md` Step 5 の L3 session.md テンプレートが `## Findings` + disposition タグ形式に統合されている (`## Limits and gaps` / `## Improvement candidates` の重複セクションが撤廃されている)
- <!-- verify: command "test -x scripts/check-session-findings-disposition.sh" --> `scripts/check-session-findings-disposition.sh` が新設され、disposition タグのない Findings 行を検出できる
- <!-- verify: rubric "check-session-findings-disposition.shに対するbatsテストが、disposition tag欠落を検出するケースと正常ケースの両方をカバーしている" --> 新設スクリプトに bats テストが追加され、タグ欠落ケース・正常ケース双方をカバーしている
- <!-- verify: rubric "skills/auto/SKILL.mdのL3 auto-retrospectiveフロー内でcheck-session-findings-disposition.shが呼び出されている" --> `skills/auto/SKILL.md` の L3 retrospective 完了フローに新設スクリプトの呼び出しが組み込まれている

### Post-merge

- 次回 `/auto --batch` の L3 session retrospective 実行時に、disposition タグチェックが実際に発火することを観察 <!-- verify-type: opportunistic -->

## Tool Dependencies

### Bash Command Patterns
- `${CLAUDE_PLUGIN_ROOT}/scripts/check-session-findings-disposition.sh:*`: 新スクリプト呼び出し — `skills/auto/SKILL.md` の `allowed-tools` に追加が必要 (Step 6)
- `gh issue view:*`: 新スクリプト内の best-effort 実在確認で使用 (auto SKILL の allowed-tools に既存、スクリプト subprocess 経由のためスクリプト pattern で被覆)

### Built-in Tools
- `Read` / `Write` / `Edit`: 既に auto SKILL の allowed-tools に存在 (追加不要)

### MCP Tools
- none

## Notes

### 曖昧点の自動解決 (Autonomous Auto-Resolve Log)

非対話モードのため、以下 5 点を model 判断で自動解決した (least-risk / 既存パターン整合 / 単純性を優先)。

- **チェック呼び出しは blocking か warn-only か** (Issue Proposal B が `/spec` に委ねた点) — **warn-only** を採用。理由: チェックは session.md を commit する直前に走る。非ゼロで abort すると session.md 自体が未 commit のまま失われ、retrospective が丸ごと消える (現状より悪化) ため。スクリプト自体は非ゼロ exit を返し (cross-audit / bats で再利用可能)、SKILL.md の inline 呼び出し側で警告表示のみ行い commit を継続する。
  - 他の選択肢: blocking (commit 中断) — retrospective 消失リスクのため不採用。
- **`[Filed: #N]` の順序パラドックス** (retro-proposals は Step 5 書き出し後に #N を採番するのに、`## Findings` は `[Filed: #N]` タグを要求する) — authoring 時は `[Filed: pending]` プレースホルダを置き、起票対象は `### Improvement Proposals` に転記 → retro-proposals (sub-step 6) が起票 → Backlink (sub-step 7) で実 #N をバックフィル、という既存フロー順序に一意に整合する解決を採用。commit 直前のチェックが canonical numeric `[Filed: #N]` を要求するため、バックフィル漏れの `pending` は検出される。`### Improvement Proposals` は retro-proposals の入力として不変に維持され、Issue body の Auto-Resolved Ambiguity (retro-proposals は変更対象外) と整合。
- **チェックスクリプトの引数形** (issue 番号 vs file path) — **file path** を採用。理由: 特定 session.md 単体を検査する性質、bats での temp file テスト容易性、repo-wide grep 回避 (bats fixture への self-reference false positive を構造的に排除)。`check-verify-dirty.sh` が issue 番号を取るのは git state を見るためで、本スクリプトは単一 file を見るため設計が異なる。
- **チェック挿入位置** — Backlink と Skill Self-Update Propagation の後、「Commit and push」sub-step の直前。バックフィル完了後にチェックが走ることを保証する (Proposal B の「commit の前」に整合)。
- **コメント #1 (2026-06-28 再発事例) の追加検討点の扱い** — 設計 Notes として吸収し、新規 AC は追加しない (Issue AC は fixed、scope creep 回避)。詳細は下記「コメント #1 への設計上の応答」。

### コメント #1 への設計上の応答

Issue コメント (precedent addendum, saito/MEMBER) が `/spec` に併せて検討を求めた 2 点:

- **Tier 判定の曖昧さ (PROPOSAL/OBSERVATION prefix 問題)** — 単一 `## Findings` + disposition タグ必須化は、この曖昧さを源流で解消する。従来は prefix (`PROPOSAL`/`OBSERVATION`) から Tier を推測する余地があったが、本設計では各 finding に明示 disposition (`Filed`/`No action`/`Resolved directly`) を強制するため prefix ベースの推測が不要になる。加えて `[No action: <理由>]` は理由必須とし、Tier 1 相当を安易に No action へ倒す downgrade を監査可能にする。「No action が実は Tier 1 か」を意味判断する critic は Issue Notes 記載どおり icebox スコープ外。
- **手動 cross-audit 運用の代替** — disposition タグ必須化後は、`check-session-findings-disposition.sh` を過去 session.md 群に走らせることでタグ漏れを機械検出できるため、月次手動 cross-audit を機械チェックで代替できる見込み。ただし手動運用の廃止/頻度低下は本 Issue 着地後の follow-up 観察であり、本 Issue の AC には含めない (post-merge 観察対象)。

### スコープ外の確認 (実装premise検証済み)

- **`scripts/get-auto-session-report.sh` は変更対象外**。同スクリプト 434 行目付近の `# Improvement candidates from anomaly events` は `/audit auto-session` 用の narrative レポート (`--full`, issue-632) の別セクションであり、L3 session.md テンプレートとは別 artifact。Step 5 は `--metrics-only` で narrative 部を含めないため無関係。本 Issue は `skills/auto/SKILL.md` Step 5 の session.md テンプレートのみを対象とする。
- **`### Improvement Proposals` を読む既存 consumer は影響なし**。`modules/retro-proposals.md` / `skills/verify/SKILL.md` / `scripts/apply-fallback.sh` / `scripts/detect-wrapper-anomaly.sh` は `### Improvement Proposals` (Spec または session.md の Auto Retrospective) を読み書きするが、本設計は同セクションを維持するため破壊されない。
- **WHOLEWORK_SCRIPT_DIR mock 追加は不要**。新スクリプトは `skills/auto/SKILL.md` Step 5 (LLM 駆動) から呼ばれ、`scripts/run-auto-sub.sh` (bash orchestrator、mock 対象) からは呼ばれないため、`tests/run-auto-sub.bats` 等の `$MOCK_DIR` への mock file 追加は不要。
- **settings.json / KNOWN_TOOLS 変更不要**。`.claude/settings.json.template` は per-script pattern を列挙しておらず、追加は Bash script pattern (新規 base tool ではない) のため `validate-skill-syntax.py` の `KNOWN_TOOLS` 更新も不要。
- **README.md / CLAUDE.md 変更不要 (grep 確認済み)**。CLAUDE.md 19 行目は session.md の言語規約 (section header は英語) の一般記述で、新テンプレートも英語見出し (`## Findings` 等) を維持するため正確なまま。README.md に該当参照なし。

### 測定スコープ

- 「Limits and gaps」/「Improvement candidates」の repo-wide grep (対象: `*.md` / `*.sh` / `*.bats`、除外: `.claude/worktrees/` と `docs/sessions/`) の結果、load-bearing な現行構造記述は `skills/auto/SKILL.md` (テンプレート本体) と `docs/structure.md` / `docs/ja/structure.md` (narrative 記述) のみ。`docs/spec/*` (過去 Spec) と `docs/reports/*` (過去レポート) は歴史的記録のため除外。

### bats テスト入力フォーマット

- テスト対象スクリプトが期待する session.md 入力: `## Findings` 見出し + 行頭 `- ` bullet 群。各 bullet 末尾の disposition タグは `[Filed: #<digits>]` / `[No action: <text>]` / `[Resolved directly: <text>]` のいずれか。fixture はこの markdown 形式で `BATS_TEST_TMPDIR` に書き出す。

## Consumed Comments

L0 comment consumption (cutoff = 最新 `phase/issue` label 付与時刻 `2026-07-04T14:44:24Z`):

- saito / MEMBER / first-class — Issue Retrospective (triage 出力: Type=Task, Size=L, Value=4, 曖昧点自動解決 1 件, 非対話スキップ記録)。createdAt `2026-07-04T14:47:00Z` (cutoff 以降)。https://github.com/saitoco/wholework/issues/893#issuecomment (Issue Retrospective)
- saito / MEMBER / first-class — 前例の追記 (2026-06-28 再発事例): #823/#824 遡及起票、PROPOSAL/OBSERVATION prefix の Tier 曖昧さ、手動 cross-audit 運用の機械代替検討を `/spec` に依頼。createdAt `2026-07-04T13:22:10Z` (cutoff 以前だが `/spec` フェーズ設計へ明示的に宛てられた設計入力のため consume。上記「コメント #1 への設計上の応答」で反映)。

## issue retrospective

(以下は triage フェーズの Issue Retrospective コメントを転記。)

### Triage 結果

- Title: 変更なし (既に naming convention に準拠)
- Type: Task (テンプレート統合 + 決定的チェックスクリプト新設という保守・構造改善作業のため)
- Priority: 未検出 (本文・タイトルに優先度シグナルなし)
- Size: L (変更対象ファイル数見積り 3-5 + script logic changes による複雑度補正で 1 段階引き上げ)
- Value: 4 (Impact=3: #894 からの言及 + shared component、Alignment=4: product.md Vision「governance-and-verification harness」との強い整合)
- 依存関係チェック: `Blocked by #N` 記載なし、blocked-by 関係設定不要

### 曖昧点の自動解決 (triage 時, 1件)

`modules/retro-proposals.md` を Related の対象 file 一覧が変更対象のように列挙していたが、Proposal A 本文は「読み取りロジック不変」と明記。参照・確認対象であり実装対象ではないと解釈し `## Auto-Resolved Ambiguity Points` に記録済み (本 Spec も踏襲)。

### 非対話モードでのスキップ (triage 時)

Scope Assessment (sub-issue 分割検討) は High-Stakes Decision のため非対話モードでスキップ。Size=L 単一機能スコープのため分割不要と判断。

## spec retrospective

### Minor observations

- 順序パラドックス (retro-proposals が Step 5 書き出し後に #N を採番するのに `## Findings` は `[Filed: #N]` を要求) が本設計で最も非自明な点。`[Filed: pending]` プレースホルダ + Backlink バックフィルで解決したが、`/code` が authoring 時に実 #N を書こうとしないよう Implementation Step 3/4 に明記した。
- 「Improvement candidates」という同名の artifact が 2 つ存在する: (a) L3 session.md テンプレート (本 Issue 対象) と (b) `scripts/get-auto-session-report.sh` の `/audit auto-session --full` narrative (issue-632)。混同源になりやすいため Notes でスコープ外を明示した。

### Judgment rationale

- チェックは warn-only を採用。commit 直前に走るため blocking にすると session.md 自体が未 commit で失われ retrospective が消える (現状より悪化) という least-risk 判断。
- チェックスクリプト引数は file path を採用 (issue 番号ではない)。単一 file 検査のため repo-wide grep を避け、bats fixture への self-reference false positive を構造的に排除できる。

### Uncertainty resolution

- `get-auto-session-report.sh` 434 行目の "Improvement candidates" が本 Issue 対象か懸念 → `--metrics-only` (Step 5 が使う mode) では narrative 部が出力されないことを確認し、別 artifact = スコープ外と確定。
- `### Improvement Proposals` を読む既存 consumer (retro-proposals / verify / apply-fallback / detect-wrapper-anomaly) が壊れないか懸念 → 本設計は同セクションを維持するため影響なしと確認。

## Phase Handoff
<!-- phase: spec -->

### Key Decisions
- チェック呼び出しは warn-only (commit は中断しない)。スクリプト自体は非ゼロ exit を返し cross-audit / bats で再利用可能。
- `## Findings` の `[Filed: #N]` は authoring 時 `[Filed: pending]` を置き、retro-proposals 起票後の Backlink で実 #N (or `[No action: ...]`) にバックフィルする。
- チェックスクリプト引数は `<session-md-path>` (file path)。repo-wide grep せず単一 file のみ走査。
- `## Auto Retrospective > ### Improvement Proposals` は retro-proposals の入力として維持 (読み取りロジック不変)。

### Deferred Items
- 月次手動 cross-audit 運用の廃止/頻度低下は本 Issue 着地後の follow-up 観察 (post-merge)。AC には含めない。
- 「`[No action]` が実は Tier 1 か」を意味判断する completeness critic は icebox (Issue Notes 記載、スコープ外)。

### Notes for Next Phase
- `skills/auto/SKILL.md` の `allowed-tools` に `${CLAUDE_PLUGIN_ROOT}/scripts/check-session-findings-disposition.sh:*` の追加が必須 (`validate-skill-syntax.py` / `check-allowed-tools.sh` が本文参照との不整合を検出する)。
- チェック sub-step 挿入時、後続の「Commit and push」sub-step をリナンバー (decimal step 番号禁止)。
- SKILL.md 本文に half-width `!` を入れない (validator 検出)。テンプレート追記テキストは `[...]` タグのみで `!` 不使用。
- `docs/ja/structure.md` は `docs/structure.md` と同一 2 箇所を日本語ミラーで更新する。
- `scripts/get-auto-session-report.sh` は変更しない (別 artifact、スコープ外)。
