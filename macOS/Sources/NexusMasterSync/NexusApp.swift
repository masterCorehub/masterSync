import AppKit
import SwiftUI

@main
@MainActor
struct NexusApp: App {
    @StateObject private var model = NexusModel()
    @Environment(\.openWindow) private var openWindow

    private var preferredScheme: ColorScheme? {
        switch model.theme {
        case "dark": .dark
        case "light": .light
        default: nil
        }
    }

    var body: some Scene {
        Window("Nexus masterSync", id: "main") {
            Dashboard(model: model)
                .preferredColorScheme(preferredScheme)
                .frame(minWidth: 780, minHeight: 570)
                .task { model.launch() }
                .onOpenURL { model.openShortcut($0) }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    model.screen.stopUSB()
                }
        }
        .defaultSize(width: 1240, height: 790)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandMenu("Sincronização") {
                Button("Dispositivos") { model.section = .devices; showWindow() }
                    .keyboardShortcut(KeyEquivalent(model.devicesShortcut.first ?? "d"), modifiers: [.command, .shift])
                Button("Arquivos") { model.section = .files; showWindow() }
                    .keyboardShortcut(KeyEquivalent(model.filesShortcut.first ?? "f"), modifiers: [.command, .shift])
            }
        }

        Window("Tela do Android", id: "mirror") {
            VStack(spacing: 12) {
                HStack {
                    Label(model.screen.sharing ? "Espelhamento ativo" : "Espelhamento", systemImage: "rectangle.on.rectangle")
                    Spacer()
                    Button("Tela cheia") { NSApp.keyWindow?.toggleFullScreen(nil) }
                        .buttonStyle(NexusPillStyle(compact: true))
                    Button("Parar") { model.screen.end() }
                        .buttonStyle(NexusPillStyle(compact: true))
                        .disabled(!model.screen.sharing && !model.screen.requesting)
                }.padding(12)
                ZStack {
                    Color.black
                    if let frame = model.screen.frame {
                        Image(nsImage: frame).resizable().scaledToFit().accessibilityLabel("Tela compartilhada pelo Android")
                    } else {
                        Text(model.screen.feedback ?? (model.screen.sharing ? "Aguardando imagem…" : "Nenhum espelhamento ativo."))
                            .foregroundStyle(.white).padding()
                    }
                }
            }.frame(minWidth: 385, minHeight: 380)
                .background { NexusBackdrop() }
                .preferredColorScheme(preferredScheme)
                .onDisappear { model.screen.end() }
        }
        .defaultSize(width: 495, height: 770)

        MenuBarExtra {
            MenuBarPanel(model: model, open: { section in model.section = section; showWindow() }, quit: {
                model.screen.stopUSB()
                NSApp.terminate(nil)
            })
            .preferredColorScheme(preferredScheme)
        } label: {
            if let battery = model.selectedStatus?.battery {
                Label("\(battery)%", systemImage: model.selectedStatus?.charging == true ? "battery.100percent.bolt" : "battery.75percent")
            } else {
                Label("Nexus masterSync", systemImage: "arrow.left.arrow.right")
            }
        }
        .menuBarExtraStyle(.window)
    }

    private func showWindow() {
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }
}
