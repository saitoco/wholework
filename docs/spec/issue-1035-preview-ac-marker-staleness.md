# Issue #1035: review/verify: preview-ac-unverified マーカーの陳腐化ガード (fix-cycle 再検証時の counter-marker or 常時投稿)

## Consumed Comments

- login: saito / authorAssociation: MEMBER / trust tier: first-class / 内容: Issue Retrospective — Type=Bug・Size=L・Value=3 の判定根拠、テスト追加先を既存 `tests/review.bats` / `tests/verify.bats` の拡張とする auto-resolve 判断、および A 案 (counter-marker) / B 案 (常時投稿) の選択を `/spec` へ委譲する旨 / URL: https://github.com/saitoco/wholework/issues/1035#issuecomment-5034526511
- login: saito / authorAssociation: MEMBER / trust tier: first-class / 内容: Issue Retrospective Addendum — `skills/issue/spec-test-guidelines.md` に従い AC4 (`github_check "gh pr checks" "Run bats tests"`) を Pre-merge に追加した経緯 / URL: https://github.com/saitoco/wholework/issues/1035#issuecomment-5034558094

## Overview

#1028 で導入した `<!-- wholework-event: type=preview-ac-unverified -->` マーカーは「未検証の preview AC が 1 件以上あるときだけ投稿する」設計になっている。このため fix-cycle で `/review` が再実行され preview AC が UNCERTAIN → PASS に変化しても、新しい状態を伝えるコメントが投稿されず、`/verify` は古いマーカーを「最新」として参照し続ける。

本 Spec は **B 案 (常時投稿)** を採用する。`/review` は Pre-merge に `ac-tier: preview` AC が 1 件以上存在する限り、実行のたびに「その時点の未検証インデックス集合」を単一マーカーとして投稿する (空集合は `ac=none` sentinel で表現)。`/verify` は従来どおり「最新 1 件のマーカーのみ」を参照するため、latest-wins だけで陳腐化が構造的に消える。あわせて `/verify` 側のマーカー解決ロジックを `scripts/resolve-preview-ac-fallback.sh` として決定論的スクリプトへ切り出し、fix-cycle (UNCERTAIN → PASS) を bats で実挙動として再現可能にする。

## Reproduction Steps

1. `capabilities.pr-preview: true` のプロジェクトで、Pre-merge に `<!-- ac-tier: preview -->` タグ付き AC (仮に通し番号 2) を持つ Issue を作る
2. `/review` 1 回目: preview URL 未解決などにより AC 2 が UNCERTAIN → `<!-- wholework-event: type=preview-ac-unverified phase=review issue=N ac=2 -->` が Issue コメントとして投稿される
3. `/review` で MUST 指摘が出るなどして fix-cycle が発生し、`/review` が再実行される
4. `/review` 2 回目: preview URL が解決され AC 2 が PASS になる。しかし現行の投稿条件は「UNCERTAIN な preview AC が 1 件以上あるとき」であるため、**新規マーカーは投稿されない**
5. `/merge` 後の `/verify` Step 5 が「`type=preview-ac-unverified` を含む最新コメント」を探すと、手順 2 で投稿された古いマーカー (`ac=2`) が最新として見つかる
6. `/verify` は AC 2 を SKIPPED にせず production URL への fallback 検証を実行する — 実際には `/review` 2 回目で検証済みであり、不要な二重検証となる

## Root Cause

マーカーの投稿が **状態遷移の片方向 (verified → unverified) しか表現していない** ことが原因である。

`skills/review/SKILL.md` Step 8 の投稿条件は「UNCERTAIN な preview AC 集合が非空のときのみ投稿し、空なら投稿を完全にスキップする」となっている。Issue コメントは append-only な L0 サーフェス (`modules/l0-surfaces.md` の Mutation kind = append-only) であり、既存コメントを無効化する手段がない。したがって「空集合」を投稿しない限り、`/verify` 側の latest-wins 探索 (`skills/verify/SKILL.md:181`) は必ず過去の非空マーカーに当たる。

つまり欠けているのは `/verify` 側の探索ロジックではなく、`/review` 側が「今回は未検証ゼロだった」という状態を append-only サーフェス上で明示的に上書き表明する経路である。

## Changed Files

