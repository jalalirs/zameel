import CoreLocation
import Photos
import PhotosUI
import SwiftUI

struct AttractionDetailView: View {
    @ObservedObject var store: TripStore
    let attractionID: String
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var showMatcher = false
    @State private var uploading = false
    @State private var error: String?

    var attraction: Attraction? { store.attractions.first { $0.id == attractionID } }

    var body: some View {
        List {
            if let a = attraction {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(a.name).font(.headline)
                            Spacer()
                            StatusBadge(status: a.status)
                        }
                        if let d = a.planned_date {
                            Label("\(Fmt.shortDate(d))\(a.planned_time.map { " at \($0)" } ?? "")",
                                  systemImage: "calendar")
                                .font(.subheadline)
                        }
                        if a.amount > 0 {
                            Label("\(Fmt.money(a.amount, a.currency)) (\(Fmt.money(a.baseAmount, "SAR")))",
                                  systemImage: "ticket")
                                .font(.subheadline)
                        }
                        if let notes = a.notes {
                            Text(notes).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    NavigationLink("Edit cost / mark paid") {
                        EditCostView(store: store, item: .attraction(a))
                    }
                    .font(.subheadline)
                }

                BookingInfoSection(title: a.name, item: a)

                Section("Photos") {
                    let photos = store.photos(of: a)
                    if photos.isEmpty {
                        Text("No photos yet").font(.caption).foregroundStyle(.secondary)
                    } else {
                        PhotoGrid(store: store, photos: photos)
                    }
                    PhotosPicker(selection: $pickerItems, matching: .images) {
                        Label(uploading ? "Uploading…" : "Attach photos from library",
                              systemImage: "photo.badge.plus")
                    }
                    .disabled(uploading)
                    if a.lat != nil {
                        Button {
                            showMatcher = true
                        } label: {
                            Label("Find photos taken here", systemImage: "location.magnifyingglass")
                        }
                    }
                    if let error { Text(error).foregroundStyle(.red).font(.caption) }
                }
            }
        }
        .navigationTitle("Attraction")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: pickerItems) { _, items in
            guard !items.isEmpty else { return }
            uploadPicked(items)
        }
        .sheet(isPresented: $showMatcher) {
            if let a = attraction {
                PhotoMatchView(store: store, attraction: a)
            }
        }
    }

    /// Upload photos chosen in the system picker. GPS/date ride along via the
    /// asset identifier when library access is granted; otherwise the backend
    /// falls back to EXIF in the image data.
    private func uploadPicked(_ items: [PhotosPickerItem]) {
        uploading = true
        error = nil
        Task {
            defer {
                uploading = false
                pickerItems = []
            }
            for item in items {
                do {
                    guard let data = try await item.loadTransferable(type: Data.self) else { continue }
                    var lat: Double?
                    var lon: Double?
                    var taken: Date?
                    if let localID = item.itemIdentifier {
                        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [localID], options: nil)
                        if let asset = assets.firstObject {
                            lat = asset.location?.coordinate.latitude
                            lon = asset.location?.coordinate.longitude
                            taken = asset.creationDate
                        }
                    }
                    _ = try await APIClient.shared.uploadPhoto(
                        tripID: store.tripID, data: data, filename: "photo.jpg",
                        attractionID: attractionID, lat: lat, lon: lon, takenAt: taken)
                } catch {
                    self.error = error.localizedDescription
                }
            }
            await store.loadAll()
        }
    }
}

// ---- server photo grid ----

struct PhotoGrid: View {
    @ObservedObject var store: TripStore
    let photos: [Photo]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: 4)], spacing: 4) {
            ForEach(photos) { photo in
                ServerPhotoView(tripID: store.tripID, photoID: photo.id)
                    .frame(minHeight: 90)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))
    }
}

struct ServerPhotoView: View {
    let tripID: String
    let photoID: String
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                ProgressView()
            }
        }
        .task {
            if image == nil,
               let data = try? await APIClient.shared.photoData(tripID: tripID, photoID: photoID) {
                image = UIImage(data: data)
            }
        }
    }
}

