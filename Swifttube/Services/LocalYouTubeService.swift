/*
 File Overview (EN)
 Purpose: Lightweight, scraping-based metadata fetcher for YouTube watch pages (title, author, views, date, duration, descriptions).
 Key Responsibilities:
 - Request and parse watch HTML, extract ytInitialPlayerResponse/ytInitialData fields robustly
 - Provide LocalVideoData without streams/subtitles; normalize views/dates centrally
 - Include resilient fallbacks (oEmbed, microformat, regex) when structured data is missing
 Used By: UnifiedAPIService.fetchVideoMetadata and enrichment helpers.

 Dosya Özeti (TR)
 Amacı: YouTube izleme sayfalarından kazıma (scrape) ile hafif metadata çekici (başlık, kanal, görüntülenme, tarih, süre, açıklama).
 Ana Sorumluluklar:
 - HTML'i isteyip ayrıştırmak; ytInitialPlayerResponse/ytInitialData alanlarını dayanıklı biçimde çıkarmak
 - Akış/altyazı olmadan LocalVideoData döndürmek; görüntülenme/tarihi merkezi fonksiyonlarla normalize etmek
 - Yapısal veri yoksa oEmbed, microformat ve regex gibi sağlam geri dönüşler sunmak
 Nerede Kullanılır: UnifiedAPIService.fetchVideoMetadata ve zenginleştirme yardımcıları.
*/


import Foundation

// Basit metadata modeli (stream / altyazı yok)
struct LocalVideoData {
    let id: String
    let title: String
    let author: String
    let channelId: String?
    let shortDescription: String
    let longDescription: String? // ek: varsa daha uzun açıklama
    let viewCountText: String
    // Ham metin (formatlamadan önce) – "12,345 watching now" gibi kalıpları tespit etmek için
    let rawViewCountText: String
    let publishedTimeText: String
    let durationSeconds: Int?
    let durationText: String
    var effectiveDescription: String { longDescription?.isEmpty == false ? longDescription! : shortDescription }
}

// Basit hata türleri
enum LocalYouTubeError: Error {
    case network
    case noPlayerResponse
    case decode
}


final class LocalYouTubeService {
    static let shared = LocalYouTubeService()
    private init() {}