- `scripts/resolve-preview-ac-fallback.sh`: 新規作成 — Issue コメントから最新の `type=preview-ac-unverified` マーカーを 1 件解決し、fallback 対象の 1-based AC インデックスをカンマ区切りで stdout に出力する (マーカー無し / `ac=none` は空出力)。bash 3.2+ 互換
- `modules/l0-surfaces.md`: 「Machine-Readable Event Marker」節の `type=preview-ac-unverified` 説明を、常時投稿方式・`ac=none` sentinel・latest-wins の 3 点を含む仕様へ更新
- `skills/review/SKILL.md`: Step 8 の「Preview-tier unverified marker (defense in depth)」節を、投稿条件「UNCERTAIN 集合が非空のときのみ」→「Pre-merge に `ac-tier: preview` AC が 1 件以上あるとき常時 (空集合は `ac=none`)」へ変更
- `skills/verify/SKILL.md`: Step 5 の pre-merge-preview AC skip rule を `resolve-preview-ac-fallback.sh` 呼び出しベースへ書き換え + frontmatter `allowed-tools` に `${CLAUDE_PLUGIN_ROOT}/scripts/resolve-preview-ac-fallback.sh:*` を追加
- `tests/resolve-preview-ac-fallback.bats`: 新規作成 — `gh` を PATH mock で差し替え、fix-cycle (古い `ac=2,5` → 新しい `ac=none`) を模擬して出力が空になることを検証。bash 3.2+ 互換
- `tests/review.bats`: Step 8 節の常時投稿ルールに対する content-assertion を追加
- `tests/verify.bats`: Step 5 節の `resolve-preview-ac-fallback.sh` 委譲に対する content-assertion を追加
- `docs/guide/customization.md`: pre-merge-preview の skip 挙動説明を常時投稿 + latest-wins 仕様へ更新
- `docs/ja/guide/customization.md`: 上記の ja ミラー同期
- `docs/structure.md`: Scripts > Project utilities に `scripts/resolve-preview-ac-fallback.sh` の行を追加
- `docs/ja/structure.md`: 上記の ja ミラー同期
- `docs/tech.md`: [Steering Docs sync candidate] L241 の `HAS_PR_PREVIEW_CAPABILITY` 説明が「skipped in `/verify` post-merge」と無条件 skip のまま。条件付き skip へ更新が必要か `/code` で判断する
- `docs/ja/tech.md`: [Steering Docs sync candidate] 上記 ja ミラーの対応行 (L228)

## Implementation Steps

1. `scripts/resolve-preview-ac-fallback.sh` を新規作成する (→ AC2, AC3)。入出力インタフェース:
   - Usage: `resolve-preview-ac-fallback.sh <issue-number>`。引数が 1 個でない、または正の整数でない場合は usage を stderr に出して exit 1 (`scripts/get-verify-iteration.sh` の引数バリデーションを踏襲)
   - マーカー取得: `gh issue view "$N" --json comments --jq '[.comments[] | select(.body | contains("<!-- wholework-event: type=preview-ac-unverified"))] | sort_by(.createdAt) | .[-1].body // empty'` の出力から、`grep -F '<!-- wholework-event: type=preview-ac-unverified'` で該当行を 1 行取り出す (`head -1`)
   - `ac=` 抽出: `sed -n 's/.*[[:space:]]ac=\([^[:space:]]*\).*/\1/p'` で値を取得
   - 出力: マーカー行が空、`ac=` が空、または `ac=none` のときは空文字を出力して exit 0。それ以外は `ac=` の値をそのまま出力して exit 0
   - `gh` 失敗時 (`2>/dev/null` + `|| true`) も空出力 + exit 0 とし、`/verify` を止めない (fail-open: 呼び出し側は「fallback 対象なし = 従来の SKIPPED 挙動」に落ちる)
   - `set -euo pipefail` を使うが、パイプ内 `grep` の no-match で落ちないよう各段に `|| true` を付ける。`mapfile` 等 bash 4+ 構文は使わない (bash 3.2+ 互換)
2. `modules/l0-surfaces.md` の「Machine-Readable Event Marker」節、`**`type=preview-ac-unverified`**:` 段落を更新する (→ AC1, AC2 の前提)。追記内容:
   - 投稿条件が「Pre-merge に `ac-tier: preview` AC が 1 件以上存在する `/review` 実行ごとに常時投稿」であること
   - `ac=` の値は「その実行時点で UNCERTAIN だった AC の 1-based インデックスのカンマ区切り」であり、**空集合は `ac=none` と書く** こと (`ac=` を空値にしない)
   - Issue コメントは append-only であるため、消費側は必ず「`createdAt` 最大の 1 件のみ (latest-wins)」を参照し、それ以前のマーカーは無視すること
   - `ac=none` を含むマーカーは「この時点で未検証の preview AC は 0 件」を意味し、`/verify` の fallback 対象は空になること
3. `skills/review/SKILL.md` Step 8 の「**Preview-tier unverified marker (defense in depth):**」節を書き換える (after 2) (→ AC1)。変更点:
   - 投稿条件を「If this set is non-empty」から「Pre-merge セクションに `<!-- ac-tier: preview -->` タグ付き AC が 1 件以上存在する場合は常に投稿する」へ変更する。preview-tier AC が 0 件のときのみ投稿を丸ごとスキップする
   - マーカー行のテンプレートを `ac=<comma-separated indices, or the literal none when the set is empty>` に変更する
   - 常時投稿の理由 (append-only な Issue コメント上で「未検証ゼロ」を明示上書きし、fix-cycle 再検証後に古いマーカーが最新として残る陳腐化を防ぐ) を 1 文で明記し、`modules/l0-surfaces.md` § "Machine-Readable Event Marker" を参照させる
   - 挿入位置は既存の `mkdir -p .tmp` を含む gh-issue-comment.sh 呼び出しブロックの直前・直後の説明文であり、コマンドブロック自体は変更しない
   - 編集時、SKILL.md 本文に半角 `!` を持ち込まないこと (validate-skill-syntax.py の MUST 制約)
