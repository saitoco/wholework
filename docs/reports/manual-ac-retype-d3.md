# manual AC 区分 D3: observation 再型付け/retire マッピング (#1165)

親 Issue #1158 の分割対応。`phase/verify` に滞留する `verify-type: manual` の post-merge AC のうち、区分 D3 (キーワード機械分類で A / B / C / D1 / D2 のいずれにも当てはまらなかった残余) の 19 Issue を対象に、1 件ずつ条件文を読んで **observation への再型付け / retire / manual 維持** のいずれかへ振り分けた記録。

## 対象・件数内訳

- 対象 Issue: 19 件 (#1135 #1056 #961 #783 #710 #706 #591 #587 #575 #563 #535 #513 #512 #491 #490 #484 #478 #477 #465)
- 対象 AC 行: 22 行 (#710 / #484 / #478 が各 2 行を持つため、Issue 単位の 19 件と AC 行単位の 22 行にずれがある。#1163 (区分 A) と同じ単位ずれが再現)
- 再型付け: **16 行** (`event=auto-run` 14 行 / `event=watchdog-kill` 1 行 / `event=pr-review-full` 1 行)
- retire: **6 行**
- `manual` 維持: **0 行**
- 対象外 (編集しない / 別扱い): **2 行** (#591 の `- [x]` 済み行、#491 のコードフェンス内サンプル行)

## `event=` 有効値の制約

`event=` に使用できるのは `modules/verify-classifier.md` § observation Type が定める 5 つの有効値のみ: `pr-review-full` / `pr-review-light` / `auto-run` / `watchdog-kill` / `fix-cycle`。未知の event 名を持つ AC 行は 5 種のどの dispatch にもマッチせず、自動評価パイプラインに乗らない。条件文が待つ将来イベントがこの 5 値のいずれにも一致しない場合は `manual` のまま維持するのが原則だが、本 Issue では前提が原理的に成立しない条件をすべて retire に倒した (#1163 からの意図的な方針変更。理由は Spec `docs/spec/issue-1165-manual-ac-retype-d3.md` § Notes 「`manual` 維持がゼロである理由」を参照)。

## OPEN 2 件 (#490 / #465) は dispatch 母集団に入らない

`scripts/opportunistic-search.sh` は `gh issue list --label phase/verify --state closed --search "verify-type: observation in:body"` (line 202)、`scripts/scan-pending-ac.sh` は `--search` フィルタなしの `gh issue list --label phase/verify --state closed` (line 106) で母集団を取る。`--search` の有無は異なるが、いずれも `--state closed` 固定である点は共通。#490 / #465 は一度も close されたことがない OPEN Issue のため、`observation` へ再型付けしても現時点では dispatch されない。両者とも Pre-merge AC は全件チェック済みで実装は着地しており、close されれば自然に母集団へ入る。close 判断は各 Issue 自身の post-merge 充足に依存するため本 Issue のスコープ外とし、事実としてここに明記する。

## 再型付けマッピング (16 AC 行 / 14 Issue)

### `event=auto-run` (14 AC 行)

| Issue | 条件文の要約 | 付与するタグ | 選定根拠 |
|---|---|---|---|
| #1135 | 回避策適用状態の `/auto --batch` で `manual-recovery-respawn` 新規エントリ発生率を適用前と比較・記録 | `event=auto-run when=mode:batch` | 観測窓は `/auto --batch` 完了時。`mode` は `when=` の宣言可能軸にあり事前排除できる |
| #1056 | `pup` 未インストール環境で `html_check` が UNCERTAIN でなく PASS/FAIL を返す | `event=auto-run` | 前提 (pup 不在) は 2026-08-07 に `command -v pup` で不在を実測済み。発火契機が無いことだけが滞留原因なので `auto-run` で `/verify` を dispatch すれば実際に判定できる |
| #961 | 並列セッション環境で merge-to-main が他セッションのブランチに影響しない | `event=auto-run` | 「並列セッション環境」は `when=` の宣言可能 3 軸に存在せず事前排除できない |
| #710 条件1 | `Blocked by #N` 付き試験 Issue を `/issue` で起票し `blockedByIssues` に relationship が設定される | `event=auto-run` | `/issue` phase は `/auto` の内側 |
| #710 条件2 | body-only `Blocked by #N` の既存 Issue に `/triage N` で relationship が backfill される | `event=auto-run` | `/triage` phase は `/auto` の内側。本リポジトリは `autonomy: L3` のため `/triage` が advisory ではなく `set-blocked-by.sh` を実行する |
| #513 | 次の同種 Issue で間接反映 AC が post-merge manual または command 型に正しく分類される | `event=auto-run` | `/issue` phase の内側 |
| #512 | `/spec` フェーズで距離ルールに「A 以上かつ B 以下」表記が使われる | `event=auto-run` | `/spec` phase の内側 |
| #491 | `/verify` 実行前に `workflow_dispatch` を促す運用が実際のワークフローで機能する | `event=auto-run` | `/verify` phase は `/auto` の内側 |
| #490 | 実際の Issue AC で cron 依存条件に注記が付くことを 1 件以上のサンプルで確認 | `event=auto-run` | `/issue` phase の内側。**ただし #490 は OPEN のため dispatch 母集団外** |
| #484 条件1 | 代表的な `/verify` 実行で Improvement Proposals が 3 層に分類され Tier 1 のみ Issue 化される | `event=auto-run` | `/verify` phase の内側 |
| #478 条件1 | `/auto --batch` 実行中に blocked Issue がスキップされ適切な警告メッセージが出力される | `event=auto-run when=mode:batch` | batch 実行が観測窓。`mode` 軸で事前排除できる |
| #478 条件2 | スキップされた Issue が checkpoint の `remaining` に保持され `--batch --resume` で再処理できる | `event=auto-run when=mode:batch` | 同上 |
| #477 | 次の外部 API 統合 Spec で本規約が適用されている | `event=auto-run` | `/spec` phase の内側。「外部 API 統合 Spec」の出現有無は `when=` 3 軸で表現できず事前排除不能 |
| #465 | `/auto` 実行で silent no-op が自動検出され 3-tier recovery へ流れる | `event=auto-run` | 条件文が `/auto` 実行を明示。**ただし #465 は OPEN のため dispatch 母集団外** |

**ゲートの内訳**: 上表 14 行のうち、`when=mode:batch` ゲート付きが 3 行 (#1135 / #478 条件1 / #478 条件2)、ゲートなしが 11 行。

### `event=watchdog-kill` (1 AC 行)

| Issue | 条件文の要約 | 付与するタグ | 選定根拠 |
|---|---|---|---|
| #535 | watchdog-kill-before-PR を再現し Tier 3 が `unsupported op` なく commit→push→PR create で自動復旧する | `event=watchdog-kill` | watchdog kill の発火そのものが観測窓。`scripts/claude-watchdog.sh:138-140` の kill handler が `observation-trigger.sh --event watchdog-kill` を呼ぶ実装済み経路 |

### `event=pr-review-full` (1 AC 行)

| Issue | 条件文の要約 | 付与するタグ | 選定根拠 |
|---|---|---|---|
| #575 | `capabilities.workflow: true` のプロジェクトで `/review --full` が Workflow 経路で完走し概算トークン使用量が出力される | `event=pr-review-full config=capabilities.workflow` | 条件文が `--full` review を明示しており `pr-review-full` が正確な観測窓。`capabilities.workflow` は block 形式 1 階層ネストキーで `get-config-value.sh capabilities.workflow false` が `true` を返すことを実測済み |

## retire マッピング (6 AC 行 / 6 Issue)

| Issue | 条件文の要約 | retire 理由 | retire 後の phase |
|---|---|---|---|
| #783 | 停止後 `/merge N` で手動 merge できることを確認 | `auto-stop-at` は本リポジトリ未設定 (既定 `verify` = フルパイプライン) で停止自体が起きない。`config=` ゲートは boolean 専用のため enum キー `auto-stop-at` を表現できず、観測窓が原理的に開かない。実装の正しさは Pre-merge AC 10 件 (全チェック済) が担保 | `phase/verify` 維持 (他に未チェックの `opportunistic` AC 2 件が残る) |
| #706 | `/audit drift` の "label namespace 整合性" チェック (将来拡張) がエラーを出さない | 条件文自身が「(将来拡張)」と明記するとおり当該チェックは未実装 (`skills/audit/SKILL.md` に該当なし)。実装されるまで発火契機が存在しない | `phase/done` へ遷移 (Pre-merge 6 件全チェック済 / 他の post-merge 条件なし) |
| #591 | 実 XL Issue (Nuxt → Next 移行) の decomposition YAML で 50+ sub-issue を一括起票 | downstream プロジェクト固有の XL Issue が前提で、upstream に該当 Issue が存在しない。区分 B 相当で upstream から観測不能 | `phase/done` へ遷移 (Pre-merge 11 件全チェック済 / 残る post-merge 1 件は既に `- [x]`) |
| #587 | Fable 5 復帰後にレポート結論が再評価され必要なら follow-up spike が起票されている | Fable 5 は 2026-07-01 に再デプロイ済 (`docs/tech.md` § Watchdog timeout calibration の #939 注記) で前提条件は既に発生済み。しかし比較基準だった「Opus 4.8 親セッション」構成は Sonnet 5 (2026-06-30) / Opus 5 (2026-07-24) のリリースで陳腐化しており、再評価に残存価値がない | `phase/done` へ遷移 (Pre-merge 5 件全チェック済 / 他の post-merge 条件なし) |
| #563 | (該当時) Fable 5 採用後に security 観点の Opus 4.8 fallback が運用上問題ないこと | `docs/tech.md` line 115 が Fable 5 を opt-in only (never a default model swap) と明記しており「採用後」という前提が成立しない。条件文自身も「(該当時)」と条件付き | `phase/done` へ遷移 (Pre-merge 6 件全チェック済 / 残る post-merge 1 件は既に `- [x]`) |
| #484 条件2 | downstream プロジェクトで retro/verify Issue の発生量がノイズ削減方向に変化することを観察 | 別リポジトリでの主観評価であり upstream から観測不能。#1163 が #501 / #500 / #479 に適用した downstream 依存の判断と同型 | `phase/verify` 維持 (同 Issue の条件1 が再型付けされ未チェックで残る) |

## 対象外 (編集しない / 別扱い, 2 行)

| Issue | 行の性質 | 扱い |
|---|---|---|
| #591 | `- [x]` (チェック済み) の manual AC 「フル auto-decomposition の follow-up Issue が起票されている」 | **編集しない**。既にチェック済みのため Manual Waiting Count にも `opportunistic-search.sh` にもマッチしない |
| #491 | `## 提案内容` 節のコードフェンス内サンプル行 `- [ ] Trigger workflow once via ... <!-- verify-type: manual -->` | **AC ではないため再型付けも retire もしない**。ただし `- [ ]` + `verify-type: manual` に機械マッチし `/audit stats` の Manual Waiting Count に計上されるため、2 スペースのインデントを付けて `scripts/opportunistic-search.sh` / `scripts/scan-pending-ac.sh` の `^- \[ \]` アンカーから外す。`skills/audit/SKILL.md` の Manual Waiting Count はアンカーなしの LLM プロース走査のため、この対処が同カウントから確実に除外することを保証するものではないが、実運用上は一致して振る舞う想定。テキスト本文と `verify-type` は変更しない |

## 検証

`scripts/opportunistic-search.sh --event auto-run` / `--event watchdog-kill` / `--event pr-review-full` を実行し、再型付けした Issue が個別に含まれることを確認した (件数差分ではなく個別含有で判定 — #1163 の Code Retrospective で母集団が他要因でも変動することが確認されているため)。

### `--event auto-run`

- 実行結果: マッチ 82 AC 行
- 再型付け対象 12 Issue (#1135 #1056 #961 #710 #513 #512 #491 #490 #484 #478 #477 #465) のうち、`opportunistic-search.sh` のマッチ集合に含まれたのは 8 件 (#1056 #961 #710 #513 #512 #491 #484 #477)
- **#1135 / #490 / #478 / #465 の 4 件はマッチ集合に含まれなかった**。理由を切り分けて確認:
  - #490 / #465 は OPEN Issue のため、`opportunistic-search.sh` の母集団取得 (`gh issue list --label phase/verify --state closed`) が `--state closed` 固定である以上、原理的にマッチしない。Spec Notes 「OPEN 2 件は dispatch 母集団に入らない」のとおりの想定内挙動
  - #1135 / #478 は CLOSED かつ `phase/verify` ラベルを保持しているにもかかわらずマッチしなかった。`gh issue view N --json body` で本文を直接確認したところ、両者とも `<!-- verify-type: observation event=auto-run when=mode:batch -->` へ正しく置換済みであることをリテラル一致で確認した (`.tmp/verify-retype.py` 実行結果: 12 Issue 全件で `auto-run` タグの存在を確認)。マッチしなかった原因は検索インデックスの遅延ではなく、`scripts/opportunistic-search.sh` の `when=` 条件ゲート (mode 軸) が `mode=single` のセッションで `when=mode:batch` 付き AC 行を設計どおり除外したこと。マッチしなかった 3 AC 行 (#1135 / #478 条件1 / #478 条件2) はレポート冒頭で `when=mode:batch` ゲート付きと記録した 3 行と完全一致しており、`scripts/collect-run-facts.sh` がこのセッションで `mode: single` を返すことも実測確認した。`mode=batch` の run facts を与えない限り常に除外されるため、`gh issue view` によるリテラル一致確認を一次情報として正とする

### `--event watchdog-kill`

- 実行結果: マッチ 3 AC 行 (#802 #535 #585)
- 再型付けした #535 は **マッチ集合に含まれることを確認済み**

### `--event pr-review-full`

- 実行結果: マッチ 1 AC 行 (#575)
- 再型付けした #575 は **マッチ集合に含まれることを確認済み**

### GitHub 上の実状態 (Pre-merge AC4〜AC8 相当)

- `gh issue view 961 --json body`: `verify-type: observation event=auto-run` へ再型付け済みを確認
- `gh issue view 535 --json body`: `verify-type: observation event=watchdog-kill` へ再型付け済みを確認
- `gh issue view 575 --json body`: `config=capabilities.workflow` ゲート付与を確認
- `gh issue view 706 --json body`: `### Retired Post-merge Conditions` 節への退避を確認
- `gh issue view 706 --json labels`: `phase/done` への遷移を確認 (#587 / #563 / #591 も同様に `phase/done` を確認済み)
