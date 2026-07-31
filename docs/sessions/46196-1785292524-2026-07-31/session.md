# L3 Session Retrospective: 46196-1785292524

## Metrics

> Known structural gaps in this section (see Issue #875 Out of Scope):
> - Manually-performed silent no-op recoveries do not go through Tier 1/2/3 machinery, so they are not reflected in Recovery Events.
> - The Phase breakdown order below follows event occurrence order, not a fixed pipeline order.

**Session start**: 2026-07-29T02:35:58Z
**Session end**: 2026-07-31T13:57:20Z
**Wall-clock**: 59:21:22
**Route mix**: patch: 3, pr: 2, xl: 0

### Summary

| Metric | Value |
|---|---|
| Issues processed | 31 |
| Throughput | 0.5 issues/hr |
| Tier 1/2/3 recoveries | 0 / 0 / 0 |
| Watchdog kills | 0 |
| Max silent window (any phase) | 2690s |
| Phase silent windows > threshold | 1 (spec:1) |
| Total token usage | input 416 / output 63892 |
| Concurrent commits detected | 13 |
| Parent session manual interventions | 11 |
| verify FAIL → reopen fix cycles | 0 |
| Merge conflicts | 0 |

**注**: Metrics の Route mix / Issues processed は `run-auto-sub.sh` 経由の実行のみを計上するため、本セッションで主に用いたフェーズ分割実行 (`run-issue.sh` / `run-spec.sh` / `run-code.sh` / `run-review.sh` / `run-merge.sh` の個別起動) は反映されていない。実際の完走は 9 件。Tier 1/2/3 recoveries が 0 なのも同様で、実際には外部 kill 4 回からの手動復旧を行っている (`manual_intervention` 11 件が実態に近い)。

## 完走した Issue (9 件)

| Issue | Size | route | 内容 |
|---|---|---|---|
| #1051 | S | patch | lighthouse-adapter に Basic Auth ヘッダ注入 |
| #1066 | L | pr | `/code` が preview ビルド成功を確認してから完了 |
| #1054 | XS | patch | 不在検証 AC に参照点を求めるガイドライン |
| #1052 | XS | patch | 大量アセット時の content filtering 回避ガイドライン |
| #1053 | M | pr | `/verify` の preview tier AC fail-open を封じる |
| #1050 | M | pr | `/review` が preview/CI 未確定なら PENDING で停止 |
| #1115 | M | pr | orchestrator が PENDING (exit 2) を失敗と区別 |
| #1097 | S | patch | headless でのテスト前景実行を規約化 |
| #1106 | S | patch | merge precondition に review-summary marker fallback |

#1056 は code→review→merge まで完了し、verify はユーザー判断で保留 (下流での実機確認方針)。

### preview/CI 待機の 4 層防御が完成

| 層 | Issue | 役割 |
|----|-------|------|
| 上流 | #1066 | `/code` が preview ビルドの成功を確認してから完了する |
| 中間 | #1050 | `/review` が preview/CI 未確定なら PENDING で停止する |
| 接続 | #1115 | orchestrator が PENDING を失敗と区別し待機後の再実行に導く |
| 下流 | #1053 | `/verify` が preview tier AC を fail-open しない |

## What worked

- **フェーズ分割実行**: `run-*.sh` を個別のバックグラウンド呼び出しとして起動する方式で 9/9 完走 (kill ゼロ)。連結実行 (`run-auto-sub.sh`) を用いた #1066 のみ外部 kill 3 回。ただし #1066 は唯一の Size L でもあり、実行方式の効果と規模の効果は本データでは分離できていない。
- **`code_phase_milestone` の resume 機構**: #1066 の 2 回目の kill 時、`pre-commit` を正しく検出して実装コミットまで進めた。破棄されるはずだった未コミット変更が保全された。
- **review の実効性**: #1066 の `--full` review が MUST 級の実バグ (`wait-ci-checks.sh` の zero-checks 分岐が実機 `gh` では到達不能) を検出。実機 gh 2.96.0 の挙動を確認したうえでの指摘で、根拠も再現手順も具体的だった。
- **completion check による silent no-op 検知**: `reconcile-phase-state.sh` が review / code フェーズの未完了を複数回正しく検出し、fail-open を防いだ。
- **ドキュメント注記による行動変容の実証**: #1097 (headless 前景実行の規約化) merge の前後で、同一 Issue (#1106)・同一 route・テスト実行を伴う実装を再実行し、silent no-op が 1 件 → 0 件になった。

## 修正した実バグ (2 件)

- **`wait-ci-checks.sh` の zero-checks 分岐が実機 `gh` では到達不能** — 実機の `gh` は check 0 件の PR に対し stdout 空 + exit 1 + stderr メッセージを返す (`[]` ではない)。`2>/dev/null` で stderr を捨てていたため `_poll_result` が空のままとなり、grace period / 警告 / `zero_checks=true` のロジック (#1066 の AC4 実装対象) が一度も発火しなかった。bats のモックが `echo '[]'` だったためテストは通るのに本番では動かない状態だった。
- **EXIT trap の `rm` が終了コードを 127 に上書き** — `set -e` 下で PATH 制限テストから `rm` が解決できず、trap の失敗がスクリプトの終了コードを上書きしていた。review の修正案には含まれておらず、引き継ぎ時に追加発見した。

## Findings

- **`run-review.sh` の PENDING (exit 2) を呼び出し側が失敗と区別していない** — 意図どおりの動作が 3-Tier recovery を誤起動する逆転が起きうる。 [Filed: #1115]
- **in-session `/verify` の event が並行 `/auto` セッションの `session_id` に誤帰属する** — `.tmp/auto-session-current` が単一グローバルポインタで、後発セッションが上書きする。`.tmp/auto-events.jsonl` で実測確認。本セッション中に 2 回再現した。 [Filed: #1075]
- **`worktree-merge-push.sh` の "base が current branch" 経路に rebase fallback が欠落** — `/verify` は Step 2 で main を checkout するため必ずこの経路を通り、並行セッションが base を進めると確定的に失敗する。 [Filed: #1076]
- **`detect-external-kill.sh` が連結ログで false negative を返す** — `run-auto-sub.sh` は全フェーズを 1 ログに連結するため、先行フェーズの `Exit code: 0` トレーラが後続フェーズの kill 判定を構造的に打ち消す。 [Filed: #1093]
- **`--write-manual-recovery` が規定の 3 箇所のうち Spec の `## Auto Retrospective` に書いていない** — `/verify` Step 12 の機械的 skip 判定がこの前提に依存している。 [Filed: #1094]
- **`run-auto-sub.sh` の spec dispatch が Size を見ておらず `/auto` Step 3 の「XS は spec 不要」規定と食い違う** — 加えて `/issue` の XS 時ラベル付与が非決定的 (#1054 は `phase/issue`、#1052 は `phase/ready`) で、どちらを直しても片方に不整合が残る。 [Filed: #1108]
- **`skills/code/SKILL.md` Step 3 が precondition の `matches_expected: false` を「Spec missing」と誤って説明** — 実際の判定軸は `phase/ready` ラベル。誤説明が誤った原因推定を誘導し、#1053 の Auto-Resolve Log にラベル timeline と矛盾する記述を残した。 [Filed: #1112]
- **issue / spec フェーズに completion check が存在せず、ラベル未遷移の silent no-op を機械検出できない** — #1115 の `/issue` が実作業完了・exit 0 のまま `phase/*` を付与せず終了した。pr route の Step 4 が Observe → Diagnose → Act を回しているのに対し Step 3 は非対称。 [Filed: #1117]
- **`/code` Step 8 の粒度別コミットと Step 11 の closes-commit 要件が衝突** — #1106 で `git commit --amend` による回避が必要になった。`closes #N` は完了判定の一級シグナルであり、付与失敗は silent no-op 誤判定に直結する。回避手段が非決定的で、push 後の `--amend` は履歴書き換えになる。 [Filed: #1134]
- **並行セッションが worktree を使わず parent main を直接編集し、`run-code.sh` の dirty ガードが 3 件をブロック** — #1113 の作業中に発生。`check-verify-dirty` の exit 1 (非 spec ファイル) / exit 2 (無関係な spec のみ) の区別自体は設計として妥当で、ブロックは正しい動作だった。約 5 時間後に解消。 [No action: ガードは意図どおり機能しており、原因は並行セッション側の worktree 未使用。#1078 (Consumed Comments が worktree fresh 作成時に失われうる) が隣接領域を扱っている]
- **待機ウォッチャー (plain bash の sleep ループ) が約 5 分で外部 kill された** — `claude -p` ではないプロセスも kill されうるというデータ点。ただしハーネス側の判断で停止された可能性もあり、1 例では因果を主張できない。 [No action: 単独では母数不足。既存の外部 kill 調査 (#1093 / 通算 25 件超) にデータ点として供する位置づけ]
- **triage の一括適用ループが zsh の単語分割仕様により完全な no-op になった** — 未クォート変数を `set -- $row` で分割する bash 前提のコードが zsh では動かず、成功表示だけが出た。適用状態を確認して気づき、`IFS=':' read -r` 方式で全件やり直した。 [Resolved directly: 全 29 件を再適用し verify-after-write で確認済み]

## Auto Retrospective

### Improvement Proposals

- **`run-review.sh` の PENDING (exit 2) を呼び出し側が失敗と区別していない**
- **in-session `/verify` の event が並行 `/auto` セッションの `session_id` に誤帰属する**
- **`worktree-merge-push.sh` の "base が current branch" 経路に rebase fallback が欠落**
- **`detect-external-kill.sh` が連結ログで false negative を返す**
- **`--write-manual-recovery` が規定の 3 箇所のうち Spec の `## Auto Retrospective` に書いていない**
- **`run-auto-sub.sh` の spec dispatch が Size を見ておらず `/auto` Step 3 の「XS は spec 不要」規定と食い違う**
- **`skills/code/SKILL.md` Step 3 が precondition の `matches_expected: false` を「Spec missing」と誤って説明**
- **issue / spec フェーズに completion check が存在せず、ラベル未遷移の silent no-op を機械検出できない**
- **`/code` Step 8 の粒度別コミットと Step 11 の closes-commit 要件が衝突**

## Filed Issues

- #1075
- #1076
- #1093
- #1094
- #1108
- #1112
- #1115
- #1117
- #1134

## その他の作業

- **triage 36 件** — 自セッション起票 7 件 + 並行セッション起票 29 件。untriaged を 0 件にした。Type / Size / Value / `triaged` を全件適用し verify-after-write で確認。Type 内訳は Bug 中心で、Value 4 が 5 件 (#1103 / #1097 / #1101 / #1096 / #1081)。
- **未着手の残 batch** — `1096 1081 1112 1093 1094 1076 1108 1075`。checkpoint (`BATCH_ID=56885-1785292524`) に保全済みで `/auto --batch --resume` で再開可能。

## 次セッションへの申し送り

- **#1096 が次の着手候補** (S/patch, Value 4)。#1066 の review が検出した「bats モックが実機と乖離しテストは通るが本番未到達」と同一の欠陥クラスを扱う。本セッションで実際に踏んだ問題であり、直す価値が実証されている。
- **#1056 の verify が保留中** — 下流プロジェクトで `pup` 未インストール環境の実機確認を行う方針。
- **Metrics の計上範囲** — 本セッションのようにフェーズ分割で実行すると `run-auto-sub.sh` を経由しないため Route mix / recoveries が実態を反映しない。#1098 (Tier 2/3 recovery の event 記録) と隣接する計装の課題。

## Skill Self-Update Propagation Note

Session 中に以下の skill が更新されました (本 session には未適用、次 session から反映):

- skills/auto/SKILL.md: eb8bda5b → 9abd852c
- skills/code/SKILL.md: b4769535 → 7d5a855d
- skills/spec/SKILL.md: 81836955 → 7d5a855d
- skills/verify/SKILL.md: b64648a3 → fce8cdfd
- skills/review/SKILL.md: 420c5f78 → 226c2839
- skills/merge/SKILL.md: f760c77d → 0af6361a
- skills/issue/SKILL.md: 0e932af9 → 7d5a855d
- skills/audit/SKILL.md: (no change)

8 skill 中 7 つが更新された。本セッション自身が merge した #1097 (`skills/review/SKILL.md` を含む `226c2839`) のように、セッション中に自分が変更した skill を同一セッションでは使えないという self-hosting 特有の遅延がある。#1097 の効果を #1106 の再実行で確認できたのは、`modules/test-runner.md` が SKILL.md ではなく実行時に Read されるモジュールだったため。SKILL.md 側の変更 (`skills/review/SKILL.md` の Non-Interactive Mode Behavior 注記) は次セッションから効く。