4. `skills/verify/SKILL.md` を編集する (after 1, 2) (→ AC2)。変更点:
   - frontmatter `allowed-tools` の Bash パターン列に `${CLAUDE_PLUGIN_ROOT}/scripts/resolve-preview-ac-fallback.sh:*` を追加する (挿入位置は既存の `${CLAUDE_PLUGIN_ROOT}/scripts/get-verify-iteration.sh:*` の直後)
   - Step 5「pre-merge-preview AC skip rule」の第 2 段落 (「From the comments consumed in Step 4, identify the most recent ...」) を、`bash ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-preview-ac-fallback.sh $NUMBER` を実行してその stdout を fallback 対象インデックスリストとして扱う手順に置き換える
   - スクリプトが「最新マーカーのみを見る (latest-wins)」ことと「出力が空なら fallback 対象なし = 全 preview AC を従来どおり SKIPPED にする」ことを明記する
   - 出力が非空のときの分岐 (`PRODUCTION_URL` 非空 → production URL で実検証 / 空 → UNCERTAIN + 手動検証必要) は既存記述をそのまま維持する
   - 編集時、SKILL.md 本文に半角 `!` を持ち込まないこと
5. `tests/resolve-preview-ac-fallback.bats` を新規作成する (after 1) (→ AC3, AC4)。`tests/append-consumed-comments-section.bats` の mock パターン (`MOCK_DIR` を `PATH` に prepend し `gh` を差し替え) を踏襲し、以下の `@test` を含める:
   - fix-cycle 再検証 (陳腐化の再現): `gh` mock が古いマーカー (`ac=2,5`) の直後に新しいマーカー (`ac=none`) を返す JSON 相当の出力を与えたとき、スクリプトの stdout が空であること — これが AC3 の本体
   - 未検証が残るケース: 最新マーカーが `ac=3` のとき stdout が `3` であること
   - マーカーが 1 件も無いとき stdout が空で exit 0 であること
   - 引数が空 / 非数値のとき exit 1 であること
   - `gh` mock は `--jq` を解釈できないため、スクリプトが最終的に `grep -F` するマーカー行をそのまま出力する形で組む (既存 mock と同じ「canned output」方式)
6. `tests/review.bats` と `tests/verify.bats` に content-assertion を追加する (after 3, 4) (→ AC3, AC4):
   - `tests/review.bats`: 既存の `step8_section()` ヘルパを再利用し、Step 8 節が `preview-ac-unverified` と `none` sentinel の常時投稿ルールを含むことを検証する `@test` を追加する
   - `tests/verify.bats`: `### Step 5: Verify Each Condition (Pre-merge Only)` 節を抽出するヘルパ (`awk '/^### Step 5: /{found=1} /^### Step / && !/Step 5: /{found=0} found{print}'` 形式、既存 `step2_section()` と同型) を追加し、その節が `resolve-preview-ac-fallback.sh` を参照していることを検証する `@test` を追加する
   - 既存の `@test` は削除・改変しない
7. `docs/guide/customization.md` の「At `/verify` (post-merge): `ac-tier: preview` ACs are skipped by default ...」の記述を更新する (after 3, 4) (→ doc consistency; 対応する AC なし)。`/review` が実行のたびにマーカーを投稿し (未検証ゼロなら `ac=none`)、`/verify` は最新 1 件のみを参照するため fix-cycle 後の再検証結果が正しく反映される旨を追記する。`docs/ja/guide/customization.md` の対応箇所 (L187 付近) を同じ内容で日本語同期する
8. `docs/structure.md` の Scripts > **Project utilities:** リストに `- \`scripts/resolve-preview-ac-fallback.sh\` — resolve the latest \`type=preview-ac-unverified\` marker from Issue comments and print the 1-based AC indices needing \`/verify\` fallback (empty when none)` を追加する (after 1) (→ doc consistency; 対応する AC なし)。挿入位置は既存の `scripts/get-verify-iteration.sh` 行の直後。`docs/ja/structure.md` の対応位置 (L188 付近) に同内容の日本語行を追加する

## Verification

