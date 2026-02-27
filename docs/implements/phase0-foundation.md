# Phase 0: 土台構築

## ゴール

Xcodeプロジェクトの作成、Core層のプロトコル定義、メニューバーUI、権限管理の土台を作る。
このフェーズ完了時点で「アプリが起動し、メニューバーに常駐し、権限状態を表示できる」状態になる。

---

## TDD方針

- プロトコル定義 → モック作成 → テストコード → 実装 の順で進める
- Phase 0 ではUIテストよりもCoreプロトコルのコンパイル確認とモックの正常動作を優先

---

## タスクリスト

### 0-1. Xcodeプロジェクト作成

- [x] macOS App プロジェクト「TalkKey」を作成（SwiftUI、macOS 14.0+）
- [x] メニューバー常駐アプリとして設定（`LSUIElement = YES`）
- [x] ディレクトリ構成を作成（App / Core / Services / UI / Models / Utilities）
- [x] テストターゲット（TalkKeyTests）を作成
- [x] `.gitignore` にXcode関連の除外設定を追加

### 0-2. モデル定義

- [x] **テスト**: `TranscriptionResult` の生成・プロパティアクセスのテストを書く
- [x] **実装**: `TranscriptionResult` を実装（rawText, formattedText, timestamp, duration）
- [x] **テスト**: `FormattingMode` の全ケース列挙テストを書く
- [x] **実装**: `FormattingMode` enum を実装（memo, email, minutes, bulletPoints）
- [x] **テスト**: `HistoryEntry` の生成・Codable準拠テストを書く
- [x] **実装**: `HistoryEntry` を実装（id, result, mode, createdAt）
- [x] **テスト**: `ServiceStatus` の状態遷移テストを書く
- [x] **実装**: `ServiceStatus` enum を実装（idle, recording, processing, error）

### 0-3. Coreプロトコル定義

- [x] `AudioCaptureProtocol` を定義（startCapture, stopCapture, audioBuffer stream）
- [x] `TranscriberProtocol` を定義（transcribe async → TranscriptionResult）
- [x] `FormatterProtocol` を定義（format async → String）※Local/LLM共通
- [x] `InserterProtocol` を定義（insert async throws）
- [x] `HistoryStoreProtocol` を定義（save, listRecent, clear）
- [x] `HotkeyManagerProtocol` を定義（onKeyDown, onKeyUp callbacks）

### 0-4. モック作成

- [x] `MockAudioCapture` を作成（プロトコル準拠、呼び出し記録）
- [x] `MockTranscriber` を作成（固定テキストを返す）
- [x] `MockFormatter` を作成（入力をそのまま返す / 加工して返す）
- [x] `MockInserter` を作成（挿入テキストを記録）
- [x] `MockHistoryStore` を作成（メモリ内保存）

### 0-5. 権限管理

- [x] **テスト**: `PermissionManager` の各権限ステータス取得テストを書く（モック利用）
- [x] **実装**: `PermissionManager` を実装
  - マイク権限チェック・リクエスト（`AVCaptureDevice`）
  - Speech認識権限チェック・リクエスト（`SFSpeechRecognizer`）
  - アクセシビリティ権限チェック（`AXIsProcessTrusted`）
  - 権限不足時のシステム設定への誘導

### 0-6. メニューバーUI

- [x] `AppDelegate` でメニューバーアイコンを表示（`NSStatusItem`）
- [x] 状態表示：待機 / 録音中 / 処理中 のアイコン切替
- [x] メニュー項目を配置:
  - 状態ラベル（現在の状態を表示）
  - セパレータ
  - Settings...（未実装、グレーアウト可）
  - Quit
- [x] 権限ステータスをメニュー内に表示（✓ / ✗ + 設定リンク）

### 0-7. VoiceInputService 骨格

- [x] **テスト**: `VoiceInputService` の初期化テスト（モック注入）
- [x] **実装**: `VoiceInputService` の骨格を実装
  - プロトコルを通じたDI（コンストラクタインジェクション）
  - `startRecording()` / `stopRecording()` の空実装（async throws）
  - `status()` で現在の状態を返す

---

## Definition of Done (DoD)

- [x] Xcodeプロジェクトがビルドでき、テストターゲットが実行できる
- [x] 全Coreプロトコルが定義され、それぞれにモックが存在する
- [x] 全モデル型（TranscriptionResult, FormattingMode, HistoryEntry, ServiceStatus）がテスト済み
- [x] `PermissionManager` がマイク・Speech認識・アクセシビリティの各権限をチェックできる
- [x] アプリを起動するとメニューバーにアイコンが表示される
- [x] メニューから権限ステータスが確認でき、不足時はシステム設定へ誘導できる
- [x] `VoiceInputService` がモック経由で初期化でき、テストが通る
- [x] 全テストがグリーン（`xcodebuild test` が成功する）
