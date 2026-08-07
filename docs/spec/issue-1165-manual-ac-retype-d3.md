# Issue #1165: verify: manual AC 区分 D3 (その他 19 件) を個別判断で再型付けまたは retire

## Overview

`phase/verify` に滞留する `verify-type: manual` の post-merge AC のうち、区分 D3 (キーワード機械分類で A / B / C / D1 / D2 のいずれにも当てはまらなかった残余) に分類された 19 Issue を対象に、1 件ずつ条件文を読んで **observation への再型付け / retire / manual 維持** のいずれかへ振り分ける。

対象 19 Issue が持つ未チェックの `verify-type: manual` post-merge AC は **22 行** (#710 / #484 / #478 が各 2 行)。全件を精査した結果、**16 行を `observation` へ再型付け** (`auto-run` 14 / `watchdog-kill` 1 / `pr-review-full` 1)、**6 行を retire**、**manual 維持は 0 行** とする。対象 Issue の内訳は再型付け 14 Issue / retire 6 Issue (#484 は両方に 1 行ずつ持つため重複) で、合計 19 Issue。

加えて AC ではないが機械走査にマッチする行が 2 件あり、うち #491 のコードフェンス内サンプル行のみインデントで無害化する。

振り分け結果と判断根拠は `docs/reports/manual-ac-retype-d3.md` に記録する。この記録ファイルがあることで Pre-merge の `rubric` AC が grader から参照可能になる (grader へ渡るのは Issue 本文・git diff・rubric 本文で名指しされたファイルのみ。Spec ファイルと Issue コメントは渡らない)。#1163 (区分 A) と同じ構成。

## Consumed Comments

cutoff: 未確定 — Issue timeline に `phase/*` ラベル付与イベントが存在せず (`/spec` Step 3 の `phase/spec` 付与が初回)、`.tmp/auto-events.jsonl` にも本 Issue の `phase_start` がない。`modules/l0-surfaces.md` § Comment Consumption Procedure の Fallback B に従い全コメントを対象とした。

結果: **コメントなし** (`gh issue view 1165 --json comments` が空配列)。Cross-phase marker (`type=verify-fail` / `type=preview-ac-unverified`) の追加スキャンも該当なし。

- saito / MEMBER / first-class / ## Acceptance Test Results / https://github.com/saitoco/wholework/issues/1165#issuecomment-5213532595
- saito / MEMBER / first-class / <!-- wholework-event: type=observation-trigger phase=observation-trigger issue=1 / https://github.com/saitoco/wholework/issues/1165#issuecomment-5213691799
## Autonomous Auto-Resolve Log

`/spec 1165 --non-interactive` で自動解決した曖昧点 3 件。詳細な却下候補は Issue 本文の `## Auto-Resolved Ambiguity Points` 節に記録済み。

- **retire の実行形態 = 新設 `### Retired Post-merge Conditions` 節へ取り消し線付きプレーン箇条書きで退避** — reason: `scripts/check-ac-checkbox-format.sh` の awk は `### Pre-merge` / `### Post-merge` 配下のみを検査し、別見出しに入った時点で `in_section = 0` になる。別節へ移せば #1156 の形式ガードに抵触せず、`- [ ]` アンカーからも外れるため機械走査の対象外になる
  - Other candidates: AC 行の削除 (判断根拠が消える) / `- [x]` 化 (未検証を検証済みと偽る) / `### Post-merge` 内にプレーン箇条書きで残す (`check-ac-checkbox-format.sh` が exit 2)
- **OPEN 2 件 (#490 / #465) も再型付けの対象に含める** — reason: 型付けとしては `observation` が正しく、両者とも Pre-merge AC は全件チェック済み。close 後は dispatch 母集団に自然に入る
  - Other candidates: OPEN のため対象外 (型が誤ったまま残る) / 本 Issue で close まで行う (スコープ外)
- **#491 のコードフェンス内サンプル行は 2 スペースのインデントで無害化する** — reason: サンプル行は AC ではないので再型付けは誤りだが、放置すると #491 が Manual Waiting Count から永久に外れない
  - Other candidates: 既知の偽陽性として記録するのみ (post-merge AC を #491 分だけ満たせない) / サンプルの `verify-type` を書き換える (ガイドラインの内容自体を誤らせる)

## Changed Files

- `docs/reports/manual-ac-retype-d3.md`: 新規作成 — 区分 D3 22 AC 行の振り分けマッピング表 (Issue 番号 / 条件文要約 / 振り分け先 / 判断根拠)、retire 6 行の理由、対象外 2 行の扱い、`opportunistic-search.sh` 実行による検証結果、および OPEN 2 件が dispatch 母集団外である旨の注記
- `docs/structure.md`: 変更不要 — Directory Layout tree に `docs/reports/` は既出 (line 62)。Key Files 側は「スクリプトが消費する report ファイル」のみ列挙する方針 (`orchestration-recoveries.md` / `orchestration-fallbacks-archive.md` が該当) であり、本記録ファイルは消費側スクリプトを持たないため追加不要 (`grep -n "reports" docs/structure.md` で確認済み)
- `docs/ja/` 同期: 対象外 — `docs/translation-workflow.md` § Exclusions が `docs/reports/` を明示的に除外 (line 21 で確認済み)
- リポジトリ外 (GitHub Issue 本文, 16 AC 行 / 14 Issue): 後掲「再型付けマッピング」表のとおり `<!-- verify-type: manual -->` を `<!-- verify-type: observation event=<name> [gate] -->` へ置換
- リポジトリ外 (GitHub Issue 本文, 6 AC 行 / 6 Issue): 後掲「retire マッピング」表のとおり `### Post-merge` から除去し `### Retired Post-merge Conditions` 節へ退避
- リポジトリ外 (GitHub Issue 本文, #491 のコードフェンス内サンプル行 1 行): 2 スペースのインデント付与
- リポジトリ外 (GitHub ラベル, 4 Issue): retire により post-merge 未チェック条件が 0 になる #706 / #587 / #563 / #591 を `phase/verify` → `phase/done` へ遷移

## 再型付けマッピング (16 AC 行 / 14 Issue)

### `event=auto-run` (14 AC 行)

| Issue | 条件文の要約 | 付与するタグ | 選定根拠 |
|---|---|---|---|
| #1135 | 回避策適用状態の `/auto --batch` で `manual-recovery-respawn` 新規エントリ発生率を適用前と比較・記録 | `event=auto-run when=mode:batch` | 観測窓は `/auto --batch` 完了時。`mode` は `when=` の宣言可能軸にあり事前排除できる (`modules/observation-trigger.md` § Condition Check Gate (`when=`)) |
| #1056 | `pup` 未インストール環境で `html_check` が UNCERTAIN でなく PASS/FAIL を返す | `event=auto-run` | 前提 (pup 不在) は 2026-08-07 に `command -v pup` で不在を実測済みで成立。発火契機が無いことだけが滞留原因なので、`auto-run` で `/verify` を dispatch すれば Step 8b/8c が実際に判定できる |
| #961 | 並列セッション環境で merge-to-main が他セッションのブランチに影響しない | `event=auto-run` | 「並列セッション環境」は `when=` の宣言可能 3 軸 (route / mode / recovery-tier) に存在せず事前排除できない。#1163 の #861 / #859 と同じ判断 |
| #710 条件1 | `Blocked by #N` 付き試験 Issue を `/issue` で起票し `blockedByIssues` に relationship が設定される | `event=auto-run` | `/issue` phase は `/auto` の内側。試験 Issue を用意しなくても `Blocked by #N` を持つ実 Issue の起票で観測窓が開く |
| #710 条件2 | body-only `Blocked by #N` の既存 Issue に `/triage N` で relationship が backfill される | `event=auto-run` | `/triage` phase は `/auto` の内側。本リポジトリは `autonomy: L3` のため `/triage` が advisory ではなく `set-blocked-by.sh` を実行する (L1 既定では advisory のみ — `skills/spec/SKILL.md` Step 4 参照) |
| #513 | 次の同種 Issue で間接反映 AC が post-merge manual または command 型に正しく分類される | `event=auto-run` | `/issue` phase の内側。#1163 の #804 / #778 と同型 |
| #512 | `/spec` フェーズで距離ルールに「A 以上かつ B 以下」表記が使われる | `event=auto-run` | `/spec` phase の内側。#1163 の #804 と同型 |
| #491 | `/verify` 実行前に `workflow_dispatch` を促す運用が実際のワークフローで機能する | `event=auto-run` | `/verify` phase は `/auto` の内側 |
| #490 | 実際の Issue AC で cron 依存条件に注記が付くことを 1 件以上のサンプルで確認 | `event=auto-run` | `/issue` phase の内側。**ただし #490 は OPEN のため dispatch 母集団外** (後掲 Notes) |
| #484 条件1 | 代表的な `/verify` 実行で Improvement Proposals が 3 層に分類され Tier 1 のみ Issue 化される | `event=auto-run` | `/verify` phase の内側 |
| #478 条件1 | `/auto --batch` 実行中に blocked Issue がスキップされ適切な警告メッセージが出力される | `event=auto-run when=mode:batch` | batch 実行が観測窓。`mode` 軸で事前排除できる |
| #478 条件2 | スキップされた Issue が checkpoint の `remaining` に保持され `--batch --resume` で再処理できる | `event=auto-run when=mode:batch` | 同上 |
| #477 | 次の外部 API 統合 Spec で本規約が適用されている | `event=auto-run` | `/spec` phase の内側。「外部 API 統合 Spec」の出現有無は `when=` 3 軸で表現できず事前排除不能 (`modules/observation-trigger.md` § Conditions That Cannot Be Pre-Excluded) |
| #465 | `/auto` 実行で silent no-op が自動検出され 3-tier recovery へ流れる | `event=auto-run` | 条件文が `/auto` 実行を明示。**ただし #465 は OPEN のため dispatch 母集団外** (後掲 Notes) |

**ゲートの内訳**: 上表 14 行のうち、`when=mode:batch` ゲート付きが 3 行 (#1135 / #478 条件1 / #478 条件2)、ゲートなしが 11 行 (#1056 / #961 / #710×2 / #513 / #512 / #491 / #490 / #484 条件1 / #477 / #465)。

### `event=watchdog-kill` (1 AC 行)

| Issue | 条件文の要約 | 付与するタグ | 選定根拠 |
|---|---|---|---|
| #535 | watchdog-kill-before-PR を再現し Tier 3 が `unsupported op` なく commit→push→PR create で自動復旧する | `event=watchdog-kill` | watchdog kill の発火そのものが観測窓。`scripts/claude-watchdog.sh:138-140` の kill handler が `observation-trigger.sh --event watchdog-kill` を呼ぶ実装済み経路 |

### `event=pr-review-full` (1 AC 行)

| Issue | 条件文の要約 | 付与するタグ | 選定根拠 |
|---|---|---|---|
| #575 | `capabilities.workflow: true` のプロジェクトで `/review --full` が Workflow 経路で完走し概算トークン使用量が出力される | `event=pr-review-full config=capabilities.workflow` | 条件文が `--full` review を明示しており `pr-review-full` が正確な観測窓。`capabilities.workflow` は block 形式 1 階層ネストキーで `get-config-value.sh capabilities.workflow false` が `true` を返すことを 2026-08-07 に実測済み (`config=` は boolean 専用の制約を満たす) |

## retire マッピング (6 AC 行 / 6 Issue)

| Issue | 条件文の要約 | retire 理由 | retire 後の phase |
|---|---|---|---|
| #783 | 停止後 `/merge N` で手動 merge できることを確認 | `auto-stop-at` は本リポジトリ未設定 (既定 `verify` = フルパイプライン) で停止自体が起きない。`config=` ゲートは boolean 専用のため enum キー `auto-stop-at` を表現できず (`modules/observation-trigger.md` § Condition Check Gate (`config=`))、観測窓が原理的に開かない。実装の正しさは Pre-merge AC 10 件 (全チェック済) が担保 | `phase/verify` 維持 (他に未チェックの `opportunistic` AC 2 件が残る) |
| #706 | `/audit drift` の "label namespace 整合性" チェック (将来拡張) がエラーを出さない | 条件文自身が「(将来拡張)」と明記するとおり当該チェックは未実装 (`grep -rn "label namespace" skills/audit/SKILL.md` で該当なし。規約は `modules/label-conventions.md` に定義されているのみ)。実装されるまで発火契機が存在しない | `phase/done` へ遷移 (Pre-merge 6 件全チェック済 / 他の post-merge 条件なし) |
| #591 | 実 XL Issue (Nuxt → Next 移行) の decomposition YAML で 50+ sub-issue を一括起票 | downstream プロジェクト固有の XL Issue が前提で、upstream に該当 Issue が存在しない。`examples/decomposition/nuxt-to-next.yml` はサンプルとして存在するが、これを使って upstream に 50+ の実 Issue を作るのは正当な操作ではない。区分 B (別 repo 依存) 相当で upstream から観測不能 | `phase/done` へ遷移 (Pre-merge 11 件全チェック済 / 残る post-merge 1 件は `- [x]`) |
| #587 | Fable 5 復帰後にレポート結論が再評価され必要なら follow-up spike が起票されている | Fable 5 は 2026-07-01 に再デプロイ済 (`docs/tech.md` § Watchdog timeout calibration の #939 注記) で前提条件は既に発生済み。しかし比較の基準だった「Opus 4.8 親セッション」構成は Sonnet 5 (2026-06-30) / Opus 5 (2026-07-24) のリリースで陳腐化しており、2026-06-14 時点のレポート (`docs/reports/auto-parent-session-comparison-2026-06-14.md`) の再評価に残存価値がない | `phase/done` へ遷移 (Pre-merge 5 件全チェック済 / 他の post-merge 条件なし) |
| #563 | (該当時) Fable 5 採用後に security 観点の Opus 4.8 fallback が運用上問題ないこと | `docs/tech.md` line 115 が Fable 5 を **opt-in only (never a default model swap)** と明記しており「採用後」という前提が成立しない。条件文自身も「(該当時)」と条件付き。cyber classifier fallback の挙動は同 line に記載済で、監視メモの追加という実装目的は Pre-merge AC 6 件で達成済 | `phase/done` へ遷移 (Pre-merge 6 件全チェック済 / 残る post-merge 1 件は `- [x]` の `auto`) |
| #484 条件2 | downstream プロジェクトで retro/verify Issue の発生量がノイズ削減方向に変化することを観察 | 別リポジトリでの主観評価であり upstream から観測不能。#1163 が #501 / #500 / #479 に適用した downstream 依存の判断と同型。さらに三層判定の既定値自体が #1159 (close 済) で見直されており、2026-05 時点の判定ロジックに対する観察は前提が変わっている | `phase/verify` 維持 (同 Issue の条件1 が再型付けされ未チェックで残る) |

## 対象外 (編集しない / 別扱い, 2 行)

| Issue | 行の性質 | 扱い |
|---|---|---|
| #591 | `- [x]` (チェック済み) の manual AC 「フル auto-decomposition の follow-up Issue が起票されている」 | **編集しない**。既に解決済みで `- [x]` のため Manual Waiting Count にも `opportunistic-search.sh` にもマッチしない (両者とも未チェック行のみを対象とする) |
| #491 | `## 提案内容` 節のコードフェンス内サンプル行 `- [ ] Trigger workflow once via ... <!-- verify-type: manual -->` | **AC ではないため再型付けも retire もしない**。ただし `- [ ]` + `verify-type: manual` に機械マッチし `/audit stats` の Manual Waiting Count に計上されるため、2 スペースのインデントを付けて `^- \[ \]` アンカーから外す。テキスト本文と `verify-type` は変更しない |

## Implementation Steps

1. `docs/reports/manual-ac-retype-d3.md` を新規作成し、本 Spec の「再型付けマッピング」「retire マッピング」「対象外」の各表 (22 AC 行 + 対象外 2 行) を転記する。冒頭に対象 Issue 一覧・件数内訳 (再型付け 16 / retire 6 / manual 維持 0 / 対象外 2) と、`event=` の有効値が `modules/verify-classifier.md` の 5 種に限られる制約、および OPEN 2 件が dispatch 母集団外である注記を記す (→ AC1, AC2, AC3)
2. `.tmp/retype-d3-mapping.json` を Write ツールで作成する (after 1)。各要素は `{"issue": N, "match": "<AC 行を一意に特定する部分文字列>", "tag": "<observation event=... の完全なタグ本文>"}`。`match` は本 Spec の表の「条件文の要約」ではなく Issue 本文の実際の AC 行から取った一意な部分文字列を使う (例: #1135 なら `manual-recovery-respawn`、#535 なら `unsupported op`)
3. `.tmp/retype-d3.py` を Write ツールで作成する (after 2)。既定は dry-run、`--apply` で適用。処理は Issue ごとに: `gh issue view N --json body -q .body` で本文取得 → `match` と `<!-- verify-type: manual -->` の両方を含む行を抽出 → **ちょうど 1 行でなければ当該 Issue を skip して警告** → 該当行の `<!-- verify-type: manual -->` のみを `<!-- verify-type: observation <tag> -->` へリテラル置換 → 本文全体を `.tmp/issue-body-N.md` へ書き出し → `scripts/gh-issue-edit.sh N .tmp/issue-body-N.md` を呼ぶ (`--apply` 時のみ)
4. `python3 .tmp/retype-d3.py` (dry-run) を実行し、16 AC 行すべてについて置換前後の行を目視確認する。skip 警告が 1 件でも出た場合は `match` 文字列を修正して再実行する (after 3) (→ AC1)
5. `python3 .tmp/retype-d3.py --apply` を実行し、16 AC 行を再型付けする (after 4) (→ AC2, AC4, AC5, AC6)
6. retire 対象 6 AC 行 (#783 / #706 / #591 / #587 / #563 / #484 条件2) を 1 件ずつ手作業で編集する (after 5)。各 Issue の本文を `.tmp/issue-body-N.md` へ取得し、(a) `### Post-merge` から該当行を除去、(b) `### Post-merge` が空になる場合は「すべての post-merge 条件は #1165 で retire 済み (下記 `### Retired Post-merge Conditions` を参照)。」という**箇条書きでない一文**を置く、(c) `### Post-merge` の直後に `### Retired Post-merge Conditions` 節を新設し `- ~~<条件文>~~ — **retired (#1165)**: <理由>` を追加 (`<!-- verify-type: manual -->` マーカーは削除する)、(d) 形式検証 — `### Pre-merge` / `### Post-merge` 見出し配下に `- [ ]` / `- [x]` 以外の箇条書きが残っていないことを確認する (`scripts/check-ac-checkbox-format.sh` は `/code` の `allowed-tools` 未登録のため、同等判定を `python3` のワンライナーで行うか目視で代替してよい)、(e) `scripts/gh-issue-edit.sh N .tmp/issue-body-N.md` で書き戻す (→ AC3, AC7)
7. #491 の `## 提案内容` 節コードフェンス内サンプル行 (`- [ ] Trigger workflow once via ...`) の行頭に半角スペース 2 個を付与し、`scripts/gh-issue-edit.sh 491` で書き戻す。同 Issue の実 AC (Step 5 で再型付け済) には触れない (after 5)
8. retire により post-merge の未チェック条件が 0 になる #706 / #587 / #563 / #591 の 4 件を `${CLAUDE_PLUGIN_ROOT}/scripts/gh-label-transition.sh <N> done` で `phase/done` へ遷移させる。遷移前に各 Issue の Pre-merge / Post-merge に未チェック行が残っていないことを `gh issue view N --json body` で確認する (after 6) (→ AC3, AC8)
9. `${CLAUDE_PLUGIN_ROOT}/scripts/opportunistic-search.sh --event auto-run` / `--event watchdog-kill` / `--event pr-review-full` をそれぞれ実行し、返却 JSON に再型付けした Issue 番号が**個別に**含まれることを確認する (件数差分だけで判定しない — #1163 の Code Retrospective で母集団が他要因でも変動することが確認されている)。OPEN の #490 / #465 が含まれないことも合わせて確認し、結果を `docs/reports/manual-ac-retype-d3.md` の `## 検証` 節へ追記する (after 5, 6, 8) (→ AC2)
10. `.tmp/retype-d3-mapping.json` / `.tmp/retype-d3.py` / `.tmp/issue-body-*.md` を削除し、コミット対象を `docs/reports/manual-ac-retype-d3.md` のみにする (after 9)

## Verification

### Pre-merge

- <!-- verify: rubric "docs/reports/manual-ac-retype-d3.md に区分 D3 の対象 AC 行全件のマッピング表があり、各行が『Issue 番号 / 元の条件文の要約 / 振り分け先 (observation の event= 名 / retire / manual 維持) / 判断根拠』を持つ。未処理の AC 行が残っていない" --> 対象全件が振り分けられ判断根拠が記録されている
- <!-- verify: rubric "docs/reports/manual-ac-retype-d3.md で observation へ再型付けした AC 行について、modules/verify-classifier.md の 5 有効値 (pr-review-full / pr-review-light / auto-run / watchdog-kill / fix-cycle) のいずれかが event= として記録され、その event を選んだ理由 (観測窓がどの実行の内側で開くか) が示されている" --> 再型付け分に有効な event= と選定根拠が記録されている
- <!-- verify: rubric "docs/reports/manual-ac-retype-d3.md で retire した AC 行について、条件を取り下げた理由 (前提が本リポジトリで成立しない / 機能が未実装 / downstream 依存で upstream から観測不能 など) が Issue 単位で記載され、取り下げ後に post-merge の未チェック条件が残らない Issue については phase/done へ遷移させたことが記録されている" --> retire 分の理由と phase 遷移が記録されている
- <!-- verify: github_check "gh issue view 961 --json body --jq .body" "verify-type: observation event=auto-run" --> 代表 Issue #961 の post-merge AC が `observation event=auto-run` へ再型付けされている (GitHub 上の実状態)
- <!-- verify: github_check "gh issue view 535 --json body --jq .body" "verify-type: observation event=watchdog-kill" --> 代表 Issue #535 の post-merge AC が `observation event=watchdog-kill` へ再型付けされている (GitHub 上の実状態)
- <!-- verify: github_check "gh issue view 575 --json body --jq .body" "config=capabilities.workflow" --> 代表 Issue #575 の post-merge AC に `config=capabilities.workflow` ゲートが付与されている (GitHub 上の実状態)
- <!-- verify: github_check "gh issue view 706 --json body --jq .body" "Retired Post-merge Conditions" --> retire した #706 の条件が `### Retired Post-merge Conditions` 節へ退避されている (GitHub 上の実状態)
- <!-- verify: github_check "gh issue view 706 --json labels" "phase/done" --> retire 完了により #706 が `phase/done` へ遷移している (GitHub 上の実状態)

### Post-merge

- 移行完了後の `/audit stats --retention` で、phase/verify の Manual waiting 件数が本 Issue で処理した 19 Issue 分だけ減少していることを確認する

## Tool Dependencies

### Bash Command Patterns

- `gh issue view:*`: 各対象 Issue の本文・ラベル取得 (`/code` の `allowed-tools` に登録済み)
- `${CLAUDE_PLUGIN_ROOT}/scripts/gh-issue-edit.sh:*`: Issue 本文の書き戻し (登録済み)
- `${CLAUDE_PLUGIN_ROOT}/scripts/gh-label-transition.sh:*`: retire 完了 4 件の `phase/done` 遷移 (登録済み)
- `${CLAUDE_PLUGIN_ROOT}/scripts/opportunistic-search.sh:*`: 再型付け後のマッチ確認 (登録済み)
- `python3:*`: 一括置換ヘルパの実行 (登録済み)
- `scripts/check-ac-checkbox-format.sh`: retire 編集後の形式検証 — **`/code` の `allowed-tools` に未登録** (frontmatter を実確認済み)。`Bash(bats:*)` / `Bash(python3:*)` 等の既存パターンにも該当しないため実行が権限で弾かれうる。`allowed-tools` への追加は本 Issue のスコープ外とし、Step 6 (d) は登録済みの `python3` による同等判定または目視確認で代替する。設計上は退避先が `### Retired Post-merge Conditions` (別見出し) なので形式違反は構造的に発生せず、この検証は安全網に留まる

### Built-in Tools

- `Write`: 記録ファイル・一時ヘルパ・Issue 本文の書き出し
- `Read` / `Grep`: 置換結果の確認

### MCP Tools

- なし

## Notes

### 「19 件」の単位ずれ (#1163 と同じ再現)

Issue 本文と `docs/stats/2026-08-05.md` Section 10 の「区分 D3 = 19 件」は Issue 単位の数え方。実際の未チェック `verify-type: manual` AC 行数は 22 行 (#710 / #484 / #478 が各 2 行)。#1163 の spec retrospective が「他の sub-issue (#1164/#1165/#1166/#1167) でも同じずれが起きうる」と予告したとおりに再現した。記録ファイルでは AC 行単位で数え、Issue 単位との対応を明記する。

### OPEN 2 件 (#490 / #465) は dispatch 母集団に入らない

`scripts/opportunistic-search.sh:202` と `scripts/scan-pending-ac.sh:106` はいずれも `gh issue list --label phase/verify --state closed` で母集団を取る。#490 / #465 は OPEN (一度も close されていない — timeline の `closed` イベントが 0 件) のため、`observation` へ再型付けしても `observation-trigger.sh` 経路でも `run-fact-matching` 経路でも dispatch されない。

両者とも Pre-merge AC は全件チェック済みで実装は着地しており、close されれば母集団に入る。close 判断は各 Issue 自身の post-merge 充足に依存するため本 Issue のスコープ外とし、記録ファイルに事実として明記する。**「closed 限定の母集団が OPEN + `phase/verify` の Issue を構造的に取りこぼす」点は本 Issue とは独立した設計上のギャップであり、別途起票候補**。

### `docs/stats/2026-08-05.md` § 11 の母集団訂正

同レポートの訂正 1 が「Section 10 の棚卸し方針も 90 日窓の母集団に基づくため、全期間へ広げた場合の対象件数は増える」と明記している。本 Issue は Issue 本文が名指しする 19 件のみを対象とし、全期間への母集団拡張は扱わない (親 #1158 側の判断事項)。

### `manual` 維持がゼロである理由

区分 D1 (UI 目視) と C (故障注入) は #1167 が担当し、D3 には真に人間の目を要する条件が残っていなかった。前提が成立しない条件は「manual のまま滞留させる」よりも retire したほうが状態が正確になるため、#1163 が「対象外 = `manual` 維持」としたケース (#704 の `autonomy: L2` 前提など) に相当するものも、本 Issue では retire を選んでいる。これは #1163 からの意図的な方針変更であり、根拠は本 Issue の scope に retire が明示的に含まれている点 (親 #1158 の「D3 = 個別判断 (再型付け / retire)」)。

### `config=` が enum キーを表現できない制約 (#783 の retire 理由)

`modules/observation-trigger.md` § Condition Check Gate (`config=`) は「The comparison is boolean-only (`true`/`false`); enum-valued keys (e.g. `auto-stop-at`) are out of scope. Both are candidates for a `config=key:value` extension if a future Issue needs them.」と明記している。#783 はまさにこの enum キー依存のケースで、`config=key:value` 拡張があれば retire ではなく再型付けできた。**`config=key:value` 拡張は別途起票候補** (本 Issue のスコープ外)。

### `when=mode:batch` の fail-open 挙動

`scripts/opportunistic-search.sh` の `when=` ゲートは run facts が取得不能・不正 JSON・文脈なしのいずれでも**無条件マッチ (fail-open)** に倒れる (`resolve_run_facts()`)。したがって `when=mode:batch` を付けた 3 行 (#1135 / #478×2) は、facts が取れない場合でも従来どおり dispatch される。dispatch 削減は best-effort であり、取りこぼしのリスクは生じない。

なお `modules/run-fact-matching.md` § Fact JSON Fields の caveat のとおり、XL sub-issue fan-out は `--batch` ではないため `mode` が `single` になる。#1135 / #478 の条件文はいずれも明示的に `--batch` を指す (XL fan-out ではない) ため、この caveat は本件の判断に影響しない。

### `event=watchdog-kill` は comment 投稿のみで `/verify` 自動 dispatch はされない

`scripts/claude-watchdog.sh:138-140` は shell context のため `Skill` ツールを持たず、`observation-trigger.sh --event watchdog-kill` の stdout を消費しない (`modules/observation-trigger.md` § Who invokes `/verify`)。#535 は kill 発火時に通知コメントが付くところまでが自動化範囲で、`/verify 535` の実行は人間または後続の `/auto` に委ねられる。それでも「発火契機が一切ない `manual`」よりは前進であるため `watchdog-kill` を採用する。

### `## Retired Post-merge Conditions` は本 Issue で導入する新しい慣行

既存の Issue 本文にこの節を持つ例はない。`scripts/check-ac-checkbox-format.sh` の awk が `^### ` で `in_section = 0` にリセットする挙動に依存するため、**必ず `### ` (h3) 見出しで、`### Post-merge` より後ろに置く**こと。h4 (`#### `) では awk の `/^## / || /^### /` にマッチせず `in_section` が解除されないため形式違反として検出される。

### 一括置換ヘルパは `.tmp/` に置き `scripts/` へ残さない

#1163 と同じ方針。区分ごとに置換対象の条件が異なるため汎用化の利得が薄く、移行完了後は dead code になる。`.tmp/` に置いて Write ツールで内容を可視化し、dry-run → apply の 2 段階で安全性を担保する。retire 6 行はタグ置換ではなく節の移動を伴うため、スクリプト化せず 1 件ずつ手作業で編集する。

### operate route ではなく pr route

#1163 と同じ理由。Pre-merge AC のうち 3 件が `rubric` であり、`modules/verify-executor.md` の定義上 grader が受け取るのは Issue 本文・git diff・rubric 本文で名指しされたファイルのみ (Spec ファイルと Issue コメントは渡らない)。operate route では成果物が `## Execution Log` コメントにしか残らず rubric が評価不能になる。記録ファイルを 1 本置く pr route に切り替えることで rubric が評価可能になる。

Size L 維持の根拠も #1163 と同じ — リポジトリ内変更は 1 ファイルで Axis 1 (diff サイズ) は XS 相当だが、実体は 19 Issue への L0 変更 + 4 件のラベル遷移であり、patch route (review なし) は blast radius に見合わない。

### GitHub 検索インデックスの遅延

`opportunistic-search.sh` の母集団取得は `gh issue list --search "verify-type: observation in:body"` に依存する。Issue 本文編集の直後は検索インデックスが未更新で、再型付けした Issue が母集団に現れないことがある。Step 9 でマッチが確認できない場合は、本文が正しく置換されていること (`gh issue view N --json body`) を先に確認したうえで時間を置いて再実行する。判定を急いで「マッチしない」と結論づけないこと。

### `session=next` は付与しない

`modules/verify-classifier.md` の `session=next` は、Issue が `skills/*/SKILL.md` を変更しその skill 自身の挙動を観察する post-merge 条件に付ける宣言。対象 19 件はいずれも変更が既に main へ着地して久しく、skill 内容の伝播は完了しているため付与しない (#1163 と同じ判断)。

### 母集団の増加

#1163 が 27 行を `auto-run` に追加した結果、`opportunistic-search.sh --event auto-run` のマッチは 59 AC 行 (2026-08-06 実測) になっている。本 Issue で `auto-run` に 14 行 (うち 3 行は `when=mode:batch` ゲート付き) が加わる。`modules/observation-trigger.md` § "Conditions That Cannot Be Pre-Excluded" が「文脈条件で事前排除できない条件が SKIPPED に解決するのは正しい挙動」と定めており、コメント蓄積は #1099 の idempotency guard (24h)、dispatch 回数は `observation-dispatch-threshold` (既定 5) が抑える。

## spec retrospective

### Minor observations

- `opportunistic-search.sh` と `scan-pending-ac.sh` はどちらも母集団を `--state closed` に固定しているため、**OPEN + `phase/verify` の Issue はどちらの自動評価経路にも乗らない**。今回対象の #490 / #465 が該当し、両者とも一度も close されたことがない (timeline の `closed` イベント 0 件)。`docs/stats/2026-08-05.md` Section 7 も `phase/verify` 167 件の内訳を CLOSED 165 / OPEN 2 と記録しており、この 2 件は棚卸しの構造的な死角になっている。区分 A (#1163) は全件 CLOSED だったため露見しなかった。
- `opportunistic-search.sh` は Issue 本文を**セクション非依存**で `^- \[ \]` に対して grep する一方、`scan-pending-ac.sh` は `### Post-merge` にスコープした awk を使う。#491 の `## 提案内容` 節にあるコードフェンス内サンプル行 (`- [ ] Trigger workflow once via ... <!-- verify-type: manual -->`) はこの差異を突く実例で、AC ではないのに `/audit stats` の Manual Waiting Count には計上される。走査のスコープが 2 系統に分かれていること自体が偽陽性の源。
- #1163 の spec retrospective が「他の sub-issue でも Issue 単位 / AC 行単位のずれが起きうる」と予告したとおり、D3 でも 19 Issue = 22 AC 行のずれが再現した。予告が記録として機能した事例。
- `verify-type: manual` の AC が Issue 本文の**表セル**や**通常の箇条書き**に現れるケース (#710 の変更履歴表、#591 の同様の表、#478 の Background 箇条書き) が 4 箇所あった。いずれも `- [ ]` で始まらないため機械走査には乗らないが、全件精査の際に AC と取り違えやすい。

### Judgment rationale

- **`manual` 維持をゼロにし、前提不成立の条件は retire に倒した**。#1163 は同型の状況 (#704 の `autonomy: L2` 前提が本リポジトリで不成立) を「対象外 = `manual` 維持」としたが、これは #1163 の scope に retire が含まれていなかったため。本 Issue は親 #1158 が D3 に対して明示的に retire を認めているので、「前提が原理的に成立しない条件を `manual` のまま滞留させる」より「取り下げて状態を正確にする」を選んだ。#1163 からの意図的な方針変更として Notes に明記した。
- **retire の実行形態を「削除」でも「`- [x]` 化」でもなく「別見出しへの退避」にした**。`scripts/check-ac-checkbox-format.sh` の awk が `^### ` で `in_section` を解除する挙動に依存する設計で、#1156 が禁じた「`### Post-merge` 配下のプレーン箇条書き」を作らずに `- [ ]` アンカーから外せる。削除は判断根拠の消失、`- [x]` は未検証を検証済みと偽ることになる。この形態は本リポジトリに前例がないため、h3 見出しであることが必須という制約を Notes に明記した。
- **`event` の選定で #1163 の「取りこぼさない最も広いイベント」原則を踏襲しつつ、2 件だけ例外を作った**。#535 は `watchdog-kill` の発火そのものが観測窓と一致し、#575 は条件文が `--full` review を明示している。この 2 件は狭いイベントのほうが正確で、かつ取りこぼしが構造的に起きない。残る 14 件は `auto-run` に倒した。
- **`when=mode:batch` を 3 行にのみ付けた**。`when=` の宣言可能軸は route / mode / recovery-tier の 3 つで、#1135 / #478 の条件文が明示する `--batch` は `mode` 軸で表現できる。一方 #961 の「並列セッション環境」や #477 の「外部 API 統合 Spec」は 3 軸のいずれでも表現できないため付けていない — `modules/observation-trigger.md` § "Conditions That Cannot Be Pre-Excluded" が、こうした条件は dispatch → SKIPPED が正しい挙動と定めている。
- **`config=capabilities.workflow` を実際に解決確認してから採用した**。`get-config-value.sh capabilities.workflow false` が `true` を返すことを実行確認済み。block 形式 1 階層ネストキーは #1055 でサポートされているが、`config=` は boolean 専用なので enum キー (#783 の `auto-stop-at`) には使えない — この非対称性が #783 を retire に倒す決め手になった。

### Uncertainty resolution

- **#1056 の前提 (pup 未インストール) が現在成立するか**: `command -v pup` を実行して不在を実測確認した。前提が成立するなら発火契機の欠如だけが滞留原因なので、`auto-run` で dispatch させれば `/verify` が実際に判定できる。もし pup が存在していれば故障注入型 (区分 C 相当) として #1167 へ回すべき条件だった。
- **#706 の「将来拡張」チェックが実装済みか**: `skills/audit/SKILL.md` を grep して label namespace 整合性チェックが存在しないことを確認した。規約自体は `modules/label-conventions.md` に SSoT 化されているが、それを検査する `/audit drift` 側の実装はない。未実装が確定したので retire が妥当と判断した。
- **#587 / #563 の Fable 5 前提の現況**: `docs/tech.md` を読み、(a) Fable 5 は 2026-07-01 に再デプロイ済み (#939 注記)、(b) ただし採用は opt-in only で既定モデル入替は行わない (line 115)、の 2 点を確認した。#587 は前提 (復帰) が発生済みだが比較基準の Opus 4.8 親構成が Sonnet 5 / Opus 5 のリリースで陳腐化しており再評価に価値がない、#563 は前提 (採用) がポリシー上成立しない、と理由を分けて retire した。
- **`watchdog-kill` イベントが `/verify` を自動 dispatch するか**: `scripts/claude-watchdog.sh:138-140` を読み、shell context のため `observation-trigger.sh` の stdout を消費せずコメント投稿のみで終わることを確認した。#535 は通知までが自動化範囲になるが、発火契機が一切ない `manual` よりは前進と判断して採用した。

### 別途起票候補 (本 Issue のスコープ外)

- **`opportunistic-search.sh` / `scan-pending-ac.sh` の母集団が closed 限定で、OPEN + `phase/verify` の Issue を構造的に取りこぼす** — #490 / #465 が実例。
- **`config=` ゲートの `config=key:value` 拡張** — `modules/observation-trigger.md` § Condition Check Gate (`config=`) 自身が候補として挙げている。#783 はこの拡張があれば retire ではなく再型付けできた。
- **`opportunistic-search.sh` の本文走査がセクション非依存であること** — コードフェンス内のサンプル AC を実 AC と誤認しうる。#491 が実例。

## Code Retrospective

### Deviations from Design

- Step 2-6 (mapping JSON + 一括置換ヘルパの作成・実行、retire の手作業編集) は、先行する非対話セッションが GitHub 側編集を完了済みだったため未実行。二重適用を避けるため `.tmp/retype-d3-mapping.json` / `.tmp/retype-d3.py` の新規作成・実行はスキップし、代わりに `gh issue view` によるリテラル一致確認を行う検証スクリプト (`.tmp/verify-retype.py`) に置き換えた。Step 1 (report ファイル作成) および Step 7-10 (検証・コミット・PR 作成) は設計どおり実施した。詳細は下記 § Rework を参照。

### Design Gaps/Ambiguities

- `/code` SKILL Step 3 (`phase/ready` ラベルチェック) で、本 Issue は `phase/ready` を経由せず既に `phase/code` だった。原因は先行する非対話セッションが Spec の Implementation Steps 2-8 (report ファイル作成を除く GitHub 側編集) を完了させた後、ローカルの commit/push/PR 作成前に中断していたため。Spec は完備しており `reconcile-phase-state.sh --check-precondition` の `matches_expected: false` は「ラベルが期待状態と異なる」ことを示すのみで実装の欠落を意味しなかったため、非対話モードの auto-resolve 方針 (warn-only) に従って続行した。

### Rework

- Step 2-3 (mapping JSON + 一括置換 python ヘルパ) と Step 6 (retire の手作業編集) は、実行前に対象 19 Issue 全件の本文・ラベルを `gh issue view` で確認した結果、先行セッションによってすでに完了済みであることが判明したため実行不要だった。二重適用を避けるため、`.tmp/retype-d3-mapping.json` / `.tmp/retype-d3.py` の新規作成・実行はスキップし、代わりに全 16 再型付け行 + 6 retire 行 + 4 ラベル遷移を個別に `gh issue view` でリテラル一致確認する検証スクリプト (`.tmp/verify-retype.py`) を書いて実データを突合した。Spec の Implementation Steps はそのまま (先行実行が失敗した場合の再実行パスとして有効なため変更なし)。
- Step 9 の `opportunistic-search.sh --event auto-run` 実行で #1135 / #478 が母集団にマッチしなかった。当初は GitHub 検索インデックスの遅延 (Spec Notes で予告済み) を原因と推測したが、`scripts/collect-run-facts.sh` がこのセッションで `mode: single` を返すこと、および #1135 / #478 の該当 AC 行がいずれも `when=mode:batch` ゲート付きであることを実測確認した結果、真因は `opportunistic-search.sh` の `when=` 条件ゲート (mode 軸) による設計どおりの除外と判明した。再実行 (2 回目) でも解消しなかったのはインデックス遅延ではなく確定的なゲート除外であることの証跡であり、`gh issue view --json body` によるリテラル一致確認を一次情報として採用した判断自体は変更していない。

## Phase Handoff
<!-- phase: merge -->

### Key Decisions

- pre-merge AC ゲート (`check-pre-merge-ac.sh`) は 8/8 チェック済み、review-incomplete-fallback も検出なしで、追加確認や override marker なしにマージへ進んだ。
- `gh-pr-merge-status.sh` の初回応答が `mergeable=UNKNOWN` (GitHub 側の計算待ち) だったため 30 秒待機後に自動リトライし、`mergeable=true, reason=clean` を得てからスカッシュマージした (`gh pr merge 1230 --squash --delete-branch`)。コンフリクト解消 (Step 3) は不要だった。
- `git merge origin/main --ff-only` で main を取り込んだところ Spec ファイルは既に main 上にあった (PR に同梱済み) ため、フェーズハンドオフの追記のみで済んだ。

### Deferred Items

- OPEN 2 件 (#490 / #465) の close 判断 — spec からの引き継ぎ、未変化。
- `check-ac-checkbox-format.sh` を `/code` の `allowed-tools` へ追加すること — spec からの引き継ぎ、未変化。
- 別途起票候補 3 件 (closed 限定母集団 / `config=key:value` 拡張 / セクション非依存走査) — spec retrospective § 別途起票候補 に記録済み。`/verify` の Improvement Proposals で扱う。

### Notes for Next Phase

- Issue #1165 自体の Post-merge AC (`/audit stats --retention` での Manual waiting 件数減少確認) を `/verify 1165` で確認すること。
- `opportunistic-search.sh --event auto-run` が #1135 / #478 をマッチ集合に含めないのは `when=mode:batch` ゲートによる設計どおりの確定的除外であり、異常や遅延として扱わないこと (review フェーズで確認済み)。
- ラベル遷移 (`gh-label-transition.sh 1165 verify`) はこの Phase Handoff コミット後に実行する。

## review retrospective

### Spec vs. implementation divergence patterns

Spec 自身が § Notes で「GitHub 検索インデックスの遅延」という仮説を code フェーズ以前に予告していたため、code フェーズで実際にマッチ不一致が発生した際、この予告済み仮説へパターンマッチして採用し、実際の除外機構 (`opportunistic-search.sh` の `when=mode:batch` 条件ゲート) を検証しないまま Report / Code Retrospective (Rework) / Phase Handoff (Notes for Next Phase) の 3 箇所へ同一の誤診断を転記した。review フェーズで 2 系統の review-bug エージェントが `scripts/collect-run-facts.sh` の実行結果と `when=` ゲートのコード読解によって誤りを検出し、3 箇所すべてを修正した。Spec が事前に用意した仮説は、実際に発生した不一致の原因を検証済みとみなす根拠にはならない、という教訓が得られた。

### Recurring issues

同一の誤診断が 1 箇所ではなく report / spec 内の 2 箇所 (Rework、Notes for Next Phase) に転記され、計 3 箇所で修正が必要になった。「先行文書 (report) の記述をそのまま後続文書 (retrospective, handoff) へ転記する」構成では、誤りが 1 箇所に留まらず伝播することが実例として確認できた。record-then-propagate 型の成果物では、転記元を修正した際に転記先も連動して修正されているか確認する工程が有効と考えられる。

### Acceptance criteria verification difficulty

Issue #1165 の Pre-merge AC 8 件 (rubric 3 + github_check 5) はいずれも Step 8 で PASS と判定され、UNCERTAIN は発生しなかった。rubric によるマッピング表の網羅性・根拠記録の意味論的検証と、github_check による GitHub 実状態の直接確認が明確に役割分担しており、verify command の記述・分類に起因する曖昧さはなかった。

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- Pre-merge AC を rubric 3 + `github_check` 5 に分担させた設計が有効だった。rubric はマッピング表の網羅性・判断根拠という意味論を、`github_check` は代表 Issue の GitHub 実状態というリテラル事実を扱い、役割が重ならなかった。
- `### 別途起票候補 (本 Issue のスコープ外)` を spec retrospective に設けて 3 件を先送りした判断は妥当だが、この見出し名は `modules/retro-proposals.md` が走査する `### Improvement Proposals` と一致しないため、そのままでは Issue 起票パイプラインに乗らない。本 verify retrospective で `### Improvement Proposals` へ転記して回収した。

#### design
- retire の実行形態を「`### Retired Post-merge Conditions` 見出しへの退避」にした判断は、`check-ac-checkbox-format.sh` の awk が `^### ` で `in_section` を解除する実挙動に依存して設計されており、実装後も破綻していない。前例のない慣行を導入する際に依存先の実挙動を明記した点が良かった。

#### code
- 先行セッションが GitHub 側編集を完了済みでレジューム状態だった (#1163 / #1164 と同型)。二重適用を避けて検証スクリプトへ置き換えた判断は正しく、実データ突合により 16 再型付け行 + 6 retire 行 + 4 ラベル遷移すべてを確認できている。

#### review
- **誤診断の転記伝播が実害として顕在化した**: Spec が事前に用意した仮説 (「GitHub 検索インデックスの遅延」) を code フェーズが検証せず採用し、report / Code Retrospective / Phase Handoff の 3 箇所へ同一の誤診断を転記した。review フェーズの review-bug エージェント 2 系統が `collect-run-facts.sh` の実行結果と `when=` ゲートのコード読解から真因 (`when=mode:batch` による設計どおりの確定的除外) を特定し、3 箇所すべてを修正した。review が spec/code の見落としを実際に捕捉した好例。

#### merge
- `gh-pr-merge-status.sh` の初回応答が `mergeable=UNKNOWN` (GitHub 側の計算待ち) で、30 秒待機後の自動リトライで `clean` を得た。リトライ機構が想定どおり機能している。

#### verify
- Post-merge AC は `observation event=auto-run` 1 件のみ。本 verify 実行時点では未発火のため SKIPPED。FAIL / UNCERTAIN は 0 件。
- Pre-merge 8 件はすべて `/review` 時点で PASS 済みのため already-checked skip rule により SKIPPED。verify 側で判定が覆る事象はなかった。

### Improvement Proposals

- **`opportunistic-search.sh` / `scan-pending-ac.sh` の母集団が `--state closed` 限定で、OPEN + `phase/verify` の Issue を構造的に取りこぼす** — 本 Issue の対象 #490 / #465 が実例で、両者とも一度も close されたことがない (timeline の `closed` イベント 0 件)。`docs/stats/2026-08-05.md` Section 7 も `phase/verify` 167 件の内訳を CLOSED 165 / OPEN 2 と記録しており、この 2 件はどちらの自動評価経路にも乗らず棚卸しの死角になっている。両スクリプトの母集団を `--state all` へ広げるか、OPEN + `phase/verify` を明示的に含める条件を追加する。区分 A (#1163) は全件 CLOSED だったため露見せず、D3 で初めて顕在化した。
- **`config=` 条件ゲートが boolean 専用で enum キーを表現できない** — `modules/observation-trigger.md` § Condition Check Gate (`config=`) 自身が `config=key:value` 拡張を候補として挙げている。本 Issue では `auto-stop-at` (enum) をゲートに使えなかったことが #783 を再型付けではなく retire に倒す決め手になった。`config=key:value` 形式をサポートすれば、enum 設定キーに依存する observation AC を retire せずに済む。
- **`opportunistic-search.sh` の Issue 本文走査がセクション非依存で、コードフェンス内のサンプル AC を実 AC と誤認する** — `scan-pending-ac.sh` は `### Post-merge` にスコープした awk を使うのに対し、`opportunistic-search.sh` はセクション非依存で `^- \[ \]` を grep する。#491 の `## 提案内容` 節にあるコードフェンス内サンプル行が実例で、AC ではないのに `/audit stats` の Manual Waiting Count に計上される。本 Issue では 2 スペースのインデントで無害化する対症処置を取ったが、走査スコープが 2 系統に分かれていること自体が偽陽性の源であり、`opportunistic-search.sh` 側を `### Post-merge` スコープへ揃えるのが本質的な修正。
