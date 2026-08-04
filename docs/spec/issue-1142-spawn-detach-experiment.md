# Issue #1142: auto: 外部 kill 切り分けの次イテレーション — spawn detachment flag 実装と再現→再起動→分離の 3 アーム実験

## Overview

#1135 で設計した次イテレーションを実行する。`scripts/run-auto-sub.sh` に opt-in の spawn detachment flag (`WHOLEWORK_SPAWN_DETACH=1`) を実装し、実 batch ワークロードで (1) 現環境での再現 (control)、(2) ホスト再起動後の再現 (H-b' 判定)、(3) detachment 有効での再現 (H-a 判定) の 3 アームを比較する。判定結果を `docs/reports/external-kill-investigation.md` に記録し、#598 解凍判断 / Anthropic 報告準備 / 運用ガイドのいずれかに接続する。

## Changed Files

- `scripts/run-auto-sub.sh`: `cd "$REPO_ROOT"` 直後 (L25-26 付近) に `_should_detach()` 判定関数と self-re-exec shim を追加 — bash 3.2+ 互換 (shim は python3 ワンライナー。python3 は本スクリプトに既存使用実績あり: `_search_recoveries_issue` ほか)
- `tests/run-auto-sub.bats`: `_should_detach` の 3 分岐 unit テスト + detached 子の `pgid == pid` を確認する軽量統合テストを追加
- `docs/reports/external-kill-investigation.md`: 3 アーム実験の結果 Update 節 (実験フェーズで PR ブランチに追記 — merge 前・親セッション対話実行)
- `docs/workflow.md`: [Steering Docs sync candidate] `WHOLEWORK_RETRY_ON_KILL_MAX_SEC` 等の既存 WHOLEWORK_ 環境変数の記載文脈を確認し、`WHOLEWORK_SPAWN_DETACH` の追記要否を判断 (実験用 opt-in のため「記載しない」判断も可 — その場合は理由を PR に記録)
- `docs/tech.md`: [Steering Docs sync candidate] 同上
- `docs/ja/workflow.md` / `docs/ja/tech.md`: [Steering Docs sync candidate] 英語側を更新した場合のみ翻訳ミラー同期 (docs/translation-workflow.md 準拠)

## Implementation Steps

1. `scripts/run-auto-sub.sh`: `_should_detach()` を追加 — `WHOLEWORK_SPAWN_DETACH=1` かつ `_WHOLEWORK_DETACHED` 未設定のとき真。真の場合に self-re-exec shim を実行: (a) 現 PGID で `.tmp/auto-session-${PGID}` pointer を読み `AUTO_SESSION_ID` を解決して export (detach で PGID が変わると pointer が読めなくなり event の session_id が欠落するため — 挿入位置が `cd "$REPO_ROOT"` の後である理由も pointer の相対パス解決)、(b) `_WHOLEWORK_DETACHED=1` を環境に設定 (再帰ガード)、(c) `exec python3 -c` で `subprocess.Popen(sys.argv[1:], start_new_session=True, env=...)` + `sys.exit(p.wait())` の shim に置換し、detached 子として `bash "$0" "$@"` を再起動。flag 未設定時は一切の挙動変更なし (→ 受入条件 1)
2. `tests/run-auto-sub.bats`: unit — (i) flag 未設定 → `_should_detach` が偽、(ii) `_WHOLEWORK_DETACHED=1` → 偽 (再帰ガード)、(iii) flag=1 かつ未 detach → 真。統合 — `WHOLEWORK_SPAWN_DETACH=1` で軽量サブコマンド (`--write-manual-recovery` の validation-error 経路等、外部依存なしで即終了するもの) を起動し、detached 子プロセスの `pgid == pid` を確認。既存の `WHOLEWORK_SCRIPT_DIR="$MOCK_DIR"` mock 慣行に従う (after 1) (→ 受入条件 1, 2)
3. **[実験フェーズ — PR 作成後・merge 前に親セッションで対話実行]** Arm 1 (control): 現環境 (ホスト未再起動) のまま、pr-route M/L の実 backlog 2〜3 件で `/auto --batch` を通常 spawn (flag 未設定) で実行し、kill 発生率 (発生 phase 数 / 実行 phase 数) を記録。Issue 選定基準: `triaged` 済み・blocked-by なし・相互に独立・15 分超 wrapper が見込める M/L (after 2) (→ 受入条件 3)
4. Arm 2 (reboot): Arm 1 で 1 件以上再現した場合のみ、ホスト Mac を再起動して Arm 1 と同一条件を再実行。kill 消滅 → H-b' (PID/PGID 再利用) 有力、継続 → H-a 強化 (after 3) (→ 受入条件 3)
5. Arm 3 (detach): `WHOLEWORK_SPAWN_DETACH=1` で同一条件を実行。control 再現 + detach 消滅 → H-a 確定 (after 4) (→ 受入条件 3)
6. 結果を `docs/reports/external-kill-investigation.md` の Update 節として PR ブランチに追記 (Arm 1 不再現時は「再現条件に未到達」の記録と再設計方針で受入条件を満たす)。H-a 一般形 / H-b' / H-b の判定を更新し、判定に応じた次アクション (#598 解凍判断 / Anthropic 報告準備 / 運用ガイド追記 / 再設計) を Related Issue へのコメントまたは新規 Issue として接続 (after 5) (→ 受入条件 3, 4)

