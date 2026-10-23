// How to Use window content. Also serves as the first-launch guide.

import SwiftUI

struct HelpView: View {
    let icon: NSImage
    @ObservedObject var permission: PermissionState
    let grantPermission: () -> Void
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                Image(nsImage: icon).resizable().frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("MacCut").font(.title2.bold())
                    Text("Cut and paste files in Finder").foregroundStyle(.secondary)
                }
            }

            PermissionBanner(granted: permission.granted, grantPermission: grantPermission)

            HelpSection(title: "Move files") {
                KeyRow(key: "X", text: "Cut selected files")
                KeyRow(key: "V", text: "Move them here")
                KeyRow(key: "C", text: "Cancel the cut")
                Text("Renaming or searching? \u{2318}X cuts text as usual.")
                    .font(.callout).foregroundStyle(.secondary)
            }

            HelpSection(title: "Menu bar icon") {
                IconRow(symbol: "scissors", text: "Ready")
                IconRow(symbol: "scissors.circle.fill", text: "Cut pending")
                IconRow(symbol: "scissors", text: "Off or no permission", dimmed: true)
            }

            HelpSection(title: "Reliable Mode") {
                Text("Use only if files do not move.")
                Text("Moves to where Finder would paste. On a name clash you choose Replace or Keep Both; replaced items go to the Trash.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button("Done", action: close).keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 380)
    }
}

private struct PermissionBanner: View {
    let granted: Bool
    let grantPermission: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 18))
                .foregroundStyle(granted ? .green : .orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(granted ? "Ready to use" : "Permission needed").bold()
                Text(granted ? "MacCut is running in the menu bar."
                             : "Allow MacCut in Privacy & Security to start.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !granted {
                    Button("Grant Permission", action: grantPermission)
                        .padding(.top, 6)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 8)
            .fill((granted ? Color.green : Color.orange).opacity(0.12)))
    }
}

private struct HelpSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content
        }
    }
}

private struct KeyRow: View {
    let key: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 3) {
                KeyCap(label: "\u{2318}")
                KeyCap(label: key)
            }
            .frame(width: 56, alignment: .leading)
            Text(text)
        }
    }
}

private struct KeyCap: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .frame(minWidth: 22, minHeight: 22)
            .background(RoundedRectangle(cornerRadius: 5).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color(nsColor: .separatorColor)))
    }
}

private struct IconRow: View {
    let symbol: String
    let text: String
    var dimmed = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 14))
                .opacity(dimmed ? 0.35 : 1)
                .frame(width: 56, alignment: .leading)
            Text(text)
        }
    }
}
