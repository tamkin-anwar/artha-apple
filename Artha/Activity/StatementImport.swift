import SwiftUI
import UniformTypeIdentifiers

/// Importing a bank statement (PDF, CSV, OFX/QFX or QIF) from the app, the same way as
/// on the website: the server reads it (in memory, never stored), the
/// person reviews every row, and nothing is saved until they tap Import.
/// The file is read straight from where it is, inside a security-scoped
/// access window, and never copied onto this device.
struct StatementImport: ViewModifier {
    @Binding var isPicking: Bool
    @Binding var isScanning: Bool

    @Environment(AppSession.self) private var session
    @State private var review: Review?
    @State private var locked: PickedFile?
    @State private var password = ""
    @State private var lockMessage = ""
    @State private var isReading = false
    @State private var message: String?

    /// Bigger than any real monthly statement; a guard against picking the
    /// wrong file, not a limit anyone should meet.
    private static let maxBytes = 15 * 1024 * 1024

    struct PickedFile {
        let data: Data
        let name: String
    }

    struct Review: Identifiable {
        let id = UUID()
        var rows: [StatementRow]
        let warnings: [String]
        let notice: String?
        let totals: String?
    }

    /// Every kind of statement file a bank exports. OFX/QFX and QIF are
    /// declared in Info.plist, so they resolve to real types here.
    static let fileTypes: [UTType] = [.pdf, .commaSeparatedText, .plainText, .image]
        + ["ofx", "qfx", "qif"].compactMap { UTType(filenameExtension: $0) }

    func body(content: Content) -> some View {
        content
            .fileImporter(isPresented: $isPicking,
                          allowedContentTypes: Self.fileTypes) { result in
                if case .success(let url) = result { read(url) }
            }
            .onChange(of: session.statementToImport, initial: true) {
                // Taken off the session as it's read, so the statement is
                // only ever read (and maybe sent to AI) once.
                guard let url = session.statementToImport else { return }
                session.statementToImport = nil
                read(url)
            }
            #if os(iOS)
            .fullScreenCover(isPresented: $isScanning) {
                StatementScanner { pdf in
                    isScanning = false
                    if let pdf { preview(PickedFile(data: pdf, name: "Scanned statement.pdf"), password: nil) }
                }
                .ignoresSafeArea()
            }
            #endif
            .overlay {
                if isReading {
                    ProgressView("Reading your statement")
                        .padding(24)
                        .background(Palette.surface, in: .rect(cornerRadius: Radius.card))
                        .accessibilityAddTraits(.updatesFrequently)
                }
            }
            .sheet(item: $review) { current in
                StatementReview(review: current) { summary in
                    review = nil
                    message = summary
                }
            }
            .alert("This PDF Is Locked", isPresented: Binding(get: { locked != nil }, set: { if !$0 { locked = nil } })) {
                SecureField("Password", text: $password)
                Button("Open") {
                    if let file = locked { preview(file, password: password) }
                    locked = nil
                }
                Button("Cancel", role: .cancel) { locked = nil }
            } message: {
                Text(lockMessage)
            }
            .alert("Import", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK") { message = nil }
            } message: {
                Text(message ?? "")
            }
    }

    private func read(_ url: URL) {
        // Picked and opened files are only readable inside this window.
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else {
            message = "Artha couldn\u{2019}t open that file. Try saving it to Files first."
            return
        }
        // A photo goes up as a JPEG, whatever the camera saved it as (HEIC),
        // and no bigger than it needs to be to read.
        if let type = UTType(filenameExtension: url.pathExtension), type.conforms(to: .image) {
            guard let jpeg = StatementPhoto.jpeg(from: data) else {
                message = "Artha couldn\u{2019}t open that photo. Try a screenshot of it instead."
                return
            }
            preview(PickedFile(data: jpeg, name: url.deletingPathExtension().lastPathComponent + ".jpg"), password: nil)
            return
        }
        guard data.count <= Self.maxBytes else {
            message = "That file is too big to be a statement. Pick the PDF or CSV your bank exports."
            return
        }
        preview(PickedFile(data: data, name: url.lastPathComponent), password: nil)
    }

    private func preview(_ file: PickedFile, password: String?) {
        isReading = true
        Task {
            defer { isReading = false }
            do {
                let result = try await session.previewStatement(file.data, filename: file.name, password: password)
                review = Review(rows: result.rows.map { row in
                    var row = row
                    row.include = !row.duplicate && !row.isTransfer
                    return row
                }, warnings: result.warnings, notice: result.notice, totals: result.totals)
            } catch APIError.rejected(let code, let text) where code == "needs_password" || code == "wrong_password" {
                self.password = ""
                lockMessage = code == "wrong_password" ? text : "Your bank locked this statement. Enter its password to read it."
                locked = file
            } catch let failure as APIError {
                message = failure.message
            } catch {
                message = "Artha couldn\u{2019}t read that file. Try again in a moment."
            }
        }
    }
}

extension View {
    func statementImport(isPicking: Binding<Bool>, isScanning: Binding<Bool>) -> some View {
        modifier(StatementImport(isPicking: isPicking, isScanning: isScanning))
    }
}

/// Every row the statement had, to keep or leave out before importing.
/// Rows already in Artha start unticked, like on the website.
private struct StatementReview: View {
    @State var review: StatementImport.Review
    let onImported: (String) -> Void

    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var isSaving = false
    @State private var error: String?

    private var keeping: Int { review.rows.filter(\.include).count }

