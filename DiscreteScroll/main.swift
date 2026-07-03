import Foundation
import ApplicationServices

nonisolated(unsafe)
let axNotification = "com.apple.accessibility.api" as CFString

nonisolated(unsafe)
var trusted: Bool = false

nonisolated(unsafe)
var lines: Int64 = 0

let kDefaultLine: Int64 = 3

/// アクセシビリティ許可をチェックし、許可済みとなったらループを止める
func notificationCallback(
    center: CFNotificationCenter?,
    observer: UnsafeMutableRawPointer?,
    name: CFNotificationName?,
    object: UnsafeRawPointer?,
    userInfo: CFDictionary?
) {
    let runLoop = CFRunLoopGetCurrent()
    CFRunLoopPerformBlock(runLoop,
                          CFRunLoopMode.defaultMode.rawValue as CFTypeRef) {
        let previouslyTrusted = trusted
        trusted = AXIsProcessTrusted()
        if (trusted && !previouslyTrusted) {
            CFRunLoopStop(runLoop)
        }
    }
}

/// スクロールイベントがきたとき、スクロール量を正規化する
func tapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    if (event.getIntegerValueField(.scrollWheelEventIsContinuous) == 0) {
        // ハードウェアによってPointDeltaはばらばらなのを固定値に変換している
        let delta = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)
        event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: delta.signum() * lines)
    }
    
    return Unmanaged.passUnretained(event)
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

let center = CFNotificationCenterGetDistributedCenter()
var observer: UInt8 = 0
withUnsafeMutablePointer(to: &observer) { ptr in
    CFNotificationCenterAddObserver(center,
                                    ptr,
                                    notificationCallback,
                                    axNotification,
                                    nil,
                                    .deliverImmediately)
}

let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
trusted = AXIsProcessTrustedWithOptions(options)
if !trusted {
    CFRunLoopRun()
}
withUnsafeMutablePointer(to: &observer) { ptr in
    CFNotificationCenterRemoveObserver(center,
                                       ptr,
                                       CFNotificationName(rawValue: axNotification),
                                       nil)
}

lines = UserDefaults.standard.object(forKey: "lines") as? Int64 ?? kDefaultLine


guard
    let tap = CGEvent.tapCreate(tap: .cgSessionEventTap,
                                place: .headInsertEventTap,
                                options: .defaultTap,
                                eventsOfInterest: CGEventMask(1 << CGEventType.scrollWheel.rawValue),
                                callback: tapCallback,
                                userInfo: nil)
else {
    displayNoticeAndExit("DiscreteScroll could not create an event tap.")
}

guard
    let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault,
                                               tap,
                                               0)
else {
    displayNoticeAndExit("DiscreteScroll could not create a run loop source.")
}

CFRunLoopAddSource(CFRunLoopGetCurrent(),
                   source,
                   CFRunLoopMode.defaultMode)
CFRunLoopRun()
