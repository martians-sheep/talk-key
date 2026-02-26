# CLAUDE.md - TalkKey プロジェクトルール

## プロジェクト概要

Mac音声入力アプリ「TalkKey」。Push-to-talkで「押して話して、離したら入力される」体験を提供する。
CoreはSwift固定、UIは将来差し替え可能。

## ドキュメント

- 仕様書: `docs/implements/mac-voice-input-spec.md`
- 実装計画: `docs/implements/implementation-plan.md`
- フェーズ別計画: `docs/implements/phase{0,1,1.5,2,3}-*.md`
- コーディング規約: `docs/coding-conventions.md`

## 開発手順（TDD: t-wata方式）

全ての実装は以下のサイクルで進める。例外なし。

1. **Red**: 失敗するテストを先に書く
2. **Green**: テストが通る最小の実装を書く（余計なコードを足さない）
3. **Refactor**: テストが通ったままコードを整理する

```
テスト作成 → テスト実行(Red確認) → 最小実装 → テスト実行(Green確認) → リファクタ → テスト実行(Green維持)
```

### TDDルール

- テストを書く前に実装コードを書かない
- 1つのテストが通るまで次のテストに進まない
- リファクタ時に新しい振る舞いを追加しない
- モックはテストターゲット内の `Mocks/` に配置する

## ビルド・テスト

```bash
# ビルド
xcodebuild -project TalkKey/TalkKey.xcodeproj -scheme TalkKey -destination 'platform=macOS' build

# テスト
xcodebuild -project TalkKey/TalkKey.xcodeproj -scheme TalkKey -destination 'platform=macOS' test
```

## ディレクトリ構成

```
TalkKey/
├── TalkKey/
│   ├── App/          # エントリポイント、AppDelegate
│   ├── Core/         # ビジネスロジック（UIに依存しない）
│   │   └── Protocols/  # Coreモジュールのプロトコル定義
│   ├── Services/     # パイプライン統合（VoiceInputService）
│   ├── UI/           # SwiftUI / AppKit ビュー
│   ├── Models/       # データ型（struct, enum）
│   └── Utilities/    # 横断的ユーティリティ
├── TalkKeyTests/
│   ├── Core/         # Coreモジュールのテスト
│   ├── Services/     # サービスのテスト
│   └── Mocks/        # テスト用モック
└── TalkKeyUITests/
```

### ファイル配置ルール

- Core層のコードはUIフレームワーク（SwiftUI, AppKit）をimportしない
- プロトコル定義は `Core/Protocols/` に置く
- モデル型は `Models/` に置く（Coreの中に置かない）
- モックは `TalkKeyTests/Mocks/` に置く（本体に含めない）
- 1ファイル1型を基本とする（関連する小さいenumは同一ファイル可）

## コミット・PR規約

**コミットメッセージ、PRタイトル・本文はすべて日本語で書く。**

```
<type>: <要約>

<詳細（任意）>
```

### type

- `feat`: 新機能
- `fix`: バグ修正
- `test`: テストの追加・修正
- `refactor`: リファクタリング（振る舞い変更なし）
- `docs`: ドキュメントのみの変更
- `chore`: ビルド設定、CI、その他雑務

### コミットのルール

- 要約は日本語、50文字以内
- TDDサイクルに合わせてこまめにコミットする（1テスト+1実装 程度の粒度もOK）

### PRのルール

- タイトルは日本語で簡潔に（70文字以内）
- 本文に変更の概要・テスト方針を日本語で記載する

## 実装時の原則

### やること

- 全Coreモジュールをプロトコルで定義し、コンストラクタインジェクションでDI
- 非同期処理は `async/await` を使う（Combine不要）
- エラーは専用のenum型（`TalkKeyError`）で統一
- フォールバックを常に用意する（LLM失敗→ローカル整形、挿入失敗→クリップボード残留）

### やらないこと

- 外部ライブラリの追加（MVPではURLSession直接利用）
- UIのテスト（Phase3の安定化まで後回し）
- 過度な抽象化（「将来使うかも」で作らない）
- Core層からのUIフレームワーク依存

## 技術的な注意事項

- **アクセシビリティ権限**: CGEvent tapに必須。MVP初期から要求する
- **SFSpeechRecognizer**: 50秒で自動停止する制限あり。タイマーで安全に止める
- **Pasteboard操作**: 挿入前に退避、挿入後に復元。他アプリのクリップボードを壊さない
- **macOS 14.0+** (Sonoma) / **Swift 5.9+** / **Xcode 15+**
