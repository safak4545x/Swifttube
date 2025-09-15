
/*
 File Overview (EN)
 Purpose: Local HTML/JSON scraping for channel search, channel info, and channel videos without using official APIs.
 Key Responsibilities:
 - Extract ytInitialData and parse channel renderers and video renderers
 - Normalize avatar/banner URLs; approximate numeric fields; cache results with TTL
 - Force en/US locale for consistency; do not parse subscriber counts locally
 Used By: ChannelService and various enrichment operations.

 Dosya Özeti (TR)
 Amacı: Resmi API kullanmadan kanal arama/bilgi ve kanal videolarını yerel HTML/JSON kazıma ile elde etmek.
 Ana Sorumluluklar:
 - ytInitialData çıkarmak; channel/video renderer yapılarını ayrıştırmak
 - Avatar/banner URL normalize etmek; sayısal alanları yaklaşık çözmek; TTL ile önbelleğe almak
 - Tutarlılık için en/US yerel ayarını zorlamak; abone sayısını yerelde ayrıştırmamak
 Nerede Kullanılır: ChannelService ve çeşitli zenginleştirme işlemleri.
*/

import Foundation

/// Yerel (FreeTube tarzı) kanal işlemleri: HTML içindeki gömülü JSON'dan parse
enum LocalChannelAdapter {
    // Basit yardımcı: detay almak için
    static func fetchChannelDetails(channelId: String) async -> YouTubeChannel? {
        return try? await fetchChannelInfo(channelId: channelId)
    }

    enum LocalError: Error { case notFound, badHTML, badJSON }

    // Kanal arama: results sayfasındaki channelRenderer öğelerini parse eder
    static func searchChannels(query: String, hl: String = "en", gl: String? = "US") async throws -> [YouTubeChannel] {
        // Cache key: channel search by query + locale
        let cacheKey = CacheKey("channel:search:q=\(query.lowercased())|hl=en|gl=US")
        if let cached: [YouTubeChannel] = await GlobalCaches.json.get(key: cacheKey, type: [YouTubeChannel].self), !cached.isEmpty {
            return cached
        }
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return [] }
    let urlString = "https://www.youtube.com/results?search_query=\(encoded)&sp=EgIQAg%253D%253D&hl=en&persist_hl=1&gl=US&persist_gl=1" // channel filter
        guard let url = URL(string: urlString) else { return [] }

    var req = RequestFactory.makeYouTubeHTMLRequest(url: url, hl: "en", gl: "US")
        let (data, _) = try await URLSession.shared.data(for: req)
        guard let html = String(data: data, encoding: .utf8) else { throw LocalError.badHTML }

