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

    // Sürekli (continuous) olaylar trackpad / Magic Mouse'tan gelir; onlara
    // dokunmuyoruz. Yalnızca ayrık (discrete) mouse tekeri olaylarını çeviriyoruz.
    let isContinuous = event.getIntegerValueField(.scrollWheelEventIsContinuous)
    if isContinuous == 0 {
        let axis1 = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
        event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: -axis1)
        let axis2 = event.getIntegerValueField(.scrollWheelEventDeltaAxis2)
        event.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: -axis2)

        let pointAxis1 = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)
        event.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: -pointAxis1)
        let pointAxis2 = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2)
        event.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: -pointAxis2)

        let fixedAxis1 = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: -fixedAxis1)
        let fixedAxis2 = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: -fixedAxis2)
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

    /// Uygulama macOS girişinde otomatik başlatılsın mı?
    @Published var launchAtLogin: Bool = false {
        didSet {
            updateLoginItem()
        }
    }

    private var runLoopSource: CFRunLoopSource?
    private var permissionTimer: Timer?

    init() {
        let saved = UserDefaults.standard.bool(forKey: Keys.mouseMode)
        isMouseModeOn = saved
        gInvertMouseScroll = saved
        isTrusted = AXIsProcessTrusted()
        // init içinde atama didSet tetiklemez; yalnızca mevcut durumu yansıtır.
        launchAtLogin = (SMAppService.mainApp.status == .enabled)

        start()
        startPermissionWatch()
    }

    /// "Girişte başlat" anahtarını gerçek login item durumuyla eşitler.
    private func updateLoginItem() {
        do {
            switch (launchAtLogin, SMAppService.mainApp.status) {
            case (true, let s) where s != .enabled:
                try SMAppService.mainApp.register()
            case (false, .enabled):
                try SMAppService.mainApp.unregister()
            default:
                break
            }
        } catch {
            NSLog("Login item güncellenemedi: \(error)")
        }
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
            return
        }

        gEventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
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