    // Yalnızca metadata döner
    func fetchVideo(videoId: String, hl: String? = nil, gl: String? = nil) async throws -> LocalVideoData {
    // İzlenme ve tarih kaynaklarını sabitlemek için daima en/US ile çek
    let urlString = "https://www.youtube.com/watch?v=\(videoId)&hl=en&persist_hl=1&gl=US&persist_gl=1&bpctr=9999999999"
    guard let url = URL(string: urlString) else { throw LocalYouTubeError.network }

    var req = RequestFactory.makeYouTubeHTMLRequest(url: url, hl: "en", gl: "US", userAgentOverride: "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_4) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36")
    req.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
    req.setValue("same-origin", forHTTPHeaderField: "Sec-Fetch-Site")
    req.setValue("document", forHTTPHeaderField: "Sec-Fetch-Dest")
    req.setValue("navigate", forHTTPHeaderField: "Sec-Fetch-Mode")
    let (data, resp) = try await URLSession.shared.data(for: req)
    guard let http = resp as? HTTPURLResponse, http.statusCode == 200, let html = String(data: data, encoding: .utf8) else { throw LocalYouTubeError.network }
    #if DEBUG
    if html.range(of: "consent.google.com") != nil { print("[METADEBUG] consent page detected for id=\(videoId)") }
    #endif

        guard let prJSON = Self.extractPlayerResponseJSON(from: html) else {
            #if DEBUG
            print("[METADEBUG] ytInitialPlayerResponse MISSING id=\(videoId) htmlLen=\(html.count)")
            #endif
            throw LocalYouTubeError.noPlayerResponse
        }
        let decoder = JSONDecoder()
    let pr: PlayerResponse? = try? decoder.decode(PlayerResponse.self, from: Data(prJSON.utf8))

        // Unescape helper for JSON string fragments
        func unescapeFrag(_ s: String) -> String {
            var out = s
            out = out.replacingOccurrences(of: "\\n", with: "\n")
            out = out.replacingOccurrences(of: "\\u0026", with: "&")
            // replace escaped quotes \" with real quotes (raw string literal for pattern)
            out = out.replacingOccurrences(of: #"\""#, with: "\"")
            return out
        }
        // Minimal regex field extraction from raw player response JSON if decoding fails
        func regexField(_ name: String, dotAll: Bool = false) -> String? {
            let pattern = "\\\"\(name)\\\"\\s*:\\s*\\\"(.*?)\\\""
            let opts: NSRegularExpression.Options = dotAll ? [.dotMatchesLineSeparators] : []
            guard let re = try? NSRegularExpression(pattern: pattern, options: opts) else { return nil }
            let ns = prJSON as NSString
            if let m = re.firstMatch(in: prJSON, range: NSRange(location: 0, length: ns.length)), m.numberOfRanges > 1 {
                if let r = Range(m.range(at: 1), in: prJSON) { return unescapeFrag(String(prJSON[r])) }
            }
            return nil
        }
    let details = pr?.videoDetails
        var title = details?.title ?? regexField("title") ?? ""
        var author = details?.author ?? regexField("author") ?? ""
        let channelId = details?.channelId ?? regexField("channelId")
        let desc = details?.shortDescription ?? regexField("shortDescription", dotAll: true) ?? ""
    var viewCountText = details?.viewCount ?? regexField("viewCount") ?? regexField("view_count") ?? ""
    var rawViewCountTextForReturn = viewCountText // başlangıç ham değer
        // publishDate bazen yok; uploadDate veya microformat datePublished kullanılabilir
        var publishedTimeText = details?.publishDate ?? regexField("publishDate") ?? regexField("uploadDate") ?? ""
        // Süre (saniye) ve metin
        var durationSecondsForReturn: Int? = nil
        var durationTextForReturn: String = ""
        if let lenStr = details?.lengthSeconds, let n = Int(lenStr), n > 0 {
            durationSecondsForReturn = n
        } else if let lenStr = regexField("lengthSeconds"), let n = Int(lenStr), n > 0 {
            durationSecondsForReturn = n
        } else if let approxMsStr = regexField("approxDurationMs"), let ms = Int(approxMsStr), ms > 0 {
            durationSecondsForReturn = ms / 1000
        }
        if let secs = durationSecondsForReturn {
            func formatDuration(_ s: Int) -> String {
                if s < 3600 { return String(format: "%d:%02d", s/60, s%60) }
                return String(format: "%d:%02d:%02d", s/3600, (s%3600)/60, s%60)
            }
            durationTextForReturn = formatDuration(secs)
        }

        // Fallback 1: HTML içinden viewCountText.simpleText yakala (lokal dil farklı olabilir, sadece rakamları çekip formatlarız)
    if viewCountText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if let m = try? NSRegularExpression(pattern: #"\"viewCountText\"\s*:\s*\{\s*\"simpleText\"\s*:\s*\"(.*?)\""#, options: [.dotMatchesLineSeparators]) {
                let ns = html as NSString
                if let match = m.firstMatch(in: html, range: NSRange(location: 0, length: ns.length)), match.numberOfRanges > 1 {
                    if let r = Range(match.range(at: 1), in: html) {
                        let raw = String(html[r])
                        rawViewCountTextForReturn = raw
                        // Önce yaklaşık sayı parse etmeyi dene ("11M", "1.2K" vb). Olmazsa sadece rakamları topla.
                        if let approx = approxNumberFromText(raw) {
                            viewCountText = String(approx)
                        } else {
                            let digits = raw.filter { $0.isNumber }
                            if !digits.isEmpty { viewCountText = digits }
                        }
                    }
                }
            }
        }
        // Fallback 2: microformat player sayfasında publishDate / uploadDate dışındaki datePublished alanı
    if publishedTimeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if let m = try? NSRegularExpression(pattern: #"\"datePublished\"\s*:\s*\"(\d{4}-\d{2}-\d{2})\""#) {
                let ns = html as NSString
                if let match = m.firstMatch(in: html, range: NSRange(location: 0, length: ns.length)), match.numberOfRanges > 1, let r = Range(match.range(at: 1), in: html) {
            publishedTimeText = String(html[r])
                }
            }
        }

