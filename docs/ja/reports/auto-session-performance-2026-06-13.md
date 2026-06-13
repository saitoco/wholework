# /auto セッションパフォーマンスレポート — 2026-06-13

Claude Fable 5（親オーケストレータ）+ Sonnet `claude -p` 子フェーズ構成で実行した長時間 `/auto` セッションのパフォーマンス記録。単一セッション・2 つの波で 14 Issue を完全処理した。時刻はすべて JST（ローカル）で、`run-*.sh` の Started/Finished バナーに基づく実測値。verify フェーズ（親セッション実行、wrapper バナーなし）の境界は次フェーズの開始時刻からの逆算（概算）。

ユーザー入力待ちのアイドル時間は、すべての Issue 別所要時間から除外している。

## サマリー

| 指標 | 値 |
|------|-----|
| 完全処理した Issue（triage → verify） | 14 件（#555–#563, #572–#574, #567, #569） |
| 完全クローズ（phase/done） | 7 件（#558, #559, #560, #561, #572, #573, #574） |
| phase/verify 残（観測型条件のみ） | 7 件（#555, #556, #557, #562, #563, #567, #569） |
| 第 1 波の実稼働時間（連続、アイドルなし） | 約 7 時間 50 分（#555–#563、22:45–06:35 JST） |
| 第 2 波の実稼働時間（連続、アイドルなし） | 約 3 時間 30 分（/audit drift + #572–#574, #567, #569、07:18–10:48 JST） |
| verify FAIL → reopen の fix サイクル | 1 回（#557、iteration 2/3 で解決） |
| 親セッションによる手動リカバリ | 1 回（#557 テストモック修正） |
| watchdog kill | 2 回（35 回以上の wrapper フェーズ実行中） |
| セッション内で起票・消化した改善 Issue | 5 件（#567, #569, #572, #573, #574） |
| Fable 5 opt-in spec 実行（`run-spec.sh --fable`） | 1 回（#560、成功） |

## Issue 別所要時間（アイドル除外）

所要時間は各 Issue の最初のフェーズ開始から verify 完了まで（親セッション verify は次 Issue の triage 開始からの逆算）。

### 第 1 波 — `/auto` バッチ #555–#563

| Issue | Size/Route | 所要時間 | フェーズ内訳 | 備考 |
|-------|-----------|----------|------------|------|
| #555 | M / pr | 約 60 分 | issue 8 分 → spec 9 分 → code 12 分 → review 12 分 → merge 2 分 → verify 約 15 分 | クリーン完走。retro から #567 起票 |
| #556 | M / pr | 約 65 分 | issue 約 7 分 → spec 約 9 分 → code 約 30 分 → review 約 12 分 → merge 約 2 分 → verify 約 6 分 | code フェーズで 1800s watchdog kill（旧デフォルト）。reconcile が自動復旧 |
| #557 | S / patch | 約 87 分 | issue 7 分 → code 17 分 → verify(1) FAIL → fix-code 45 分（kill）→ 手動修正 約 10 分 → CI 待ち 約 6 分 → verify(2) | フル fix サイクル。reconcile false positive を経験。#569 起票 |
| #558 | S / patch | 約 28 分 | issue 約 8 分 → code 約 15 分 → verify 約 5 分 | 最もクリーンな patch 実行 |
| #559 | M / pr | 約 48 分 | issue 約 6 分 → spec 約 8 分 → code 約 12 分 → review 約 10 分 → merge 約 6 分 → verify 約 6 分 | verify 内で ZDR 擬似環境テストを構築 |
| #560 | M→S / patch | 約 45 分 | issue 約 7 分 → spec(Fable 5) 8 分 52 秒 → code 約 25 分 → verify 約 5 分 | spec 後に Size M→S 再判定 |
| #561 | M / pr | 約 62 分 | issue 約 6 分 → spec 約 12 分 → code 約 18 分 → review 約 14 分 → merge 約 3 分 → verify 約 9 分 | Not-adopted 結論で全 AC PASS |
| #562 | S / patch | 約 35 分 | issue 約 7 分 → spec 約 8 分 → code 約 13 分 → verify 約 7 分 | |
| #563 | S / patch | 約 40 分 | issue 約 5 分 → spec 約 7 分 → code 約 15 分 → verify 約 13 分 | バッチ末尾（最終レポート含む） |

### 第 2 波 — /audit drift + フォローアップ