    var body: some View {
        NavigationStack {
            List {
                if let totals = review.totals {
                    Section {
                        // The statement's own totals: proof nothing was
                        // missed, or a heads-up that something was.
                        if totals == "match" {
                            Label("Every transaction adds up to your statement\u{2019}s totals.", systemImage: "checkmark.seal.fill")
                                .foregroundStyle(Palette.good)
                        } else {
                            Label("These don\u{2019}t add up to your statement\u{2019}s totals, so something may be missing. Compare with your statement before importing.",
                                  systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(Palette.caution)
                        }
                    }
                    .font(.system(.subheadline))
                    .listRowBackground(Palette.surface)
                }
                if let notice = review.notice {
                    Section {
                        Label(notice, systemImage: "sparkles")
                            .font(.system(.subheadline))
                            .foregroundStyle(Palette.ink)
                    }
                    .listRowBackground(Palette.surface)
                }
                Section {
                    ForEach($review.rows) { $row in
                        StatementRowView(row: $row, categories: session.activity.categories)
                    }
                } header: {
                    Text("\(keeping) of \(review.rows.count) selected")
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        if !review.warnings.isEmpty {
                            Text(review.warnings.count == 1
                                 ? "1 line couldn\u{2019}t be read and was left out."
                                 : "\(review.warnings.count) lines couldn\u{2019}t be read and were left out.")
                        }
                        if review.rows.contains(where: \.duplicate) {
                            Text("Rows already in Artha start unticked, so nothing counts twice.")
                        }
                        if review.rows.contains(where: { $0.isTransfer && !$0.duplicate }) {
                            Text("Moves between your own accounts start unticked too: they aren\u{2019}t spending or income.")
                        }
                        if let error {
                            Text(error).foregroundStyle(Palette.caution).announcedWhenShown(error)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Palette.ground)
            .navigationTitle("Review Statement")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button(keeping == 1 ? "Import 1" : "Import \(keeping)", action: save)
                            .disabled(keeping == 0)
                    }
                }
            }
            .interactiveDismissDisabled(isSaving)
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 520)
        #endif
    }

    private func save() {
        isSaving = true
        error = nil
        Task {
            defer { isSaving = false }
            do {
                let result = try await session.importStatement(review.rows.filter(\.include))
                var summary = result.imported == 1 ? "Imported 1 transaction." : "Imported \(result.imported) transactions."
                if result.skipped > 0 { summary += " \(result.skipped) couldn\u{2019}t be saved." }
                onImported(summary)
            } catch let failure as APIError {
                error = failure.message
            } catch {
                self.error = "Artha couldn\u{2019}t save those. Try again in a moment."
            }
        }
    }
}

private struct StatementRowView: View {
    @Binding var row: StatementRow
    let categories: [CategoryList.Category]
    @Environment(\.dynamicTypeSize) private var typeSize

    private var isIncome: Bool { row.type == "income" }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Button {
                row.include.toggle()
            } label: {
                Image(systemName: row.include ? "checkmark.circle.fill" : "circle")
                    .font(.system(.title3))
                    .foregroundStyle(row.include ? Palette.accent : Palette.secondary)
                    .contentTransition(.symbolEffect(.replace))
                    // The whole 44-point square answers the tap, not just the circle.
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(row.include ? "Included" : "Left out")
            .accessibilityHint("Toggles whether this row is imported")

            VStack(alignment: .leading, spacing: 3) {
                // Statement names run long ("SQ *BLUE BOTTLE COFFEE SF CA").
                Text(row.description)
                    .foregroundStyle(row.include ? Palette.ink : Palette.secondary)
                    .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    Text(Date.apiDay(row.date)?.formatted(.dateTime.month(.abbreviated).day()) ?? row.date)
                        .fixedSize()
                    if isIncome {
                        Text("Income")
                    } else {
                        Menu {
                            Picker("Category", selection: categoryBinding) {
                                ForEach(categories.filter { $0.key != "income" }) { Text($0.label).tag(Optional($0.key)) }
                                Text("Uncategorized").tag(String?.none)
                            }
                        } label: {
                            HStack(spacing: 2) {
                                Text(row.categoryLabel)
                                Image(systemName: "chevron.up.chevron.down").font(.system(.caption2, weight: .semibold))
                                    .accessibilityHidden(true)
                            }
                            .foregroundStyle(Palette.accent)
                        }
                        .menuStyle(.button)
                        .buttonStyle(.plain)
                        .fixedSize()
                        .accessibilityLabel("Category")
                        .accessibilityValue(row.categoryLabel)
                    }
                }
                .font(.system(.footnote))
                .foregroundStyle(Palette.secondary)
                .lineLimit(1)
                if row.duplicate {
                    Text("Already in Artha")
                        .font(.system(.footnote))
                        .foregroundStyle(Palette.secondary)
                } else if row.isTransfer {
                    Text("Between your own accounts")
                        .font(.system(.footnote))
                        .foregroundStyle(Palette.secondary)
                }
                // At the largest text sizes the amount moves under the
                // name, so neither gets squeezed to a sliver.
                if typeSize.isAccessibilitySize { amount }
            }
            .layoutPriority(1)

            if !typeSize.isAccessibilitySize {
                Spacer(minLength: 8)
                amount
            }
        }
        .padding(.vertical, 2)
        .contentShape(.rect)
        .listRowBackground(Palette.surface)
    }

    private var amount: some View {
        Text((isIncome ? "+" : "") + Money.cents(Decimal.api(row.amount), row.currency))
            .font(.system(.body, design: .rounded, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(row.include ? Palette.ink : Palette.secondary)
            // An amount never breaks across lines; the name wraps instead.
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }

    private var categoryBinding: Binding<String?> {
        Binding(
            get: { row.category },
            set: { key in
                row.category = key
                row.categoryLabel = categories.first { $0.key == key }?.label ?? "Uncategorized"
            }
        )
    }
}
