# 1枚仕様書：Mac音声入力アプリ（CoreはSwift固定／UIは将来差し替え）

## 目的

macOS上で、AquaVoice/Typeless風の **"押して話して、離したら入力される"** 音声入力体験を提供する。
**音声認識はApple標準（日本語）**、文字起こし後の整形は **速度重視モデル（例：Gemini Flash系）** を任意で使う。
将来的にUIをElectron/Tauriへ置き換えても、**Core（Swift）はそのまま再利用**できる構造にする。

---

## 成果物（MVP / Phase1）

### アプリ形態

* macOSメニューバー常駐アプリ（Swift + SwiftUI/AppKit）
* 将来のUI差し替えを見越して、内部は **Core層とUI層を分離**して実装

### コア体験（Must）

1. **グローバルホットキーのPush-to-talk**

   * 押下：録音開始
   * 解除：録音停止 → 文字起こし →（整形）→ 挿入
2. **Apple標準音声認識で日本語文字起こし**
3. **挿入方式（MVP）**

   * 文字列をクリップボードへ格納 → `Cmd+V` を送出して貼り付け
   * 失敗時もクリップボードに結果を残す（保険）
4. **整形（2段階）**

   * ローカル整形（無料・高速）：空白/改行/句読点など最小ルール
   * LLM整形（任意ON）：Gemini Flash系で"意味を変えずに整える"
5. **履歴**

   * 直近10件（再コピー可能）。検索は不要。

---

## 非機能要件（品質）

* 体感遅延：録音終了から挿入まで **目標1〜2秒**（LLMタイムアウト時はローカル整形で続行）
* LLM送信は **短文限定（例：最大2000文字）**。超過はLLM整形をスキップ。
* "賢く書き換えない"：**意味変更禁止・固有名詞/数値/専門用語保持**を強制。

---

## 権限・セキュリティ

* 必須：マイク、Speech認識
* 任意（Phase2以降推奨）：アクセシビリティ（AX直接挿入をやる場合）
* APIキー（Gemini等）は **Keychain** に保存
* LLM整形ON時のみ外部送信。OFF時はローカル完結。

---

## UI（MVP）

### メニューバー

* 状態：待機 / 録音中 / 処理中
* メニュー：

  * Mode（メモ/メール/議事録/箇条書き）※MVPは「メモ」だけでも可
  * LLM整形 ON/OFF
  * 履歴（直近10件）
  * Settings…
  * Quit

### Settings

* ホットキー設定
* LLM整形ON/OFF、モデル/タイムアウト、APIキー設定
* ローカル整形ON/OFF
* 権限ステータス表示と誘導

---

## Core設計（将来UI差し替え前提）

### モジュール（Swift内部）

* `AudioCapture`：録音開始/停止、音声バッファ生成
* `Transcriber`：Apple Speechで `ja-JP` 文字起こし
* `LocalFormatter`：ルール整形
* `LLMFormatter`：外部モデル整形（timeout付き）
* `Inserter`：Pasteboard + Cmd+V（Phase2でAXに差し替え）
* `HistoryStore`：直近N件保存

### Core API（将来の外部UI接続用に"概念として"固定）

* `startRecording()`
* `stopRecording() -> { rawText, formattedText }`
* `format(text, mode) -> formattedText`
* `insert(text)`
* `history.listRecent()`
* `status()`

※Phase1では内部呼び出しでOK。Phase2でHTTP/Socket/XPCのどれかにする。

---

## 例外処理（必須）

* 音声認識失敗：通知＋履歴に失敗記録（可能なら音声も保持はPhase2）
* LLM失敗/タイムアウト：ローカル整形結果を挿入し「整形スキップ」通知
* 挿入失敗：クリップボードに残し「手動で貼り付け」通知

---

## Doneの定義（受け入れ条件）

* ホットキー押下中録音 → 解除で日本語文字起こしされる
* LLM整形ON/OFFが動作し、ON時も意味が変わらない（固有名詞が壊れない）
* 複数アプリ（メモ、ブラウザ、Slack等）で貼り付け入力が安定して動く
* 権限不足時に、ユーザーが迷わず有効化できる導線がある
* 直近履歴から再利用できる

---

## Phase2（次の拡張）

* AXUIElementによる直接挿入（選択範囲置換、カーソル位置精度UP）
* 辞書（固有名詞登録）／アプリ別プロファイル（Slackは口語、メールは丁寧）
* UI差し替え（Electron/Tauri）：CoreにAPIで接続、UIだけ置換
* ローカルLLM整形（Ollama等）オプション
