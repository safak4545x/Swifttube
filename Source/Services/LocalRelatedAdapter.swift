/*
 File Overview (EN)
 Purpose: Local adapter to fetch related videos from a watch page using structured JSON traversal with robust fallbacks.
 Key Responsibilities:
 - Parse ytInitialData secondaryResults to build YouTubeVideo items
 - Fallback to deep traversal, raw renderer scanning, and regex extraction when needed
 - Cache results per videoId with TTL to reduce network
 Used By: RelatedVideosView population and enrichment flows.

 Dosya Özeti (TR)
 Amacı: İzleme sayfasından ilgili videoları yapısal JSON üzerinden çıkaran, güçlü geri dönüşler içeren yerel adaptör.
 Ana Sorumluluklar:
 - ytInitialData secondaryResults yolunu ayrıştırıp YouTubeVideo öğeleri üretmek
 - Gerekirse derin tarama, ham renderer taraması ve regex çıkarımı ile yedeklemek
 - videoId başına sonuçları TTL ile önbelleğe almak
 Nerede Kullanılır: RelatedVideosView doldurma ve zenginleştirme akışları.
*/


import Foundation

enum LocalRelatedAdapter {
    struct ParseError: Error, LocalizedError { var errorDescription: String? { "Related parse failed" } }

    static func fetchRelated(videoId: String, hl: String? = nil, gl: String? = nil) async throws -> [YouTubeVideo] {
    // Bölgeye bağlı değişimi önlemek için daima en/US kullan
        // Cache key: related by videoId + locale
        let cacheKey = CacheKey("related:vid=\(videoId)|hl=en|gl=US")
        if let cached: [YouTubeVideo] = await GlobalCaches.json.get(key: cacheKey, type: [YouTubeVideo].self), !cached.isEmpty {
            return cached
        }
    let urlString = "https://www.youtube.com/watch?v=\(videoId)&hl=en&persist_hl=1&gl=US&persist_gl=1"
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }

        var req = RequestFactory.makeYouTubeHTMLRequest(url: url, hl: "en", gl: "US")
        // Preserve explicit Accept header used previously
        req.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
    print("🔍 Fetch related (local) videoId=\(videoId) url=\(urlString)")

        let (data, _) = try await URLSession.shared.data(for: req)
        guard let html = String(data: data, encoding: .utf8) else { throw URLError(.cannotDecodeContentData) }

        if html.contains("consent.youtube.com") || html.lowercased().contains("consent") {
            print("⚠️ Consent interstitial detected; cookies may be insufficient.")
        }

    guard let root = ParsingUtils.extractInitialDataDict(html: html) else {
            print("⚠️ ytInitialData not found for related videos.")
            return []
        }

        // Primary path: contents.twoColumnWatchNextResults.secondaryResults.secondaryResults.results[*]
        var results: [YouTubeVideo] = []
        let contents = ((root["contents"] as? [String: Any])? ["twoColumnWatchNextResults"] as? [String: Any])
        let secondaryLevel1 = (contents?["secondaryResults"] as? [String: Any])
        let secondary = (secondaryLevel1?["secondaryResults"] as? [String: Any])
        let itemsPrimary = (secondary?["results"] as? [[String: Any]]) ?? []

        // Alternate path observed sometimes: contents.twoColumnWatchNextResults.secondaryResults.results
        let itemsAlt = (secondaryLevel1?["results"] as? [[String: Any]]) ?? []

        var consumedItems: [[String: Any]] = []
        if !itemsPrimary.isEmpty {
            consumedItems = itemsPrimary
        } else if !itemsAlt.isEmpty {
            print("🧩 Using alternate secondaryResults.results path (primary empty)")
            consumedItems = itemsAlt
        }

        if !consumedItems.isEmpty {
            var usedPrimaryIds = Set<String>()
            for item in consumedItems {
                if let built = buildVideo(from: item, currentVideoId: videoId) {
                    if usedPrimaryIds.insert(built.id).inserted {
                        results.append(built)
                    }
                }
            }
            if results.isEmpty && !consumedItems.isEmpty {
                print("⚠️ Primary/alternate path had \(consumedItems.count) items but none built into videos (likely no renderers).")
            }
        }