### Pre-merge
- <!-- verify: rubric "skills/review/SKILL.md に fix-cycle 再検証時の状態更新マーカー投稿ロジックが実装されている (Counter-marker 導入 or 常時投稿方式のいずれか)" --> Counter-marker または常時投稿マーカーの仕様が定義され、`/review` が preview AC 状態に応じて投稿するようになっている
- <!-- verify: rubric "skills/verify/SKILL.md の pre-merge-preview AC skip rule が、Counter-marker または常時投稿マーカーの最新状態から fallback 対象 AC を決定する挙動になっている" --> `/verify` の pre-merge-preview AC skip rule が、最新の verify 状態を反映して fallback 対象を決定する
- <!-- verify: rubric "tests/ 配下に fix-cycle 再検証で preview AC が UNCERTAIN→PASS に変化した場合に /verify が誤って fallback を実行しないことを検証するテストが存在する" --> マーカー陳腐化を再現するテストが追加されている (fix-cycle 再検証で UNCERTAIN→PASS を模擬)
- <!-- verify: github_check "gh pr checks" "Run bats tests" --> 全 bats テストが PASS する (PR route)

### Post-merge
- downstream プロジェクトの fix-cycle 事例で誤 fallback が発生しなくなることを観察 <!-- verify-type: observation event=auto-run -->

## Alternatives Considered

- **A 案: Counter-marker (`type=preview-ac-verified`) の導入 — 不採用**: `/review` が PASS 判定した preview AC に対して別種のマーカーを投稿し、`/verify` が 2 種類のマーカーを AC インデックス単位で時系列比較する案。不採用理由は 3 点。(1) `/verify` 側のロジックが「per-AC で 2 マーカーの `createdAt` を比較」となり、単一マーカーの latest-wins より明確に複雑化する。(2) マーカー種別が 2 つになるため `modules/l0-surfaces.md` の Cross-phase marker exception (cutoff 無視スキャン) の対象文字列も 2 つに増え、`skills/verify/SKILL.md` / `modules/l0-surfaces.md` 双方で同期対象が増える。(3) 陳腐化は「append-only サーフェス上で古い状態が生き残る」ことが本質であり、counter-marker はそれを打ち消す第 2 の状態を足すだけで、3 回目以降の fix-cycle でも同じ時系列比較を毎回要求する。B 案は「最新 1 件が常に全状態を持つ」ため、比較そのものが不要になる。
- **C 案: `/verify` 側のみで cutoff を厳格化する — 不採用**: `/review` は変更せず、`/verify` が「最後の `/review` 実行時刻より後のマーカーのみ有効」と判定する案。`/review` の実行時刻を機械的に同定する L0 サーフェスが存在せず (`phase/review` ラベルは fix-cycle の再レビューで必ずしも再付与されない)、`/merge` による `phase/verify` 付与を挟むため時系列だけでは「2 回目の `/review` が走ったか」を区別できない。マーカー不在と「未検証ゼロ」を区別できない点は変わらないため不採用。
- **D 案: マーカーコメントを毎回編集して上書きする — 不採用**: `gh issue comment --edit-last` 等で既存コメントを更新する案。`modules/l0-surfaces.md` の L0 サーフェス表で Issue comments は `append-only` と定義されており、編集操作を導入すると SSoT の mutation kind 定義自体の変更が必要になる。影響範囲が本 Issue のスコープを大きく超えるため不採用。

## Tool Dependencies

### Bash Command Patterns
- `${CLAUDE_PLUGIN_ROOT}/scripts/resolve-preview-ac-fallback.sh:*`: `skills/verify/SKILL.md` の Step 5 から呼び出す。同 SKILL.md の `allowed-tools` frontmatter に未登録のため追加が必要 (Implementation Step 4)
- `gh issue view:*`: 新規スクリプト内で使用。`skills/verify/SKILL.md` の `allowed-tools` に登録済みのため追加不要

### Built-in Tools
- none (既存の Read / Write / Edit / Grep で足りる)

### MCP Tools
- none

## Uncertainty

- **`gh issue view --json comments` の返却順序**: GitHub API は作成日時の昇順で返すのが通例だが、明示的な保証は取っていない。
  - **検証方法**: 順序に依存しない実装で回避済み — スクリプトの jq 式に `sort_by(.createdAt)` を明示的に含め、`.[-1]` で最新を取る (Implementation Step 1)。したがって返却順序が変わっても結果は不変
  - **影響範囲**: Implementation Step 1
- **`gh` mock 経由の bats テストは `--jq` 式そのものを検証しない**: 既存 `tests/append-consumed-comments-section.bats` と同じ canned-output 方式を採るため、jq フィルタの正しさ (特に `sort_by(.createdAt)` と `.[-1]`) は実 `gh` 実行時にのみ確かめられる。
  - **検証方法**: bats では `grep -F` / `sed` によるマーカー行解析と分岐 (`ac=none` / 非空 / マーカー無し / 引数エラー) を検証対象とし、jq 部分は Post-merge AC の観察に委ねる
  - **影響範囲**: Implementation Steps 1, 5

## Notes

### Auto-Resolve Log (non-interactive mode)