| Issue | Size/Route | 所要時間 | 備考 |
|-------|-----------|----------|------|
| /audit drift | — | 約 22 分 | drift 2 件検出 → #572/#573 起票。#558/#560 の post-merge 条件を同時消化 |
| #572 | XS / patch | 約 30 分 | audit/drift フォローアップ。phase/done |
| #573 | XS / patch | 約 35 分 | triage が「常に PASS する verify command」を修正。phase/done。verify で積み残し検出 → #574 起票 |
| #574 | XS / patch | 約 27 分 | retro→Issue→修正→検証のループが 1 サイクルで完結。phase/done |
| #567 | S / patch | 約 39 分 | triage が「既に true の verify command」を section_not_contains に強化 |
| #569 | M / pr | 約 55 分 | reconcile の fix-cycle フレッシュネス条件（reopen_ts + git log --after）。fix-cycle 新規 3 ケース含む bats 55/55 |

### 所要時間の所見

- **patch ルート（XS/S）**: end-to-end で 27〜40 分。支配的コストは code フェーズ（13〜25 分）で、triage と verify は各 5〜8 分で安定。
- **PR ルート（M）**: クリーン完走で 45〜65 分。patch ルートに対し review が 10〜14 分、merge が 2〜6 分上乗せ。
- **fix サイクルのコスト**: #557 の FAIL → reopen → 修正 → 再 verify の 1 サイクルで、クリーン完走比 約 60 分の追加。うち 45 分は watchdog kill された空振り wrapper 実行。親セッションの手動リカバリ（5 ファイルのテストモック修正）はローカルテスト実行込みで約 10 分。
- **issue triage は極めて安定**: Size によらず 5〜8 分。うち 3 件では verify command の実質的な修復を実施（#573 の常時 PASS コマンド、#567 の既に true なコマンド、#555 の grep 引数順序）。

## watchdog 観測（#556 post-merge AC に直結）

本セッションの 35 回以上の wrapper フェーズ実行中、kill は 2 回:

| # | フェーズ | 適用タイムアウト | 結果 | リカバリ |
|---|---------|----------------|------|---------|
| 1 | #556 code (pr) | 1800s（旧デフォルト） | kill 前に PR #568 作成済み | Tier 1 reconcile が OPEN PR を検出 → 自動 success、手動対応不要 |
| 2 | #557 fix-cycle code (patch) | 2700s（新デフォルト） | 真の作業中 kill、コミットゼロ | Tier 1 reconcile が reopen 前の `closes #557` コミットに **false positive**。親セッションが `git log` HEAD 確認で検出し手動リカバリ。根本原因は #569 で修正済み |

#556 マージ後（#558 以降は 2700s デフォルト有効）: 後続 25 回以上の wrapper 実行で **kill 0 回**。最長のクリーン code フェーズ（約 25 分、#560）も完走。2700s への引き上げにより 1800s 時代の kill クラスは解消され、2700s での 1 回（#557）は質的に異なる事象（真にストールした実行 = watchdog が kill すべき対象）だった。Layer 3 リカバリの両挙動（完了後 kill の自動復旧、作業中 kill の検出 — #569 修正後は正しく検出）が実地で確認された。

完走した実行で観測された最長 silent window: 約 660 秒（review フェーズ）、約 480〜540 秒（spec/code フェーズ）— 2700s 予算に対し十分な余裕。

## 品質ループのイベント

- **verify FAIL 検出が機能**: #557 の iteration 1 が、code フェーズの不正確な自己報告（テスト green 申告）に対し CI red の条件を正しく FAIL 判定。reopen → 修正 → iteration 2 PASS のループが上限（3 回）に達せず完了。
- **triage の verify command 監査レイヤー化**: 3 件の Issue で、false PASS（#573, #567）や false FAIL（#555）を生む前に欠陥のある verify command が triage 段で修復された。
- **自己修復パイプライン**: 本セッションの retrospective が生成した改善 Issue（#567, #569, #572, #573, #574）はすべて同一セッション内で実装・検証・クローズまで完結。#557 のインシデント → #569 の構造修正のループは、fix-cycle bats 回帰テスト込みで 10 時間以内に閉じた。
- **Fable 5 opt-in**: 初の本番 `run-spec.sh --fable` 実行（#560）が成功 — 警告 3 行出力、effort=high で 8 分 52 秒の spec 生成、Size の M→S 再判定も正常。ZDR graceful degrade は擬似環境 bats テストで検証済み（#559）。

## 残存する観測条件

phase/verify の 7 Issue が持つのは将来イベント観測型の条件のみ: 実 PR `/review --full` の所見量（#555）、watchdog kill 再発（#556）、early-stop 不発生（#557）、retrospective 参照効果（#562）、cyber-classifier fallback（#563）、format 変更の一括反映（#567）、実 fix-cycle での reconcile 挙動（#569）。それぞれ通常運用で該当イベントが発生した時点で `/verify N` によりクローズできる。
