# Issue #223: /review --ultra Option Spike

## Overview

Spike to evaluate the value of adding a `--ultra` option to `/review`. Claude Opus 4.7 introduced an "ultrareview command" — a dedicated deep-dive code review capability. This spike compares ultrareview vs. the existing `--full` mode on quality / cost / time axes and produces a written recommendation for or against adopting `--ultra` as a new `/review` depth mode.

Current `/review` modes: `--light` (1-agent: review-light/Sonnet) and `--full` (3-agent: review-spec/Opus + review-bug×2/Opus). The spike evaluates whether ultrareview offers meaningful uplift over `--full` to justify the integration effort.

Reference: `docs/reports/claude-opus-4-7-optimization-strategy.md` §2.3, §5.3 #9.

## Changed Files

- `docs/reports/ultrareview-spike.md`: new file — spike report with Overview, Comparison (quality/cost/time vs `--full`), and Recommendation sections

## Implementation Steps

1. Research ultrareview command: WebFetch Anthropic documentation (Claude Code CLI reference, Opus 4.7 release notes, GitHub changelog) to determine the ultrareview interface, capabilities, and any configuration options (→ Comparison section)
2. Analyze current `/review --full` baseline: read `skills/review/SKILL.md` and `agents/review-spec.md`, `agents/review-bug.md` to characterize depth, agent configuration, estimated token cost, and typical execution time (→ Comparison section)
3. Compose and save `docs/reports/ultrareview-spike.md` with: `## Overview`, `## Comparison` (quality / cost / time table comparing `--full` and ultrareview), and `## Recommendation` (採用/非採用 + rationale and, if adopted, proposed skill/agent layout) (→ all 3 acceptance criteria)

## Verification

### Pre-merge

- <!-- verify: file_exists "docs/reports/ultrareview-spike.md" --> スパイクレポート `docs/reports/ultrareview-spike.md` が作成されている
- <!-- verify: section_contains "docs/reports/ultrareview-spike.md" "Comparison" "--full" --> `Comparison` セクションに既存 `--full` モードとの比較結果が記載されている
- <!-- verify: section_contains "docs/reports/ultrareview-spike.md" "Recommendation" "採用" --> `Recommendation` セクションに採用可否の結論と理由が記載されている

### Post-merge

- 採用決定の場合、`/review --ultra` の本実装 Issue を起票する
- 非採用の場合、理由がレポートに記録されている

## Notes

- ultrareview command の詳細は WebFetch で Anthropic 公式ドキュメントを確認する。公式ドキュメントが見つからない場合は、optimization strategy レポート §2.3 の記述をベースに理論的分析を行い、その旨をレポートに明記する
- `## Recommendation` セクションに「採用」または「非採用」が含まれていれば `section_contains ... "採用"` が PASS する（どちらの結論でも acceptance criteria を満たす）
- Auto-resolve (non-interactive): 実装 Step 1 で ultrareview の公式仕様が確認できない場合は、利用可能な情報に基づく定性的分析を行い、不確実性をレポートに明記する（ハードエラーとしない）
