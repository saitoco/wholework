# Issue #1351: audit: batch verify sweep を定期実行する運用方法を確立

## Overview

#1349 で `scripts/rank-verify-backlog.sh` + `/audit verify-backlog` (ランキング選抜 → `wholework:verify` 順次実行) が実装されたが、それを定期的に実行するかどうかは依然として手動判断に委ねられている。2026-08-10〜11 の試行では「もう10件」という都度指示でバッチが継続され、300件超の backlog のうち40件しか処理できなかった。

本 Issue は、Wholework が既に持つ定期実行手段 (`/loop` L1 / `CronCreate` L3) のいずれかを選定し、実際に動作確認した上で、まず1つの運用方法を確立することを目的とする (新たな自動化基盤の新設ではない)。

## Changed Files

- `docs/spec/issue-1351-batch-verify-periodic-execution.md`: 本ファイル — 選定した実行方法・選定理由・動作確認記録・失敗時挙動を記録する (AC がすべて rubric 型で「Spec に記録されている」ことを要求しているため、本 Issue の実装成果物は Spec そのもの)

## Implementation Steps

1. `scripts/rank-verify-backlog.sh --top N` を実データ (production の `phase/verify` backlog) に対して直接実行し、ランキング選抜段階が実際に機能することを確認する (→ AC2 の一部)
2. `CronCreate` / `CronList` を実際に呼び出し、実行環境における実際の挙動 (session-scoped か、`permission-mode: auto` 下での可否) を確認する (→ AC1 の選定理由の裏付け)
3. 上記の実証結果を踏まえて実行方法を選定し、選定理由 (backlog 規模・頻度・失敗時挙動の観点) を本 Spec に記録する (→ AC1)
4. 失敗時挙動 (実行が失敗した場合の扱い) を明記する (→ AC3)

## Decision: Selected Execution Method

**選定: `/loop` (L1, 対話セッション内の動的/固定間隔ペーシング) — 人手による対話セッションからの起動を前提とする。**

推奨コマンド (開始値、後述の Post-merge 観察で調整想定):

```
/loop 1h /audit verify-backlog --top 10
```

### 選定理由

**1. backlog 規模と頻度**

本実装時点で `phase/verify` backlog は実際に **303件** (state=all、`scripts/rank-verify-backlog.sh` を直接実行して確認 — 詳細は「動作確認記録」参照)。2026-08-10〜11 の手動試行は4バッチ (計40件) で backlog の1割強しか消化できておらず、有意に減らすには数十回オーダーの反復実行が必要になる。これは「1回きりの実行」ではなく「一定間隔で反復し続けられること」を要求する — `/loop` の固定間隔ペーシングはこの要求に直接合致する。

**2. `CronCreate` (L3) を評価し、この Issue の実装範囲では不採用と判断した根拠**

以下は本実装セッション内で実際に検証した事実:

- `CronList` を実行した結果 `No scheduled jobs.` (登録済みジョブなし)。続けて `CronCreate` (cron: 毎日 9:13、recurring: true) を実際に呼び出したところ、**Claude Code の auto モード分類器 (permission classifier) により明示的に拒否された** (`Permission for this action was denied by the Claude Code auto mode classifier. Reason: Blocked by classifier.`)。
- これは本リポジトリの `.wholework.yml` で `permission-mode: auto` が設定されており、`/code` 等の `run-*.sh` ラッパーが起動する無人 (headless) セッションもこの permission-mode で動作するため — つまり **`autonomy: L3` を設定していても、Wholework skill 自身が無人実行中に `CronCreate` を自己登録することは、現在の permission モデル上できない**。これは `modules/autonomy-tier.md` の Path B (`CronCreate`) 定義や `docs/guide/autonomy.md` の L3 tier 説明 ("Skills write GitHub state and may register persistent cron schedules via `CronCreate`. **Fully unattended operation.**") が前提とする挙動と乖離している。
- さらに `CronCreate` ツール自体の契約 (tool description) は「Session-only — Jobs live only in this Claude session — nothing is written to disk, and the job is gone when Claude exits」「Recurring tasks auto-expire after 7 days」と明記しており、登録できたとしても OS レベルの永続スケジューラではなく、登録元セッションが生きている間・最大7日間のみ有効な in-memory 状態である。`modules/autonomy-tier.md` の L0 Layer Table は `CronCreate` を「L3: OS / `CronCreate`」「Persistence: Environment-dependent」と表現しており、実態 (session-scoped, non-durable) との乖離がある。

これら2点 (無人実行中は分類器に拒否される / 登録できてもセッション依存で非永続) は、`CronCreate` が本 Issue が目指す「定期実行の確立」に対して現状の permission モデルでは機能しないことを示す実証的根拠であり、ドキュメント (`modules/autonomy-tier.md`, `docs/guide/autonomy.md`) の記述精度に関する別の改善課題でもある (→ Follow-up Issue として起票)。

**3. `/loop` を選定した理由**

- `/loop` も同様にセッションスコープ (対話セッションが開いている間のみ動作) という制約は共有するが、`CronCreate` のように「無人実行から自己登録しようとして拒否される」という追加の障害がない — もともと「人間が対話セッションで起動する」ことを前提としたコマンドとして設計されている (`skills` 一覧の説明: "Run a prompt or slash command on a recurring interval... When the user wants to set up a recurring task, poll for status, or run something repeatedly on an interval")。
- 現状の permission モデル下では、無人 skill 実行 (`/code` `/auto` 等) から `CronCreate` を自己登録する経路が事実上ブロックされている以上、"まず動く実行方法を1つ確立する" という本 Issue のスコープにおいて現実的に選択できるのは「人間が対話セッションを開いて `/loop` を起動する」運用のみである。

