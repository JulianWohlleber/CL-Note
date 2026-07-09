import SwiftUI
import AppKit

// MARK: – Vault model

struct VaultEntry: Codable, Identifiable {
    let id: String
    var name: String
    var path: String
}

struct VaultsConfig: Codable {
    var active: String
    var vaults: [VaultEntry]
}

// MARK: – Vault switcher button (top-left of topbar)

struct VaultSwitcherButton: View {
    @EnvironmentObject var store: NoteStore
    @State private var hovered = false

    var body: some View {
        Menu {
            // Current vaults
            ForEach(store.vaultEntries) { vault in
                Button {
                    store.switchVault(vault)
                } label: {
                    HStack {
                        Text(vault.name)
                        if vault.id == store.activeVaultID { Image(systemName: "checkmark") }
                    }
                }
            }

            Divider()

            Button("Add Vault…") { store.addVault() }
            Button("Open Vault Folder") {
                if let url = store.vaultURL {
                    NSWorkspace.shared.open(url)
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text(store.activeVaultName)
                    .font(F.syneUI(13, weight: .bold))
                    .foregroundColor(C.text)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer()
                // Subtle caret (chevron-down line, no fill)
                CaretDown()
                    .stroke(C.textDim, lineWidth: 1.2)
                    .frame(width: 8, height: 5)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(hovered ? C.bgHover : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(C.border, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .onHover { hovered = $0 }
        .help("Switch vault")
    }
}

/// Minimal line-art caret (used by the vault dropdown).
private struct CaretDown: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to:    CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return p
    }
}

/// Compact icon-only vault switcher for the left rail.
/// Shows the first two letters of the vault name in a rounded square.
struct VaultSwitcherIconButton: View {
    @EnvironmentObject var store: NoteStore
    @State private var hovered = false

    private var initials: String {
        let cleaned = store.activeVaultName
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
        let parts = cleaned.split(separator: " ")
        if parts.count >= 2 {
            return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased()
        }
        return String(cleaned.prefix(2)).uppercased()
    }

    var body: some View {
        Menu {
            ForEach(store.vaultEntries) { vault in
                Button {
                    store.switchVault(vault)
                } label: {
                    HStack {
                        Text(vault.name)
                        if vault.id == store.activeVaultID {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
            Divider()
            Button("Add Vault…") { store.addVault() }
            Button("Open Vault Folder") {
                if let url = store.vaultURL {
                    NSWorkspace.shared.open(url)
                }
            }
        } label: {
            Text(initials)
                .font(F.syneUI(11, weight: .bold))
                .foregroundColor(hovered ? C.text : C.textDim)
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(C.border, lineWidth: 1)
                )
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .onHover { hovered = $0 }
        .help(store.activeVaultName)
    }
}
