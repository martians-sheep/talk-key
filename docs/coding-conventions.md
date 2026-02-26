# コーディング規約：TalkKey

本プロジェクトのSwiftコード規約。迷ったらこのドキュメントを参照する。

---

## 1. 命名規則

### 型名

| 種類 | 規則 | 例 |
|------|------|-----|
| struct / class | UpperCamelCase | `TranscriptionResult`, `AudioCapture` |
| enum | UpperCamelCase | `ServiceStatus`, `FormattingMode` |
| enum case | lowerCamelCase | `.idle`, `.recording`, `.bulletPoints` |
| protocol | UpperCamelCase + 役割を示す接尾辞 | `AudioCaptureProtocol`, `FormatterProtocol` |

### 変数・関数

| 種類 | 規則 | 例 |
|------|------|-----|
| 変数 / 定数 | lowerCamelCase | `rawText`, `isRecording` |
| 関数 | lowerCamelCase、動詞始まり | `startRecording()`, `format(text:mode:)` |
| Bool変数 | `is` / `has` / `should` 接頭辞 | `isRecording`, `hasPermission` |
| クロージャ引数 | 内容が自明なら省略名可 | `$0`, `entry` |

### ファイル名

- 1ファイル1型: `AudioCapture.swift`, `TranscriptionResult.swift`
- プロトコル: `AudioCaptureProtocol.swift`
- テスト: `AudioCaptureTests.swift`
- モック: `MockAudioCapture.swift`

---

## 2. プロトコル設計

### 基本方針

Coreモジュールは必ずプロトコルを定義してから実装する。

```swift
// Core/Protocols/AudioCaptureProtocol.swift
protocol AudioCaptureProtocol {
    func startCapture() throws
    func stopCapture() -> AVAudioPCMBuffer?
    var isCapturing: Bool { get }
}

// Core/AudioCapture.swift
final class AudioCapture: AudioCaptureProtocol {
    // 実装
}
```

### ルール

- プロトコルには最小限のインタフェースのみ定義する（実装詳細を漏らさない）
- `@MainActor` はUI層でのみ使う。Coreプロトコルには付けない
- プロトコルの関数にはデフォルト実装を与えない（明示的な実装を強制）

---

## 3. DI（依存性注入）

コンストラクタインジェクションを使う。プロパティインジェクションは使わない。

```swift
// Good
final class VoiceInputService {
    private let audioCapture: AudioCaptureProtocol
    private let transcriber: TranscriberProtocol
    private let formatter: FormatterProtocol
    private let inserter: InserterProtocol

    init(
        audioCapture: AudioCaptureProtocol,
        transcriber: TranscriberProtocol,
        formatter: FormatterProtocol,
        inserter: InserterProtocol
    ) {
        self.audioCapture = audioCapture
        self.transcriber = transcriber
        self.formatter = formatter
        self.inserter = inserter
    }
}

// Bad: プロパティインジェクション
final class VoiceInputService {
    var audioCapture: AudioCaptureProtocol!  // 使わない
}
```

---

## 4. async/await パターン

### 基本方針

- 非同期処理は `async/await` を使う
- Combine は使わない（依存を最小化）
- コールバック（completion handler）ではなく async に統一

### パターン

```swift
// 非同期関数の定義
func stopRecording() async throws -> TranscriptionResult {
    let buffer = audioCapture.stopCapture()
    guard let buffer else {
        throw TalkKeyError.recognitionFailed(reason: "No audio buffer")
    }
    return try await transcriber.transcribe(buffer: buffer)
}

// タイムアウト付きの非同期処理
func formatWithTimeout(text: String, timeout: Duration = .seconds(2.5)) async throws -> String {
    try await withThrowingTaskGroup(of: String.self) { group in
        group.addTask {
            try await self.llmFormatter.format(text: text, mode: .memo)
        }
        group.addTask {
            try await Task.sleep(for: timeout)
            throw TalkKeyError.formattingFailed(reason: "LLM timeout")
        }
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}
```

### ルール

- `Task { }` の無秩序な生成を避ける。ライフサイクルが明確な場所でのみ使う
- `@Sendable` を意識する。Core層のプロトコルメソッドは `Sendable` 準拠を前提とする
- テストでは `async` テストメソッドを使う（`func testXxx() async throws`）

---

## 5. エラーハンドリング

### TalkKeyError

全エラーを1つの enum に集約する。

```swift
enum TalkKeyError: LocalizedError {
    case permissionDenied(permission: Permission)
    case recognitionFailed(reason: String)
    case formattingFailed(reason: String)
    case insertionFailed(reason: String)
    case rateLimitExceeded

    var errorDescription: String? {
        switch self {
        case .permissionDenied(let permission):
            return "\(permission.displayName)の権限が必要です"
        case .recognitionFailed(let reason):
            return "音声認識に失敗しました: \(reason)"
        case .formattingFailed(let reason):
            return "テキスト整形に失敗しました: \(reason)"
        case .insertionFailed(let reason):
            return "テキスト挿入に失敗しました: \(reason)"
        case .rateLimitExceeded:
            return "音声認識の利用制限に達しました。しばらく待ってから再試行してください"
        }
    }
}
```