- **A 案 (counter-marker) / B 案 (常時投稿) の選択 → B 案 (常時投稿) を採用** — reason: `/verify` Step 5 は既に「`createdAt` 最大のマーカー 1 件を参照する」latest-wins 実装であり、B 案なら消費側の探索ロジックを変えずに陳腐化が消える。A 案は per-AC の 2 マーカー時系列比較を新規に要求し、cutoff 無視スキャン対象文字列も 2 種に増える。詳細な比較は `## Alternatives Considered` に記載。
- **未検証ゼロの表現 → `ac=none` sentinel を採用** — reason: `ac=` を空値にすると `<!-- ... ac= -->` のように次のトークンとの境界が曖昧になり、`sed`/`grep -oE` ベースの属性抽出が誤動作しやすい。既存の marker 属性は全て非空値であり、`none` という明示的な語を置くほうが既存パーサ・人間の双方にとって曖昧性がない。
- **AC3 のテスト実現方法 → マーカー解決ロジックを `scripts/resolve-preview-ac-fallback.sh` へ切り出し、bats で fix-cycle を実挙動として再現** — reason: AC3 の rubric は「fix-cycle 再検証で UNCERTAIN→PASS に変化した場合に `/verify` が誤って fallback を実行しないことを検証するテスト」を要求している。`/verify` Step 5 が prose のままだと content-assertion (SKILL.md に文言があるかの grep) しか書けず、#1028 の review retrospective が指摘した「prose-driven SKILL.md への bats カバレッジの実務的難しさ」がそのまま再発する。決定論的な判定部分をスクリプトへ切り出せば、古いマーカー → 新しい `ac=none` という時系列を mock で与えて「出力が空」を直接アサートできる。

### Conflict with implementation

- **Issue 本文の「Auto-Resolved Ambiguity Points」の前提が事実と異なる**: Issue 本文は「両ファイル (`tests/review.bats` / `tests/verify.bats`) は #1028 で導入された同一マーカー機構 (`type=preview-ac-unverified`) を対象とした content-assertion テストを既に持つ」と述べているが、`grep -rn "preview-ac" tests/` の結果は 0 件であり、該当アサーションは存在しない。実際には `tests/review.bats` は #942 (Opportunistic Verification の `--context-file` 配線)、`tests/verify.bats` は #1000 (Step 2 の foreign-worktree ガード) を対象としたテストである。#1028 Spec の Notes も「新規 bats テストは追加しない」と明記しており、Issue 本文の記述と矛盾する。
  - **解決**: 結論 (既存 2 ファイルを拡張する) は維持する — 両ファイルは対象 SKILL.md ごとの content-assertion テストの正規の置き場であり、Step 6 の追加はその慣習に沿う。ただし **根拠は「既存の同機構テストの延長」ではなく「対象 SKILL.md ごとの content-assertion テストファイルの慣習」に置き換える**。
  - **加えて Issue の auto-resolve から意図的に逸脱する点**: 新規スクリプト `scripts/resolve-preview-ac-fallback.sh` に対しては新規テストファイル `tests/resolve-preview-ac-fallback.bats` を作成する。本リポジトリの `tests/` は `scripts/<name>.sh` に対して `tests/<name>.bats` を 1:1 で置く慣習 (`tests/append-consumed-comments-section.bats`、`tests/apply-fallback.bats`、`tests/get-sub-issue-graph.bats` 等) であり、Issue の auto-resolve が想定していた「SKILL.md content-assertion のための新規ファイル」とは別種のため、この逸脱は auto-resolve の意図と衝突しない。

### allowed-tools impact chain

- 新規 `scripts/resolve-preview-ac-fallback.sh` は `run-*.sh` パターンではないが、`skills/verify/SKILL.md` 本文から直接呼び出されるため、同 SKILL.md の `allowed-tools` に `${CLAUDE_PLUGIN_ROOT}/scripts/resolve-preview-ac-fallback.sh:*` のリテラル追加が必要 (Implementation Step 4 に含めた)。`skills/review/SKILL.md` は本スクリプトを呼ばないため追加不要。
- `.claude/settings.json.template` は個別スクリプトパスを列挙していない (`grep` で `get-verify-iteration` / `append-consumed-comments` ともにヒット 0) ため、settings.json 側の変更は不要。
- `scripts/validate-skill-syntax.py` の `KNOWN_TOOLS` 更新も不要 — 追加するのは既存 `Bash(...)` 内のコマンドパターンであり、新しいツール名 (base tool name) を導入しないため。

### Steering Docs sync scope note

