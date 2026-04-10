# Issue #70: skill: effort 最適化戦略の調査（advisor tool / effort パラメータ）

## Overview

Claude Code CLI（`claude -p`）での advisor tool（`advisor_20260301`）および `--effort` パラメータのサポート状況を調査し、Wholework の effort 最適化 3 軸戦略の対応方針を `docs/tech.md` の Architecture Decisions セクションに記録する。

調査結果（Spec 作成時に確認済み）:

| 対象 | 利用可否 | 詳細 |
|------|---------|------|
| `--effort` パラメータ | 利用可能 | `claude -p` が `low/medium/high/max` をサポート（`claude --help` で確認） |
| advisor tool (`advisor_20260301`) | 条件付き | Anthropic API beta（`advisor-tool-2026-03-01` ヘッダー必須）。`--betas` フラグで有効化可能だが API キーユーザーのみ。OAuth/サブスクリプション認証（`run-*.sh` のデフォルト）では利用不可 |

## Changed Files

- `docs/tech.md`: Architecture Decisions セクションに effort 最適化 3 軸戦略エントリーを追加

## Implementation Steps

1. `claude --help` で `--effort` オプション（low/medium/high/max）が `claude -p` で利用可能であることを確認し、また `--betas` オプション（API キーユーザーのみ）経由での advisor tool 有効化の制約を確認する（→ 受入条件 A、B）

2. `docs/tech.md` の `## Architecture Decisions` セクションに以下の内容を追記する（→ 受入条件 A、B、C）:
   - **Effort optimization strategy (3 axes)**: 3 軸それぞれの CLI サポート状況と Wholework での適用方針
     - Axis 1 — Model selection: `--model` フラグ経由ですでに実装済み（Sonnet デフォルト、`run-spec.sh --opus` で Opus に切替可能）
     - Axis 2 — Adaptive Thinking (`--effort`): `claude -p` が `low/medium/high/max` をサポート。現在 `run-*.sh` では未使用。medium effort + Opus advisor の組み合わせでデフォルト effort の Sonnet と同等品質をより低コストで実現可能（Anthropic 公表値）
     - Axis 3 — Advisor strategy (`advisor_20260301`): Anthropic API beta (`advisor-tool-2026-03-01` ヘッダー必須)。`claude` CLI の `--betas` フラグ（API キーユーザーのみ）経由で有効化可能。OAuth/サブスクリプション認証では利用不可。Sonnet+Opus advisor で SWE-bench +2.7pp・コスト −11.9%（vs Sonnet 単体）、Haiku+Opus advisor で BrowseComp 41.2%（ソロ 19.7%）・コスト −85%（vs Sonnet）。`run-*.sh` への実装は follow-up Issue で対応

## Verification

### Pre-merge

- <!-- verify: file_contains "docs/tech.md" "advisor" --> `claude -p` で advisor tool（`advisor_20260301`）が利用可能かを調査し、結果を `docs/tech.md` に記録する
- <!-- verify: file_contains "docs/tech.md" "effort" --> `claude -p` で `--effort` パラメータが利用可能かを調査し、結果を `docs/tech.md` に記録する
- <!-- verify: section_contains "docs/tech.md" "## Architecture Decisions" "effort" --> 調査結果に基づき、3軸（model + effort + advisor）の対応方針を `docs/tech.md` の `## Architecture Decisions` セクションに記載する

### Post-merge

- `docs/tech.md` Architecture Decisions セクションに "Effort optimization strategy (3 axes)" エントリーが追加されていることを確認

## Notes

- `--betas` フラグは「API key users only」のため、OAuth/Claude サブスクリプション認証（`run-*.sh` デフォルト）では advisor tool は利用不可
- advisor tool はモデルが自律的に呼び出すツールであり、CLI フラグではない点に注意
- `docs/tech.md` Architecture Decisions の既存エントリー形式（バレット + 太字ヘッダー + 説明）に合わせて追記すること
- Auto-resolved ambiguity: `docs/tech.md` への記述形式は既存エントリーと同形式（バレット＋太字ヘッダー）で追記（根拠: tech.md の既存パターン）
- Auto-resolved ambiguity: Follow-up Issue の作成は本 Issue のスコープ外（「候補」として Background に記載済み）

## Code Retrospective

### Deviations from Design
- N/A

### Design Gaps/Ambiguities
- N/A

### Rework
- N/A