## Alternatives Considered

- **採用: self-re-exec shim (run-auto-sub.sh 自身ごと detach)** — F1/F2 の kill シグネチャは「run-auto-sub.sh のプロセスグループごと SIGKILL」であり、守るべき単位は wrapper サブツリー全体。冒頭数行の変更で既存挙動 (flag 未設定) が完全不変
- 不採用 (a) `skills/auto/SKILL.md` 側の起動 prose 変更: 制御プレーンの二重実装ドリフト (#1108 類型) を増やし、LLM 実行の非決定性に依存する
- 不採用 (b) 子 wrapper (`run-code.sh` 等) のみ detach: 子だけ守っても run-auto-sub.sh 本体がプロセスグループごと死ぬため、実験としても修正としても不十分
- 不採用 (c) tmux / launchd 外部 supervisor 経由: 依存追加が重く、実行サーフェス自体の移行は #598 (in-session 移行) のスコープと重複する

## Verification

### Pre-merge

- <!-- verify: rubric "scripts/run-auto-sub.sh に環境変数による opt-in の spawn detachment 経路が実装されている。デフォルト (変数未設定) では既存挙動が変わらないことがテストまたは実装から確認でき、detachment 有効時に子 wrapper が新しいプロセスグループで起動する方式 (setsid 相当) であることが読み取れる" --> detachment flag がデフォルト無効の opt-in として実装されている
- <!-- verify: command "bats tests/run-auto-sub.bats" --> `tests/run-auto-sub.bats` が PASS する
- <!-- verify: rubric "docs/reports/external-kill-investigation.md に本 Issue の実験結果の Update 節が追記され、実施した各アームの kill 発生率が数値で記録されている。Arm 1 で再現しなかった場合は『再現条件に未到達』の記録と再設計方針の記述でも AC を満たす" --> 3 アーム実験の結果 (または未到達の記録) がレポートに追記されている
- <!-- verify: rubric "H-a 一般形 / H-b' (PID 再利用) / H-b について、実験結果に基づく判定の更新 (確定・棄却・未決の別と根拠) がレポートに明記され、判定に応じた次アクション (#598 解凍判断 / Anthropic 報告準備 / 運用ガイド追記 / 再設計のいずれか) が接続されている" --> 仮説判定の更新と次アクション接続が明記されている

### Post-merge

- H-a 確定時: detachment flag のデフォルト有効化 (または #598 移行) の判断が別 Issue として起票されている。H-a 非確定時: 本条件は「該当なし」として手動確認でチェックする

## Tool Dependencies

なし (新規 `scripts/*.sh` ファイルなし。既存 allowed-tools の範囲で実装・テスト可能)

## Uncertainty

- **harness kill の発火条件**: 観測不能 (それ自体が実験対象)。**検証方法**: 3 アーム実験。**影響範囲**: Implementation Steps 3–6
- **shim が kill された後の harness 側挙動**: shim (harness 管理下 PG) が SIGKILL されたとき、harness のタスク完了通知がどう振る舞うか、detached 子の生存がどう観測されるかは未知。**検証方法**: Arm 3 実行時に L0 (labels / PR / commit) と wrapper ログの `WRAPPER_EXIT` trailer 有無で detached 子の完走を判定する (親側通知に依存しない判定設計)。**影響範囲**: Implementation Steps 3, 5 の記録方法
- **Arm 1 の再現性**: kill はバースト性があり (7/21 は 2 セッション連続クリーン)、2〜3 件の batch で再現しない可能性がある。**検証方法**: 不再現時は受入条件 3 の「再現条件に未到達」記録 + 再設計 (件数増・時間帯変更) で対応。**影響範囲**: Implementation Steps 4–6 の実施可否

## Notes

- **実験は PR open 中に親セッションで対話実行する (phase 分割運用)**: `/code` (headless) は Steps 1–2 の実装・テスト・push までを担当し、Steps 3–6 の実験は実行しない。headless `claude -p` では「harness 管理下 background」の意味論が成立せず (background 完了通知が届かない)、#1135 の code フェーズがまさにこの構造で silent no-op になった実証がある。`/review` → `/merge` は実験結果の追記後に実行する。**`/auto` 一気通貫は不可**
- **AUTO_SESSION_ID の伝搬 (設計上の要点)**: detach すると PGID が変わり `.tmp/auto-session-${PGID}` pointer が読めなくなる (run-auto-sub.sh は L405 付近で PGID ベースの pointer 復元を行う)。shim が detach 前に現 PGID で解決して env に焼き込むことで、event の session_id 欠落を防ぐ
- **`--write-manual-recovery` 経路への影響なし**: flag 有効時も shim の `p.wait()` で同期するため、呼び出し側から見た挙動 (同期実行・exit code) は不変
- **実験の交絡排除**: 実験中は並行セッション・並行 /auto を走らせない。Arm 間で Issue 件数・route・時間帯を揃える。Arm 2 の再起動は実験のアームでありメンテナンスではない (external-kill-investigation.md Addendum の順序厳守)
- **macOS 互換**: setsid(1) バイナリは macOS に存在しないため python3 `start_new_session=True` を使う (#1135 実験 wrapper の先例)。`ps -o pgid=` は POSIX で macOS / Linux CI 両対応

## spec retrospective

### Minor observations
- `run-auto-sub.sh` の PGID ベース pointer 復元 (L405 付近) は、spawn 方式を変えるあらゆる変更に対する隠れた結合点。今後 detach / supervisor / in-session 移行 (#598) を扱う Issue は必ずこの復元経路への影響を確認すべき
- WHOLEWORK_ 環境変数の文書化場所は docs/workflow.md と docs/tech.md に分散しており、単一の環境変数リファレンスが存在しない (今回は sync candidate として個別確認で対応)

### Judgment rationale
- detach 対象を子 wrapper でなく run-auto-sub.sh 自身 (self-re-exec shim) にした: F1/F2 の kill シグネチャが「run-auto-sub.sh のプロセスグループごと SIGKILL」であるため、守る単位は wrapper サブツリー全体でなければ実験として意味をなさない
- 実験 (Steps 3–6) を code フェーズから切り離し「PR open 中の親セッション対話実行」とした: #1135 の code フェーズが headless で background 意味論を再現できず silent no-op になった実証に基づく。/auto 一気通貫不可を Spec に明記した
- 実験ワークロードは Spec に固定せず選定基準のみ記載: backlog は流動的で、実行時点の open M/L から選ぶ方が Arm 間の比較可能性を保ちやすい

### Uncertainty resolution
- shim が kill された後の harness 側挙動 (完了通知の有無) は事前検証不能 → 実験の観測対象に組み込み、detached 子の完走判定を L0 (labels/PR/commit) + WRAPPER_EXIT trailer ベースにして親通知非依存の設計とした

## Code Retrospective

### Deviations from Design
- `WHOLEWORK_SPAWN_DETACH` の文書化判断 (Spec が code フェーズに委任した sync candidate) は「記載する」で確定: `docs/tech.md` の Environment Variables 表 + `docs/ja/tech.md` ミラーに 1 行追加。理由: 同表はテスト専用変数まで掲載する WHOLEWORK_* の網羅的リファレンスであり、省略すると /audit drift の検出対象になる。`docs/workflow.md` は追記なし (実験用 opt-in はワークフロー本文の記述に影響しないため)
- スコープ外の付随修正 1 件: `docs/spec/issue-1136-bats-emit-log-isolation.md` の deprecated term 引用行に除外マーカー (旧称 プレフィックス) を追加。main が forbidden-expressions スキャンで赤の状態にあり、放置すると本 PR の CI と /review Step 9 が確実にブロックされるため、#1136 review の inline 修正先例に準拠して別コミットで解消

### Design Gaps/Ambiguities
- なし。Spec Notes の設計要点 (AUTO_SESSION_ID burn-in、挿入位置は `cd "$REPO_ROOT"` 直後、`--write-manual-recovery` への影響なし) はいずれもそのまま成立。`restore_auto_session_pointer()` が `${AUTO_SESSION_ID:-$_sid}` で env 値を優先することを実装検証で確認済み — burn-in 設計の前提が正しいことの裏付け

### Rework
- なし。本セッションは前回 /code セッション (親セッションがユーザーのオフライン移行に伴い TaskStop で明示停止した中断 — **外部 kill ではない**。resume 実行時の推定「外部 kill と推定される中断」は誤りだったため親セッションが訂正済み。kill 統計 (orchestration-recoveries.md / manual_intervention event) への記録なしを確認済み) の resume。worktree に残っていた未コミット実装が Spec Steps 1–2 と一致していたため採用し、追加検証を経てコミットした

### Confirmed Approaches
- macOS /bin/bash 3.2.57 では `set -u` + 引数ゼロの `"$@"` はエラーにならないことを実機確認 (shim の `exec python3 ... bash "$_SELF_PATH" "$@"` は bash 3.2 互換ガード不要)
- shim の負 returncode → 128+N 変換により `retry-on-kill.sh` の 137/143 検出が shim 越しでも維持される
- canary bash テストパターン (PATH 解決される `bash` を MOCK_DIR に置き、shim 発火時のみ canary が呼ばれる構造) により、外部依存なしで shim の発火/非発火を両方向検証できた
- Tier 0 recovery: 発動なし (フルスイート 1329 tests + `tests/run-auto-sub.bats` 単体 86 tests とも初回 PASS)。Smoke Test: Spec に節なしのためスキップ

## Consumed Comments

No new comments since last phase. (cutoff: `phase/ready` 付与 2026-08-01T00:39:49Z。それ以前の Design Complete コメント (saito, OWNER, 2026-08-01T00:39:46Z) は /spec 自身の出力のため対象外。cross-phase marker `type=verify-fail` / `type=preview-ac-unverified` も検出なし)

## Autonomous Auto-Resolve Log

- **`phase/ready` ラベル不在での続行 (resume 判定)**: Step 3 の `phase/ready` チェック時点でラベルは既に `phase/code` (2026-08-01T01:39:31Z 遷移済み)。前回の /code セッションが実装途中 (`scripts/run-auto-sub.sh` / `tests/run-auto-sub.bats` の未コミット変更が worktree に残存) で中断された resume ケースと判定し、Spec 存在 + 実装内容が Spec Steps 1–2 と一致することを確認のうえ続行を選択。

## Phase Handoff
<!-- phase: merge -->

### Key Decisions
- rebase conflict (`docs/spec/issue-1136-bats-emit-log-isolation.md`) を origin/main 側 (HEAD) の既存 forbidden-expressions 修正を採用して解消: 本 PR 自身の独立修正コミット (`f3904bd7`) は main の別コミットで同一 CI 問題が既に解消済みだったための重複修正だったので、main 側の検証済みバージョンを残し重複マーカーを排除
- 解消後にフルスイート `bats tests/` を再実行 (Step 6 必須) — 1332 tests 全 PASS を確認してから push
- `gh pr merge --squash --delete-branch` がローカル `main` checkout 競合 (primary worktree で `main` が既にチェックアウト済み) で local branch 削除に失敗したため、remote branch は `gh api -X DELETE` で明示削除し、Phase Handoff コミット用に `git checkout --detach origin/main` で代替 (`main` ブランチ名を使わず detached HEAD で `git push origin HEAD:main` に接続)

### Deferred Items
- Post-merge AC (H-a 確定時の detachment デフォルト有効化 / #598 移行判断): 全仮説 (H-a 一般形 / H-b' / H-b) が Arm 1 不再現により未決のまま。次アクションは #1146 (Arm 1 opportunistic 再観測 + ~2026-08-17 expiry 判断) に接続済み — 現時点では「該当なし」として手動チェックされる見込み
- 3 アーム実験のうち Arm 2 (reboot) / Arm 3 (detach) は Arm 1 不再現のため未実施のまま (実験設計上の意図的スキップ、再設計方針は `docs/reports/external-kill-investigation.md` § 2026-08-03 Update 参照)

### Notes for Next Phase
- `/verify` は Post-merge AC (`H-a 確定時...`) を確認すること。現状は全仮説未決のため「該当なし」判定・手動チェックになる見込み (PR Verification (post-merge) 節と一致させること)
- 一次証跡は `docs/sessions/64199-1785717064-2026-08-03/events.jsonl` と `docs/reports/external-kill-investigation.md` § 2026-08-03 Update — Arm 1 (control): 0 kills / 6 wrappers / 13 phase subprocesses (~3時間)
- 今回発生した worktree 競合 (`main` の二重 checkout 不可によるブランチ削除失敗) は merge スキル運用上の既知の落とし穴として記録: 再発時は remote branch の明示削除 + `origin/main` への detached HEAD checkout で回避可能

## Verify Retrospective

### Phase-by-Phase Review

#### issue
- AC の「H-a 確定時 / 非確定時」二分岐設計が機能した — 実験不再現という結果でも verify が迷わず「該当なし」分岐で完全クローズできた。実験系 Issue の AC はこの形 (結果条件付き分岐 + 未到達の逃げ道) を先例とすべき

#### spec
- phase 分割運用 (「/auto 一気通貫不可」の明記) が正しく機能し、code は Steps 1-2 で停止、実験は親セッション対話実行、review は実験結果追記後 — 設計どおりの進行

#### code
- 前回中断 (TaskStop) の resume を含めクリーン。中断帰属の誤記 (「外部 kill と推定」) は親セッションが訂正済み (95a97846)

#### review
- **notable (Auto Retrospective 未記録の手動介入)**: review fork agent が初回実行で「エージェントの完了通知を待機します」を宣言して停止 (Review Response Summary 未投稿・PR コメント 0 件の silent no-op 状態)。親セッションが reconcile-phase-state で観測し、SendMessage resume + 「テスト同期実行」規約の再提示で完遂させた。**#1123 Cause A (headless での background 完了通知待ち) と同型の失敗が fork 実行サーフェスでも発生する**ことの実証 — #1103 (Workflow の headless 非互換) と同族で、「非対話・非 fork-aware な実行文脈での通知依存待機の禁止」横断規約 (#1123 AC 1) のスコープに fork surface を含めるべき根拠。--write-manual-recovery の枠外 (wrapper 経由でないため) につき本節が一次記録
- review agent が gh-pr-review.sh の own-PR REQUEST_CHANGES 422 に遭遇し COMMENT 降格で手動回避 — **open #1102 の再現実証** (improvement proposal は review retrospective に記録済み、新規起票なし)

#### merge
- rebase コンフリクト 1 件 (両側が同一 CI 修正を独立実装) を main 側採用で解消し、フルスイート 1332 tests 再実行後に merge — 手順どおり。worktree 競合の回避手順は Phase Handoff に記録済み

#### verify
- FAIL 0 / UNCERTAIN 0。bats 86/86 再確認 (spawn-detach 3 テスト含む)

### Improvement Proposals
- fork 実行サーフェスでの通知依存待機の禁止を #1123 の横断規約スコープに含める (新規起票なし — #1123 へのコメント接続で対応。fan-out 抑制方針と整合)
