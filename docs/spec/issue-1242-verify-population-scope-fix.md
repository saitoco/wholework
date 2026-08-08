# Issue #1242: opportunistic-search/scan-pending-ac: 母集団の closed 限定と走査スコープの不一致を解消

## Overview

`phase/verify` 滞留 AC を自動評価する 2 つの走査スクリプト (`scripts/opportunistic-search.sh` / `scripts/scan-pending-ac.sh`) が、母集団取得 (`--state closed` 固定) と本文走査スコープ (Post-merge セクション境界の有無) の 2 軸で挙動が食い違っている。これにより (1) OPEN のまま `phase/verify` に留まる Issue が自動評価パイプラインから構造的に除外され、(2) `opportunistic-search.sh` がコードフェンス内のサンプル `- [ ]` 行を実 AC と誤認する、という 2 つの実害が生じている。両スクリプトの母集団取得を `--state all` に揃え、`opportunistic-search.sh` の本文走査を `scan-pending-ac.sh` 既存の Post-merge セクションスコープ awk ロジックに合わせて修正する。

## Reproduction Steps

1. `phase/verify` ラベルを持つ Issue が OPEN のまま残るケースを作る (実例: #490 / #465 — 2026-08-08 時点で `gh issue list --label phase/verify --state open --limit 500` で 2 件確認, 全 `phase/verify` 325 件中)。
2. `scripts/opportunistic-search.sh --event auto-run` または `scripts/scan-pending-ac.sh` を実行する。両スクリプトとも `gh issue list --label "phase/verify" --state closed ...` を呼んでいるため、上記の OPEN Issue は母集団に一切含まれない。
3. 別のケースとして、CLOSED + `phase/verify` の Issue 本文の `### Post-merge` セクション外 (例: `## 提案内容` 節のコードフェンス内) に説明用サンプルの `- [ ] ... <!-- verify-type: manual -->` 行を書く (実例: #491)。`scripts/opportunistic-search.sh <skill-name>` を実行すると、本文走査がセクション非依存の `grep -E '^- \[ \]'` (`:311`, `:314`) であるため、このサンプル行が実 AC として誤ってマッチする。`scripts/scan-pending-ac.sh` は既に `### Post-merge` / `## Post-merge` にスコープした awk (`:127`) を持っているため、この誤マッチは起きない。

## Root Cause

同じ「未チェックの post-merge AC を探す」目的を持つ 2 つのスクリプトが、独立に実装されたため以下の 2 軸で挙動が乖離した:

1. **母集団軸**: `opportunistic-search.sh` (`:291`) と `scan-pending-ac.sh` (`:106`) の双方が `gh issue list --label "phase/verify" --state closed` を固定でハードコードしている。`gh issue list --state` は `open`/`closed`/`all` のみを受け付ける (2026-08-08 時点で `gh issue list --state open|closed|all` を直接実行し実測で確認済み)。`--label phase/verify` によるラベル絞り込みが既に母集団を適切な範囲に限定しているため、`--state closed` → `--state all` が最小差分の修正となる。
2. **走査スコープ軸**: `scan-pending-ac.sh` (`:125-153`) は `^### Post-merge` / `^## Post-merge` から次の `^## `/`^### ` までを抽出する awk 境界ロジックを既に持つが、`opportunistic-search.sh` (`:309-315`) は本文全体に対してセクション非依存で `grep -E '^- \[ \]'` を実行しており、Post-merge セクション外の `- [ ]` 行 (コードフェンス内のサンプル行等) も候補に含めてしまう。

両スクリプトとも `gh issue list` の呼び出し箇所は 1 か所のみ (grep で確認済み) であり、修正は各スクリプト内の局所的なロジック変更で完結する。

## Changed Files

- `scripts/opportunistic-search.sh`: `gh issue list` の `--state closed` (現 `:291`) を `--state all` に変更; Post-merge セクション境界抽出 (awk, `scan-pending-ac.sh:125-153` の境界ロジックを踏襲) を追加し、event モード (現 `:311`) と opportunistic モード (現 `:314`) の両方の grep パイプラインの入力をセクションスコープ済み本文に差し替える — bash 3.2+ 互換 (awk ベース、bash 4 限定構文なし)
- `scripts/scan-pending-ac.sh`: `gh issue list` の `--state closed` (現 `:106`) を `--state all` に変更 — bash 3.2+ 互換
- `docs/structure.md`: `:210` の `scan-pending-ac.sh` 説明文から陳腐化する "closed" 限定の記述を削除 (Steering Docs sync candidate — 母集団拡大後は closed 限定ではなくなるため)
- `docs/ja/structure.md`: `:202` の同記述を日本語ミラーとして同様に修正 (`docs/translation-workflow.md` の sync 対象)
- `tests/opportunistic-search.bats`: (a) 既存の `MOCK_ISSUE_BODY_*` フィクスチャ全件 (40 件) に `## Post-merge` 見出しを前置する — Post-merge スコープ化後も既存テストが有効であり続けるための機械的必須変更 (詳細は Implementation Steps 4 の Notes 参照); (b) 新規テスト: `gh issue list` が `--state all` で呼ばれること (`--state closed` ではないこと) の検証、および `## Post-merge` 外のサンプル `- [ ]` 行が候補から除外されることの検証
- `tests/scan-pending-ac.bats` (新規ファイル): `scan-pending-ac.sh` 用の新規 bats スイート。`gh issue list --label phase/verify --json number,body` が `--state all` で呼ばれることを検証する最小スイート (Post-merge スコープや `--facts`/`--max-candidates` の既存挙動は `tests/run-fact-matching.bats` で既にカバー済みのため重複させない)

## Implementation Steps

1. `scripts/opportunistic-search.sh`: `gh issue list` 呼び出しの `--state closed` を `--state all` に変更する (→ 受入条件 1)
2. `scripts/scan-pending-ac.sh`: `gh issue list` 呼び出しの `--state closed` を `--state all` に変更する; あわせて `docs/structure.md:210` と `docs/ja/structure.md:202` の `scan-pending-ac.sh` 説明文から "closed" 限定の記述を削除する (Steering Docs sync) (→ 受入条件 2)
3. `scripts/opportunistic-search.sh`: `scan-pending-ac.sh:125-153` の awk 境界ロジック (`^### Post-merge` / `^## Post-merge` で開始、次の `^## ` / `^### ` で終了) を踏襲した Post-merge セクション抽出処理を追加する。抽出したスコープ済み本文を、event モード (現 `:311`) と opportunistic モード (現 `:314`) の両方の grep パイプラインの入力として使う (元の生 `BODY` ではなく) (after 1) (→ 受入条件 3, 4)
4. `tests/opportunistic-search.bats`: 既存の `MOCK_ISSUE_BODY_*` フィクスチャ全件 (40 件、`[]` を期待する「除外」系テストのフィクスチャも含む — 除外系フィクスチャを見出しなしのまま放置すると「Post-merge セクション自体が無いため無条件除外」という別理由で偶然パスしてしまい、本来検証すべき checked/skill不一致/event不一致フィルタの検証力が失われるため、全件に一律で適用する) に `## Post-merge\n` を前置する。あわせて (a) `gh issue list` が `--state all` で呼ばれ `--state closed` ではないことを `gh-list-args.txt` で検証するテスト (既存の "search filter" テストと同じパターン)、(b) `## Post-merge` 見出し外に配置したサンプル `- [ ] ... <!-- verify-type: opportunistic -->` 行が候補から除外されることを検証するテストを追加する (after 1, 3) (→ 受入条件 6 の opportunistic-search.sh 部分)
5. `tests/scan-pending-ac.bats` (新規作成): `docs/tech.md` § BATS Mocking Convention に従い `gh` を `PATH` 経由でモックする (`tests/run-fact-matching.bats` と同じ「`gh issue list` が `--json number,body` を直接返す」単一呼び出し形式 — `opportunistic-search.bats` の list+view 2 段呼び出し形式とは異なる点に注意)。`gh issue list` が `--state all` で呼ばれ `--state closed` ではないことを `gh-list-args.txt` 相当のログで検証するテストを最小構成で追加する (after 2) (→ 受入条件 6 の scan-pending-ac.sh 部分)

## Verification

### Pre-merge

- <!-- verify: file_not_contains "scripts/opportunistic-search.sh" "--state closed" --> `scripts/opportunistic-search.sh` の Issue 母集団取得が `--state closed` 固定でなくなり、OPEN + `phase/verify` の Issue も対象に含まれる
- <!-- verify: file_not_contains "scripts/scan-pending-ac.sh" "--state closed" --> `scripts/scan-pending-ac.sh` の Issue 母集団取得が `--state closed` 固定でなくなり、OPEN + `phase/verify` の Issue も対象に含まれる
- <!-- verify: rubric "scripts/opportunistic-search.sh の本文走査ロジックが Post-merge セクション (### Post-merge / ## Post-merge) 内の行のみを候補とし、セクション外 (コードフェンス内のサンプル行等) の - [ ] 行を候補から除外している" --> `scripts/opportunistic-search.sh` の本文走査が `### Post-merge` / `## Post-merge` セクションにスコープされ、セクション外の `- [ ]` 行を拾わなくなっている
- <!-- verify: file_contains "scripts/opportunistic-search.sh" "Post-merge" --> (上記の機械的裏付け) `scripts/opportunistic-search.sh` 内に `Post-merge` セクション境界を参照するロジックが存在する
- <!-- verify: rubric "母集団拡大による dispatch 件数への影響が評価され、observation-dispatch-threshold との関係が Spec に記載されている" --> 母集団を広げたことによる dispatch 数の増加が `observation-dispatch-threshold` の範囲に収まるか、収まらない場合の抑制方針が Spec に記録されている
- <!-- verify: command "bats tests/opportunistic-search.bats tests/scan-pending-ac.bats" --> bats テストが追加され、(a) OPEN + `phase/verify` の Issue がマッチ集合に入ること、(b) コードフェンス内のサンプル `- [ ]` 行がマッチ集合に入らないこと、を検証している (`tests/scan-pending-ac.bats` は本 Issue の実装で新規作成、`tests/opportunistic-search.bats` は既存ファイルへの追記を想定)

### Post-merge

- 次回 `/audit stats --retention` で #490 / #465 が pending AC の走査対象に含まれ、#491 の偽陽性が Manual Waiting Count から消えていることを確認する (verify-type: observation event=auto-run)

## Notes

### dispatch 件数への影響評価 (受入条件 5 の裏付け)

2026-08-08 時点で実測 (`gh issue list --label phase/verify --state {open,closed,all} --limit 500`):

| 母集団 | 件数 |
|---|---|
| OPEN + phase/verify | 2 件 (#490, #465) |
| CLOSED + phase/verify | 323 件 |
| ALL (open+closed) + phase/verify | 325 件 |

`--state closed` → `--state all` への変更で新規に母集団入りするのは最大 2 件 (#490, #465) であり、これは `.wholework.yml` で明示未設定 (デフォルト値適用) の `observation-dispatch-threshold` (デフォルト 5、`modules/detect-config-markers.md`) の範囲内に収まる。この閾値は `/auto` の Event-based observation scan (`--event` モード) の dispatch 件数を絞るものであり (`modules/observation-trigger.md` § `/auto` dispatch cap)、母集団拡大は `opportunistic-search.sh` の `--state` 変更 1 か所が event/opportunistic 両モード共通で影響するが、実際に閾値と衝突しうるのは dispatch を伴う `--event` モードのみ。追加抑制策は不要と判断した。OPEN 滞留 Issue が将来的に増加する可能性は `phase/verify` dwell の median/p95 監視 (`/audit stats --retention`) が別途カバーしている。

### 本 Issue のスコープ外とした判断

- Post-merge の Post-merge AC (`verify-type: observation event=auto-run`) は、既存のプレーン文が観測イベント (次回 `/audit stats --retention` 実行) と期待される出力構造 (#490/#465 の走査対象化、#491 偽陽性の解消) を実質的に分離して記述できているため、2 部構成への再構成や rubric verify command の追加は行わない。
- `docs/migration-notes.md` / `docs/ja/migration-notes.md` の `opportunistic-search.sh` エントリは private→public 移行時点の "Interface changes: None" という履歴記録であり、`--state` の値には言及していないため変更不要 (歴史的記録として除外)。
- `tests/observation-trigger.bats` は `opportunistic-search.sh` を `WHOLEWORK_SCRIPT_DIR` 経由でモック全置換しており、`tests/verify.bats:101` は文字列 "opportunistic-search.sh --event" の存在確認のみのため、いずれも本 Issue の変更の影響を受けない (変更不要、確認済み)。
- `tests/run-fact-matching.bats` の既存 `scan-pending-ac.sh` 向けテスト (Post-merge スコープ / `--facts` フィルタ / gh 失敗時 / `--max-candidates`) は `gh` を state 非依存でモックしており、フィクスチャも既に `### Post-merge` 見出し付きのため、本 Issue の `--state` 変更の影響を受けない (変更不要、確認済み)。新規 `tests/scan-pending-ac.bats` はこれらと重複させず、`--state all` 検証のみに最小スコープする。

### 曖昧点の自動解決 (Issue 本文からの引き継ぎ)

非対話モードのため、Issue 本文の「Auto-Resolved Ambiguity Points」節および Issue Retrospective コメントで既に 3 点が自動解決済み (`--state all` への変更、Post-merge スコープ方式は `scan-pending-ac.sh` の awk 実装踏襲、bats テスト配置先) — SPEC_DEPTH=light のため本 Spec では曖昧点解決ステップ (Step 7) 自体を実行していないが、上記の Implementation Steps はこの自動解決結果と整合させている。

## Consumed Comments

- login: saito / authorAssociation: MEMBER / trust tier: first-class / 概要: `/issue` フェーズの Issue Retrospective コメント。AC1/AC2 の verify command を `grep -n` から `file_not_contains` に、AC3 を rubric+file_contains 併記に、AC5 を `command "bats ..."` に修正した経緯と、Background 節の行番号引用 (`:291`, `:311`/`:314`) のドリフト修正を記録。本 Spec の Background/Root Cause の行番号・Implementation Steps はこの修正後の内容と整合させた。 / URL: https://github.com/saitoco/wholework/issues/1242#issuecomment-5225061949