### ルール

- `try!` / `try?` は原則禁止。`try?` は明示的にフォールバック処理がある場合のみ許可
- `fatalError()` はプログラミングエラー（到達不能コード）のみ。ランタイムエラーには使わない
- フォールバックがある箇所はコメントで理由を書く

```swift
// LLM整形失敗時はローカル整形結果をフォールバックとして使用
let formatted = try? await llmFormatter.format(text: text, mode: mode)
return formatted ?? localFormatted
```

---

## 6. テストコード

### ファイル構成

```
TalkKeyTests/
├── Core/
│   ├── LocalFormatterTests.swift    # ユニットテスト
│   └── ...
├── Services/
│   └── VoiceInputServiceTests.swift # 結合テスト（モック経由）
└── Mocks/
    ├── MockAudioCapture.swift
    └── ...
```

### テストの命名

```swift
// パターン: test_<対象>_<条件>_<期待結果>
func test_format_withFillerWords_removesFillers() async throws { }
func test_stopRecording_afterTimeout_returnsPartialResult() async throws { }
func test_insert_withEmptyText_skipsInsertion() async throws { }
```

### モックの書き方

呼び出し記録 + 戻り値の注入を両立する。

```swift
final class MockTranscriber: TranscriberProtocol {
    // 呼び出し記録
    var transcribeCallCount = 0
    var lastBuffer: AVAudioPCMBuffer?

    // 戻り値の注入
    var transcribeResult: TranscriptionResult?
    var transcribeError: Error?

    func transcribe(buffer: AVAudioPCMBuffer) async throws -> TranscriptionResult {
        transcribeCallCount += 1
        lastBuffer = buffer
        if let error = transcribeError { throw error }
        return transcribeResult ?? TranscriptionResult(rawText: "mock", formattedText: nil, timestamp: Date(), duration: 0)
    }
}
```

### テストのルール

- Arrange / Act / Assert の3ブロックで構成する（空行で区切る）
- 1テスト1アサーションを基本とする（関連する複数アサーションは許可）
- テスト間の依存を作らない（各テストは独立して実行可能）
- テスト内でsleepしない。非同期待ちには `async/await` を使う

```swift
func test_insert_preservesClipboard() async throws {
    // Arrange
    let mockPasteboard = MockPasteboard(initialContent: "original")
    let inserter = Inserter(pasteboard: mockPasteboard)

    // Act
    try await inserter.insert(text: "voice input")

    // Assert
    XCTAssertEqual(mockPasteboard.currentContent, "original")
}
```

---

## 7. アクセス制御

| レベル | 使い方 |
|--------|--------|
| `public` | 使わない（フレームワークではないため） |
| `internal` | デフォルト。明示不要 |
| `private` | クラス/構造体の内部実装 |
| `fileprivate` | 原則使わない |

- プロトコルのメソッドは `internal`（デフォルト）
- 実装クラスの内部状態は `private`
- テストからアクセスが必要な場合は `@testable import` で対応

---

## 8. その他のスタイル

### Guard Early Return

ネストを減らすために `guard` で早期リターンする。

```swift
// Good
func transcribe(buffer: AVAudioPCMBuffer?) async throws -> TranscriptionResult {
    guard let buffer else {
        throw TalkKeyError.recognitionFailed(reason: "No audio buffer")
    }
    // メイン処理
}

// Bad: ネストが深い
func transcribe(buffer: AVAudioPCMBuffer?) async throws -> TranscriptionResult {
    if let buffer {
        // メイン処理
    } else {
        throw TalkKeyError.recognitionFailed(reason: "No audio buffer")
    }
}
```

### マジックナンバー禁止

定数は名前付きで定義する。

```swift
// Good
private enum Constants {
    static let maxRecordingDuration: TimeInterval = 50
    static let pasteboardRestoreDelay: Duration = .milliseconds(100)
    static let llmTimeoutDuration: Duration = .seconds(2.5)
    static let maxLLMInputLength = 2000
    static let maxHistoryCount = 10
}

// Bad
if duration > 50 { ... }
try await Task.sleep(for: .milliseconds(100))
```

### コメント

- コードで意図が明確なら書かない
- 「なぜ」を書く。「何をしているか」は書かない
- TODO コメントは `// TODO: [Phase X] 説明` の形式

```swift
// Good: なぜこのディレイが必要かを説明
// Cmd+V送出後にPasteboardを復元するまでの猶予。短すぎると貼り付け前に復元されてしまう
try await Task.sleep(for: Constants.pasteboardRestoreDelay)

// Bad: 自明なことを書いている
// Pasteboardにテキストをセットする
pasteboard.setString(text, forType: .string)
```
