"""テストから仕様一覧を生成し、計画のテストケース一覧と照合する。

テストが仕様の正本である(docs/harness/adr/0002-tests-as-specification.md)ことを支える道具。
- pytest_plugin: テストを収集し、ID・テスト名・パラメータ・why を JSON に書き出す
- spec: 収集結果を仕様の行(SpecItem)に解釈する
- render: 仕様一覧を Markdown にする(docs:spec)
- plan / verify: 計画のテストケース一覧を読み、仕様と照合する(plan:verify)
"""