// ---- PhotoKit location matcher ----

/// Scans the local photo library for shots taken within `radius` meters of the
/// attraction and offers to upload them.
struct PhotoMatchView: View {
    @ObservedObject var store: TripStore
    let attraction: Attraction
    @Environment(\.dismiss) private var dismiss

    @State private var matches: [PHAsset] = []
    @State private var selected: Set<String> = []
    @State private var scanning = true
    @State private var uploading = false
    @State private var denied = false

    private let radius: CLLocationDistance = 500

    var body: some View {
        NavigationStack {
            Group {
                if denied {
                    ContentUnavailableView("Photo access needed",
                                           systemImage: "lock.circle",
                                           description: Text("Allow photo library access in Settings to match photos by location."))
                } else if scanning {
                    ProgressView("Scanning your library…")
                } else if matches.isEmpty {
                    ContentUnavailableView("No photos found here",
                                           systemImage: "photo.on.rectangle.angled",
                                           description: Text("No photos within \(Int(radius)) m of \(attraction.name)."))
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 4)], spacing: 4) {
                            ForEach(matches, id: \.localIdentifier) { asset in
                                AssetThumb(asset: asset,
                                           selected: selected.contains(asset.localIdentifier))
                                    .onTapGesture {
                                        if selected.contains(asset.localIdentifier) {
                                            selected.remove(asset.localIdentifier)
                                        } else {
                                            selected.insert(asset.localIdentifier)
                                        }
                                    }
                            }
                        }
                        .padding(4)
                    }
                }
            }
            .navigationTitle("Photos near \(attraction.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(uploading ? "Uploading…" : "Attach \(selected.count)") { upload() }
                        .disabled(selected.isEmpty || uploading)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task { await scan() }
        }
    }

    private func scan() async {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        guard status == .authorized || status == .limited else {
            denied = true
            scanning = false
            return
        }
        guard let lat = attraction.lat, let lon = attraction.lon else {
            scanning = false
            return
        }
        let target = CLLocation(latitude: lat, longitude: lon)
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let all = PHAsset.fetchAssets(with: .image, options: options)
        var found: [PHAsset] = []
        all.enumerateObjects { asset, _, _ in
            if let loc = asset.location, loc.distance(from: target) <= radius {
                found.append(asset)
            }
        }
        matches = found
        scanning = false
    }

    private func upload() {
        uploading = true
        Task {
            for asset in matches where selected.contains(asset.localIdentifier) {
                if let data = await assetData(asset) {
                    _ = try? await APIClient.shared.uploadPhoto(
                        tripID: store.tripID, data: data, filename: "photo.jpg",
                        attractionID: attraction.id,
                        lat: asset.location?.coordinate.latitude,
                        lon: asset.location?.coordinate.longitude,
                        takenAt: asset.creationDate)
                }
            }
            await store.loadAll()
            uploading = false
            dismiss()
        }
    }

    private func assetData(_ asset: PHAsset) async -> Data? {
        await withCheckedContinuation { cont in
            let options = PHImageRequestOptions()
            options.isNetworkAccessAllowed = true
            options.deliveryMode = .highQualityFormat
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) {
                data, _, _, _ in
                cont.resume(returning: data)
            }
        }
    }
}

struct AssetThumb: View {
    let asset: PHAsset
    let selected: Bool
    @State private var image: UIImage?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Color.gray.opacity(0.2)
                }
            }
            .frame(width: 100, height: 100)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .stroke(selected ? Color.accentColor : .clear, lineWidth: 3))
            if selected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.white, Color.accentColor)
                    .padding(4)
            }
        }
        .task {
            let options = PHImageRequestOptions()
            options.isNetworkAccessAllowed = true
            PHImageManager.default().requestImage(
                for: asset, targetSize: CGSize(width: 200, height: 200),
                contentMode: .aspectFill, options: options) { img, _ in
                if let img { image = img }
            }
        }
    }
}
