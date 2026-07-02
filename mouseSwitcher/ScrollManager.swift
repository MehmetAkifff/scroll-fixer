//
//  ScrollManager.swift
//  mouseSwitcher
//
//  Mouse tekerinden gelen kaydırmayı (scroll) anlık olarak ters çevirir.
//  Trackpad / Magic Mouse gibi sürekli (continuous) cihazlara dokunmaz,
//  böylece sistemin global "natural scrolling" ayarı hiç değişmez.
//

import AppKit
import Combine
import CoreGraphics
import ApplicationServices
import ServiceManagement

// C event-tap geri çağrımı yalnızca ana thread'de çalıştığı için bu global
// değişkenler oradan güvenle okunur/yazılır. Aktör izolasyonu dışında tutuluyor.
nonisolated(unsafe) var gInvertMouseScroll = false
nonisolated(unsafe) var gEventTap: CFMachPort?
nonisolated(unsafe) var gTailTap: CFMachPort?
nonisolated(unsafe) var gScrollEventSeen = 0
nonisolated(unsafe) var gTailEventSeen = 0

/// Teşhis için /tmp/mouseSwitcher.log dosyasına yazar.
nonisolated func msLog(_ msg: String) {
    let line = "\(Date()): \(msg)\n"
    let path = "/tmp/mouseSwitcher.log"
    guard let data = line.data(using: .utf8) else { return }
    if let fh = FileHandle(forWritingAtPath: path) {
        fh.seekToEndOfFile()
        fh.write(data)
        try? fh.close()
    } else {
        try? data.write(to: URL(fileURLWithPath: path))
    }
}

/// Yakalanan her scroll olayı için çağrılan düşük seviye geri çağrım.
private nonisolated func scrollEventCallback(proxy: CGEventTapProxy,
                                             type: CGEventType,
                                             event: CGEvent,
                                             refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    // Tap sistem tarafından devre dışı bırakılırsa (timeout vb.) tekrar aç.
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let tap = gEventTap {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
        return Unmanaged.passUnretained(event)
    }

    guard type == .scrollWheel, gInvertMouseScroll else {
        return Unmanaged.passUnretained(event)
    }

    gScrollEventSeen += 1
    let logThis = gScrollEventSeen <= 6
    if logThis {
        let d1 = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
        let p1 = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)
        let f1 = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
        msLog("HEAD önce: delta1=\(d1) point1=\(p1) fixed1=\(f1)")
    }

    // Mod açıkken kaydırmanın her iki eksenini de ters çeviriyoruz.
    // ÖNEMLİ: delta alanı yazıldığında macOS point/fixedPt alanlarını otomatik
    // yeniden hesaplar. Bu yüzden önce TÜM orijinal değerler okunur, sonra
    // hepsi tek seferde yazılır; yoksa ikinci okuma yeniden hesaplanmış değeri
    // görür ve çevirme kendini iptal eder.
    let axis1 = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
    let axis2 = event.getIntegerValueField(.scrollWheelEventDeltaAxis2)
    let pointAxis1 = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)
    let pointAxis2 = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2)
    let fixedAxis1 = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
    let fixedAxis2 = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2)

    event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: -axis1)
    event.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: -axis2)
    event.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: -pointAxis1)
    event.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: -pointAxis2)
    event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: -fixedAxis1)
    event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: -fixedAxis2)

    if logThis {
        let d1 = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
        let p1 = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)
        let f1 = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
        msLog("HEAD sonra: delta1=\(d1) point1=\(p1) fixed1=\(f1)")
    }

    return Unmanaged.passUnretained(event)
}

/// Zincirin SONUNA eklenen salt-dinleme tap'i: uygulamalara giden son hâli loglar.
private nonisolated func tailListenCallback(proxy: CGEventTapProxy,
                                            type: CGEventType,
                                            event: CGEvent,
                                            refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    if type == .scrollWheel, gInvertMouseScroll {
        gTailEventSeen += 1
        if gTailEventSeen <= 6 {
            let d1 = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
            let p1 = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)
            let f1 = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
            msLog("TAIL final: delta1=\(d1) point1=\(p1) fixed1=\(f1)")
        }
    }
    return Unmanaged.passUnretained(event)
}

final class ScrollManager: ObservableObject {

    private enum Keys {
        static let mouseMode = "isMouseModeOn"
    }

    /// "Mouse kullanıyorum" anahtarı. Açıkken mouse kaydırması ters çevrilir.
    @Published var isMouseModeOn: Bool = false {
        didSet {
            gInvertMouseScroll = isMouseModeOn
            UserDefaults.standard.set(isMouseModeOn, forKey: Keys.mouseMode)
        }
    }

    /// Erişilebilirlik izni verildi mi?
    @Published private(set) var isTrusted: Bool = false

    private var runLoopSource: CFRunLoopSource?
    private var permissionTimer: Timer?

    init() {
        let saved = UserDefaults.standard.bool(forKey: Keys.mouseMode)
        isMouseModeOn = saved
        gInvertMouseScroll = saved
        isTrusted = AXIsProcessTrusted()

        // İzin yoksa sistem iznini bir kez otomatik iste (butona gerek kalmasın).
        if !isTrusted {
            requestPermission()
        }
        // Menü çubuğunda kalıcı olsun: girişte otomatik başlat.
        try? SMAppService.mainApp.register()

        start()
        startPermissionWatch()
    }

    /// Event tap'i kurar. İzin yoksa sessizce başarısız olur; izin gelince
    /// zamanlayıcı yeniden dener.
    func start() {
        guard gEventTap == nil else { return }

        let mask = (1 << CGEventType.scrollWheel.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: scrollEventCallback,
            userInfo: nil
        ) else {
            msLog("tap OLUSTURULAMADI. trusted=\(AXIsProcessTrusted())")
            return
        }
        msLog("tap olusturuldu OK. trusted=\(AXIsProcessTrusted())")

        gEventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        // Teşhis: zincirin sonunda salt-dinleme tap'i (uygulamalara giden son hâl).
        if let tail = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .tailAppendEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(mask),
            callback: tailListenCallback,
            userInfo: nil
        ) {
            gTailTap = tail
            let tailSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tail, 0)
            CFRunLoopAddSource(CFRunLoopGetMain(), tailSource, .commonModes)
            CGEvent.tapEnable(tap: tail, enable: true)
            msLog("tail tap kuruldu")
        } else {
            msLog("tail tap kurulamadı")
        }
    }

    /// Erişilebilirlik izin penceresini açar.
    func requestPermission() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    /// Sistem Ayarları > Gizlilik ve Güvenlik > Erişilebilirlik bölümünü açar.
    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// İzin durumunu periyodik kontrol eder; izin gelince tap'i başlatır.
    private func startPermissionWatch() {
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            let trusted = AXIsProcessTrusted()
            if trusted != self.isTrusted {
                self.isTrusted = trusted
            }
            if trusted && gEventTap == nil {
                self.start()
            }
        }
    }
}
