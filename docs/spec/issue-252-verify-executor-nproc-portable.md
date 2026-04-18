# Issue #252: verify-executor: nproc コマンド未インストール環境での command ヒント実行をポータブルに

## Overview

`command` ヒントに `$(nproc)` が含まれる場合、macOS 環境では `nproc` が未インストールのためコマンド展開に失敗し、検証が実行できない。`modules/verify-executor.md` の `command` 行にポータビリティガイダンスを追記し、Issue 作成者がポータブルな記述を選べるようにする。

## Reproduction Steps

1. macOS 環境で `<!-- verify: command "bats --jobs $(nproc) tests/*.bats" -->` を含む Issue に対して `/verify` を実行
2. `$(nproc)` の展開で `command not found: nproc` が発生し、`command` ヒントが実行できない

## Root Cause

`nproc` は Linux 固有のコマンドで macOS には標準インストールされていない。`verify-executor.md` に macOS 非互換コマンドへの対処方針が記述されていないため、Issue 作成者がポータブルな代替記述を知る手段がなかった。

## Changed Files

- `modules/verify-executor.md`: 翻訳テーブルの `command` 行に `nproc` 非互換の説明と macOS 代替コマンド（`sysctl -n hw.logicalcpu`）およびポータブル one-liner の推奨記述を追加 — bash 3.2+ compatible

## Implementation Steps

1. `modules/verify-executor.md` の翻訳テーブル `command` 行を編集し、既存の `**Note**`（`find` による glob ポータビリティ注記）の直後に以下を追記する（→ 受入条件 A, B）:
   - `nproc` が Linux 固有（macOS 未インストール）であることを明示
   - macOS 代替: `$(sysctl -n hw.logicalcpu)`
   - ポータブル one-liner: `$(nproc 2>/dev/null || sysctl -n hw.logicalcpu)`
   - 例: `bats --jobs $(nproc 2>/dev/null || sysctl -n hw.logicalcpu) tests/*.bats`

## Verification

### Pre-merge

- <!-- verify: file_contains "modules/verify-executor.md" "nproc" --> verify-executor.md に `nproc` の代替処理またはポータブル化に関する記述が追加される
- <!-- verify: grep "sysctl" "modules/verify-executor.md" --> macOS 代替コマンド（`sysctl -n hw.logicalcpu`）への言及が verify-executor.md に存在する

### Post-merge

- macOS 環境で `<!-- verify: command "bats --jobs $(nproc) tests/*.bats" -->` を含む Issue に対して `/verify N` を実行し、コマンドが失敗せず（UNCERTAIN または代替実行で）検証完了することを確認

## Notes

- 追記位置は `command` 行の既存 Note（glob ポータビリティ注記）の直後が最も文脈的に適切と判断（自動解決済み）
- `bats --jobs N` の GNU parallel 依存（macOS でのシーケンシャル fallback）は Non-Goal（別 Issue で追跡）