          // Daha sağlam: önce basit çıkarma, olmazsa robust dengeli süslü metodu dene
          var root: [String: Any]? = nil
          if let jsonStr = ParsingUtils.extractJSON(from: html, startMarker: "ytInitialData = ", endMarker: "};"),
              let jsonData = (jsonStr + "}").data(using: .utf8),
              let r = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] { root = r }
          if root == nil { root = ParsingUtils.extractInitialDataDict(html: html) }
          guard let root else { return [] }

        var channels: [YouTubeChannel] = []
        if let contents = ((root["contents"] as? [String: Any])? ["twoColumnSearchResultsRenderer"] as? [String: Any])? ["primaryContents"] as? [String: Any],
           let sectionList = contents["sectionListRenderer"] as? [String: Any],
           let sections = sectionList["contents"] as? [[String: Any]] {
            for section in sections {
                if let itemSection = section["itemSectionRenderer"] as? [String: Any],
                   let items = itemSection["contents"] as? [[String: Any]] {
                    for item in items {
                        guard let cr = item["channelRenderer"] as? [String: Any] else { continue }
                        let id = cr["channelId"] as? String ?? ((cr["navigationEndpoint"] as? [String: Any])? ["browseEndpoint"] as? [String: Any])? ["browseId"] as? String ?? ""
                        let title = ((cr["title"] as? [String: Any])? ["simpleText"] as? String)
                            ?? (((cr["title"] as? [String: Any])? ["runs"] as? [[String: Any]])?.first? ["text"] as? String) ?? ""
                        let description = ((cr["descriptionSnippet"] as? [String: Any])? ["runs"] as? [[String: Any]])?.map { ($0["text"] as? String) ?? "" }.joined() ?? ""
                        var avatarThumb = ((cr["thumbnail"] as? [String: Any])? ["thumbnails"] as? [[String: Any]])?.last? ["url"] as? String ?? ""
                        // Normalize & fallback
                        avatarThumb = normalizeAvatarURL(avatarThumb)
                        if avatarThumb.isEmpty {
                            // Fallback: channelRenderer JSON'unda geçen ilk yt3.* görsel URL'sini regex ile tara
                            if let data = try? JSONSerialization.data(withJSONObject: cr), let jsonText = String(data: data, encoding: .utf8) {
                                if let fallback = firstYT3Image(in: jsonText) { avatarThumb = fallback }
                            }
                        }
                        // Subscriber count intentionally NOT parsed locally anymore.
                        // It will be provided solely by official YouTube Data API – always 0 here.
                        let subscriberCount = 0

                        channels.append(
                            YouTubeChannel(
                                id: id,
                                title: title,
                                description: description,
                                thumbnailURL: avatarThumb,
                                bannerURL: nil,
                                subscriberCount: subscriberCount,
                                videoCount: 0
                            )
                        )
                    }
                }
            }
        }
    // Write-through cache (6 saat TTL)
    await GlobalCaches.json.set(key: cacheKey, value: channels, ttl: CacheTTL.sixHours)
    return channels
    }

    // Kanal bilgisi: header.c4TabbedHeaderRenderer'dan temel bilgiler
    static func fetchChannelInfo(channelId: String, hl: String = "en", gl: String? = "US") async throws -> YouTubeChannel? {
        // Cache key: channel info by id + locale
        // Force a stable cache key regardless of app region choices
        let cacheKey = CacheKey("channel:info:id=\(channelId)|hl=en|gl=US")
        if let cached: YouTubeChannel = await GlobalCaches.json.get(key: cacheKey, type: YouTubeChannel.self) {
            return cached
        }
    // Always request with en/US for consistent subscriber counts
    let urlString = "https://www.youtube.com/channel/\(channelId)?hl=en&persist_hl=1&gl=US&persist_gl=1"
        guard let url = URL(string: urlString) else { return nil }
    var req = RequestFactory.makeYouTubeHTMLRequest(url: url, hl: "en", gl: "US")
        let (data, _) = try await URLSession.shared.data(for: req)
        guard let html = String(data: data, encoding: .utf8) else { throw LocalError.badHTML }
        print("🧪 fetchChannelInfo start channel=\(channelId) htmlSize=\(html.count)")
        var root: [String: Any]? = nil
        if let jsonStr = ParsingUtils.extractJSON(from: html, startMarker: "ytInitialData = ", endMarker: "};") {
            let jsonData = Data((jsonStr + "}").utf8)
            if let r = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] { root = r } else {
                print("⚠️ fetchChannelInfo JSON parse failed (simple) channel=\(channelId) fragmentLen=\(jsonStr.count)")
            }
        }
        if root == nil {
            // Fallback: robust brace matching after various patterns
            print("🔁 fetchChannelInfo fallback robust extraction channel=\(channelId)")
            if let r = ParsingUtils.extractInitialDataDict(html: html) {
                root = r
            } else {
                print("❌ fetchChannelInfo could not extract ytInitialData channel=\(channelId)")
                return nil
            }
        }
        guard let root else { return nil }

        // --- ÇOKLU PARSE STRATEJİSİ ---
        var title = ""
        var id = channelId
        var description = ""
        var avatar = ""
    var bannerURL: String? = nil
        var subscriberCount = 0
    var videoCount = 0
        var sourceTag = ""

        // Ekstra erken pattern: imageBannerBackgroundImageUrl (escaped JSON içinde düz metin araması) şimdi bannerURL deklarasyonundan sonra
        if let earlyRange = html.range(of: "imageBannerBackgroundImageUrl\\\":\\\"") {
            let after = earlyRange.upperBound
            if let end = html[after...].firstIndex(of: "\"") {
                var raw = String(html[after..<end])
                raw = raw.replacingOccurrences(of: "\\/", with: "/").replacingOccurrences(of: "\\u0026", with: "&")
                raw = ParsingUtils.normalizeURL(raw)
                if raw.lowercased().contains("yt3") { bannerURL = raw }
            }
        }
    // (Not: Önceki ham string test kalıntıları kaldırıldı)

        // 1) header.c4TabbedHeaderRenderer
        if let header = root["header"] as? [String: Any], let c4 = header["c4TabbedHeaderRenderer"] as? [String: Any] {
            sourceTag = "c4"
            title = c4["title"] as? String ?? title
            id = c4["channelId"] as? String ?? id
            avatar = ((c4["avatar"] as? [String: Any])? ["thumbnails"] as? [[String: Any]])?.last? ["url"] as? String ?? avatar
            // Subscriber count parsing removed – will be fetched via official API.
            subscriberCount = 0
            // Video count text (ör: "1.234 video" / "1,234 videos")
            if let videosTextObj = c4["videosCountText"] as? [String: Any] {
                let vcTxt = (videosTextObj["simpleText"] as? String) ?? ((videosTextObj["runs"] as? [[String: Any]])?.map { ($0["text"] as? String) ?? "" }.joined()) ?? ""
                videoCount = approxNumber(from: vcTxt)
            }
            description = ((c4["description"] as? [String: Any])? ["simpleText"] as? String)
                ?? (((c4["description"] as? [String: Any])? ["runs"] as? [[String: Any]])?.map { ($0["text"] as? String) ?? "" }.joined()) ?? description
            // ---------- Banner Extraction (extended) ----------
            func extractBanner(_ dict: [String: Any], key: String) -> String? {
                if let b = dict[key] as? [String: Any], let ths = b["thumbnails"] as? [[String: Any]], let u = ths.last? ["url"] as? String { return u }
                return nil
            }
            // Try common keys (order matters)
            for key in ["banner", "imageBanner", "tvBanner", "mobileBanner", "desktopBanner"] {
                if bannerURL == nil, let u = extractBanner(c4, key: key) { bannerURL = u; sourceTag += "+" + key }
            }
            // Ek: hiçbir şey bulunmadıysa CSS background-image içinde çift tırnaklı varyantları ara
            if bannerURL == nil {
                let ns = html as NSString
                let fullRange = NSRange(location: 0, length: ns.length)
                if let cssRx = try? NSRegularExpression(pattern: #"background(?:-image)?:\s*url\("(https?:[^"]+)"\)"#, options: [.caseInsensitive]) {
                    if let m = cssRx.firstMatch(in: html, options: [], range: fullRange), m.numberOfRanges > 1 {
                        var cnd = ns.substring(with: m.range(at: 1)).replacingOccurrences(of: "\\/", with: "/")
                        cnd = ParsingUtils.normalizeURL(cnd)
                        if cnd.lowercased().contains("yt3") { bannerURL = cnd; print("🎯 css banner candidate channel=\(channelId) url=\(cnd.prefix(140))") }
                    }
                }
            }
            // Deep recursive search inside c4 if still nil
            if bannerURL == nil, let deep = findBannerRecursive(in: c4) { bannerURL = deep; sourceTag += "+deepC4" }
            if bannerURL == nil { print("🛑 c4 banner not found channel=\(channelId) keysTried=[banner,imageBanner,tvBanner,mobileBanner,desktopBanner]") }
        } else {
            print("ℹ️ fetchChannelInfo header c4TabbedHeaderRenderer yok channel=\(channelId)")
        }

        // 1b) Yeni layout olasılığı: channelHeaderRenderer
        if bannerURL == nil, let header = root["header"] as? [String: Any], let ch = header["channelHeaderRenderer"] as? [String: Any] {
            sourceTag = sourceTag.isEmpty ? "channelHeaderRenderer" : sourceTag + "+channelHeaderRenderer"
            func extractBanner(_ dict: [String: Any], key: String) -> String? {
                if let b = dict[key] as? [String: Any], let ths = b["thumbnails"] as? [[String: Any]], let u = ths.last? ["url"] as? String { return u }
                return nil
            }
            for key in ["banner", "imageBanner", "tvBanner", "mobileBanner", "desktopBanner"] {
                if bannerURL == nil, let u = extractBanner(ch, key: key) { bannerURL = u; sourceTag += "+" + key }
            }
            if bannerURL == nil, let deep = findBannerRecursive(in: ch) { bannerURL = deep; sourceTag += "+deepCH" }
            if bannerURL == nil { print("🛑 channelHeaderRenderer banner not found channel=\(channelId)") }
        }

        // 2) metadata.channelMetadataRenderer (fallback / override boşları)
        if let meta = (root["metadata"] as? [String: Any])? ["channelMetadataRenderer"] as? [String: Any] {
            if title.isEmpty { title = meta["title"] as? String ?? title }
            if let externalId = meta["externalId"] as? String, id == channelId { id = externalId }
            if description.isEmpty { description = meta["description"] as? String ?? description }
            if avatar.isEmpty { avatar = ((meta["avatar"] as? [String: Any])? ["thumbnails"] as? [[String: Any]])?.last? ["url"] as? String ?? avatar }
            if bannerURL == nil { bannerURL = ((meta["banner"] as? [String: Any])? ["thumbnails"] as? [[String: Any]])?.last? ["url"] as? String }
            if bannerURL == nil { bannerURL = ((meta["imageBanner"] as? [String: Any])? ["thumbnails"] as? [[String: Any]])?.last? ["url"] as? String }
            // Local subscriber count extraction removed.
            if !avatar.isEmpty && sourceTag.isEmpty { sourceTag = "metadata" }
        } else {
            // metadata olmayabilir, normal.
        }
        // Geniş spektrum tarama: metadata olsun/olmasın hâlâ yoksa tüm yt3.* image URL adaylarını topla
        if bannerURL == nil {
            let candidates = extractBannerCandidates(from: html)
            if !candidates.isEmpty {
                let chosen = candidates.first!
                bannerURL = chosen
                print("🧮 banner candidate sweep count=\(candidates.count) chosen=\(chosen.prefix(140))")
            }
        }

        // 3) microformat.microformatDataRenderer.thumbnail (son çare avatar)
        if avatar.isEmpty, let micro = (root["microformat"] as? [String: Any])? ["microformatDataRenderer"] as? [String: Any] {
            if let ths = ((micro["thumbnail"] as? [String: Any])? ["thumbnails"] as? [[String: Any]]), let u = ths.last? ["url"] as? String {
                avatar = u
                if sourceTag.isEmpty { sourceTag = "microformat" }
            }
            if title.isEmpty { title = micro["title"] as? String ?? title }
            if description.isEmpty { description = micro["description"] as? String ?? description }
        }

        // Eğer açıklama boşsa About sekmesini ayrı çek (lazy ek istek)
        if description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if let aboutURL = URL(string: "https://www.youtube.com/channel/\(channelId)/about?hl=en&gl=US" ) {
                var aboutReq = RequestFactory.makeYouTubeHTMLRequest(url: aboutURL, hl: "en", gl: "US")
                if let (aboutData, _) = try? await URLSession.shared.data(for: aboutReq), let aboutHTML = String(data: aboutData, encoding: .utf8) {
                    if let aboutRoot = ParsingUtils.extractInitialDataDict(html: aboutHTML) ?? {
                        if let js = ParsingUtils.extractJSON(from: aboutHTML, startMarker: "ytInitialData = ", endMarker: "};") { return try? JSONSerialization.jsonObject(with: Data((js + "}").utf8)) as? [String: Any] }
                        return nil
                    }() {
                        if let meta = (aboutRoot["metadata"] as? [String: Any])? ["channelMetadataRenderer"] as? [String: Any], description.isEmpty {
                            description = meta["description"] as? String ?? description
                        }
                        if description.isEmpty, let micro = (aboutRoot["microformat"] as? [String: Any])? ["microformatDataRenderer"] as? [String: Any] {
                            description = micro["description"] as? String ?? description
                        }
                    }
                }
            }
        }

        let normalizedAvatar: String = ParsingUtils.normalizeURL(avatar)

        if bannerURL == nil {
            // Recursive arama: herhangi bir yerde {"banner":{"thumbnails":[...}} yapısını ara
            if let deep = findBannerRecursive(in: root) {
                print("🧩 deep banner candidate channel=\(channelId) url=\(deep.prefix(120))")
                // normalize
                bannerURL = ParsingUtils.normalizeURL(deep)
            } else {
                // Regex fallback çeşitleri (escaped JSON içindeki \/ şeklinde olabilir)
                let patterns = [
                    #"https?:\\/\\/yt3\\.googleusercontent\\.com\\/[^"']+"#,
                    #"https?:\\/\\/yt3\\.ggpht\\.com\\/[^"']+"#,
                    #"background-image:\\s*url\\((https?:[^)"']+)"#
                ]
                let ns = html as NSString
                let fullRange = NSRange(location: 0, length: ns.length)
                regexLoop: for p in patterns {
                    guard let rx = try? NSRegularExpression(pattern: p, options: [.caseInsensitive, .dotMatchesLineSeparators]) else { continue }
                    if let m = rx.firstMatch(in: html, options: [], range: fullRange) {
                        var candidate = ns.substring(with: m.range)
                        // pattern 3'te grup 1 gerçek URL
                        if m.numberOfRanges > 1, m.range(at: 1).location != NSNotFound {
                            candidate = ns.substring(with: m.range(at: 1))
                        }
                        // Unescape JSON tarzı
                        candidate = candidate
                            .replacingOccurrences(of: "\\/", with: "/")
                            .replacingOccurrences(of: "\\u0026", with: "&")
                        candidate = ParsingUtils.normalizeURL(candidate)
                        // Filtre: banner kelimesi yoksa da genişlik parametresi (=w) olabilir; çok küçük thumb'ları atla (=s88 gibi)
                        if candidate.lowercased().contains("banner") || candidate.contains("=w") || candidate.contains("-no") {
                            bannerURL = candidate
                            print("🧩 regex banner candidate channel=\(channelId) pattern=\(p) url=\(candidate.prefix(140))")
                            break regexLoop
                        }
                    }
                }
            }
        }
        // Son aşama: fallback sırasında bulunan banner'ı şimdi normalize et
        let finalNormalizedBanner: String? = bannerURL.map { ParsingUtils.normalizeURL($0) }
    if finalNormalizedBanner == nil {
            // Ek debug: HTML içinde geçen ilk birkaç (escaped veya normal) yt3 image URL'sini listele
            let patterns = [
                #"https:\\/\\/yt3[^\"' )]+"#,
                #"https?:\/\/yt3[^\"' )]+"#
            ]
            var collected: [String] = []
            for p in patterns {
                if let rx = try? NSRegularExpression(pattern: p, options: [.caseInsensitive]) {
                    let ns = html as NSString
                    let range = NSRange(location: 0, length: ns.length)
                    for m in rx.matches(in: html, options: [], range: range) {
                        let raw = ns.substring(with: m.range)
                        var cleaned = raw.replacingOccurrences(of: "\\/", with: "/").replacingOccurrences(of: "\\u0026", with: "&")
                        cleaned = ParsingUtils.normalizeURL(cleaned)
                        if !collected.contains(cleaned) { collected.append(cleaned) }
                        if collected.count >= 6 { break }
                    }
                }
                if collected.count >= 6 { break }
            }
            if !collected.isEmpty {
                print("🔍 debug yt3 sample channel=\(channelId) urls=\(collected)")
            } else {
                print("🔍 debug no yt3 urls captured channel=\(channelId) htmlSize=\(html.count)")
            }
        }
        // Final debug
        if let finalNormalizedBanner { print("✅ banner found channel=\(channelId) url=\(finalNormalizedBanner)") } else { print("🚫 banner not found channel=\(channelId)") }

        if normalizedAvatar.isEmpty {
            print("⚠️ fetchChannelInfo avatar bulunamadı channel=\(channelId) sourcesTried=[c4,metadata,microformat]")
            return nil // enrichment gereksiz boş dönersek tekrar tekrar deneyecek; nil iyi.
        } else {
            print("🔎 fetchChannelInfo(\(sourceTag)) channel=\(channelId) avatar=\(normalizedAvatar)")
        }
    // Removed legacy HTML/regex fallback for subscriber count.
    let built = YouTubeChannel(id: id, title: title, description: description, thumbnailURL: normalizedAvatar, bannerURL: finalNormalizedBanner, subscriberCount: subscriberCount, videoCount: videoCount)
    // Write-through cache (12 saat TTL)
    await GlobalCaches.json.set(key: cacheKey, value: built, ttl: CacheTTL.twelveHours)
    return built
    }

    // robustInitialDataDict ve balancedJSONObject artık ParsingUtils'te merkezileştirildi

    // Kanal videoları: /channel/{id}/videos sayfasından first page
    static func fetchChannelVideos(channelId: String, hl: String = "en", gl: String? = "US") async throws -> [YouTubeVideo] {
        // Cache key: channel videos first page by id + locale
        let cacheKey = CacheKey("channel:videos:id=\(channelId)|hl=en|gl=US")
        if let cached: [YouTubeVideo] = await GlobalCaches.json.get(key: cacheKey, type: [YouTubeVideo].self), !cached.isEmpty {
            return cached
        }
    let urlString = "https://www.youtube.com/channel/\(channelId)/videos?hl=en&gl=US"
        guard let url = URL(string: urlString) else { return [] }
    var req = RequestFactory.makeYouTubeHTMLRequest(url: url, hl: "en", gl: "US")
        let (data, _) = try await URLSession.shared.data(for: req)
    guard let html = String(data: data, encoding: .utf8) else { throw LocalError.badHTML }
    guard let jsonStr = ParsingUtils.extractJSON(from: html, startMarker: "ytInitialData = ", endMarker: "};") else { return [] }
        let jsonData = Data((jsonStr + "}").utf8)
        guard let root = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else { return [] }

        // Path: contents.twoColumnBrowseResultsRenderer.tabs[].tabRenderer.content.richGridRenderer.contents[].richItemRenderer.content.videoRenderer
        var videos: [YouTubeVideo] = []
        if let contents = ((root["contents"] as? [String: Any])? ["twoColumnBrowseResultsRenderer"] as? [String: Any])? ["tabs"] as? [[String: Any]] {
            for tab in contents {
                guard let tr = tab["tabRenderer"] as? [String: Any] else { continue }
                // 'Videos' tab has title or selected true
                let selected = (tr["selected"] as? Int == 1) || (tr["selected"] as? Bool == true)
                let title = ((tr["title"] as? String) ?? "").lowercased()
                guard selected || title.contains("video") || title.contains("videolar") else { continue }
                if let content = tr["content"] as? [String: Any] {
                    // New layout: richGridRenderer
                    if let rich = content["richGridRenderer"] as? [String: Any],
                       let items = rich["contents"] as? [[String: Any]] {
                        for item in items {
                            if let rir = item["richItemRenderer"] as? [String: Any],
                               let c = rir["content"] as? [String: Any],
                               let vr = c["videoRenderer"] as? [String: Any] {
                                if let v = parseVideoRenderer(vr, defaultChannelId: channelId) { videos.append(v) }
                            }
                        }
                    }
                    // Fallback: gridRenderer
                    if let grid = content["sectionListRenderer"] as? [String: Any],
                       let sec = (grid["contents"] as? [[String: Any]])?.first? ["itemSectionRenderer"] as? [String: Any],
                       let gr = (sec["contents"] as? [[String: Any]])?.first? ["gridRenderer"] as? [String: Any],
                       let items = gr["items"] as? [[String: Any]] {
                        for item in items {
                            if let gvr = item["gridVideoRenderer"] as? [String: Any] {
                                if let v = parseGridVideoRenderer(gvr, defaultChannelId: channelId) { videos.append(v) }
                            }
                        }
                    }
                }
            }
        }
    // Write-through cache (6 saat TTL)
    await GlobalCaches.json.set(key: cacheKey, value: videos, ttl: CacheTTL.sixHours)
    return videos
    }

    // MARK: - Helpers
    private static func parseVideoRenderer(_ vr: [String: Any], defaultChannelId: String) -> YouTubeVideo? {
        guard let id = vr["videoId"] as? String else { return nil }
        // Title
        let title = (((vr["title"] as? [String: Any])? ["runs"] as? [[String: Any]])?.first? ["text"] as? String) ?? ""
        // Channel title + id
        let ownerRuns = ((vr["ownerText"] as? [String: Any])? ["runs"] as? [[String: Any]])
        let channelTitle = ownerRuns?.first? ["text"] as? String ?? ""
        let channelBrowseId = ((ownerRuns?.first? ["navigationEndpoint"] as? [String: Any])? ["browseEndpoint"] as? [String: Any])? ["browseId"] as? String ?? defaultChannelId
        // Kanal thumb (bazı layoutlarda channelThumbnailSupportedRenderers içinde)
        var channelThumb = ""
        if let channelThumbRenderer = (vr["channelThumbnailSupportedRenderers"] as? [String: Any])? ["channelThumbnailWithLinkRenderer"] as? [String: Any],
           let ths = (channelThumbRenderer["thumbnail"] as? [String: Any])? ["thumbnails"] as? [[String: Any]], let u = ths.last? ["url"] as? String {
            channelThumb = u
        }
        if channelThumb.isEmpty { // alternatif path
            if let channelThumbRenderer = (vr["channelThumbnail"] as? [String: Any])? ["thumbnails"] as? [[String: Any]], let u = channelThumbRenderer.last? ["url"] as? String {
                channelThumb = u
            }
        }
    channelThumb = normalizeAvatarURL(channelThumb)
        // Duration (lengthText.simpleText veya lengthText.runs)
        var durationText = ""
        if let lt = vr["lengthText"] as? [String: Any] {
            if let simple = lt["simpleText"] as? String { durationText = simple }
            else if let runs = lt["runs"] as? [[String: Any]], let t = runs.first? ["text"] as? String { durationText = t }
        }
        var durationSeconds: Int? = nil
        if let lenStr = (vr["lengthSeconds"] as? String) ?? (vr["lengthSeconds"] as? NSNumber)?.stringValue {
            durationSeconds = Int(lenStr)
        }
        // Views + published time
        let rawView = ((vr["viewCountText"] as? [String: Any])? ["simpleText"] as? String)
            ?? ((vr["shortViewCountText"] as? [String: Any])? ["simpleText"] as? String) ?? ""
        let viewCount = normalizeViewCountText(rawView)
        let publishedAt = ((vr["publishedTimeText"] as? [String: Any])? ["simpleText"] as? String) ?? ""
        // Thumb
    var thumb = youtubeThumbnailURL(id, quality: .mqdefault)
        if let ths = (vr["thumbnail"] as? [String: Any])? ["thumbnails"] as? [[String: Any]], let u = ths.last? ["url"] as? String { thumb = u }

    return YouTubeVideo(
            id: id,
            title: title,
            channelTitle: channelTitle,
            channelId: channelBrowseId,
            viewCount: viewCount,
            publishedAt: publishedAt,
            thumbnailURL: thumb,
            description: "",
            channelThumbnailURL: channelThumb,
            likeCount: "0",
            durationText: durationText,
            durationSeconds: durationSeconds
        )
    }

    private static func parseGridVideoRenderer(_ gvr: [String: Any], defaultChannelId: String) -> YouTubeVideo? {
        guard let id = gvr["videoId"] as? String else { return nil }
        let title = (((gvr["title"] as? [String: Any])? ["runs"] as? [[String: Any]])?.first? ["text"] as? String) ?? ""
        let channelTitle = (((gvr["shortBylineText"] as? [String: Any])? ["runs"] as? [[String: Any]])?.first? ["text"] as? String) ?? ""
        let channelBrowseId = ((((gvr["shortBylineText"] as? [String: Any])? ["runs"] as? [[String: Any]])?.first? ["navigationEndpoint"] as? [String: Any])? ["browseEndpoint"] as? [String: Any])? ["browseId"] as? String ?? defaultChannelId
        // Grid renderer için kanal avatarı farklı bir yapıda olabilir
        var channelThumb = ""
        if let owner = (gvr["channelThumbnail"] as? [String: Any])? ["thumbnails"] as? [[String: Any]], let u = owner.last? ["url"] as? String { channelThumb = u }
    channelThumb = normalizeAvatarURL(channelThumb)
    // Duration
    var durationText = ""
    if let lt = gvr["lengthText"] as? [String: Any] {
        if let simple = lt["simpleText"] as? String { durationText = simple }
        else if let runs = lt["runs"] as? [[String: Any]], let t = runs.first? ["text"] as? String { durationText = t }
    }
    var durationSeconds: Int? = nil
    if let lenStr = (gvr["lengthSeconds"] as? String) ?? (gvr["lengthSeconds"] as? NSNumber)?.stringValue { durationSeconds = Int(lenStr) }
    let rawView = ((gvr["viewCountText"] as? [String: Any])? ["simpleText"] as? String) ?? ""
    let viewCount = normalizeViewCountText(rawView)
        let publishedAt = ((gvr["publishedTimeText"] as? [String: Any])? ["simpleText"] as? String) ?? ""
    var thumb = youtubeThumbnailURL(id, quality: .mqdefault)
        if let ths = (gvr["thumbnail"] as? [String: Any])? ["thumbnails"] as? [[String: Any]], let u = ths.last? ["url"] as? String { thumb = u }
        return YouTubeVideo(
            id: id,
            title: title,
            channelTitle: channelTitle,
            channelId: channelBrowseId,
            viewCount: viewCount,
            publishedAt: publishedAt,
            thumbnailURL: thumb,
            description: "",
            channelThumbnailURL: channelThumb,
            likeCount: "0",
            durationText: durationText,
            durationSeconds: durationSeconds
        )
    }

    private static func approxNumber(from text: String) -> Int {
        // Delegate to centralized parser; fallback to 0 on unknown
        return approxNumberFromText(text) ?? 0
    }

    // Removed duplicate view normalization and grouping helpers.

    private static func firstYT3Image(in text: String) -> String? {
        let patterns = [
            #"https?:\\/\\/yt3[^"]+"#,
            #"https?:\/\/yt3[^"\\ ]+"#
        ]
        for p in patterns {
            if let rx = try? NSRegularExpression(pattern: p, options: [.caseInsensitive]) {
                let ns = text as NSString
                let range = NSRange(location: 0, length: ns.length)
                if let m = rx.firstMatch(in: text, options: [], range: range) {
                    var candidate = ns.substring(with: m.range)
                    candidate = candidate.replacingOccurrences(of: "\\/", with: "/").replacingOccurrences(of: "\\u0026", with: "&")
                    candidate = normalizeAvatarURL(candidate)
                    return candidate
                }
            }
        }
        return nil
    }
}