    // Ek Fallback 3: ytInitialData -> videoPrimaryInfoRenderer.viewCount.videoViewCountRenderer.viewCount.simpleText
    if viewCountText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if let m = try? NSRegularExpression(pattern: #"videoViewCountRenderer"\s*:\s*\{[^{]*?\"viewCount\"\s*:\s*\{[^{]*?\"simpleText\"\s*:\s*\"(.*?)\""#, options: [.dotMatchesLineSeparators]) {
                let ns = html as NSString
                if let match = m.firstMatch(in: html, range: NSRange(location: 0, length: ns.length)), match.numberOfRanges > 1, let r = Range(match.range(at: 1), in: html) {
                    let raw = String(html[r])
            rawViewCountTextForReturn = raw
                    if let approx = approxNumberFromText(raw) {
                        viewCountText = String(approx)
                    } else {
                        let digits = raw.filter { $0.isNumber }
                        if !digits.isEmpty { viewCountText = digits }
                    }
                }
            }
        }
        // Ek Fallback 4: shortViewCount.simpleText
        if viewCountText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        if let m = try? NSRegularExpression(pattern: #"\"shortViewCount\"[^}]*?\"simpleText\"\s*:\s*\"(.*?)\""#, options: [.dotMatchesLineSeparators]) {
                let ns = html as NSString
                if let match = m.firstMatch(in: html, range: NSRange(location: 0, length: ns.length)), match.numberOfRanges > 1, let r = Range(match.range(at: 1), in: html) {
                    let raw = String(html[r])
            rawViewCountTextForReturn = raw
                    if let approx = approxNumberFromText(raw) {
                        viewCountText = String(approx)
                    } else {
                        let digits = raw.filter { $0.isNumber }
                        if !digits.isEmpty { viewCountText = digits }
                    }
                }
            }
        }
        // Ek Fallback 5: microformat.playerMicroformatRenderer.viewCount
        if viewCountText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        if let m = try? NSRegularExpression(pattern: #"playerMicroformatRenderer"[^{]*?\{[^}]*?\"viewCount\"\s*:\s*\"(\d+)\""#, options: [.dotMatchesLineSeparators]) {
                let ns = html as NSString
                if let match = m.firstMatch(in: html, range: NSRange(location: 0, length: ns.length)), match.numberOfRanges > 1, let r = Range(match.range(at: 1), in: html) {
            viewCountText = String(html[r])
        rawViewCountTextForReturn = viewCountText
                    // microformat viewCount captured
                }
            }
        }
        // Ek Fallback 6: dateText.simpleText (relative string direkt gösterilebilir)
        if publishedTimeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if let m = try? NSRegularExpression(pattern: #"\"dateText\"\s*:\s*\{\s*\"simpleText\"\s*:\s*\"(.*?)\""#, options: [.dotMatchesLineSeparators]) {
                let ns = html as NSString
                if let match = m.firstMatch(in: html, range: NSRange(location: 0, length: ns.length)), match.numberOfRanges > 1, let r = Range(match.range(at: 1), in: html) {
                    publishedTimeText = String(html[r])
                    // dateText simpleText captured
                }
            }
        }
        // Ek Fallback 7: microformat.playerMicroformatRenderer.publishDate
        if publishedTimeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if let m = try? NSRegularExpression(pattern: #"playerMicroformatRenderer"[^{]*?\{[^}]*?\"publishDate\"\s*:\s*\"(\d{4}-\d{2}-\d{2})\""#, options: [.dotMatchesLineSeparators]) {
                let ns = html as NSString
                if let match = m.firstMatch(in: html, range: NSRange(location: 0, length: ns.length)), match.numberOfRanges > 1, let r = Range(match.range(at: 1), in: html) {
                    publishedTimeText = String(html[r])
                    // microformat publishDate captured
                }
            }
        }

        // Yapısal JSON (ytInitialData) içinden primaryInfo (viewCount/dateText) çıkarmayı dene
        if (viewCountText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || publishedTimeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
            if let primary = Self.extractPrimaryInfo(from: html) {
                if viewCountText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let rawVC = primary.viewCountRaw {
                    // Ham metni kaydet (örn: "12,345 watching now")
                    rawViewCountTextForReturn = rawVC
                    if let approx = approxNumberFromText(rawVC) {
                        viewCountText = String(approx)
                    } else {
                        let digits = rawVC.filter { $0.isNumber }
                        if !digits.isEmpty { viewCountText = digits }
                    }
                }
                if publishedTimeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    if let rel = primary.dateText, !rel.isEmpty { publishedTimeText = rel }
                    if let iso = primary.publishDateISO, publishedTimeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { publishedTimeText = iso }
                }
            }
        }

        // Her durumda: canlılarda "watching now" genelde primaryInfo.run'larda olur; rawViewCountText'i koşulsuz doldur
        if let primary = Self.extractPrimaryInfo(from: html), let rawVC = primary.viewCountRaw, !rawVC.isEmpty {
            rawViewCountTextForReturn = rawVC
        }

    // Not: Tüm istekler zaten en/US ile yapıldığından, ikinci bir en/US denemesine gerek yok.

        // oEmbed fallback (çok hafif JSON) – başlık ve kanal ismi sıklıkla buradan gelir
        if title.isEmpty || author.isEmpty {
            if let o = try? await fetchOEmbed(videoId: videoId) {
                if title.isEmpty { title = o.title }
                if author.isEmpty { author = o.author }
            }
        }

    // Görüntüleme sayısını tek merkezden normalize et
    viewCountText = normalizeViewCountText(viewCountText)

        // Yayınlanma tarihini tek merkezden normalize et
        let (displayDate, _) = normalizePublishedDisplay(publishedTimeText)
        publishedTimeText = displayDate
        // Daha uzun açıklamayı HTML + ytInitialData içinden çek
        let longDesc = Self.extractLongDescription(from: html, shortDescription: desc)

        let result = LocalVideoData(
            id: videoId,
            title: title,
            author: author,
            channelId: channelId,
            shortDescription: desc,
            longDescription: longDesc,
            viewCountText: viewCountText,
            rawViewCountText: rawViewCountTextForReturn,
            publishedTimeText: publishedTimeText,
            durationSeconds: durationSecondsForReturn,
            durationText: durationTextForReturn
        )
        #if DEBUG
    // (Debug loglar temizlendi)
        #endif
        return result
    }

    // MARK: - PlayerResponse extraction
    private static func extractPlayerResponseJSON(from html: String) -> String? {
        let markers = [
            "ytInitialPlayerResponse = ",
            "var ytInitialPlayerResponse = ",
            "window.ytInitialPlayerResponse = "
        ]
        for marker in markers {
            guard let r = html.range(of: marker) else { continue }
            let after = r.upperBound
            guard let braceStart = html[after...].firstIndex(of: "{") else { continue }
            if let (json, _) = ParsingUtils.balancedJSONObject(from: html, startIndex: braceStart) {
                return json
            }
        }
        return nil
    }
}

