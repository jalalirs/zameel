import Foundation

struct APIError: Error, LocalizedError {
    let status: Int
    let message: String
    var errorDescription: String? { "\(status): \(message)" }
}

final class APIClient {
    static let shared = APIClient()

    var baseURL: URL {
        URL(string: UserDefaults.standard.string(forKey: "baseURL") ?? "https://jalalirs.tailedf721.ts.net/zameel")!
    }
    var token: String? {
        get { UserDefaults.standard.string(forKey: "token") }
        set { UserDefaults.standard.set(newValue, forKey: "token") }
    }

    private func request(_ method: String, _ path: String, body: Data? = nil,
                         contentType: String = "application/json") async throws -> Data {
        var req = URLRequest(url: baseURL.appendingPathComponent(path))
        req.httpMethod = method
        req.httpBody = body
        if body != nil { req.setValue(contentType, forHTTPHeaderField: "Content-Type") }
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let (data, resp) = try await URLSession.shared.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let detail = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["detail"]
            throw APIError(status: status, message: (detail as? String) ?? String(data: data, encoding: .utf8) ?? "error")
        }
        return data
    }

    func get<T: Decodable>(_ path: String) async throws -> T {
        try JSONDecoder().decode(T.self, from: await request("GET", path))
    }

    func send<T: Decodable>(_ method: String, _ path: String, json: [String: Any?]) async throws -> T {
        let body = try JSONSerialization.data(withJSONObject: json.compactMapValues { $0 })
        return try JSONDecoder().decode(T.self, from: await request(method, path, body: body))
    }

    func delete(_ path: String) async throws {
        _ = try await request("DELETE", path)
    }

    // ---- auth ----

    var currentUserID: String? { UserDefaults.standard.string(forKey: "userID") }
    var currentUserName: String { UserDefaults.standard.string(forKey: "userName") ?? "" }
    var currentUserEmail: String { UserDefaults.standard.string(forKey: "userEmail") ?? "" }

    func refreshMe() async throws {
        let me: UserOut = try await get("auth/me")
        UserDefaults.standard.set(me.id, forKey: "userID")
        UserDefaults.standard.set(me.name, forKey: "userName")
        UserDefaults.standard.set(me.email, forKey: "userEmail")
    }

    func login(email: String, password: String) async throws {
        let t: TokenOut = try await send("POST", "auth/login", json: ["email": email, "password": password])
        token = t.access_token
        try await refreshMe()
    }

    func register(email: String, name: String, password: String) async throws {
        let t: TokenOut = try await send("POST", "auth/register",
                                         json: ["email": email, "name": name, "password": password])
        token = t.access_token
        try await refreshMe()
    }

    // ---- photos ----

    func uploadPhoto(tripID: String, data: Data, filename: String, attractionID: String?,
                     lat: Double?, lon: Double?, takenAt: Date?) async throws -> Photo {
        let boundary = "zameel-\(UUID().uuidString)"
        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".data(using: .utf8)!)
        }
        if let attractionID { field("attraction_id", attractionID) }
        if let lat { field("lat", String(lat)) }
        if let lon { field("lon", String(lon)) }
        if let takenAt { field("taken_at", ISO8601DateFormatter().string(from: takenAt)) }
        body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\nContent-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        let respData = try await request("POST", "trips/\(tripID)/photos", body: body,
                                         contentType: "multipart/form-data; boundary=\(boundary)")
        return try JSONDecoder().decode(Photo.self, from: respData)
    }

    // ---- attachments ----

    func uploadAttachment(tripID: String, itemPath: String, data: Data,
                          filename: String, contentType: String) async throws -> AttachmentOut {
        let boundary = "zameel-\(UUID().uuidString)"
        var body = Data()
        body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\nContent-Type: \(contentType)\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        let resp = try await request("POST", "trips/\(tripID)/\(itemPath)/attachments", body: body,
                                     contentType: "multipart/form-data; boundary=\(boundary)")
        return try JSONDecoder().decode(AttachmentOut.self, from: resp)
    }

    /// Downloads an attachment into a temp file (named so QuickLook can infer
    /// the type) and returns the local URL.
    func downloadAttachment(_ att: AttachmentOut) async throws -> URL {
        let data = try await request("GET", "trips/\(att.trip_id)/attachments/\(att.id)/file")
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("attachments/\(att.id)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(att.filename)
        try data.write(to: url)
        return url
    }

    func photoURL(tripID: String, photoID: String) -> URL {
        baseURL.appendingPathComponent("trips/\(tripID)/photos/\(photoID)/file")
    }

    /// AsyncImage can't send the auth header, so fetch image bytes manually.
    func photoData(tripID: String, photoID: String) async throws -> Data {
        try await request("GET", "trips/\(tripID)/photos/\(photoID)/file")
    }
}
