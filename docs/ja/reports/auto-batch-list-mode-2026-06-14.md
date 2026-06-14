日本語 | [English](../../reports/auto-batch-list-mode-2026-06-14.md)

# /auto --batch List モードパフォーマンスレポート — 2026-06-14

Opus 4.7 親オーケストレータ + Sonnet `claude -p` 子フェーズ構成で実行した `/auto --batch 581 554 548 547 546 541`（List モード）のパフォーマンス記録。単一バッチ実行で 6 Issue を順次処理した。時刻はすべて JST（ローカル）で、`run-auto-sub.sh` の Started/Finished バナーおよび git commit timestamp に基づく。ユーザーは実行序盤に離席を宣言したため、親セッションは入力待ちでブロックしておらず、アイドル時間は構造的にゼロ。

同じリポジトリ上で別の単一セッション `/auto` 実行（`auto-parent-session-comparison-2026-06-14.md` を生成したセッション）が並行稼働しており、両者のコミットが `main` 上でインターリーブされた。本実行は、並行 `/auto` 実行の最初の自然観察例である。

## サマリー

| 指標 | 値 |
|------|-----|
| 完全処理した Issue（spec → code → review → merge） | 6 件（#581, #554, #548, #547, #546, #541） |
| 完全クローズ（phase/done） | 0 件 |
| phase/verify 残（opportunistic pending、観測型 post-merge AC） | 6 件（#581, #554, #548, #547, #546, #541） |
| 実稼働時間（連続、アイドル除外） | 約 4 時間 43 分（00:36:23 → 05:19:37 JST） |
| スループット | 約 1.27 Issue/時 |
| Tier 1 reconcile 自動復旧 | 0 回 |
| Tier 2 fallback-catalog 復旧 | 0 回 |
| Tier 3 recovery sub-agent 起動 | 1 回（#554 code フェーズ、`action=recover`、成功） |
| watchdog kill | 0 回 |
| 親セッションによる手動介入 | 0 回 |
| verify FAIL → reopen の fix サイクル | 0 回（verify フェーズ呼び出しは保留 — 「verify フェーズの観測」参照） |
| 並行 `/auto` セッションの検出 | あり（同時間帯に別セッションが約 10 Issue を処理） |
| 並行コミットによる merge conflict | 0 回 |

## Issue 別所要時間

所要時間は `run-auto-sub.sh` の Started → Finished バナー（各 Issue の spec → code → review → merge エンドツーエンド）。verify は所要時間に**含まれない** — 後述の「verify フェーズの観測」を参照。

| Issue | Size/Route | 所要時間 | spec | code+review+merge | PR | 備考 |
|-------|-----------|----------|------|-------------------|-----|------|
| #581 | M → XS / pr→pr | 48 分 04 秒（00:36:23→01:24:27） | 9 分 42 秒 | 約 38 分 | #602 | spec フェーズで Size M→XS に再判定（ドキュメント onlyの ADR）。route は `pr` のまま継続（Step 3a の re-routing は実行中フェーズには適用されない設計） |
| #554 | M / pr | 32 分 28 秒（01:25:34→01:58:02） | 8 分 03 秒 | 約 24 分 | #606 | code フェーズで Tier 3 recovery sub-agent 起動。`action=recover` 成功（PR push と remote branch 作成ヒントの競合状態をリカバリ） |
| #548 | M → XS / pr→pr | 44 分 40 秒（01:58:34→02:43:14） | 10 分 43 秒 | 約 33 分 | #607 | spec フェーズで Size M→XS に再判定 |
| #547 | M / pr | 約 44 分（02:43:30→03:27:25） | 約 13 分 | 約 30 分 | #609 | クリーン完走 |
| #546 | M / pr | 47 分 02 秒（03:27:47→04:14:49） | 11 分 23 秒 | 約 35 分 | #611 | クリーン完走 |
| #541 | M / pr | 64 分 23 秒（04:15:14→05:19:37） | 13 分 03 秒 | 約 50 分 | #613 | 最長。base 先行 mergeability 事前検出機能を実装する PR（並行セッションが同時に main へ merge する実環境下で実行された皮肉な配置） |

### 所要時間の観察