// MARK: - Fallback helpers & formatting
private extension LocalYouTubeService {
    func fetchOEmbed(videoId: String) async throws -> (title: String, author: String) {
        let urlString = "https://www.youtube.com/oembed?url=https://www.youtube.com/watch?v=\(videoId)&format=json"
        guard let url = URL(string: urlString) else { throw LocalYouTubeError.network }
        let (data, resp) = try await URLSession.shared.data(from: url)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw LocalYouTubeError.network }
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let title = (obj["title"] as? String) ?? ""
            let author = (obj["author_name"] as? String) ?? (obj["author"] as? String) ?? ""
            return (title, author)
        }
        throw LocalYouTubeError.decode
    }

    // Dil duyarlı global yardımcılar kullanıldığı için yerel formatlayıcılar kaldırıldı
}

// MARK: - Long Description Extraction Helpers
private extension LocalYouTubeService {
    // YouTube sayfasında bazen uzun açıklama ek JSON bloklarında geçer.
    // Heuristik: "attributedDescription" veya "description":{"simpleText":"..."} kalıbını ara.
    static func extractLongDescription(from html: String, shortDescription: String) -> String? {
        func unescape(_ raw: String) -> String {
            raw.replacingOccurrences(of: "\\n", with: "\n")
                .replacingOccurrences(of: "\\u0026", with: "&")
        }
        // 1) attributedDescription içinde content veya simpleText yakala
        if let attrRange = html.range(of: "\"attributedDescription\":") {
            let snippet = String(html[attrRange.lowerBound...].prefix(8000))
            let patterns = ["\\\"content\\\":\\\"(.*?)\\\"", "\\\"simpleText\\\":\\\"(.*?)\\\""]
            for p in patterns {
                if let regex = try? NSRegularExpression(pattern: p, options: [.dotMatchesLineSeparators]) {
                    if let m = regex.firstMatch(in: snippet, range: NSRange(location: 0, length: (snippet as NSString).length)) {
                        if let r1 = Range(m.range(at: 1), in: snippet) {
                            let candidate = unescape(String(snippet[r1]))
                            if candidate.count > shortDescription.count { return candidate }
                        }
                    }
                }
            }
        }
        // 2) microformatDataRenderer description.simpleText
        if let microRange = html.range(of: "microformatDataRenderer") {
            let snippet = String(html[microRange.lowerBound...].prefix(6000))
            if let regex = try? NSRegularExpression(pattern: "\\\"description\\\"\\s*:\\s*\\{.*?\\\"simpleText\\\":\\\"(.*?)\\\"", options: [.dotMatchesLineSeparators]) {
                if let m = regex.firstMatch(in: snippet, range: NSRange(location: 0, length: (snippet as NSString).length)), let r1 = Range(m.range(at: 1), in: snippet) {
                    let candidate = unescape(String(snippet[r1]))
                    if candidate.count > shortDescription.count { return candidate }
                }
            }
        }

        // 2.5) Yapısal JSON parse ile ytInitialData içinden videoSecondaryInfoRenderer.description.runs
        if let structured = extractStructuredDescriptionFromInitialData(html: html), structured.count > shortDescription.count {
            return structured
        }
        // 3) ytInitialData içindeki description.runs dizisi (birçok metin + \n ayrı öğeler halinde olabilir)
        if let initDataRange = html.range(of: "ytInitialData") {
            let tail = String(html[initDataRange.lowerBound...])
        // Regex kalıplarını raw string ( #"..."# ) ile yazarak kaçış sorunlarını önlüyoruz
        let runsPattern = #"\"description\"\s*:\s*\{\s*\"runs\"\s*:\s*\["#
        if let runsStart = tail.range(of: runsPattern, options: .regularExpression) {
                let after = tail[runsStart.upperBound...]
                var depth = 1 // bracket depth for runs array
                var collected = ""
                var idx = after.startIndex
                let end = after.endIndex
                // basit state machine: her \"text\":\"...\" değerini çek
                while idx < end && depth > 0 && collected.count < 20000 {
                    let ch = after[idx]
                    if ch == "[" { depth += 1 }
                    else if ch == "]" { depth -= 1; if depth == 0 { break } }
            let textPattern = #"\"text\"\s*:\s*\""#
            if let textRange = after[idx...].range(of: textPattern, options: .regularExpression) {
                        let start = textRange.upperBound
                        var j = start
                        var buffer = ""
                        while j < end {
                            let cj = after[j]
                            if cj == "\\" { // escape
                                let nextIndex = after.index(after: j)
                                if nextIndex < end {
                                    let esc = after[nextIndex]
                                    switch esc {
                                    case "n": buffer.append("\n")
                                    case "\\": buffer.append("\\")
                                    case "\"": buffer.append("\"")
                                    default: buffer.append(esc)
                                    }
                                    j = after.index(after: nextIndex)
                                    continue
                                }
                            } else if cj == "\"" { // end of this text token
                                j = after.index(after: j)
                                idx = j
                                collected.append(buffer)
                                break
                            }
                            buffer.append(cj)
                            j = after.index(after: j)
                        }
                    } else { idx = after.index(after: idx) }
                }
                let final = unescape(collected)
                if final.count > shortDescription.count { return final }
            }
        }
        return nil
    }

