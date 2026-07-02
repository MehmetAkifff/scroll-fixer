//
//  mouseSwitcherApp.swift
//  mouseSwitcher
//
//  Created by Mehmet Akif ERGANİ on 2.07.2026.
//

import SwiftUI

@main
struct mouseSwitcherApp: App {
    @StateObject private var manager = ScrollManager()

    var body: some Scene {
        MenuBarExtra {
            MenuContent(manager: manager)
        } label: {
            Image(systemName: manager.isMouseModeOn ? "computermouse.fill" : "computermouse")
        }
        .menuBarExtraStyle(.menu)
    }
}

struct MenuContent: View {
    @ObservedObject var manager: ScrollManager

    var body: some View {
        if !manager.isTrusted {
            Text("Erişilebilirlik izni gerekli")
            Button("İzin ver…") { manager.requestPermission() }
            Button("Ayarları aç…") { manager.openAccessibilitySettings() }
            Divider()
        }

        Toggle("Mouse kullanıyorum", isOn: $manager.isMouseModeOn)
            .disabled(!manager.isTrusted)

        Text(manager.isMouseModeOn
             ? "Kaydırma: ters (mouse için)"
             : "Kaydırma: normal (trackpad)")

        Divider()

        Toggle("Girişte başlat", isOn: $manager.launchAtLogin)

        Button("Çıkış") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }
}
