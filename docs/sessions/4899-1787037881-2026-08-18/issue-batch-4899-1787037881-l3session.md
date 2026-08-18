## Auto Retrospective
### Improvement Proposals
- Opportunistic Verification (Step 14) の単一 Issue `/verify` 実行あたりの全件スイープが、セッション内で複数回実行された際に高コスト・低歩留まりになる構造的な傾向を持つ (毎回 ~100件の候補を再検索し発見率ほぼゼロ)。`--facts`/`--context-file` フィルタリングの精度改善、または実行頻度・対象範囲の見直しを検討する
