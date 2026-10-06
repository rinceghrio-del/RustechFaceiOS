import Foundation

struct EspReply {
    let code: Int
    let body: String
}

/// HTTP client papunta sa ESP32: GET http://<ip>/command?dir=X[&servo=N] , /ping , dir=PLAY&track=N
/// Isang connection lang bawat host (httpMaximumConnectionsPerHost = 1) kasi hindi kaya ng
/// web server ng ESP32 ang sabay-sabay na requests.
/// Lahat ng callback ay tinatawag sa main thread.
final class Esp32Client {
    private let settings: Settings
    private let session: URLSession

    private var trackingInFlight = false
    private var lastTrackingSend = Date.distantPast
    private let trackingInterval: TimeInterval = 0.3

    init(settings: Settings) {
        self.settings = settings
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 3
        cfg.timeoutIntervalForResource = 5
        cfg.httpMaximumConnectionsPerHost = 1
        cfg.waitsForConnectivity = false
        session = URLSession(configuration: cfg)
    }

    func get(_ path: String, _ items: [URLQueryItem] = [], done: ((EspReply?) -> Void)? = nil) {
        guard var comps = URLComponents(string: settings.baseURL + path) else { done?(nil); return }
        if !items.isEmpty { comps.queryItems = items }
        guard let url = comps.url else { done?(nil); return }

        session.dataTask(with: url) { data, response, error in
            var reply: EspReply? = nil
            if error == nil, let http = response as? HTTPURLResponse {
                let body = String(data: data ?? Data(), encoding: .utf8) ?? ""
                reply = EspReply(code: http.statusCode, body: body)
            }
            DispatchQueue.main.async { done?(reply) }
        }.resume()
    }

    func ping(done: @escaping (String?) -> Void) {
        get("/ping") { reply in
            if let r = reply, r.code == 200 {
                done(r.body.trimmingCharacters(in: .whitespacesAndNewlines))
            } else {
                done(nil)
            }
        }
    }

    func send(dir: String, servo: Int? = nil, done: ((EspReply?) -> Void)? = nil) {
        var items = [URLQueryItem(name: "dir", value: dir)]
        if let s = servo { items.append(URLQueryItem(name: "servo", value: String(s))) }
        get("/command", items, done: done)
    }

    func play(track: Int, done: ((EspReply?) -> Void)? = nil) {
        get("/command", [URLQueryItem(name: "dir", value: "PLAY"),
                         URLQueryItem(name: "track", value: String(track))], done: done)
    }

    /// Para sa face tracking: throttled (300ms) at hindi nagpa-pile up kapag may hinihintay pang sagot.
    func sendTracking(dir: String, servo: Int?) {
        let now = Date()
        if trackingInFlight { return }
        if now.timeIntervalSince(lastTrackingSend) < trackingInterval { return }
        lastTrackingSend = now
        trackingInFlight = true
        send(dir: dir, servo: servo) { [weak self] _ in
            self?.trackingInFlight = false
        }
    }
}
