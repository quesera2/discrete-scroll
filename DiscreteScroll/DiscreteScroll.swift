import AppKit
import ApplicationServices

@main
@MainActor
struct DiscreteScroll {
    
    static let defaultLineCount: Int64 = 3
    
    static let keyLineCount = "lines"
    
    static let tapCallback: CGEventTapCallBack = { _, _, event, userInfo in
        guard
            let userInfo
        else {
            return Unmanaged.passUnretained(event)
        }
        
        if event.getIntegerValueField(.scrollWheelEventIsContinuous) == 0 {
            let delta = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)
            let lines = userInfo.load(as: Int64.self)
            event.setIntegerValueField(.scrollWheelEventDeltaAxis1,
                                       value: delta.signum() * lines)
        }
        return Unmanaged.passUnretained(event)
    }
    
    private let lines: Int64?
    
    static func main() {
        let lines = UserDefaults.standard.object(forKey: keyLineCount) as? Int64
        let app = DiscreteScroll(lines: lines)
        Task {
            await app.waitUntilTrusted()
            app.setupObserveScroll()
        }
        RunLoop.current.run()
    }
    
    /// アクセシビリティ許可をチェックし、許可済みとなったらループを止める
    func waitUntilTrusted() async {
        // kAXTrustedCheckOptionPrompt の定数を直接参照する
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
        while !AXIsProcessTrusted() {
            try? await Task.sleep(for: .seconds(0.2))
        }
    }
    
    /// スクロール状態の監視のコールバックを設定する
    func setupObserveScroll() {
        // スクロール行数をポインタに詰める、これはアプリが常駐している間、意図的に解放しない
        let linesValue = self.lines ?? DiscreteScroll.defaultLineCount
        let pointer = UnsafeMutablePointer<Int64>.allocate(capacity: 1)
        pointer.initialize(to: linesValue)
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
        
        RunLoop.current.add(port, forMode: .default)
    }
    
    /// エラーダイアログを表示して終了
    func displayNoticeAndExit(_ alertHeader: String) -> Never {
        let alert = NSAlert()
        alert.messageText = alertHeader
        alert.alertStyle = .critical
        alert.runModal()
        exit(EXIT_FAILURE)
    }
}
