# Phase 1: 音声パイプライン

## ゴール

Push-to-talkでグローバルホットキーを押している間録音し、離したらストリーミング音声認識の結果が得られる状態を作る。
このフェーズ完了時点で「ホットキーを押して話して離す → 日本語テキストが得られる」が動く。

---

## TDD方針

- HotkeyManager / AudioCapture / Transcriber の各モジュールをプロトコル経由でテスト
- ハードウェア依存部分（実マイク、実CGEvent）はモックで代替し、ロジックのみテスト
- 結合テスト：モック経由でパイプライン全体の流れを検証

---

## タスクリスト

### 1-1. HotkeyManager（グローバルホットキー）

- [x] **テスト**: キー押下コールバックが呼ばれることを検証（モックイベント）
- [x] **テスト**: キー解除コールバックが呼ばれることを検証（モックイベント）
- [x] **テスト**: ホットキーの登録・解除が正しく動作することを検証
- [x] **テスト**: アクセシビリティ権限未取得時にエラーを返すことを検証
- [x] **実装**: `HotkeyManager` を実装
  - `CGEvent tap` でグローバルキーイベントを監視
  - keyDown → `onKeyDown` コールバック発火
  - keyUp → `onKeyUp` コールバック発火
  - デフォルトホットキー設定（例：`Fn` キーまたは `Ctrl+Shift+Space`）
  - アクセシビリティ権限チェックをstart時に実施

### 1-2. AudioCapture（録音）

- [x] **テスト**: `startCapture()` で録音状態になることを検証
- [x] **テスト**: `stopCapture()` で録音が停止し、バッファが取得できることを検証
- [x] **テスト**: 録音中にオーディオバッファが生成されることを検証（モック）
- [x] **テスト**: マイク権限未取得時にエラーを返すことを検証
- [x] **実装**: `AudioCapture` を実装
  - `AVAudioEngine` でマイク入力をキャプチャ
  - オーディオバッファを `SFSpeechAudioBufferRecognitionRequest` に供給可能な形で出力
  - 録音開始/停止の状態管理

### 1-3. Transcriber（ストリーミング音声認識）

- [x] **テスト**: 音声バッファ入力に対してテキスト結果を返すことを検証（モック）
- [x] **テスト**: `isFinal` フラグで最終結果のみ採用されることを検証
- [x] **テスト**: 認識言語が `ja-JP` であることを検証
- [x] **テスト**: 50秒制限で自動停止し通知することを検証
- [x] **テスト**: レート制限エラー時に適切なエラーを返すことを検証
- [x] **テスト**: オンデバイス認識の可否チェックが動作することを検証
- [x] **実装**: `Transcriber` を実装
  - `SFSpeechRecognizer(locale: Locale(identifier: "ja-JP"))` を使用
  - `SFSpeechAudioBufferRecognitionRequest` でストリーミング認識
  - 途中結果を内部保持し、`stopRecording()` 時に最新結果を返す
  - `isFinal` フラグで最終結果を判定
  - 50秒タイマーで自動停止（Apple制限の安全マージン）
  - `supportsOnDeviceRecognition` チェック
  - レート制限エラーのハンドリング

### 1-4. パイプライン結合（Recording → Transcription）

- [x] **テスト**: `VoiceInputService.startRecording()` が AudioCapture + Transcriber を起動することを検証
- [x] **テスト**: `VoiceInputService.stopRecording()` が TranscriptionResult を返すことを検証
- [x] **テスト**: 録音中→処理中→完了 の状態遷移を検証
- [x] **テスト**: 50秒自動停止時にもTranscriptionResultが取得できることを検証
- [x] **テスト**: 音声認識失敗時に適切なエラーが返ることを検証
- [x] **実装**: `VoiceInputService` に録音→認識パイプラインを組み込む
  - `startRecording()`: AudioCapture開始 + Transcriber開始
  - `stopRecording()`: AudioCapture停止 + Transcriber最終結果取得
  - 状態管理（idle → recording → processing → idle）

### 1-5. メニューバー連携

- [x] メニューバーのアイコンが録音中/処理中で変化する
- [x] ホットキー押下で録音開始、解除で停止が実際に動作する
- [x] 認識結果をコンソール（またはメニューバーの一時表示）で確認できる

---

## Definition of Done (DoD)

- [x] グローバルホットキー（CGEvent tap）でkeyDown/keyUpが検知できる
- [x] ホットキー押下中にマイク録音が行われ、音声バッファがストリーミング認識に渡される
- [x] ホットキー解除時点でストリーミング認識の最終結果（日本語テキスト）が取得できる
- [x] 50秒を超える録音は自動停止し、それまでの認識結果が取得できる
- [x] レート制限・認識失敗時に適切なエラーが発生し、アプリがクラッシュしない
- [x] メニューバーアイコンが状態（待機/録音中/処理中）に応じて変化する
- [x] HotkeyManager / AudioCapture / Transcriber の各ユニットテストがグリーン
- [x] パイプライン結合テスト（モック経由）がグリーン
- [x] 全テストがグリーン（`xcodebuild test` が成功する）