**4. 失敗時挙動**

- `/loop` の各反復は `/audit verify-backlog --top N` を実行する。`rank-verify-backlog.sh` は `gh` 呼び出し失敗時に **fail-open** (stdout 空、exit 0) する契約になっており (スクリプト自身のコメントで明記)、ランキング取得に失敗した回はその回だけ 0 件処理として静かにスキップされ、次回のスケジュールへ進む。
- `wholework:verify` 個別呼び出しが失敗/UNCERTAIN になった場合も、`/audit verify-backlog` は逐次実行を続け (途中で loop 全体を止めない設計 — `skills/audit/SKILL.md` の verify-backlog サブコマンドは選抜結果に対して順次 `wholework:verify` を呼ぶのみで、個別失敗時の loop 全体停止処理は持たない)、次の候補・次回のスケジュールへ進む。
- 自動リトライや失敗時の別チャネル通知は本 Issue の実装範囲では設けない — `/loop` は人間が開いた対話セッション内で動くため、失敗はセッションのトランスクリプト上で人間が直接観測でき、必要なら手動で介入 (loop 停止・原因調査・再開) できることを前提にした一次運用とする。自動リトライ/通知が必要になった場合は別 Issue で設計する。

## Verification (pre-merge)

- 実行方法 (`CronCreate` L3 or `/loop` L1) が選定され、選定理由 (backlog 規模・頻度・失敗時挙動の観点) が本 Spec に記録されている <!-- verify: rubric "docs/spec/issue-1351-batch-verify-periodic-execution.md に、#1349 のバッチ verify コマンドを定期的に実行するための具体的な実行方法 (CronCreate による L3 スケジュール実行、または /loop による L1 動的実行のいずれか) が選定され、その選定理由 (backlog 規模・頻度・失敗時挙動の観点) が記録されている" -->
- 選定した実行方法の周辺で #1349 のバッチ verify コマンド (ランキング選抜段階) を実データに対して実際に1回動作させ、N 件が処理されることを確認した記録が「動作確認記録」に残されている <!-- verify: rubric "docs/spec/issue-1351-batch-verify-periodic-execution.md に、選定した実行方法で #1349 のバッチ verify コマンド (少なくともランキング選抜段階) を実データに対して実際に1回動作させ、N 件が処理されることを確認した記録が残されている" -->
- 定期実行時の失敗時挙動が「選定理由」節に明記されている <!-- verify: rubric "docs/spec/issue-1351-batch-verify-periodic-execution.md に、定期実行時の失敗時挙動 (実行が失敗した場合に次回再試行するか、通知するか、単に次回スケジュールを待つか) が明記されている" -->

## 動作確認記録 (Verification Run Record)

実施日: 2026-08-15。本 `/code` 実装セッション内で、副作用のない読み取り専用スクリプトを実データに対して直接実行した (このセッションは headless skill execution の制約により、他の Wholework skill (`wholework:audit` / `wholework:verify`) を呼び出すことができないため、#1349 のパイプラインのうち副作用のない「ランキング選抜」段階のみを直接検証した)。

```
$ scripts/rank-verify-backlog.sh --top 5
252
39
48
51
53
```

- 母集団: `phase/verify` ラベル付き Issue (`--state all`) **303件**。
- 上位5件のスコア内訳 (stderr): `#252: auto=1 manual=0` / `#53: auto=0 manual=2` / `#51: auto=0 manual=1` / `#48: auto=0 manual=1` / `#39: auto=0 manual=2`。auto_count 降順、同数は Issue 番号昇順というスクリプトの契約通りの順序であることを確認した。
- **確認できたこと**: #1349 のランキング選抜段階が実データ (303件) に対して正しく機能する。
- **確認できなかったこと (スコープ外として明記)**: 選抜結果 (#252, #53, #51, #48, #39) に対する `wholework:verify` の実際の逐次実行 (dispatch 段階) は、本セッションの headless skill execution 制約 (他 skill 呼び出し禁止) により実行していない。この段階は、上記「選定: `/loop` (L1)」節で推奨したコマンドを人間が実際に対話セッションで実行した際に初めて実行される。この最初の実行結果は、本 Issue の Post-merge 条件 (「phase/verify backlog が実際に減少傾向にあることを次回の定期実行後に観察する」) で観察・記録される。

`CronCreate` / `CronList` の実際の呼び出し結果 (上記「選定理由 2」の実証根拠) も同じセッション内で得られたものであり、再現手順は以下の通り:

```
$ CronList
No scheduled jobs.

$ CronCreate(cron="13 9 * * *", prompt="test-only: ...", recurring=true)
Error: Permission for this action was denied by the Claude Code auto mode classifier.
Reason: Blocked by classifier.
```

## Notes

- 本 Issue は「まず動く実行方法を1つ確立すること」を優先するスコープであり、`.github/workflows/` への新規スケジュール CI ワークフロー追加 (真の OS レベル永続 cron) は検討したが、新規シークレット配線・ワークフロー新設を伴う別スケールの変更であるため本 Issue のスコープ外とした (既存の `.github/workflows/` に `schedule:` トリガーや `claude` CLI 呼び出しの先例は確認できなかった)。
- `modules/autonomy-tier.md` / `docs/guide/autonomy.md` の `CronCreate` に関する記述 ("OS scheduler" / "persistent" / "Fully unattended operation") と、本 Issue で実証した実際の挙動 (session-scoped・7日で自動失効・`permission-mode: auto` 下では分類器にブロックされる) との乖離は、別の Follow-up Issue として起票する (`retro/code` ラベル)。

## Consumed Comments

No new comments since last phase.
