# 実装計画：Mac音声入力アプリ "TalkKey"

## 概要

macOS上で「押して話して、離したら入力される」音声入力体験を提供するメニューバー常駐アプリ。
CoreはSwift固定、UIは将来差し替え可能な構造で実装する。

---

## 設計原則

1. **「賢さ」より「気持ちよさ」** - Push-to-talkの成功率が最優先
2. **Core/UI分離** - CoreモジュールはUIに依存しない。将来Electron/Tauriへ差し替え可能
3. **TDD** - テストを先に書き、テストが通る最小の実装を行う（t-wata方式）
4. **フォールバック前提** - LLM失敗→ローカル整形、挿入失敗→クリップボード残留

---

## アーキテクチャ

```
┌─────────────────────────────────────────────┐
│  UI Layer (SwiftUI / AppKit)                │
│  ┌──────────┐ ┌──────────┐ ┌─────────────┐ │
│  │MenuBar   │ │Settings  │ │HistoryView  │ │
│  └──────────┘ └──────────┘ └─────────────┘ │
├─────────────────────────────────────────────┤
│  App Layer (Orchestration)                  │
│  ┌──────────────────────────────────────┐   │
│  │ VoiceInputService (async pipeline)  │   │
│  │ startRecording()                    │   │
│  │ stopRecording() async -> Result     │   │
│  └──────────────────────────────────────┘   │
├─────────────────────────────────────────────┤
│  Core Layer (Protocol-based, testable)      │
│  ┌────────────┐ ┌────────────────────────┐  │
│  │AudioCapture│ │Transcriber             │  │
│  │(AVAudio)   │ │(SFSpeechRecognizer)    │  │
│  └────────────┘ │ストリーミング認識       │  │
│                 └────────────────────────┘  │
│  ┌──────────────┐ ┌────────────────────┐    │
│  │LocalFormatter│ │LLMFormatter        │    │
│  │(ルール整形)   │ │(Gemini Flash等)    │    │
│  │              │ │timeout + fallback   │    │
│  └──────────────┘ └────────────────────┘    │
│  ┌────────────┐ ┌────────────────────────┐  │
│  │Inserter    │ │HistoryStore            │  │
│  │(Pasteboard │ │(UserDefaults/JSON)     │  │
│  │ +Cmd+V     │ │直近N件                 │  │
│  │ +退避復元)  │ └────────────────────────┘  │
│  └────────────┘                             │
│  ┌────────────────────────────────────────┐  │
│  │HotkeyManager (CGEvent tap)            │  │
│  │Push-to-talk: keyDown/keyUp検知        │  │
│  │※アクセシビリティ権限が必須             │  │
│  └────────────────────────────────────────┘  │
└─────────────────────────────────────────────┘
```

---

## 技術的決定事項（レビュー反映済み）

### 1. 音声認識：ストリーミング方式を採用

- `SFSpeechAudioBufferRecognitionRequest` でストリーミング認識
- `stopRecording()` 時点で既に途中結果を保持 → 体感遅延を最小化
- 逐次表示UIはPhase2以降。裏でストリーミングするだけでも効果大

### 2. クリップボード退避・復元

`Inserter` モジュール内で以下のフローを実装：
1. 現在のPasteboardを退避
2. テキストをPasteboardにセット
3. `Cmd+V` 送出
4. 短いディレイ（~100ms）後にPasteboardを復元

### 3. グローバルホットキー：CGEvent tap

- `CGEvent tap` を採用（keyDown/keyUp検知が可能でPush-to-talkに最適）
- **アクセシビリティ権限がMVPから必須**になる（仕様書の「任意」から変更）
- 権限要件の整理：
  - **必須**：マイク、Speech認識、**アクセシビリティ**
  - 任意：なし（Phase2でもAX権限は既に取得済み）

### 4. SFSpeechRecognizer の制約対応

- 録音時間上限：**50秒で自動停止** + ユーザー通知
- レート制限エラー時：エラーハンドリング + ユーザー通知
- オンデバイス認識の可否チェック（`supportsOnDeviceRecognition`）

### 5. Core APIは非同期設計

```swift
protocol VoiceInputServiceProtocol {
    func startRecording() throws
    func stopRecording() async throws -> TranscriptionResult
    func format(text: String, mode: FormattingMode) async throws -> String
    func insert(text: String) async throws
    func recentHistory() -> [HistoryEntry]
    func status() -> ServiceStatus
}
```

### 6. テスト方針（TDD）

- **Red → Green → Refactor** サイクルを厳守
- 各Coreモジュールは**プロトコルで定義**し、DIでモック差し替え可能にする
- `LocalFormatter`：ユニットテスト必須（ルールベース）
- `LLMFormatter`：プロトコル化してモックテスト
- `Inserter`：Pasteboard操作のユニットテスト
- `HotkeyManager`：イベント生成のモックテスト
- 結合テスト：パイプライン全体のモックテスト

### 7. 用語定義