        if results.isEmpty {
            // Deep recursive search for any compactVideoRenderer/videoRenderer objects
            var deepRenderers: [[String: Any]] = []
            collectVideoRenderers(from: root, into: &deepRenderers, limit: 40)
            if !deepRenderers.isEmpty {
                print("🧩 Deep search found \(deepRenderers.count) renderer objects (using as fallback)")
                var usedIds = Set<String>()
                for vr in deepRenderers {
                    guard let built = buildVideo(from: vr, currentVideoId: videoId) else { continue }
                    if usedIds.insert(built.id).inserted { results.append(built) }
                    if results.count >= 25 { break }
                }
            }
        }

        if results.isEmpty {
            // Scan raw HTML for compactVideoRenderer JSON chunks and parse individually
            let scanned = scanRendererObjects(html: html, currentId: videoId)
            if !scanned.isEmpty {
                print("🔎 Renderer-scan fallback produced \(scanned.count) items")
                return scanned
            }

            // Fallback regex extraction from raw HTML if JSON traversal failed
            let regexVideos = regexFallback(html: html, currentId: videoId)
            if !regexVideos.isEmpty {
                print("🧪 Regex fallback produced \(regexVideos.count) related items")
                return regexVideos
            }
            // Additional diagnostics
            let cvCount = html.components(separatedBy: "compactVideoRenderer").count - 1
            print("⚠️ All related extraction strategies empty. compactVideoRenderer occurrences=\(cvCount)")
        }