- **PR route (M)**: spec + code + review + merge エンドツーエンドで 32〜64 分、中央値 約 46 分。2026-06-14 単一セッションのベースライン（M/pr で 27〜53 分）と同等で、2026-06-13 Fable 5 ベースライン（クリーン完走で 45〜65 分）より速い。
- **spec フェーズの安定性**: 6 件すべてで 8〜13 分。4 時間 43 分の窓全体で劣化なし。
- **code フェーズの分散**: 支配的コスト（24〜50 分）。#541 が最も遅いが、spec が記述したマルチステップ事前チェック（git fetch + behind-by 解析 + コメント投稿）が実装ボリュームを正当化する。
- **再判定された Size（M→XS）は実行中のルートを変更しない**: #581 と #548 はそれぞれ spec フェーズ中に XS に再判定されたが、すでに選択された `pr` ルートでそのまま継続した。これは auto スキルの Step 3a の文書化された挙動（spec 後の Size リフレッシュは次のルーティング判定にのみ適用、実行中フェーズシーケンスには遡及しない）に合致する。

## Tier 3 リカバリイベント（#554）

#554 の code フェーズで wrapper レベルの異常が発生したが、wrapper 内のリカバリ階層が親セッション介入なしで処理した:

```
[spawn-recovery] action=recover: executing recovery steps
remote: Create a pull request for 'worktree-code+issue-554' on GitHub by visiting:
remote:      https://github.com/saitoco/wholework/pull/new/worktree-code+issue-554
* [new branch]      worktree-code+issue-554 -> worktree-code+issue-554
https://github.com/saitoco/wholework/pull/606
[spawn-recovery] step 1: op=run_command
[spawn-recovery] step 2: op=run_command
[spawn-recovery] all recovery steps completed
[recovery] tier3 sub-agent: recovered
PR number: 606
```

トレースの読み取り: branch push は成功したが、wrapper の通常パスでの PR 作成は失敗（`gh pr create` が push 直後の branch state と競合した可能性が高い）。Tier 3 recovery sub-agent が状態を認識（push 成功・PR 未作成）、リカバリプラン（`action=recover`）を生成し、2 つの `run_command` ステップを実行した。プランの validate を通過し、リカバリされたフェーズが `PR number: 606` を出力した。後続の review・merge フェーズは正常実行。

これは**プロダクションでの Tier 3 recovery sub-agent 起動の初観測例**である。これまでの報告では Tier 1（reconcile）と親セッション手動リカバリ（2026-06-13 ベースラインの #557）のみが観測されていた。Tier 3 パスは子 wrapper 内で完結し、親セッション介入はゼロ回。

## 並行 /auto セッションの共存

このバッチ実行中、同じ `main` ブランチ上で別の `/auto` セッションが並行稼働し、2026-06-13 バックログからの改善 Issue（#583, #584, #585, #586, #587）に加えて複数の `/audit drift` フォローアップ（#601, #604, #605, #606）を処理した。両セッションは worktree ベースの分離経由で `main` にコミットを書き込んだ。

コミットのインターリーブ時系列（抜粋、JST）:

```
00:36:23  本バッチ: #581 sub-issue 開始
01:22:35  本バッチ: #581 PR #602 merge
01:30:21  本バッチ: #554 design commit
01:32:38  別セッション: #583 PR #603 merge
01:56:40  別セッション: #606（audit issue）merge
01:56:45  別セッション: #604 merge
01:57:18  本バッチ: #554 merge handoff
02:11:31  別セッション: #605 merge
02:42:03  本バッチ: #548 PR #607 merge
02:43:21  別セッション: #584 PR #608 merge
03:26:02  本バッチ: #547 PR #609 merge
03:43:49  別セッション: #585 PR #610 merge
04:13:44  本バッチ: #546 PR #611 merge
05:12:45  別セッション: #586 PR #612 merge
05:18:01  本バッチ: #541 PR #613 merge
05:37:04  別セッション: #587 design commit
```

### 観察

