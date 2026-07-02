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
            SwitchView(manager: manager)
        } label: {
            Image(systemName: manager.isMouseModeOn ? "computermouse.fill" : "hand.tap.fill")
        }
        .menuBarExtraStyle(.window)
    }
}

struct SwitchView: View {
    @ObservedObject var manager: ScrollManager

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "hand.tap.fill")
                .foregroundStyle(manager.isMouseModeOn ? .secondary : .primary)

            Toggle("", isOn: $manager.isMouseModeOn)
                .labelsHidden()
                .toggleStyle(.switch)

            Image(systemName: "computermouse.fill")
                .foregroundStyle(manager.isMouseModeOn ? .primary : .secondary)
        }
        .font(.title2)
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }
}
