# Issue #278: scripts: run-auto-sub.sh の patch lock 取得が stale 不在時でも 300s で false timeout する

## Overview

`/auto --batch 2` で #276 → #274 を順次処理中、#274 の code phase で `mkdir` ベースの patch lock 獲得が 300s timeout。手動 `ls` では lock ディレクトリは空（stale file なし）。手動 `run-code.sh --patch` (lock 不使用) で即時成功した。

原因仮説 (優先度順):
1. **stale empty directory**: `rmdir` は空ディレクトリに対しては成功するが、macOS Finder などが `.DS_Store` を一瞬作成 → `rmdir` 失敗 → `|| true` で silent 失敗 → 以降は空だが存在する状態で固定。
2. **orphaned lock**: 過去の crashed run (想定しない SIGKILL 等) で EXIT trap がスキップされ、空 directory が残存。
3. **race / timing**: 極短時間の競合。実質 300s 待機する頻度は低いため、主要因ではない。

いずれの仮説でも同一の対策（PID stamping + stale 検出 + diagnostic log）で解消できる。

## Changed Files

- `scripts/run-auto-sub.sh`: `acquire_patch_lock` に PID stamping と stale 検出を追加、diagnostic log 追加 (bash 3.2+ 互換)
- `tests/run-auto-sub.bats`: stale PID reclaim と診断ログ出力のテストケース追加

## Implementation Steps

1. `acquire_patch_lock` の mkdir 成功直後に `$$` を `${PATCH_LOCK_DIR}/pid` に書き込み。`release_patch_lock` は `rmdir` の代わりに `rm -rf "$PATCH_LOCK_DIR"` を使用（`.DS_Store` 等の副ファイルも掃除） (→ AC1, AC2)
2. mkdir 失敗時、既存 lock の `pid` ファイルを読み、`kill -0 $PID` で生存確認。死んでいれば `rm -rf` で強制解放してリトライ。60s ごとに `waiting for lock held by pid=XXX (age=Ys)` を stderr に診断ログ出力 (→ AC2, AC3)
3. `tests/run-auto-sub.bats` に: (a) stale PID reclaim ケース（ダミー PID を書いて kill -0 失敗をエミュレート）、(b) 60s 診断ログ閾値（タイムアウトを短縮するテスト環境変数で検証） (→ AC3)
4. 全 bats テスト PASS 確認 (→ AC3)

## Verification

### Pre-merge

- <!-- verify: file_contains "scripts/run-auto-sub.sh" "claude-auto-patch-lock" --> `run-auto-sub.sh` の patch lock 処理が引き続き存在する
- <!-- verify: grep "kill -0\|stale" "scripts/run-auto-sub.sh" --> stale PID 検出ロジック (`kill -0` または `stale` キーワード) が追加されている
- <!-- verify: command "bats tests/run-auto-sub.bats" --> 既存/新規 bats テストが PASS

### Post-merge

- `/auto --batch N` で N ≥ 2 を複数回実行し、false timeout が再発しないことを確認
- lock 獲得失敗時に、保持プロセスの PID と経過秒数が診断ログに出力されることを確認

## Notes

- **設計上の判断**: `rmdir` → `rm -rf` への切替は `.DS_Store` 等の副作用ファイルを吸収するため (`rmdir` 非空時失敗問題の根本回避)。lock dir 内の想定ファイルは `pid` のみなので `rm -rf` でも安全
- **bash 3.2 互換性**: `kill -0`, `cat`, `rm -rf` すべて bash 3.2 互換
- **テスト時 timeout**: 300s はテスト実行時間が長すぎるため、環境変数 `WHOLEWORK_PATCH_LOCK_TIMEOUT` で上書き可能にする (bats テスト用に 5s 等を指定)
- **Issue body verify 更新**: AC2 の verify command を `"lock.*timeout\|timeout.*lock\|stale"` → `"kill -0\|stale"` に具体化（stale 検出ロジックを直接検証する）。これに合わせて Issue body 側も自動更新

## Code Retrospective

### Deviations from Design

- Spec では `WHOLEWORK_PATCH_LOCK_TIMEOUT` のみ明示したが、60s 診断ログをテストするために `WHOLEWORK_PATCH_LOCK_LOG_INTERVAL` も追加した。テストで 2s 間隔を使い、4s timeout で診断ログ出力を短時間で確認できるようにした。

### Design Gaps/Ambiguities

- N/A

### Rework

- N/A

## Verify Retrospective

### Phase-by-Phase Review

#### spec
- 受け入れ条件は明確かつ自動検証可能な形式（`file_contains`、`grep`、`command` hint）で設計されており、ambiguity は観察されなかった
- 観測タイムラインと調査ヒントが詳細で、原因仮説（stale empty directory、orphaned lock、race）も妥当

#### design
- 設計は実装と概ね一致。`WHOLEWORK_PATCH_LOCK_LOG_INTERVAL` の追加はテスト容易性のための小さな逸脱であり、設計判断として妥当
- `rmdir` → `rm -rf` の切替は `.DS_Store` 問題の根本回避として適切に文書化されている

#### code
- 単一コミットで実装完了（`a07e347`）。rework なし
- `WHOLEWORK_PATCH_LOCK_LOG_INTERVAL` 環境変数の追加により bats テストで短時間に診断ログ出力を検証できる設計は良い

#### review
- patch route のため formal review なし。bats テスト15件（stale PID reclaim・診断ログのテストを含む）でカバーされており、品質は確保されている

#### merge
- main 直コミット（patch route）。コンフリクトなし

#### verify
- 全3件の auto-verify 条件が PASS
- Post-merge manual 条件2件（実運用での確認）は `/auto --batch` の長時間実行が必要なため自動検証不可なのは適切
- bats テストが lock の動作を十分にカバーしており、verify コマンドとの整合性が高い

### Improvement Proposals
- N/A
