# 計画

ストーリーごとの計画([テンプレート](../templates/plan.md))を置く。プランニング skill(`.claude/skills/planning/`)が書き出す。
置き場所を決めた理由は [HADR-0004](../harness/adr/0004-plan-location.md) にある。

- **ここにある計画は、書いた時点の記録であり、今の仕様ではない。** 今の仕様は `mise run docs:spec` でテストから引く(仕様の正本はテスト。[HADR-0002](../harness/adr/0002-tests-as-specification.md))。
- ファイル名は `<ストーリーの短い英語名>.md`。
- テストや実装と同じ作業ブランチでコミットし、PR 概要からリンクする。
- 計画ができたら、計画だけでドラフトの PR を開き、ゲート 1 のレビューを受ける([HADR-0006](../harness/adr/0006-gate1-draft-pr.md))。
- マージした後は更新しない。続きの変更は新しい計画にする。