    // MARK: - Structured ytInitialData JSON parsing
    static func extractStructuredDescriptionFromInitialData(html: String) -> String? {
        // ytInitialData sözlüğünü ParsingUtils ile çek
        guard let rootAny = ParsingUtils.extractInitialDataDict(html: html) else { return nil }
        // path: contents.twoColumnWatchNextResults.results.results.contents[] -> videoSecondaryInfoRenderer.description
    func firstDict(_ any: Any?) -> [String: Any]? { any as? [String: Any] }
    func arr(_ any: Any?) -> [[String: Any]]? { any as? [[String: Any]] }
        guard
            let contents = firstDict(rootAny["contents"]),
            let twoCol = firstDict(contents["twoColumnWatchNextResults"]),
            let results = firstDict(twoCol["results"]),
            let innerResults = firstDict(results["results"]),
            let contentArray = arr(innerResults["contents"]) else { return nil }
    // Yardımcı: runs dizisini satır sonlarını koruyarak birleştir
    func combineRuns(_ runs: [[String: Any]]) -> String {
            var out = String()
            out.reserveCapacity(runs.count * 12)
            let timestampRegex = try? NSRegularExpression(pattern: "^(?:[0-5]?\\d:)?[0-5]\\d:[0-5]\\d\\s+.+")
            for (idx, run) in runs.enumerated() {
                guard var t = run["text"] as? String else { continue }
                // JSON içinde kaçışmış \n'leri gerçek newline'a çevir
                t = t.replacingOccurrences(of: "\\n", with: "\n")
                // Tek başına \r -> atla
                t = t.replacingOccurrences(of: "\r", with: "")
                // Eğer bu bir timestamp satırıysa ve önceki satır newline ile bitmiyorsa newline ekle
                if let tsRegex = timestampRegex,
                   tsRegex.firstMatch(in: t, range: NSRange(location: 0, length: (t as NSString).length)) != nil {
                    if !out.hasSuffix("\n") && !out.isEmpty { out.append("\n") }
                }
                out.append(t)
                // Eğer bu run açıkça newline içermiyorsa ve bir sonraki run timestamp ile başlıyorsa araya newline ekle
                if !out.hasSuffix("\n"), idx + 1 < runs.count {
                    if let nextText = runs[idx+1]["text"] as? String, let tsRegex = timestampRegex,
                       tsRegex.firstMatch(in: nextText, range: NSRange(location: 0, length: (nextText as NSString).length)) != nil {
                        out.append("\n")
                    }
                }
            }
            return out
        }
        var bestCandidate: String = ""
        func consider(_ text: String?) {
            guard let text = text, !text.isEmpty else { return }
            if text.count > bestCandidate.count { bestCandidate = text }
        }
        // videoSecondaryInfoRenderer.description
        for item in contentArray {
            if let sec = firstDict(item["videoSecondaryInfoRenderer"]),
               let desc = firstDict(sec["description"]) {
                if let simple = desc["simpleText"] as? String { consider(simple.replacingOccurrences(of: "\\n", with: "\n")) }
                if let runs = desc["runs"] as? [[String: Any]] {
                    let combined = combineRuns(runs)
                    consider(combined)
                }
            }
        }

        // 2) engagementPanels -> structuredDescriptionContentRenderer (daha uzun / tamamen biçimlendirilmiş açıklama burada olabilir)
    if let panels = rootAny["engagementPanels"] as? [[String: Any]] {
            for panel in panels {
                guard let list = panel["engagementPanelSectionListRenderer"] as? [String: Any] else { continue }
                // identifier genellikle "engagement-panel-structured-description" olur
                if let identifier = list["identifier"] as? String, identifier.contains("structured-description") {
                    if let content = list["content"] as? [String: Any],
                       let structured = content["structuredDescriptionContentRenderer"] as? [String: Any],
                       let items = structured["items"] as? [[String: Any]] {
                        // items içinde videoDescriptionMetadataRenderer ara
                        for item in items {
                            if let meta = item["videoDescriptionMetadataRenderer"] as? [String: Any],
                               let desc = meta["description"] as? [String: Any] {
                if let simple = desc["simpleText"] as? String { consider(simple.replacingOccurrences(of: "\\n", with: "\n")) }
                if let runs = desc["runs"] as? [[String: Any]] { consider(combineRuns(runs)) }
                            }
                        }
                    }
                }
            }
        }
    return bestCandidate.isEmpty ? nil : bestCandidate
    }
}

