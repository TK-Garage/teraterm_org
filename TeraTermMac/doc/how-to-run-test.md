# testElseIfChain_MatchSecondBranch テストの実行方法

## Xcode から

1. `TeraTermMac` プロジェクトを Xcode で開く
2. `TTLControlFlowTests.swift` を開く
3. `testElseIfChain_MatchSecondBranch` の左側の菱形アイコンをクリック

または、Product → Test (⌘U) で全テスト実行。

## コマンドラインから (macOS)

```bash
cd TeraTermMac
swift test --filter TTLControlFlowTests/testElseIfChain_MatchSecondBranch
```

全 elseif テストをまとめて実行する場合：

```bash
swift test --filter TTLControlFlowTests/testElseIfChain
```
