import QuickLook
import SwiftUI
import UniformTypeIdentifiers

/// Tickets, booking emails, receipts — PDF/HTML/images stuck to a cost item.
/// Drop this section into any edit form.
struct AttachmentsSection: View {
    @ObservedObject var store: TripStore
    let itemPath: String  // e.g. "legs/<id>"

    @State private var attachments: [AttachmentOut] = []
    @State private var previewURL: URL?
    @State private var showImporter = false
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        Section("Attachments") {
            ForEach(attachments) { att in
                Button {
                    open(att)
                } label: {
                    HStack(spacing: 12) {
                        IconChip(system: att.icon, color: .indigo, size: 30)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(att.filename)
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Text(att.content_type)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "eye").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .onDelete { indexSet in
                for i in indexSet { delete(attachments[i]) }
            }
            Button {
                showImporter = true
            } label: {
                Label(busy ? "Working…" : "Attach PDF / image / HTML",
                      systemImage: "paperclip")
            }
            .disabled(busy)
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
        }
        .task { await reload() }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.pdf, .html, .image],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result { upload(urls) }
        }
        .quickLookPreview($previewURL)
    }

    private func reload() async {
        attachments = (try? await APIClient.shared.get("trips/\(store.tripID)/\(itemPath)/attachments")) ?? []
    }

    private func open(_ att: AttachmentOut) {
        busy = true
        Task {
            defer { busy = false }
            do {
                previewURL = try await APIClient.shared.downloadAttachment(att)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func upload(_ urls: [URL]) {
        busy = true
        error = nil
        Task {
            defer { busy = false }
            for url in urls {
                do {
                    guard url.startAccessingSecurityScopedResource() else { continue }
                    defer { url.stopAccessingSecurityScopedResource() }
                    let data = try Data(contentsOf: url)
                    let type = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType
                        ?? "application/octet-stream"
                    _ = try await APIClient.shared.uploadAttachment(
                        tripID: store.tripID, itemPath: itemPath, data: data,
                        filename: url.lastPathComponent, contentType: type)
                } catch {
                    self.error = error.localizedDescription
                }
            }
            await reload()
        }
    }

    private func delete(_ att: AttachmentOut) {
        Task {
            try? await APIClient.shared.delete("trips/\(store.tripID)/attachments/\(att.id)")
            await reload()
        }
    }
}
