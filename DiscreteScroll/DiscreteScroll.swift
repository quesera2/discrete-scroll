import AppKit
import ApplicationServices


struct TapContext {
    let lineValue: Int64
    let port: CFMachPort
}

@main
@MainActor
struct DiscreteScroll {
    
    static let accessibilityNotificationName: Notification.Name = Notification.Name("com.apple.accessibility.api")
    
    static let defaultLineCount: Int64 = 3
    
    static let keyLineCount = "lines"
    
    static let tapCallback: CGEventTapCallBack = { _, type, event, userInfo in
        guard
            let userInfo = userInfo?.load(as: TapContext.self)
        else {
            return Unmanaged.passUnretained(event)
        }
        
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            CGEvent.tapEnable(tap: userInfo.port, enable: true)
            return nil
        }
        
        if event.getIntegerValueField(.scrollWheelEventIsContinuous) == 0 {
            let delta = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)
            event.setIntegerValueField(.scrollWheelEventDeltaAxis1,
                                       value: delta.signum() * userInfo.lineValue)
        }
        return Unmanaged.passUnretained(event)
    }
    
    private let lines: Int64?
    
    static func main() async {
        let lines = UserDefaults.standard.object(forKey: keyLineCount) as? Int64
        let app = DiscreteScroll(lines: lines)
        await app.waitUntilTrusted()
        app.setupObserveScroll()
        await parkForever()
    }
    
    /// アクセシビリティ許可をチェックし、許可済みとなるまで待機する
    func waitUntilTrusted() async {
        if AXIsProcessTrusted() { return }
        
        // kAXTrustedCheckOptionPrompt の定数を直接参照する
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
        
        let center = DistributedNotificationCenter.default()
        let stream = center.notifications(named: DiscreteScroll.accessibilityNotificationName)
        for await _ in stream {
            if AXIsProcessTrusted() { break }
        }
    }
    
    /// スクロール状態の監視のコールバックを設定する
    func setupObserveScroll() {
        // スクロール行数と作成したCFMachPortをポインタに詰める、これはアプリが常駐している間、意図的に解放しない
        let linesValue = self.lines ?? DiscreteScroll.defaultLineCount
        let pointer = UnsafeMutablePointer<TapContext>.allocate(capacity: 1)
        guard
            let port = CGEvent.tapCreate(tap: .cgSessionEventTap,
                                         place: .headInsertEventTap,
                                         options: .defaultTap,
                                         eventsOfInterest: CGEventMask(1 << CGEventType.scrollWheel.rawValue),
                                         callback: DiscreteScroll.tapCallback,
                                         userInfo: pointer)
        else {
            pointer.deallocate()
            displayNoticeAndExit("DiscreteScroll could not create an event tap.")
        }
        pointer.pointee = TapContext(lineValue: linesValue, port: port)
        RunLoop.current.add(port, forMode: .default)
    }
    
    /// エラーダイアログを表示して終了
    func displayNoticeAndExit(_ alertHeader: String) -> Never {
        CFUserNotificationDisplayNotice(0,
                                        kCFUserNotificationCautionAlertLevel,
                                        nil,
                                        nil,
                                        nil,
                                        alertHeader as CFString,
                                        nil,
                                        nil)
        exit(EXIT_FAILURE)
    }
    
    /// プロセスを終了させず、イベントタップの発火を待ち続ける
    private static func parkForever() async {
        await withUnsafeContinuation { (_: UnsafeContinuation<Void, Never>) in }
    }
}
