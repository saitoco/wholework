# Issue #132: gh-label-transition: target ラベルの消失バグを修正

## Overview

`scripts/gh-label-transition.sh` の else 分岐で、target ラベル自身が `--remove-label` リストに含まれてしまう。これにより `gh issue edit --remove-label X --add-label X` の形となり、GitHub API の「add 後に remove」処理で target ラベルが消失する。

if 分岐（target ラベルが既に設定済みのケース、line 62-65）には除外ガードが存在するが、else 分岐（通常遷移フロー、line 70-73）には同様のガードがない。else 分岐にも同じ guard を追加し、バグを修正する。

## Reproduction Steps

1. Issue に `phase/spec` が設定された状態で `scripts/gh-label-transition.sh <number> ready` を実行
2. GitHub API が `--add-label phase/ready --remove-label phase/ready` を受信
3. `phase/ready` が add 後に remove され、ラベルが消失する

## Root Cause

`scripts/gh-label-transition.sh` の else 分岐（line 70-73）で、`PHASE_LABELS` を全てループして `--remove-label` を構築する際に、`TARGET_LABEL` を除外する条件がない。

if 分岐（line 62-65）は `if [ "$label" != "$TARGET_LABEL" ]; then` で除外しているが、else 分岐には同様の guard がなかった。fix として else 分岐にも同じ guard を追加する。

## Changed Files

- `scripts/gh-label-transition.sh`: else 分岐（line 70-73）の for ループに `if [ "$label" != "$TARGET_LABEL" ]; then` guard を追加
- `tests/gh-label-transition.bats`: else 分岐で target ラベルが `--remove-label` に含まれないことを検証する回帰テストケースを追加

## Implementation Steps

1. `scripts/gh-label-transition.sh` の else 分岐（line 70-73）を修正: `REMOVE_ARGS+=(--remove-label "$label")` の前に `if [ "$label" != "$TARGET_LABEL" ]; then` guard を追加し、`fi` で閉じる。if 分岐（line 62-65）のパターンを参考にする。(→ 受け入れ基準 1)

2. `tests/gh-label-transition.bats` の末尾に回帰テストケースを追加: `phase/spec` が現在ラベルとして返す mock を用意し、`run bash "$SCRIPT" 42 ready` を実行後、`--add-label phase/ready` が記録され、`--remove-label phase/ready` が記録されないことを assert する。(→ 受け入れ基準 2)

## Verification

### Pre-merge

- <!-- verify: grep 'if \[ "$label" != "$TARGET_LABEL" \]' "scripts/gh-label-transition.sh" --> `scripts/gh-label-transition.sh` の else 分岐でも target ラベル除外ロジックが適用されている
- <!-- verify: command "bats tests/gh-label-transition.bats" --> 通常遷移フロー（else 分岐）での target ラベル非除去を検証する回帰テストケースが `tests/gh-label-transition.bats` に追加され、全 bats テストが PASS する

### Post-merge

- `/spec` 実行後に `phase/ready` ラベルが確実に付与される
- `/auto` 実行中にラベル消失による連鎖的な fallback が発生しない

## Notes

- if 分岐（line 59）の既存 guard は「target ラベルが既に設定済み」ケースのみカバーしており、else 分岐には適用されていない。今回の fix で else 分岐も同じ除外ロジックを持つようになり、2つの分岐のパターンが一致する
- 関連: Issue #39 で冪等性（target ラベルが既に設定済みのケース）を修正済み。今回は「通常遷移時」の同種バグ
- `TARGET_PHASE=""` 時（ラベル削除のみの呼び出し）: `TARGET_LABEL="phase/"` は `PHASE_LABELS` に一致しないため、追加した guard は no-op として安全