- **merge conflict ゼロ**: 4 時間 43 分の窓で 2 つの独立したセッションから `main` に約 16 件の merge が発生したが、どちらの wrapper log にも merge 失敗は記録されなかった。worktree ベースの branch 分離（`worktree-code+issue-N`）＋ PR merge モデル（各 PR が merge 時に fetch・rebase）が並行 base 移動を吸収した。
- **mergeability 事前チェックが、自身の実装中に実行された**: #541 は `run-code.sh` 用 base mergeability 事前チェックを実装中だった。自身の code フェーズ中に、並行セッションが #608, #610, #612 を `main` に merge した — まさに #541 の事前チェックが検出する設計のシナリオ。これらはいずれも #541 自身の merge を失敗させなかった。merge 時の PR rebase が base 移動を解決したため。
- **spawn-recovery のカスケードは観測されず**: 単一の Tier 3 リカバリ（#554）は PR 作成競合がトリガーであり、並行 merge 競合ではなかった。並行セッションに帰属できる他の異常はなかった。

これは単一リポジトリ上の並行 `/auto` 安全性に関する最初の経験データである。結果は希望的だがサンプルは小（1 ペア実行・約 16 merge）であり、一般的な主張はできない。

## verify フェーズの観測

バッチ wrapper（`run-auto-sub.sh`）は各 Issue で spec → code → review → merge を実行するが、wrapper 内では verify フェーズを**呼び出さない**（verify は単一 Issue auto ルートでは親セッション Skill 呼び出し — `Skill(skill="wholework:verify", args="$NUMBER")`）。`--batch` List モードの設計では、各子 wrapper が return した後に親セッションが verify をオーケストレートする想定だが、本実行ではユーザーが離席宣言とともに manual AC を後回しにするよう依頼したため、親セッションは verify を保留した。

6 件の最終状態:

| Issue | 状態 | ラベル | 理由 |
|-------|------|-------|------|
| #581 | CLOSED | phase/verify | PR #602 が `closes` 参照で issue を auto-close。verify 型 post-merge AC 未チェック |
| #554 | CLOSED | phase/verify | 同上 |
| #548 | CLOSED | phase/verify | 同上 |
| #547 | CLOSED | phase/verify | 同上 |
| #546 | CLOSED | phase/verify | 同上 |
| #541 | CLOSED | phase/verify | 同上 |

6 件すべてが観測型 / 将来イベント型の post-merge AC を持つ（retro 由来の改善 Issue で設計上想定される形）: 実際の watchdog kill 再発、実際の fix-cycle reconcile 挙動、CI 上での fullPage screenshot 忠実度など。これらは通常運用中にトリガーイベントが発生した際に `/verify N` 経由でクローズされる想定 — セッション内完結は不可。

**浮上したギャップ**: バッチ wrapper が verify を意図的に除外しているため、`phase/verify` ラベルがバッチ完了 Issue の普遍的終端状態になる。AC が今日擬似環境テスト可能かどうか、観測型のみかどうかに関係なく。2026-06-13 報告書の構造的修正（#583、`verify-type: observation event=<name>`）は verify フェーズが AC を分類し観測型を auto-PASS させるが、本バッチ実行は verify が走らなかったためそのパスを行使できなかった。

## リカバリ監査トレイル更新

#554 の Tier 3 リカバリは `run-auto-sub.sh` のリカバリ emission パス経由で `docs/reports/orchestration-recoveries.md` にエントリを生成した。fallback-catalog エントリは適用されなかった（Tier 2 の detector 出力が空で、直接 Tier 3 へエスカレート）。

## 評価

### 機能した点

1. **シーケンシャルバッチ wrapper の安定性**: 6 回連続の `run-auto-sub.sh` 起動が Opus 4.7 親下でクリーンに完了。wrapper レベルの state 破損、フェーズスキップなし。
2. **Tier 3 リカバリ初回実行がクリーン**: recovery sub-agent が有効プランを生成し（`validate-recovery-plan.sh` をパス）、実行し、wrapper が親介入なしで継続した。sub-agent の存在が合成テストを超えて実証された。
3. **並行セッション安全性**: 2 つの `/auto` セッションから `main` に約 16 件の merge、conflict ゼロ。worktree 分離 + merge 時 PR rebase がこのスケールでは並行 base 移動を吸収する。
4. **親アイドル時間が真にゼロ**: ユーザーが親に離席を早期に伝えたため、本実行は入力待ちなしで 4 時間 43 分の連続進捗を維持した。1.27 Issue/時のスループットは下限（PR ルートのみ・M サイズ支配）であり上限ではない。

