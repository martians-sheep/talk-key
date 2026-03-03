# TalkKey

macOS向けの音声入力アプリ。**押して話して、離したら入力される** Push-to-talk体験を提供します。

## 特徴

- **Push-to-talk方式** - グローバルホットキーで、どのアプリでも音声入力が可能
- **Apple標準の音声認識** - SFSpeechRecognizerによる日本語ストリーミング認識
- **テキスト整形** - ローカルルール整形 + LLM整形（Gemini Flash等）に対応
- **フォールバック設計** - LLM失敗時はローカル整形で続行、挿入失敗時はクリップボードに残留
- **メニューバー常駐** - 状態表示（待機/録音中/処理中）とクイックアクセス
- **履歴管理** - 直近の入力履歴から再コピー可能

## 動作環境

- macOS 14.0+（Sonoma）
- Xcode 15+
- Swift 5.9+

## 必要な権限

| 権限 | 用途 |
| --- | --- |
| マイク | 音声の録音 |
| 音声認識 | SFSpeechRecognizerによる文字起こし |
| アクセシビリティ | グローバルホットキー検知（CGEvent tap） |

## セットアップ

```bash
git clone https://github.com/martians-sheep/talk-key.git
cd talk-key
```

Xcode でプロジェクトを開く:

```bash
open TalkKey/TalkKey.xcodeproj
```

## ビルド

```bash
# デバッグビルド
xcodebuild -project TalkKey/TalkKey.xcodeproj -scheme TalkKey -destination 'platform=macOS' build

# Releaseビルド
xcodebuild -project TalkKey/TalkKey.xcodeproj -scheme TalkKey -configuration Release -destination 'platform=macOS' build
```

## テスト

```bash
xcodebuild -project TalkKey/TalkKey.xcodeproj -scheme TalkKey -destination 'platform=macOS' test
```

## アーキテクチャ

CoreはSwift固定、UIは将来差し替え可能な構造で設計しています。

```text
┌─────────────────────────────────────────────┐
│  UI Layer (SwiftUI / AppKit)                │
│  MenuBar / Settings / History               │
├─────────────────────────────────────────────┤
│  Service Layer                              │
│  VoiceInputService (async pipeline)         │
├─────────────────────────────────────────────┤
│  Core Layer (Protocol-based, testable)      │
│  AudioCapture / Transcriber / Inserter      │
│  LocalFormatter / LLMFormatter              │
│  HotkeyManager / HistoryStore               │
└─────────────────────────────────────────────┘
```

### ディレクトリ構成

```text
TalkKey/
├── TalkKey/
│   ├── App/          # エントリポイント、AppDelegate
│   ├── Core/         # ビジネスロジック（UIに依存しない）
│   │   └── Protocols/  # Coreモジュールのプロトコル定義
│   ├── Services/     # パイプライン統合（VoiceInputService）
│   ├── UI/           # SwiftUI / AppKit ビュー
│   ├── Models/       # データ型（struct, enum）
│   └── Utilities/    # 横断的ユーティリティ
├── TalkKeyTests/     # ユニットテスト・モック
└── TalkKeyUITests/   # UIテスト
```

## 使い方

1. アプリを起動するとメニューバーに常駐します
2. 初回起動時に必要な権限（マイク・音声認識・アクセシビリティ）を許可してください
3. 設定したホットキーを**押している間**、録音が行われます
4. ホットキーを**離す**と、文字起こし → 整形 → アクティブなアプリへ貼り付けが行われます

### メニュー操作

- **LLM整形 ON/OFF** - 外部LLMによるテキスト整形の切り替え
- **履歴** - 直近の入力履歴を表示・再コピー
- **Settings** - ホットキー、LLM設定、APIキーなどの変更

## 開発方針

- **TDD（Red → Green → Refactor）** を厳守
- 全CoreモジュールはProtocolで定義し、DIでテスト可能に
- 非同期処理は `async/await` を使用
- 外部ライブラリは最小限（MVPではURLSession直接利用）

詳細は [CLAUDE.md](CLAUDE.md) を参照してください。
