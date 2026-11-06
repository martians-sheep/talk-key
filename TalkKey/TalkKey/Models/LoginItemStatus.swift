import Foundation

/// ログイン時に起動する設定の状態
enum LoginItemStatus: Equatable {
    case enabled
    case disabled
    /// 登録したが、システム設定の「ログイン項目」で利用者の承認が要る
    case requiresApproval
}