### 制約とギャップ

1. **verify 除外 → 普遍的 phase/verify 終端状態**: バッチ完了 6 件すべてが `phase/verify` にとどまる。バッチ wrapper は verify を走らせず、親セッションは verify を保留した。ユーザーは Issue 単位で `/verify N` を実行できるが、スケールするとバッチ終端状態は AC 検証可能性に関係なく単一バケットに収束する。#583 の修正案（イベント駆動観測型）は AC 側の問題を解決するがバッチ wrapper 側の除外を変えるものではない。
2. **Size 再判定は実行中の Issue をルート再配線しない**: #581 と #548 は spec 中に M→XS に再判定されたが、実行中の `pr` ルートは `patch` に縮小されなかった。これは文書化された挙動（Step 3a は次のルーティング判定で適用）だが、コストは実在する — #581 は documentation only な ADR に対して 38 分の code+review+merge を支払った（patch ルートなら約 10 分でクローズした可能性が高い）。
3. **並行安全性主張のサンプルサイズが 1 ペア実行**: conflict ゼロの結果は希望的だが統計的に有意ではない。意図的なストレステスト（両セッションが同時に `skills/` ファイルに触れる）が一般安全性の主張には必要。
4. **`--batch` List モードと単一セッションの価値比較は本稿で未実施**: 単一セッションレポート（`auto-parent-session-comparison-2026-06-14.md`）の結論は「`--batch` は推奨されない」。本実行はそれと矛盾しない — `--batch` が安全で並行耐性があることを示すが、より好ましいことを示すわけではない。スループット（1.27/時）は単一セッションベースライン（比較レポートでの 2.4/時）より低く、これはバッチオーバーヘッドではなく M 偏重の Issue mix に整合する。

### 浮上した改善候補

（本レポートからは Issue 化していない — ユーザーの判断に委ねる）

1. **バッチ wrapper の verify オーケストレーション**: 各 `run-auto-sub.sh` の return 後に親セッションが子 Issue ごとに `/verify` を呼び出す（List モードなら Issue 間で実施可能）、または「バッチモードは常に `phase/verify` で終端し、後続の `/verify N` を要する」と文書化する。現挙動は正しいが、暗黙の backlog を生成する。
2. **Step 3a 再判定での実行中ルート縮退**: spec が Size を M から XS に再判定した際、残るフェーズ（code, review, merge）を patch ルートに再計画できる。これにより #581 と #548 で各約 25 分節約できた。トレードオフはフェーズオーケストレータの複雑性増加であり、ヒューリスティックケースにそれだけの価値があるかは要検討 — ただし提起する価値はある。
3. **Tier 3 sub-agent 起動のログ記録**: トレースは wrapper log のみに残った。`docs/reports/orchestration-recoveries.md` に `source: recovery-sub-agent` キーで要約行を追加（auto スキルで現在「#316 ship 後に有効」とされている）すれば監査トレイルループが閉じる。

## 結論

`--batch` List モードで 6 Issue 実行が Opus 4.7 親下、4 時間 43 分連続実行でクリーンに完了した。プロダクション初観測の 2 点は (1) Tier 3 recovery sub-agent 起動が親介入なしで解決されたこと、(2) 同リポジトリ上で並行稼働する単一セッション `/auto` と merge conflict なしで共存したこと。約 1.27 Issue/時のスループットは M 偏重 Issue mix と整合する。

未解決の構造的観察は、バッチ完了 Issue の普遍的終端状態 `phase/verify` である — AC 側の修正（#583、イベント駆動観測型）が解決しない wrapper 設計のギャップ。バッチモードが Issue 間で verify をオーケストレートすべきか、あるいは「バッチは verify で終端し、ユーザーが後続フォローアップごとに `/verify N` を実行する」と設計を明示すべきか、どちらかの判断が必要。

---

## 後続: 改善 Issue 起票 + 第 2 バッチ + 単独 Issue 実行