// MARK: - Deep banner search
private extension LocalChannelAdapter {
    static func findBannerRecursive(in any: Any) -> String? {
        if let dict = any as? [String: Any] {
            if let banner = dict["banner"] as? [String: Any],
               let ths = banner["thumbnails"] as? [[String: Any]],
               let u = ths.last? ["url"] as? String { return u }
            // Diğer olası adlar
            for key in ["imageBanner", "tvBanner", "mobileBanner"] {
                if let b = dict[key] as? [String: Any],
                   let ths = b["thumbnails"] as? [[String: Any]],
                   let u = ths.last? ["url"] as? String { return u }
            }
            for v in dict.values { if let found = findBannerRecursive(in: v) { return found } }
        } else if let arr = any as? [Any] {
            for v in arr { if let found = findBannerRecursive(in: v) { return found } }
        }
        return nil
    }

    // HTML içinde geçen tüm yt3.* (googleusercontent / ggpht) büyük olasılıkla kanal görselleri; genişlik parametrelerine bakarak büyük olanları seç.
    static func extractBannerCandidates(from html: String) -> [String] {
        // Tüm yt3 görsellerini topla; genişlik / boyut / 'banner' içeriğine göre skorla
        let pattern = #"https?:\/\/yt3\.(?:googleusercontent|ggpht)\.com\/[^"' )]+"#
        guard let rx = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let ns = html as NSString
        let range = NSRange(location: 0, length: ns.length)
        let matches = rx.matches(in: html, options: [], range: range)
        struct Candidate { let url: String; let score: Int }
        var scored: [Candidate] = []
        for m in matches {
            var url = ns.substring(with: m.range)
            url = url.replacingOccurrences(of: "\\/", with: "/").replacingOccurrences(of: "\\u0026", with: "&")
            if let q = url.firstIndex(of: "?") { url = String(url[..<q]) }
            if url.contains("=s48") || url.contains("=s64") || url.contains("=s88") || url.contains("=s176") { continue } // küçük avatarlar
            var score = 0
            if let wRange = url.range(of: "=w") ?? url.range(of: "-w") {
                let tail = url[wRange.upperBound...]
                let digits = tail.prefix { $0.isNumber }
                if let w = Int(digits) { score += w }
            }
            if let sRange = url.range(of: "=s") {
                let tail = url[sRange.upperBound...]
                let digits = tail.prefix { $0.isNumber }
                if let s = Int(digits) { score += (s >= 512 ? s/2 : -200) }
            }
            if url.lowercased().contains("banner") { score += 8000 }
            if url.contains("fcrop") { score += 4000 }
            if url.contains("-no") { score += 500 } // bazı büyük banner varyantı suffix
            if score >= 2000 && url.contains("=w") == false { score += 500 } // büyük ama width param yok -> yine öne al
            if score == 0 { score = 100 }
            scored.append(Candidate(url: url, score: score))
        }
        let sorted = scored.sorted { $0.score > $1.score }
        if !sorted.isEmpty {
            let preview = sorted.prefix(5).map { "\($0.score):\($0.url.split(separator: "/").last ?? Substring(""))" }
            print("🧪 candidate scores top=\(preview)")
        }
        return sorted.map { $0.url }
    }
}