    print("✅ Parsed related count=\(results.count)")
    // Cache for 1 hour
    await GlobalCaches.json.set(key: cacheKey, value: results, ttl: CacheTTL.oneHour)
    return results
    }

    // extractInitialData / extractJSONObject kaldırıldı: ParsingUtils kullanılıyor

    // MARK: - Deep traversal utilities
    private static func collectVideoRenderers(from node: Any, into arr: inout [[String: Any]], limit: Int) {
        if arr.count >= limit { return }
        if let dict = node as? [String: Any] {
            if let vr = dict["compactVideoRenderer"] as? [String: Any] { arr.append(["compactVideoRenderer": vr]) }
            else if let vr = dict["videoRenderer"] as? [String: Any] { arr.append(["videoRenderer": vr]) }
            if arr.count >= limit { return }
            for (_, v) in dict { collectVideoRenderers(from: v, into: &arr, limit: limit) }
        } else if let list = node as? [Any] {
            for v in list { collectVideoRenderers(from: v, into: &arr, limit: limit); if arr.count >= limit { break } }
        }
    }

    private static func buildVideo(from wrapper: [String: Any], currentVideoId: String) -> YouTubeVideo? {
        let vr = (wrapper["compactVideoRenderer"] as? [String: Any]) ?? (wrapper["videoRenderer"] as? [String: Any])
        guard let videoRenderer = vr,
              let vid = videoRenderer["videoId"] as? String,
              vid != currentVideoId else { return nil }
        func extractTextBlock(_ dict: [String: Any]?) -> String {
            guard let dict else { return "" }
            if let simple = dict["simpleText"] as? String { return simple }
            if let runs = dict["runs"] as? [[String: Any]] {
                return runs.compactMap { $0["text"] as? String }.joined()
            }
            if let label = (dict["accessibility"] as? [String: Any])?["accessibilityData"] as? [String: Any], let l = label["label"] as? String { return l }
            return ""
        }
    func decodeHTML(_ s: String) -> String { ParsingUtils.decodeHTMLEntities(s) }

        // Title: try several fields
        let titleDict = (videoRenderer["title"] as? [String: Any])
            ?? (videoRenderer["headline"] as? [String: Any])
            ?? (videoRenderer["detailedMetadataSnippets"] as? [[String: Any]])?.first?["snippetText"] as? [String: Any]
        var title = extractTextBlock(titleDict)
        // Channel
        let ownerRuns = ((videoRenderer["shortBylineText"] as? [String: Any])? ["runs"] as? [[String: Any]])
            ?? ((videoRenderer["ownerText"] as? [String: Any])? ["runs"] as? [[String: Any]])
            ?? ((videoRenderer["longBylineText"] as? [String: Any])? ["runs"] as? [[String: Any]])
        let channelTitle = ownerRuns?.first? ["text"] as? String ?? ""
        let channelBrowseId = ((ownerRuns?.first? ["navigationEndpoint"] as? [String: Any])? ["browseEndpoint"] as? [String: Any])? ["browseId"] as? String ?? ""
        // View count
        var viewCount = extractTextBlock(videoRenderer["shortViewCountText"] as? [String: Any])
        if viewCount.isEmpty { viewCount = extractTextBlock(videoRenderer["viewCountText"] as? [String: Any]) }
        // Published time
        var publishedAt = extractTextBlock(videoRenderer["publishedTimeText"] as? [String: Any])
        // Thumbnail
    var thumb = youtubeThumbnailURL(vid, quality: .mqdefault)
        if let th = (videoRenderer["thumbnail"] as? [String: Any])? ["thumbnails"] as? [[String: Any]], let u = th.last? ["url"] as? String { thumb = u }

        title = decodeHTML(title)
        publishedAt = decodeHTML(publishedAt)
        viewCount = decodeHTML(viewCount)

        // Fallback: some compactVideoRenderer variants only expose metadata in aggregated lines (metadataLine / inlineMetadata)
        if (viewCount.isEmpty || publishedAt.isEmpty) {
            var collected: [String] = []
            func walk(_ node: Any, depth: Int = 0) {
                if depth > 4 { return } // limit depth for performance
                if let dict = node as? [String: Any] {
                    if let st = dict["simpleText"] as? String { collected.append(st) }
                    if let runs = dict["runs"] as? [[String: Any]] {
                        for r in runs {
                            if let t = r["text"] as? String { collected.append(t) }
                        }
                    }
                    // Recurse values
                    for (_, v) in dict { walk(v, depth: depth + 1) }
                } else if let arr = node as? [Any] {
                    for v in arr { walk(v, depth: depth + 1) }
                }
            }
            walk(videoRenderer)
            // Heuristics: pick first string containing view keywords and digits, and first containing relative time keywords
            if viewCount.isEmpty {
                if let vc = collected.first(where: { str in
                    let lower = str.lowercased()
                    let hasDigits = str.range(of: "[0-9]", options: .regularExpression) != nil
                    return hasDigits && (lower.contains("view") || lower.contains("izlenme") || lower.contains("görüntüleme"))
                }) { viewCount = vc }
            }
            if publishedAt.isEmpty {
                if let pub = collected.first(where: { str in
                    let lower = str.lowercased()
                    return lower.contains("ago") || lower.contains("önce") || lower.contains("yıl") || lower.contains("ay") || lower.contains("gün")
                }) { publishedAt = pub }
            }
            if (viewCount.isEmpty && publishedAt.isEmpty) == false {
                // Optionally log once per video when fallback used
                // Uncomment for debugging:
                // print("ℹ️ Fallback metadata extracted for related vid=\(vid) views=\(viewCount) published=\(publishedAt)")
            }
        }

        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { title = vid }

        return YouTubeVideo(
            id: vid,
            title: title,
            channelTitle: channelTitle,
            channelId: channelBrowseId,
            viewCount: viewCount,
            publishedAt: publishedAt,
            thumbnailURL: thumb,
            description: "",
            channelThumbnailURL: "",
            likeCount: "0",
            durationText: "",
            durationSeconds: nil
        )
    }

    // MARK: - Raw HTML renderer scan fallback
    private static func scanRendererObjects(html: String, currentId: String) -> [YouTubeVideo] {
        var videos: [YouTubeVideo] = []
        let marker = "\"compactVideoRenderer\":"
        var searchRange: Range<String.Index>? = html.startIndex..<html.endIndex
        var seenIds = Set<String>()
        while let range = html.range(of: marker, options: [], range: searchRange) {
            // After marker expect '{'
            guard let brace = html[range.upperBound...].firstIndex(of: "{") else { break }
            // Use balanced brace to extract object
            var depth = 0
            var idx = brace
            var inString = false
            var prev: Character = "\0"
            while idx < html.endIndex {
                let ch = html[idx]
                if ch == "\"" && prev != "\\" { inString.toggle() }
                if !inString {
                    if ch == "{" { depth += 1 }
                    else if ch == "}" {
                        depth -= 1
                        if depth == 0 { // end of object
                            let jsonStr = String(html[brace...idx])
                            if let data = jsonStr.data(using: .utf8),
                               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                                let wrapper: [String: Any] = ["compactVideoRenderer": obj]
                                if var built = buildVideo(from: wrapper, currentVideoId: currentId) {
                                    if built.title == built.id {
                                        // Lightweight regex: look for "title":{"runs":[{"text":"..."}] or simpleText
                                        let titlePatterns = [
                                            #"\"title\":\{[^}]*\"simpleText\":\"([^\"]+)"#,
                                            #"\"title\":\{[^}]*\"runs\":\[\{\"text\":\"([^\"]+)"#
                                        ]
                                        for pat in titlePatterns {
                                            if let r = jsonStr.range(of: pat, options: .regularExpression) {
                                                let matchStr = String(jsonStr[r])
                                                if let extracted = matchStr.components(separatedBy: "\"").last, !extracted.isEmpty {
                                                    built = YouTubeVideo(id: built.id, title: extracted, channelTitle: built.channelTitle, channelId: built.channelId, viewCount: built.viewCount, publishedAt: built.publishedAt, thumbnailURL: built.thumbnailURL, description: "", channelThumbnailURL: built.channelThumbnailURL)
                                                    // duration defaults preserved
                                                    break
                                                }
                                            }
                                        }
                                    }
                                    if !seenIds.contains(built.id) {
                                        videos.append(built)
                                        seenIds.insert(built.id)
                                        if videos.count >= 25 { return videos }
                                    }
                                }
                            }
                            searchRange = html.index(after: idx)..<html.endIndex
                            break
                        }
                    }
                }
                prev = ch
                idx = html.index(after: idx)
            }
            if idx >= html.endIndex { break }
        }
        return videos
    }

    // MARK: - Regex Fallback
    // Extract videoIds & titles from raw HTML when JSON path fails
    private static func regexFallback(html: String, currentId: String) -> [YouTubeVideo] {
        var videos: [YouTubeVideo] = []
        // Simple videoId pattern
        let pattern = "\\\"videoId\\\":\\\"([A-Za-z0-9_-]{11})\\\""
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return [] }
        let matches = regex.matches(in: html, options: [], range: NSRange(location: 0, length: html.utf16.count))
        var seen = Set<String>()
        for m in matches {
            if m.numberOfRanges < 2 { continue }
            let nsr = m.range(at: 1)
            if let r = Range(nsr, in: html) {
                let vid = String(html[r])
                if vid == currentId || seen.contains(vid) { continue }
                seen.insert(vid)
                // Find a nearby title snippet
                let contextRadius = 500
                let utf16 = html.utf16
                let startOffset = max(nsr.location - contextRadius, 0)
                let endOffset = min(nsr.location + nsr.length + contextRadius, utf16.count)
                let ctxRange = NSRange(location: startOffset, length: endOffset - startOffset)
                var title = ""
                if let ctx = Range(ctxRange, in: html) {
                    let snippet = String(html[ctx])
                    // Patterns for title
                    if let titleRange = snippet.range(of: "\"title\":\\\"") { // simpleText style
                        let after = snippet[titleRange.upperBound...]
                        if let endQuote = after.firstIndex(of: "\"") {
                            title = String(after[..<endQuote])
                        }
                    }
                    if title.isEmpty, let runsRange = snippet.range(of: "\"title\":{\"runs\":[{\"text\":\"") {
                        let after = snippet[runsRange.upperBound...]
                        if let endQuote = after.firstIndex(of: "\"") { title = String(after[..<endQuote]) }
                    }
                }
                if title.isEmpty { title = vid }
                videos.append(
                    YouTubeVideo(
                        id: vid,
                        title: title,
                        channelTitle: "", // Unknown in fallback
                        channelId: "",
                        viewCount: "",
                        publishedAt: "",
                        thumbnailURL: youtubeThumbnailURL(vid, quality: .mqdefault),
                        description: "",
                        channelThumbnailURL: "",
                        likeCount: "0",
                        durationText: "",
                        durationSeconds: nil
                    )
                )
                if videos.count >= 25 { break }
            }
        }
        return videos
    }
}