主バッチおよびレポート作成後、同セッション内で 3 つの追加 `/auto` 実行が走り、追加のコードパスを exercise した。生データとレポート自身の予測の検証を兼ねてここに追記する。

### レポートから起票した改善 Issue

上記「浮上した改善候補」セクションの 3 候補をユーザーの依頼で起票:

| # | Title（抜粋） | 元になった候補 |
|---|---|---|
| #615 | auto: --batch List モードで Issue 間 verify を親セッションがオーケストレート | 1. バッチ wrapper の verify オーケストレーション |
| #616 | auto: Step 3a 再判定で実行中ルートを M/pr → patch に縮退 | 2. Step 3a 再判定での実行中ルート縮退 |
| #617 | auto: Tier 3 recovery sub-agent 起動を orchestration-recoveries.md に記録 | 3. Tier 3 sub-agent 起動のログ記録 |

### Wave 2: `/auto --batch 615 616 617`

同じ Opus 4.7 親、同じ `--batch` List モード wrapper。3 件いずれも phase ラベルなしで開始し triage → spec → code → review → merge の全フェーズを実行。

| Issue | Size/Route | 所要時間（triage + run-auto-sub） | PR | 結果 |
|-------|-----------|------------------------------------|-----|------|
| #615 | M / pr | 約 50 分（06:42→07:32 JST: triage 7分 + spec→code→review→merge 42分） | #619 | CLOSED / phase/verify（クリーン） |
| #616 | M / pr | 約 57 分（07:40→08:37 JST: triage 10分 + spec→code→review→merge 47分） | #620 | CLOSED / **phase/review**（異常 — 下記参照） |
| #617 | M / pr | 約 70 分（08:39→09:38 JST: triage 10分 + spec→code→review→merge 60分） | #622 | CLOSED / phase/verify（クリーン、spec 中に最大 1080s の silent window 観測） |

実稼働時間: 約 3 時間（06:42→09:38 JST）。スループット: 約 1.0 Issue/時（Wave 1 の 1.27/時より低いのは、Wave 2 は Issue ごとに triage フェーズが追加されたため）。

### 異常: #616 が merge 後 phase/review 滞留

#616 の `run-auto-sub.sh` は exit 0、PR #620 は実際に `2026-06-13T23:36:01Z` に MERGED、issue は PR の `closes #616` で auto-close。しかし phase ラベルは `phase/review` のまま — merge 子 wrapper 内部で `merge → verify` のラベル遷移が抜けた。手動で `gh-label-transition.sh 616 verify` を実行して補正。`reconcile-phase-state.sh merge 616 --pr 620 --check-completion` は `matches_expected: true`（merge は成功）を返したため、既存の wrapper validation では検出できない構造。

これは**未観測の wrapper 異常**である。同フローで #615 と #617 は正常に遷移したため、非決定的に発生する症状 — merge skill 内の `gh pr merge` と `gh-label-transition.sh` 呼び出しの間で `claude -p` が early-stop した可能性が最も高い。

異常を **#624 — merge: PR merge 後の phase/review → phase/verify ラベル遷移漏れを検出・補正**（Size S, patch route）として起票。

### Wave 3: `/auto 624`（単独 Issue、patch route）

同じ Opus 4.7 親。単独 Issue auto、patch route。

| Phase | 所要時間 | 結果 |
|-------|----------|------|
| triage (run-issue.sh) | 約 7 分（10:23→10:30 JST） | Size 判定 S（提案は M）。verify command を `section_contains`（shell script に適用不可）から `grep` x2 に修正。Auto-Resolved Ambiguity Points に記録。 |
| spec (run-spec.sh) | 約 10 分（10:30→10:40 JST） | Option A（run-merge.sh の completion-check 拡張）を採用。 |
| code --patch (run-code.sh) | 約 8 分（10:40→10:48 JST） | main 直 commit: `run-merge.sh` を `phase/review` 滞留検出と自動遷移に拡張。bats 17/17 PASS（新規ケース "label stuck: merge succeeded but phase/review label stuck, auto-transitions to verify" を含む）。実装 commit `6f6f29f`。 |
| verify（親セッション Skill） | 約 30 分（retro 記録と改善 Issue 起票を含む） | Pre-merge 3/3 PASS。Post-merge AC4 は**代替検証で PASS**（下記参照）。Post-merge AC5 は deferred（observation 型）。 |