| 用語 | 定義 |
|------|------|
| **最小動作版** | Phase 0〜1.5 完了時点。ホットキー録音→貼り付けが動く |
| **MVP** | Phase 0〜3 完了時点。仕様書の受け入れ条件をすべて満たす |
| **Phase2拡張** | 仕様書の「Phase2」。AX直接挿入、辞書、UI差し替え等 |

---

## フェーズ一覧

| Phase | 名称 | ゴール | 主要成果物 |
|-------|------|--------|-----------|
| **0** | 土台構築 | プロジェクト構造・権限・メニューバー・Core分割 | Xcodeプロジェクト、プロトコル定義、メニューバーUI、権限管理 |
| **1** | 音声パイプライン | Push-to-talk → ストリーミング文字起こし完成 | AudioCapture、Transcriber、HotkeyManager、50秒制限 |
| **1.5** | テキスト挿入 | 「話す→入る」体験の完成 | Inserter（退避・復元付き）、パイプライン結合 |
| **2** | 整形 | ローカル整形 + LLM整形（タイムアウト/フォールバック） | LocalFormatter、LLMFormatter、モード切替 |
| **3** | 履歴・安定化 | MVP完成（仕様書の受け入れ条件を満たす） | HistoryStore、Keychain、エラーハンドリング強化、安定化 |

---

## ディレクトリ構成（想定）

```
TalkKey/
├── TalkKey.xcodeproj
├── TalkKey/
│   ├── App/
│   │   ├── TalkKeyApp.swift          # エントリポイント
│   │   └── AppDelegate.swift         # メニューバー管理
│   ├── Core/
│   │   ├── Protocols/
│   │   │   ├── AudioCaptureProtocol.swift
│   │   │   ├── TranscriberProtocol.swift
│   │   │   ├── FormatterProtocol.swift
│   │   │   ├── InserterProtocol.swift
│   │   │   └── HistoryStoreProtocol.swift
│   │   ├── AudioCapture.swift
│   │   ├── Transcriber.swift
│   │   ├── LocalFormatter.swift
│   │   ├── LLMFormatter.swift
│   │   ├── Inserter.swift
│   │   ├── HistoryStore.swift
│   │   └── HotkeyManager.swift
│   ├── Services/
│   │   └── VoiceInputService.swift    # パイプライン統合
│   ├── UI/
│   │   ├── MenuBarView.swift
│   │   ├── SettingsView.swift
│   │   └── HistoryView.swift
│   ├── Models/
│   │   ├── TranscriptionResult.swift
│   │   ├── FormattingMode.swift
│   │   ├── HistoryEntry.swift
│   │   └── ServiceStatus.swift
│   └── Utilities/
│       ├── PermissionManager.swift
│       └── KeychainHelper.swift
├── TalkKeyTests/
│   ├── Core/
│   │   ├── AudioCaptureTests.swift
│   │   ├── TranscriberTests.swift
│   │   ├── LocalFormatterTests.swift
│   │   ├── LLMFormatterTests.swift
│   │   ├── InserterTests.swift
│   │   ├── HistoryStoreTests.swift
│   │   └── HotkeyManagerTests.swift
│   ├── Services/
│   │   └── VoiceInputServiceTests.swift
│   └── Mocks/
│       ├── MockAudioCapture.swift
│       ├── MockTranscriber.swift
│       ├── MockFormatter.swift
│       ├── MockInserter.swift
│       └── MockHistoryStore.swift
└── TalkKeyUITests/
    └── ...
```

---

## 依存関係

- **macOS 14.0+**（Sonoma以降。SFSpeechRecognizerのオンデバイス認識対応）
- **Swift 5.9+** / **Xcode 15+**
- 外部ライブラリ：MVPでは最小限（LLM API通信はURLSession直接利用）

---

## リスクと対策

| リスク | 影響 | 対策 |
|--------|------|------|
| SFSpeechRecognizer のレート制限 | 連続使用でブロック | エラー検知 + クールダウン表示 + リトライ間隔制御 |
| CGEvent tap の権限拒否 | アプリが機能しない | 初回起動時に分かりやすい権限誘導UI |
| Cmd+V が効かないアプリ | 挿入失敗 | クリップボード残留 + 通知で手動貼り付け誘導 |
| LLM API の遅延/障害 | 体験が止まる | タイムアウト（2〜3秒）+ ローカル整形フォールバック |
| ストリーミング認識の途中結果不安定 | 最終結果と乖離 | `isFinal` フラグで最終結果のみ採用 |

---

## 各フェーズの詳細

各フェーズの詳細なタスクリストとDoDは以下のファイルを参照：

- [Phase 0: 土台構築](./phase0-foundation.md)
- [Phase 1: 音声パイプライン](./phase1-voice-pipeline.md)
- [Phase 1.5: テキスト挿入](./phase1.5-text-insertion.md)
- [Phase 2: 整形](./phase2-formatting.md)
- [Phase 3: 履歴・安定化](./phase3-history-stabilization.md)