// MARK: - Minimal modeller
private struct PlayerResponse: Decodable { let videoDetails: VideoDetails? }
private struct VideoDetails: Decodable {
    let title: String?
    let author: String?
    let channelId: String?
    let shortDescription: String?
    let viewCount: String?
    let publishDate: String?
    let lengthSeconds: String?
}

// MARK: - PrimaryInfo structured extraction
private extension LocalYouTubeService {
    struct PrimaryInfoData { let viewCountRaw: String?; let dateText: String?; let publishDateISO: String? }
    static func extractPrimaryInfo(from html: String) -> PrimaryInfoData? {
        // ytInitialData sözlüğünü ParsingUtils ile çek
        guard let root = ParsingUtils.extractInitialDataDict(html: html) else { return nil }
        func firstDict(_ any: Any?) -> [String: Any]? { any as? [String: Any] }
        func arr(_ any: Any?) -> [[String: Any]]? { any as? [[String: Any]] }
        guard
            let contents = firstDict(root["contents"]),
            let twoCol = firstDict(contents["twoColumnWatchNextResults"]),
            let results = firstDict(twoCol["results"]),
            let innerResults = firstDict(results["results"]),
            let contentArray = arr(innerResults["contents"])
        else { return nil }
        var vc: String? = nil
        var dateText: String? = nil
        var publishISO: String? = nil
        for item in contentArray {
            if let primary = firstDict(item["videoPrimaryInfoRenderer"]) {
                if let viewCount = firstDict(primary["viewCount"]),
                   let renderer = firstDict(viewCount["videoViewCountRenderer"]) ?? firstDict(viewCount["viewCountRenderer"]) {
                    if let simple = firstDict(renderer["viewCount"])?["simpleText"] as? String { vc = simple }
                    if vc == nil, let vcObj = firstDict(renderer["viewCount"]), let runs = vcObj["runs"] as? [[String: Any]] {
                        let joined = runs.compactMap { $0["text"] as? String }.joined()
                        if !joined.isEmpty { vc = joined }
                    }
                    if vc == nil, let simple = renderer["shortViewCount"] as? [String: Any], let st = simple["simpleText"] as? String { vc = st }
                }
                if let dt = firstDict(primary["dateText"])?["simpleText"] as? String { dateText = dt }
            }
            if let secondary = firstDict(item["videoSecondaryInfoRenderer"]) {
                if publishISO == nil, let owner = firstDict(secondary["owner"]), owner.isEmpty { /* placeholder */ }
            }
        }
        // microformat publishDate fallback
        if publishISO == nil, let micro = firstDict(root["microformat"]), let renderer = firstDict(micro["playerMicroformatRenderer"]) {
            if let p = renderer["publishDate"] as? String { publishISO = p }
        }
        return (vc != nil || dateText != nil || publishISO != nil) ? PrimaryInfoData(viewCountRaw: vc, dateText: dateText, publishDateISO: publishISO) : nil
    }
}
