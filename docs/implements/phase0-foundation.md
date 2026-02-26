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

- [ ] macOS App プロジェクト「TalkKey」を作成（SwiftUI、macOS 14.0+）
- [ ] メニューバー常駐アプリとして設定（`LSUIElement = YES`）
- [ ] ディレクトリ構成を作成（App / Core / Services / UI / Models / Utilities）
- [ ] テストターゲット（TalkKeyTests）を作成
- [ ] `.gitignore` にXcode関連の除外設定を追加

### 0-2. モデル定義

- [ ] **テスト**: `TranscriptionResult` の生成・プロパティアクセスのテストを書く
- [ ] **実装**: `TranscriptionResult` を実装（rawText, formattedText, timestamp, duration）
- [ ] **テスト**: `FormattingMode` の全ケース列挙テストを書く
- [ ] **実装**: `FormattingMode` enum を実装（memo, email, minutes, bulletPoints）
- [ ] **テスト**: `HistoryEntry` の生成・Codable準拠テストを書く
- [ ] **実装**: `HistoryEntry` を実装（id, result, mode, createdAt）
- [ ] **テスト**: `ServiceStatus` の状態遷移テストを書く
- [ ] **実装**: `ServiceStatus` enum を実装（idle, recording, processing, error）

### 0-3. Coreプロトコル定義

- [ ] `AudioCaptureProtocol` を定義（startCapture, stopCapture, audioBuffer stream）
- [ ] `TranscriberProtocol` を定義（transcribe async → TranscriptionResult）
- [ ] `FormatterProtocol` を定義（format async → String）※Local/LLM共通
- [ ] `InserterProtocol` を定義（insert async throws）
- [ ] `HistoryStoreProtocol` を定義（save, listRecent, clear）
- [ ] `HotkeyManagerProtocol` を定義（onKeyDown, onKeyUp callbacks）

### 0-4. モック作成

- [ ] `MockAudioCapture` を作成（プロトコル準拠、呼び出し記録）
- [ ] `MockTranscriber` を作成（固定テキストを返す）
- [ ] `MockFormatter` を作成（入力をそのまま返す / 加工して返す）
- [ ] `MockInserter` を作成（挿入テキストを記録）
- [ ] `MockHistoryStore` を作成（メモリ内保存）

### 0-5. 権限管理

- [ ] **テスト**: `PermissionManager` の各権限ステータス取得テストを書く（モック利用）
- [ ] **実装**: `PermissionManager` を実装
  - マイク権限チェック・リクエスト（`AVCaptureDevice`）
  - Speech認識権限チェック・リクエスト（`SFSpeechRecognizer`）
  - アクセシビリティ権限チェック（`AXIsProcessTrusted`）
  - 権限不足時のシステム設定への誘導

### 0-6. メニューバーUI

- [ ] `AppDelegate` でメニューバーアイコンを表示（`NSStatusItem`）
- [ ] 状態表示：待機 / 録音中 / 処理中 のアイコン切替
- [ ] メニュー項目を配置:
  - 状態ラベル（現在の状態を表示）
  - セパレータ
  - Settings...（未実装、グレーアウト可）
  - Quit
- [ ] 権限ステータスをメニュー内に表示（✓ / ✗ + 設定リンク）

### 0-7. VoiceInputService 骨格

- [ ] **テスト**: `VoiceInputService` の初期化テスト（モック注入）
- [ ] **実装**: `VoiceInputService` の骨格を実装
  - プロトコルを通じたDI（コンストラクタインジェクション）
  - `startRecording()` / `stopRecording()` の空実装（async throws）
  - `status()` で現在の状態を返す

---

## Definition of Done (DoD)

- [ ] Xcodeプロジェクトがビルドでき、テストターゲットが実行できる
- [ ] 全Coreプロトコルが定義され、それぞれにモックが存在する
- [ ] 全モデル型（TranscriptionResult, FormattingMode, HistoryEntry, ServiceStatus）がテスト済み
- [ ] `PermissionManager` がマイク・Speech認識・アクセシビリティの各権限をチェックできる
- [ ] アプリを起動するとメニューバーにアイコンが表示される
- [ ] メニューから権限ステータスが確認でき、不足時はシステム設定へ誘導できる
- [ ] `VoiceInputService` がモック経由で初期化でき、テストが通る
- [ ] 全テストがグリーン（`xcodebuild test` が成功する）
