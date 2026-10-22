import SwiftUI

/// The currency control used everywhere a currency is chosen (Settings,
/// signing up, an account): the current choice as a button that opens a
/// searchable list of every currency Artha supports, the six most people
/// use first. A menu can't hold about 160 currencies usefully; a search
/// field finds "Hong Kong" or "HKD" in two letters.
struct CurrencyButton: View {
    @Binding var selection: String
    /// Show the full name ("Hong Kong Dollar") or just the code ("HKD").
    var showsName = true

    @State private var isPicking = false

    var body: some View {
        Button {
            isPicking = true
        } label: {
            HStack(spacing: 4) {
                Text(showsName ? Currencies.name(selection) : "\(Money.symbol(for: selection)) \(selection)")
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(.caption2, weight: .semibold))
                    .accessibilityHidden(true)
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(Palette.accent)
        .accessibilityLabel("Currency")
        .accessibilityValue(Currencies.name(selection))
        .accessibilityHint("Opens the list of currencies")
        .sheet(isPresented: $isPicking) {
            CurrencyPicker(selection: selection) { selection = $0 }
        }
    }
}

/// The list itself, in its own navigation stack so it works from a sheet
/// or a pushed screen alike.
struct CurrencyPicker: View {
    let selection: String
    let onPick: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    /// Everything but the common six, alphabetical in the person's language.
    private var others: [String] {
        Currencies.codes
            .filter { !Currencies.common.contains($0) }
            .sorted { Currencies.name($0).localizedCaseInsensitiveCompare(Currencies.name($1)) == .orderedAscending }
    }

    private var matches: [String] {
        let needle = query.trimmingCharacters(in: .whitespaces)
        return (Currencies.common + others).filter {
            $0.localizedCaseInsensitiveContains(needle) || Currencies.name($0).localizedCaseInsensitiveContains(needle)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if query.trimmingCharacters(in: .whitespaces).isEmpty {
                    Section("Common") {
                        ForEach(Currencies.common, id: \.self, content: row)
                    }
                    Section("All currencies") {
                        ForEach(others, id: \.self, content: row)
                    }
                } else if matches.isEmpty {
                    Text("No currency matches \u{201C}\(query)\u{201D}.")
                        .foregroundStyle(Palette.secondary)
                        .listRowBackground(Palette.surface)
                } else {
                    ForEach(matches, id: \.self, content: row)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Palette.ground)
            .searchable(text: $query, prompt: "Name or code")
            .navigationTitle("Currency")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 380, minHeight: 480)
        #endif
    }

    private func row(_ code: String) -> some View {
        Button {
            if code != selection { onPick(code) }
            dismiss()
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Currencies.name(code))
                        .foregroundStyle(Palette.ink)
                    Text(code)
                        .font(.system(.footnote))
                        .foregroundStyle(Palette.secondary)
                }
                Spacer(minLength: 8)
                Text(Money.symbol(for: code))
                    .font(.system(.body, design: .rounded, weight: .semibold))
                    .foregroundStyle(Palette.secondary)
                if code == selection {
                    Image(systemName: "checkmark")
                        .font(.system(.body, weight: .semibold))
                        .foregroundStyle(Palette.accent)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .listRowBackground(Palette.surface)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(code == selection ? .isSelected : [])
    }
}