合計: triage → code → verify で約 55 分。verify だけで run の半分を占めた。

### #624 の verify が露呈した verify command 設計問題

Post-merge AC4 は以下の形で書かれていた:

```
<!-- verify: github_check "gh run list --workflow=test.yml --limit=1 --json conclusion --jq '.[0].conclusion'" "success" -->
```

verify command は `""`（空）を返した — `--limit=1` は `main` の最新 run を取るが、それは並行 /auto セッションが push した Issue #600（commit `7a918fca`、status `in_progress`）であり、#624 自身の commit ではなかったため。#624 の実装 commit (`3dec8ac8`) と design commit (`175b3cfe`) は `headSha` でフィルタすれば `success` 結論だが、AC の verify command は commit フィルタを持たない。

これは主バッチの「並行 /auto セッションの共存」セクションで言及した同じ並行セッション干渉ダイナミクスが、新しい場所（verify command セマンティクス）で表面化したもの。AC4 は代替検証（手動で commit フィルタ）で PASS と判定し、改善 Issue を起票した:

**#626 — verify-patterns: github_check の gh run list テンプレートに --commit フィルタを標準化**

### 後続のサマリー

| 指標 | 値 |
|------|-----|
| Wave 2 処理 Issue（バッチ） | 3 件（#615, #616, #617） |
| Wave 3 処理 Issue（単独） | 1 件（#624） |
| 実稼働時間（Wave 2 + Wave 3） | 約 4 時間 15 分（06:42→11:00 JST、アイドルなし） |
| watchdog kill | 0 回 |
| 観測した wrapper 異常 | 1 回（#616 の merge→verify ラベル遷移漏れ） |
| 親セッションによる手動リカバリ | 1 回（`gh-label-transition.sh 616 verify`） |
| 新規起票した改善 Issue | 2 件（#624, #626） |
| `/auto` 内で起動した verify フェーズ | 1 回（Wave 3 #624 のみ。Wave 2 はユーザ要望により保留） |

### 後続が確認したこと

1. **phase/verify 普遍的終端状態は実在する** — `/auto` 単独実行で verify が走った Wave 3 #624 ですら、自身の `event=auto-run` observation AC のために `phase/verify` で終端する。wrapper 側のギャップ（#615）と AC 側のギャップ（#583）は独立であり、両方の対応が必要。
2. **wrapper 異常はレアではない**: 未観測の `phase/review` 滞留パスが次バッチで即出現した。Wave 1 の Tier 3 リカバリ（#554）と本ギャップを合わせると、wrapper 異常の表面積は既存 fallback カタログのカバー範囲より広い可能性が高い。
3. **並行 /auto 安全性は新次元では維持、別次元では破綻**: merge conflict ゼロは継続（Wave 2 + 3 でも並行 main merge が続いた）。しかし verify command セマンティクスは並行 push 下で破綻 — 主バッチの「並行 /auto セッション共存」主張が想定していなかった新クラスの干渉。
4. **triage の verify command 監査価値が再確認**: #624 の triage が `section_contains`（markdown 見出し用、shell script には適用不可）を `grep` x2 に修正。同パターンは 2026-06-13 ベースライン（14 Issue 中 3 件の triage 修正）でも観測されており、本セッション 4 Issue でも再現。triage skill の安定した特性として明示推進する価値あり。

### Loose ends

- **#624 自身は `phase/verify` で終端した** — post-merge AC5 が `verify-type: observation event=auto-run` のため。`run-merge.sh` の auto-recover 挙動は実際にラベル遷移漏れが発生したときだけ動くが、それ自体が非決定的。AC5 は将来 `/auto` 実行でリカバリパスが exercise されたときにクローズする。
- **#626（verify command 修正）は未処理**: 標準 `--commit=$(git rev-parse HEAD)` 形を `modules/verify-classifier.md` と `skills/issue/spec-test-guidelines.md` に追加し、既存 patch route AC を移行する必要あり。次セッションに繰り越し。