- Steering Docs sync candidate check の一般手順 (skill 名 `review` / `verify` での `grep -l`) は、これらが一般的な英単語のため大量の無関係ヒットを生む (#1028 Spec Notes と同じ問題)。代わりに `preview-ac`、`ac-tier: preview`、`pre-merge-preview` という特異的キーワードで `docs/*.md docs/ja/*.md docs/guide/*.md docs/ja/guide/*.md` を調査し、`docs/guide/customization.md` (+ ja ミラー) と `docs/tech.md` (+ ja ミラー) のみが該当することを確認した。
- `docs/tech.md` L241 / `docs/ja/tech.md` L228 の `HAS_PR_PREVIEW_CAPABILITY` 説明は「skipped in `/verify` post-merge」と無条件 skip のまま記述されており、これは #1028 の時点で既に古い。本 Issue で条件がさらに明確化されるため Steering Docs sync candidate として Changed Files に載せた。`/code` フェーズが実際に読んで include/exclude を最終判断する。
- `docs/workflow.md` は変更不要: phase 遷移・label 遷移レベルの記述しか持たず、AC tier の詳細を記述していない (#781 / #1028 Spec で同じ判断が既になされている)。本 Issue も phase 遷移/routing を変えない。
- `docs/spec/issue-1028-preview-ac-unverified-marker.md` は `preview-ac-unverified` を含むが、完了済み Issue の履歴記録 (disposable) であり更新対象外。

### bats テストの入力データ形式

`tests/resolve-preview-ac-fallback.bats` の `gh` mock は、既存 `tests/append-consumed-comments-section.bats` と同じく引数を解釈せず canned output を返す方式にする。スクリプトが `--jq` の結果として期待するのは「最新マーカーコメントの body 文字列 (複数行可)」であるため、mock はそのマーカー行を含むプレーンテキストを stdout に出せばよい。JSON を返す必要はない。

fix-cycle 再現テストでは、mock が「新しいマーカー (`ac=none`) の body」だけを返す形にする — スクリプト側の `sort_by(.createdAt) | .[-1]` が実 `gh` では最新 1 件に絞る責務を負うため。加えて「古い行と新しい行が両方入った複数行 body」を与えて `head -1` の挙動が壊れないことも確認する。

### 実装上の注意

- `scripts/resolve-preview-ac-fallback.sh` は bash 3.2+ 互換で書くこと (macOS システム bash が 3.2)。`mapfile` / 連想配列 / `${var,,}` 等 bash 4+ 構文を使わない。
- `set -euo pipefail` 下で `grep` が no-match のとき exit 1 になりパイプ全体が落ちるため、各 `grep` / `gh` 呼び出しに `|| true` を付けて fail-open にする。マーカーが存在しないのは正常系であり、エラーにしてはならない。
- `skills/review/SKILL.md` / `skills/verify/SKILL.md` の本文編集時、半角 `!` を持ち込まないこと (`scripts/validate-skill-syntax.py` の MUST 制約)。
- 新規 `.bats` ファイルは `#!/usr/bin/env bats` shebang で始め、既存テストと同じく `$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)` でリポジトリルートを解決する。

## issue retrospective

(`/issue` フェーズの Issue コメントから転記)

### Triage 判定根拠

- **Type=Bug**: #1028 のマーカー機構が「re-review で PASS に変化しても新規マーカーが投稿されず、`/verify` が古いマーカーを最新として誤参照し得る」という設計ギャップの是正であり、"behavior different from expected" (Bug 分類基準) に該当すると判断。
- **Size=L** (Value=3): 変更対象が `skills/review/SKILL.md` (マーカー投稿ロジック) と `skills/verify/SKILL.md` (skip rule) の複数スキル横断に加え、`modules/l0-surfaces.md` (マーカー仕様 SSoT) の更新、新規テスト追加が見込まれ、ファイル数 (Axis 1: M 相当) + 複数スキル横断の複雑度加算 (+1 step) で L と判定。
- **Value=3**: Impact=2 (shared_flag: modules/ + 複数スキルにまたがる変更)、Alignment=4 (product.md Vision の "Post-merge verification" / "Governance and verification depth" に直接資する)、raw=6 → Value 3。

### `/issue` フェーズの Auto-Resolve

- テスト追加先を既存 `tests/review.bats` / `tests/verify.bats` の拡張とした (根拠は `/spec` で訂正済み — 本 Spec の Notes § Conflict with implementation 参照)。
- A 案 / B 案の選択は `docs/product.md` § "`/issue` (What) vs `/spec` (How) Responsibility Boundary" に従い意図的に未解決のまま `/spec` へ委譲した。
- Addendum: `skills/issue/spec-test-guidelines.md` に従い AC4 (`github_check "gh pr checks" "Run bats tests"`) を追加した。

## spec retrospective

### Minor observations

- Issue 本文の Auto-Resolve Log が「既存テストが同一マーカー機構を対象にしている」と述べていたが、`grep -rn "preview-ac" tests/` はヒット 0 件だった。`/issue` フェーズが「既存ファイル名が対象 SKILL.md と一致する」ことから中身を確認せずに内容まで推定したものと見られる。Auto-Resolve の reason に「既存 X が Y を持つ」型の事実主張を書く場合は、その主張自体を grep で裏取りしてから書く必要がある。
- `docs/tech.md` L241 の `HAS_PR_PREVIEW_CAPABILITY` 説明が「skipped in `/verify` post-merge」と無条件 skip のまま残っており、#1028 の時点で既に古くなっていた。#1028 Spec の Doc sync scope note は `docs/tech.md` を「新規 `.wholework.yml` キーを追加しないため変更不要」と判定していたが、キー追加の有無と既存キー説明の陳腐化は別問題であり、この判定基準では取りこぼす。

### Judgment rationale

- A 案 (counter-marker) ではなく B 案 (常時投稿) を採ったのは、陳腐化の本質が「append-only サーフェス上で古い状態が生き残ること」だからである。counter-marker は打ち消しの第 2 状態を足すだけで、3 回目以降の fix-cycle でも per-AC の時系列比較を毎回要求し続ける。B 案は「最新 1 件が常に全状態を持つ」ため比較そのものが不要になり、消費側 (`/verify`) のロジックを変えずに済む。
- 未検証ゼロを `ac=` の空値ではなく `ac=none` sentinel で表したのは、既存の marker 属性がすべて非空値であり、空値だと `sed`/`grep -oE` ベースの属性抽出で次トークンとの境界が曖昧になるため。
- Issue の auto-resolve は「新規テストファイルを作らない」としていたが、新規スクリプトに対しては `scripts/<name>.sh` ↔ `tests/<name>.bats` の 1:1 慣習に従って新規ファイルを作る判断をした。auto-resolve が想定していたのは SKILL.md content-assertion 用の新規ファイルであり、種類が異なるため意図と衝突しないと整理した。

### Uncertainty resolution

- `gh issue view --json comments` の返却順序は明示保証がないという不確実性を、jq 式に `sort_by(.createdAt)` を明示して `.[-1]` を取ることで設計段階から回避した (順序依存を残して Post-merge 観察に委ねる選択肢は採らなかった)。
- `gh` を canned-output で mock する既存 bats 方式では `--jq` 式そのものを検証できない、という制約は解消できなかった。Uncertainty セクションに明記し、jq 部分の妥当性は Post-merge の observation AC に委ねる整理とした。

### Cross-phase note

- 本 Spec は「prose-driven な SKILL.md ステップは bats で挙動検証できない」という #1028 review retrospective の指摘に対し、判定ロジックのスクリプト切り出しという一般解を初めて適用した事例になる。同型の問題 (`/verify` の他ステップ、`/review` Step 8 の分類ロジック等) にも横展開できる可能性があるが、本 Issue のスコープ外として記録に留める。

## Code Retrospective

### Deviations from Design

N/A — Implementation Steps 1–8 は Spec の記述どおりに実装した。`tests/resolve-preview-ac-fallback.bats` に Spec Implementation Step 5 が列挙した 4 ケース (fix-cycle 再現・未検証残存・マーカー無し・引数エラー) に加えて `gh` 失敗時の fail-open ケースと複数行 body での marker 行選択ケースを追加したが、これは Step 1 の fail-open 仕様と `head -1` の意図を直接カバーする範囲内の追加であり、設計からの逸脱ではない。

### Design Gaps/Ambiguities

- `docs/tech.md` L241 / `docs/ja/tech.md` L228 の `HAS_PR_PREVIEW_CAPABILITY` 説明 (Steering Docs sync candidate として Spec Notes に include/exclude 判断を委譲されていた項目) は、`/verify` post-merge の skip 挙動が「常時 skip」から「最新マーカーが未検証の場合はフォールバック」に変わった以上、既存記述をそのまま残すと新仕様と矛盾するため、include (更新する) と判断した。

### Rework

N/A — 手戻りは発生しなかった。

## review retrospective

### Spec vs. implementation divergence patterns

- 構造的な乖離は無し。Implementation Steps 1–8 は `/code` で Spec どおりに実装されており、`/review` の Step 8 (rubric AC1–3) 再確認でも PASS を再現できた。
- ただし Spec の Design Gaps/Ambiguities で「include (更新する)」と判断した Steering Docs sync candidate (`HAS_PR_PREVIEW_CAPABILITY` / preview AC skip 挙動の説明箇所) の sync 範囲確定が、`docs/tech.md` の変数テーブルセルと `docs/guide/customization.md` の詳細な箇条書き (旧 L200 付近) の 2 箇所に留まっていた。同じ `capabilities.pr-preview` の挙動を説明する `docs/guide/customization.md` の設定リファレンス表セル (config-reference table、L131) と ja 版 (L120) は sync 対象として認識されず、旧仕様 (無条件 skip) の記述のまま残っていた。`/review` の Multi-perspective Code Review (review-spec) がこれを SHOULD として検出し、Step 12 で修正済み。

### Recurring issues

- 「1 つの挙動変更につき、同じキーを説明する複数箇所 (詳細な prose の箇条書き / 変数テーブル / 設定リファレンス表など) が独立して存在し、sync 漏れが起きやすい」というパターンは #1028 (本 Issue の検出元) の Review Retrospective でも触れられていた一般的な論点であり、本 PR でも再現した。Spec Notes で Steering Docs sync candidate を洗い出す際は、変更対象キーを `grep -rn` で横断的に検索し、prose 箇条書きだけでなく設定リファレンス表 (config-reference table) のようなテーブル形式の記述も明示的に sync 対象へ含めることを次回以降の Spec フェーズで意識するとよい。

### Acceptance criteria verification difficulty

- UNCERTAIN・verify command の不備は無し。rubric AC (AC1–3) は `/code` 実装済み内容との突き合わせで PASS 判定でき、`github_check` AC (AC4) は CI (`Run bats tests` 含む全ジョブ SUCCESS) で機械的に PASS 判定できた。AC3 (「テストが存在する」) がスクリプト切り出し (`resolve-preview-ac-fallback.sh`) により実挙動ベースの bats アサーションとして検証可能になっていた点は、#1028 が指摘した「prose-driven SKILL.md ステップは bats で検証しづらい」という課題への有効な対処であり、AC 記述の検証難度を下げていた。

## Phase Handoff
<!-- phase: merge -->

### Key Decisions

- `mergeable=true` (clean/CI success/review approved) だったため、Step 3 (Resolve Conflicts) はスキップし Step 4 (Squash Merge) へ直接進んだ。
- `gh pr merge 1038 --squash --delete-branch` で squash merge・リモートブランチ削除を実行し、`closes #1035` により Issue #1035 は自動クローズ対象 (BASE_BRANCH=main)。

### Deferred Items

- Spec Deferred Items を継承: `gh` の `--jq` 式 (`sort_by(.createdAt) | .[-1]`) の正しさは bats で検証できず、Post-merge の observation AC に委ねる。
- prose-driven SKILL.md ステップのスクリプト切り出しを他ステップへ横展開する話は本 Issue のスコープ外 (変更なし)。

### Notes for Next Phase

- Post-merge AC (downstream プロジェクトでの fix-cycle 誤 fallback 観察) は observation type のため `/verify` 時に手動確認が必要。
- Issue #1035 の Pre-merge AC 4 件は全て `[x]` 済み。squash merge 完了、Issue 自動クローズ・`phase/verify` ラベル遷移待ち。

## Verify Retrospective

### Phase-by-Phase Review

#### issue
- Nothing to note — Auto-Resolved Ambiguity Points に triage 判断の根拠が明記されており、`/spec` フェーズで訂正された事実誤認 (tests/review.bats・tests/verify.bats の性質) は Spec Notes に追記済み。issue triage 品質は妥当。

#### spec
- Spec Notes で「Steering Docs sync candidate」として `HAS_PR_PREVIEW_CAPABILITY` の tech.md 記述を include したが、同キーを説明する `docs/guide/customization.md` の config-reference table (L131) と ja 版 (L120) は sync 対象として明示認識されておらず、review-spec で SHOULD 検出された。ここは Recurring issue パターン (下記) として次回以降 `grep -rn` cross-search が必要。

#### code
- Nothing to note — Implementation Steps 1-8 通りに実装、逸脱なし。テストは Spec 記載の 4 ケース + fail-open 対応で 9 ケースに増強され、いずれも 1 発 PASS。

#### review
- review-spec が SHOULD で sync gap を検出し Step 12 で修正済み (`docs/guide/customization.md` L131 と ja 版 L120)。review process 自体が期待通り機能した。
- ただし「複数箇所 sync 漏れ」パターンが #1028 と本 #1035 の 2 サイクル連続で観測された。1 度目 (#1028) は observation として記録に留めたが、2 度目 (#1035) で再現した以上、Spec フェーズでの cross-search 手順化を提案する (Improvement Proposal 参照)。

#### merge
- Nothing to note — 通常のスカッシュマージ成功。

#### verify
- Nothing to note — Pre-merge AC 4 件はすべて自動検証で PASS、UNCERTAIN 0。scripts 切り出しにより rubric AC が bats テストで裏付け可能になったのは #1028 の Review Retrospective で指摘された課題への有効な対処。

### Improvement Proposals

- **Spec Notes での Steering Docs sync candidate 洗い出しに `grep -rn` cross-search を明示的手順化**: 2 サイクル連続で「同じ挙動変更を説明する複数箇所 (prose 箇条書き / 変数テーブル / config-reference table) の sync 漏れ」が発生 (#1028 → #1035)。Spec Notes で対象キー (例: `HAS_PR_PREVIEW_CAPABILITY`) を確定する際、`grep -rn "<key>" docs/` で全出現箇所を洗い出し、prose 箇条書き以外のテーブル・リファレンス系の記述も明示的に sync 対象へ include するステップを `skills/spec/SKILL.md` (または `modules/detect-config-markers.md` の Steering Docs sync candidate 節) に追記する。優先度は low-medium (review-spec が catch する safety net が既にあるため実害は最小限だが、review の負荷軽減効果あり)。
