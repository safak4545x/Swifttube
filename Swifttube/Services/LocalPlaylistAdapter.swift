/*
 File Overview (EN)
 Purpose: Perform playlist search and item fetching by scraping YouTube HTML (and youtubei) with robust fallbacks.
 Key Responsibilities:
 - Collect playlist renderers from multiple layouts (desktop, mobile, youtubei)
 - Enrich placeholder titles by scraping playlist pages; cache results with TTL
 - Fetch playlist items via browse/next continuations and merge incrementally
 Used By: Playlist search UI and playlist details view.

 Dosya Özeti (TR)
 Amacı: Sağlam yedeklerle YouTube HTML (ve youtubei) kazıyarak oynatma listesi araması ve öğe çekimi yapmak.
 Ana Sorumluluklar:
 - Birçok yerleşimden (masaüstü, mobil, youtubei) playlist renderer’ları toplamak
 - Playlist sayfalarını kazıyarak yer tutucu başlıkları zenginleştirmek; TTL ile önbelleğe almak
 - browse/next devam token’larıyla playlist öğelerini çekip kademeli olarak birleştirmek
 Nerede Kullanılır: Oynatma listesi arama arayüzü ve detay görünümü.
*/

import Foundation

/// Local playlist operations (search and fetch videos) via YouTube HTML scraping.
/// Mirrors LocalChannelAdapter and LocalSearchAdapter style, enforcing en/US for stability.
enum LocalPlaylistAdapter {
    enum LocalError: Error { case badHTML, badJSON }

    // Search playlists by query
    
    static func search(query: String) async throws -> [YouTubePlaylist] {
    // Cache key: playlist search by query (always en/US) – v3 to bypass v2 entries that may contain placeholder titles
    let cacheKey = CacheKey("playlist:search:v3:q=\(query.lowercased())|hl=en|gl=US")
        if let cached: [YouTubePlaylist] = await GlobalCaches.json.get(key: cacheKey, type: [YouTubePlaylist].self), !cached.isEmpty {
            // Try to upgrade any placeholder titles from the per-playlist meta cache
            var upgraded: [YouTubePlaylist] = []
            for p in cached {
                var title = p.title.trimmingCharacters(in: .whitespacesAndNewlines)
                if title.isEmpty || title.lowercased() == "playlist" {
                    let metaKey = CacheKey("playlist:meta:title:id=\(p.id)")
                    if let real: String = await GlobalCaches.json.get(key: metaKey, type: String.self), !real.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        title = real
                    } else if title.isEmpty {
                        title = "Playlist"
                    }
                }
                upgraded.append(YouTubePlaylist(id: p.id, title: title, description: p.description, thumbnailURL: p.thumbnailURL, videoCount: p.videoCount, videoIds: p.videoIds, coverName: p.coverName, customCoverPath: p.customCoverPath))
            }
            return upgraded
        }
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return [] }
    // Candidate URLs we'll try in order for maximum compatibility
    let baseURL = "https://www.youtube.com/results?search_query=\(encoded)&hl=en&persist_hl=1&gl=US&persist_gl=1"
    let doubleEncodedURL = "https://www.youtube.com/results?search_query=\(encoded)&sp=EgIQAw%253D%253D&hl=en&persist_hl=1&gl=US&persist_gl=1"
    let singleEncodedURL = "https://www.youtube.com/results?search_query=\(encoded)&sp=EgIQAw%3D%3D&hl=en&persist_hl=1&gl=US&persist_gl=1"

        func fetchHTML(_ urlString: String, ua: String? = nil) async throws -> String? {
            guard let url = URL(string: urlString) else { return nil }
            // Build with centralized defaults (en/US + consent bypass). Allow UA override for mobile layout when needed.
            var req = RequestFactory.makeYouTubeHTMLRequest(url: url, hl: "en", gl: "US")
            if let ua = ua, !ua.isEmpty { req.setValue(ua, forHTTPHeaderField: "User-Agent") }
            req.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
            let (data, _) = try await URLSession.shared.data(for: req)
            return String(data: data, encoding: .utf8)
        }

        func extractRoot(from html: String) -> [String: Any]? {
            if let jsonStr = ParsingUtils.extractJSON(from: html, startMarker: "ytInitialData = ", endMarker: "};"),
               let jsonData = (jsonStr + "}").data(using: .utf8),
               let r = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                return r
            }
            return ParsingUtils.extractInitialDataDict(html: html)
        }

    func collectPlaylistRenderers(from root: [String: Any]) -> [[String: Any]] {
            var out: [[String: Any]] = []
            func walk(_ any: Any) {
                if let d = any as? [String: Any] {
                    if let pr = d["playlistRenderer"] as? [String: Any] { out.append(pr) }
                    // Some search layouts use compactPlaylistRenderer (sidebar-like cards)
                    if let cpr = d["compactPlaylistRenderer"] as? [String: Any] { out.append(cpr) }
                    // Grid variant (rare in search)
                    if let gpr = d["gridPlaylistRenderer"] as? [String: Any] { out.append(gpr) }
                    // Occasionally appears on some containers
                    if let pwcr = d["playlistWithChannelRenderer"] as? [String: Any] { out.append(pwcr) }
                    // Another variant observed in some responses
                    if let pwvr = d["playlistWithVideoRenderer"] as? [String: Any] { out.append(pwvr) }
                    // Auto-generated mixes sometimes appear as radioRenderer (playlist-like)
                    if let rr = d["radioRenderer"] as? [String: Any] { out.append(rr) }
                    for v in d.values { walk(v) }
                } else if let a = any as? [Any] {
                    for v in a { walk(v) }
                }
            }
            walk(root)
            return out
        }

        // Generic fallback: collect dictionaries that clearly carry a playlist id,
        // even if there is no explicit playlistRenderer in the response.
        func collectPlaylistCandidates(from any: Any) -> [[String: Any]] {
            var seen = Set<String>()
            var result: [[String: Any]] = []
            func addCandidate(id: String, source: [String: Any]) {
                guard !id.isEmpty, !seen.contains(id) else { return }
                seen.insert(id)
                // Try to form a renderer-like dictionary for downstream parsing
                var candidate: [String: Any] = ["playlistId": id]
                if let titleDict = source["title"] as? [String: Any] {
                    candidate["title"] = titleDict
                } else if let t = ((source["text" ] as? [String: Any])? ["simpleText"] as? String) ?? ((source["title"] as? [String: Any])? ["runs"] as? [[String: Any]])?.first? ["text"] as? String {
                    candidate["title"] = ["simpleText": t]
                }
                if let thumb = source["thumbnail"] as? [String: Any] {
                    candidate["thumbnail"] = thumb
                } else if let thumbs = source["thumbnails"] as? [String: Any] {
                    candidate["thumbnails"] = thumbs
                }
                result.append(candidate)
            }
            func walk(_ node: Any) {
                if let d = node as? [String: Any] {
                    if let pid = d["playlistId"] as? String {
                        addCandidate(id: pid, source: d)
                    }
                    if let browse = d["browseEndpoint"] as? [String: Any], let bid = browse["browseId"] as? String, bid.hasPrefix("VL") {
                        let id = String(bid.dropFirst(2))
                        addCandidate(id: id, source: d)
                    }
                    if let watch = d["watchEndpoint"] as? [String: Any], let pid = watch["playlistId"] as? String {
                        addCandidate(id: pid, source: d)
                    }
                    for v in d.values { walk(v) }
                } else if let a = node as? [Any] {
                    for v in a { walk(v) }
                }
            }
            walk(any)
            return result
        }

        // Diagnostic: count renderer markers in raw HTML
        func countOccurrences(in text: String, needle: String) -> Int {
            var count = 0
            var searchRange: Range<String.Index>? = text.startIndex..<text.endIndex
            while let r = text.range(of: needle, options: [], range: searchRange) {
                count += 1
                searchRange = r.upperBound..<text.endIndex
            }
            return count
        }

        // Try to discover the exact filter param for "Playlists" from the search chips
        func findPlaylistFilterParam(in any: Any) -> String? {
            if let d = any as? [String: Any] {
                // Chips variant
                if let chip = d["chipCloudChipRenderer"] as? [String: Any] {
                    let textSimple = ((chip["text"] as? [String: Any])? ["simpleText"] as? String)
                        ?? (((chip["text"] as? [String: Any])? ["runs"] as? [[String: Any]])?.first? ["text"] as? String)
                    let t = textSimple?.lowercased() ?? ""
                    if t.contains("playlist") || t.contains("playlists") || t.contains("çalma") { // tolerate localization
                        if let params = (((chip["navigationEndpoint"] as? [String: Any])? ["searchEndpoint"] as? [String: Any])? ["params"] as? String) {
                            return params
                        }
                    }
                }
                // Filter panels variant
                if let sfr = d["searchFilterRenderer"] as? [String: Any] {
                    let label = ((sfr["label"] as? [String: Any])? ["simpleText"] as? String)
                        ?? (((sfr["label"] as? [String: Any])? ["runs"] as? [[String: Any]])?.first? ["text"] as? String)
                    let t = label?.lowercased() ?? ""
                    let filterType = sfr["filterType"] as? String // often like "TYPE_PLAYLIST"
                    if filterType == "TYPE_PLAYLIST" || t.contains("playlist") || t.contains("playlists") || t.contains("çalma") {
                        if let params = (((sfr["navigationEndpoint"] as? [String: Any])? ["searchEndpoint"] as? [String: Any])? ["params"] as? String) {
                            return params
                        }
                    }
                }
                for v in d.values { if let p = findPlaylistFilterParam(in: v) { return p } }
            } else if let a = any as? [Any] {
                for v in a { if let p = findPlaylistFilterParam(in: v) { return p } }
            }
            return nil
        }

        var rendererDicts: [[String: Any]] = []
        // 1) First attempt: base search without filters, collect any playlistRenderer in the mixed results
    if let html = try await fetchHTML(baseURL) {
            print("🧩 playlist baseHTML size=\(html.count)")
            // Quick marker scan to see if server even sent playlist structures
            let m1 = countOccurrences(in: html, needle: "\"playlistRenderer\"")
            let m2 = countOccurrences(in: html, needle: "\"compactPlaylistRenderer\"")
            let m3 = countOccurrences(in: html, needle: "\"radioRenderer\"")
            let m4 = countOccurrences(in: html, needle: "\"chipCloudChipRenderer\"")
            print("🧪 markers base playlist=\(m1) compact=\(m2) radio=\(m3) chips=\(m4)")
            if let root = extractRoot(from: html) {
            rendererDicts = collectPlaylistRenderers(from: root)
                print("🧩 playlist base collect count=\(rendererDicts.count)")
            // Quick filter diagnostics
            func hasSFR(_ any: Any) -> Bool {
                var found = false
                func walk(_ x: Any) {
                    if let d = x as? [String: Any] {
                        if d["searchFilterRenderer"] != nil { found = true }
                        for v in d.values { if !found { walk(v) } }
                    } else if let a = x as? [Any] {
                        for v in a { if !found { walk(v) } }
                    }
                }
                walk(any); return found
            }
            print("🔎 playlist filters present=\(hasSFR(root))")
            if rendererDicts.isEmpty {
                // 1a) Try to extract the exact playlist filter params from chips and retry
                if let params = findPlaylistFilterParam(in: root) {
                    let chipURL = "https://www.youtube.com/results?search_query=\(encoded)&sp=\(params)&hl=en&persist_hl=1&gl=US&persist_gl=1"
                    if let htmlChip = try await fetchHTML(chipURL) {
                        print("🧩 playlist chipHTML size=\(htmlChip.count) sp=\(params)")
                        let cm1 = countOccurrences(in: htmlChip, needle: "\"playlistRenderer\"")
                        let cm2 = countOccurrences(in: htmlChip, needle: "\"compactPlaylistRenderer\"")
                        let cm3 = countOccurrences(in: htmlChip, needle: "\"radioRenderer\"")
                        let cm4 = countOccurrences(in: htmlChip, needle: "\"chipCloudChipRenderer\"")
                        print("🧪 markers chip playlist=\(cm1) compact=\(cm2) radio=\(cm3) chips=\(cm4)")
                        if let rootChip = extractRoot(from: htmlChip) {
                        let alt = collectPlaylistRenderers(from: rootChip)
                            print("🧩 playlist chip collect count=\(alt.count)")
                            if !alt.isEmpty {
                            print("🔁 Playlist chip filter used (sp from chip): \(params)")
                            rendererDicts = alt
                            }
                        }
                    }
                }
            }
            } else {
                print("⚠️ playlist extractRoot failed for baseHTML")
            }
        }
        // 2) Fallback: double-encoded sp hard-coded
    if rendererDicts.isEmpty, let html = try await fetchHTML(doubleEncodedURL) {
            print("🧩 playlist doubleEncodedHTML size=\(html.count)")
            let d1 = countOccurrences(in: html, needle: "\"playlistRenderer\"")
            let d2 = countOccurrences(in: html, needle: "\"compactPlaylistRenderer\"")
            let d3 = countOccurrences(in: html, needle: "\"radioRenderer\"")
            print("🧪 markers double playlist=\(d1) compact=\(d2) radio=\(d3)")
            if let root = extractRoot(from: html) {
                let alt = collectPlaylistRenderers(from: root)
                print("🧩 playlist double collect count=\(alt.count)")
                if !alt.isEmpty { rendererDicts = alt }
            } else {
                print("⚠️ playlist extractRoot failed for doubleEncodedHTML")
            }
        }
        // 3) Fallback: single-encoded sp hard-coded
        if rendererDicts.isEmpty, let html2 = try await fetchHTML(singleEncodedURL) {
            print("🧩 playlist singleEncodedHTML size=\(html2.count)")
            let s1 = countOccurrences(in: html2, needle: "\"playlistRenderer\"")
            let s2 = countOccurrences(in: html2, needle: "\"compactPlaylistRenderer\"")
            let s3 = countOccurrences(in: html2, needle: "\"radioRenderer\"")
            print("🧪 markers single playlist=\(s1) compact=\(s2) radio=\(s3)")
            if let root2 = extractRoot(from: html2) {
                let alt2 = collectPlaylistRenderers(from: root2)
                print("🧩 playlist single collect count=\(alt2.count)")
                if !alt2.isEmpty {
                    print("🔁 Playlist search fallback used (single-encoded sp)")
                    rendererDicts = alt2
                }
            } else {
                print("⚠️ playlist extractRoot failed for singleEncodedHTML")
            }
        }

        // 4) Mobile site fallback: m.youtube.com often embeds simpler initial data
        if rendererDicts.isEmpty {
            let mBase = "https://m.youtube.com/results?search_query=\(encoded)&hl=en&gl=US"
            let mSingle = "https://m.youtube.com/results?search_query=\(encoded)&sp=EgIQAw%3D%3D&hl=en&gl=US"
            let iphoneUA = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"

            if let htmlM = try await fetchHTML(mBase, ua: iphoneUA) {
                print("🧩 playlist mBaseHTML size=\(htmlM.count)")
                let m1 = countOccurrences(in: htmlM, needle: "\"playlistRenderer\"")
                let m2 = countOccurrences(in: htmlM, needle: "\"compactPlaylistRenderer\"")
                let m3 = countOccurrences(in: htmlM, needle: "\"radioRenderer\"")
                let m4 = countOccurrences(in: htmlM, needle: "\"chipCloudChipRenderer\"")
                print("🧪 markers mBase playlist=\(m1) compact=\(m2) radio=\(m3) chips=\(m4)")
                if let rootM = extractRoot(from: htmlM) {
                    let altM = collectPlaylistRenderers(from: rootM)
                    print("🧩 playlist mBase collect count=\(altM.count)")
                    if !altM.isEmpty { rendererDicts = altM }
                } else {
                    print("⚠️ playlist extractRoot failed for mBaseHTML")
                }
            }
            if rendererDicts.isEmpty, let htmlMS = try await fetchHTML(mSingle, ua: iphoneUA) {
                print("🧩 playlist mSingleHTML size=\(htmlMS.count)")
                let s1m = countOccurrences(in: htmlMS, needle: "\"playlistRenderer\"")
                let s2m = countOccurrences(in: htmlMS, needle: "\"compactPlaylistRenderer\"")
                let s3m = countOccurrences(in: htmlMS, needle: "\"radioRenderer\"")
                print("🧪 markers mSingle playlist=\(s1m) compact=\(s2m) radio=\(s3m)")
                if let rootMS = extractRoot(from: htmlMS) {
                    let altMS = collectPlaylistRenderers(from: rootMS)
                    print("🧩 playlist mSingle collect count=\(altMS.count)")
                    if !altMS.isEmpty {
                        print("🔁 Playlist search fallback used (mobile single-encoded sp)")
                        rendererDicts = altMS
                    }
                } else {
                    print("⚠️ playlist extractRoot failed for mSingleHTML")
                }
            }
        }

        // 5) InnerTube fallback: use youtubei/v1/search with playlist filter if available
        if rendererDicts.isEmpty {
            // Fetch base desktop HTML to extract ytcfg (API key and context)
            if let html = try await fetchHTML(baseURL) {
                if let cfg = ParsingUtils.extractYtConfig(html: html) {
                    let apiKey = (cfg["INNERTUBE_API_KEY"] as? String)
                        ?? (cfg["INNERTUBE_API_KEY"]) as? String
                    var context = cfg["INNERTUBE_CONTEXT"] as? [String: Any]
                    // Minimal default context if not present
                    if context == nil {
                        context = [
                            "client": [
                                "clientName": "WEB",
                                "clientVersion": "2.20240101.00.00",
                                "hl": "en",
                                "gl": "US"
                            ]
                        ]
                    }
                    if let apiKey = apiKey, let ctx = context {
                        // Force en/US for stability, even if ytcfg differs
                        var forcedCtx = ctx
                        if var client = forcedCtx["client"] as? [String: Any] {
                            client["hl"] = "en"
                            client["gl"] = "US"
                            // Reasonable defaults if missing
                            if client["clientName"] == nil { client["clientName"] = "WEB" }
                            if client["clientVersion"] == nil { client["clientVersion"] = "2.20240101.00.00" }
                            if let visitor = cfg["VISITOR_DATA"] as? String, !visitor.isEmpty {
                                client["visitorData"] = visitor
                            }
                            forcedCtx["client"] = client
                        }
                        func youtubeiPost(_ params: String?) async -> [String: Any]? {
                            guard let url = URL(string: "https://www.youtube.com/youtubei/v1/search?key=\(apiKey)") else { return nil }
                            var req = URLRequest(url: url)
                            req.httpMethod = "POST"
                            req.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
                            req.setValue("application/json", forHTTPHeaderField: "Accept")
                            // Standard web UA and origins
                            req.setValue(RequestFactory.defaultUserAgent, forHTTPHeaderField: "User-Agent")
                            // Prefer numeric client name header for WEB (1)
                            let cfgClientName = (cfg["INNERTUBE_CLIENT_NAME"] as? String)
                                ?? (forcedCtx["client"] as? [String: Any])? ["clientName"] as? String
                            let numericClientName: String = {
                                guard let n = cfgClientName?.uppercased() else { return "1" }
                                if n == "WEB" { return "1" }
                                if n.contains("ANDROID") { return "3" } // best-effort
                                return "1"
                            }()
                            req.setValue(numericClientName, forHTTPHeaderField: "X-YouTube-Client-Name")
                            if let clientVersion = (cfg["INNERTUBE_CLIENT_VERSION"] as? String) ?? (forcedCtx["client"] as? [String: Any])? ["clientVersion"] as? String {
                                req.setValue(clientVersion, forHTTPHeaderField: "X-YouTube-Client-Version")
                            }
                            req.setValue("https://www.youtube.com", forHTTPHeaderField: "Origin")
                            req.setValue("https://www.youtube.com", forHTTPHeaderField: "Referer")
                            req.setValue(RequestFactory.defaultAcceptLanguage, forHTTPHeaderField: "Accept-Language")
                            var cookie = RequestFactory.cookieHeaderValue(hl: "en", gl: "US")
                            if let visitor = cfg["VISITOR_DATA"] as? String, !visitor.isEmpty {
                                // Set visitor cookie parts to stabilize personalization gates
                                cookie += "; VISITOR_INFO1_LIVE=\(visitor)"
                                req.setValue(visitor, forHTTPHeaderField: "X-Goog-Visitor-Id")
                            }
                            req.setValue(cookie, forHTTPHeaderField: "Cookie")
                            var body: [String: Any] = [
                                "context": forcedCtx,
                                "query": query,
                                // These flags occasionally gate results
                                "contentCheckOk": true,
                                "racyCheckOk": true
                            ]
                            if let p = params { body["params"] = p }
                            req.httpBody = try? JSONSerialization.data(withJSONObject: body)
                            do {
                                let (data, resp) = try await URLSession.shared.data(for: req)
                                if let http = resp as? HTTPURLResponse { print("🛰️ youtubei status=\(http.statusCode) bytes=\(data.count)") }
                                if let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] { return root }
                                return nil
                            } catch {
                                print("⚠️ youtubei post error: \(error)")
                                return nil
                            }
                        }

                        // Continuation fetch for youtubei
                        func youtubeiContinuation(_ token: String) async -> [String: Any]? {
                            guard let url = URL(string: "https://www.youtube.com/youtubei/v1/search?key=\(apiKey)") else { return nil }
                            var req = URLRequest(url: url)
                            req.httpMethod = "POST"
                            req.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
                            req.setValue("application/json", forHTTPHeaderField: "Accept")
                            req.setValue(RequestFactory.defaultUserAgent, forHTTPHeaderField: "User-Agent")
                            let cfgClientName = (cfg["INNERTUBE_CLIENT_NAME"] as? String)
                                ?? (forcedCtx["client"] as? [String: Any])? ["clientName"] as? String
                            let numericClientName: String = {
                                guard let n = cfgClientName?.uppercased() else { return "1" }
                                if n == "WEB" { return "1" }
                                if n.contains("ANDROID") { return "3" }
                                return "1"
                            }()
                            req.setValue(numericClientName, forHTTPHeaderField: "X-YouTube-Client-Name")
                            if let clientVersion = (cfg["INNERTUBE_CLIENT_VERSION"] as? String) ?? (forcedCtx["client"] as? [String: Any])? ["clientVersion"] as? String {
                                req.setValue(clientVersion, forHTTPHeaderField: "X-YouTube-Client-Version")
                            }
                            req.setValue("https://www.youtube.com", forHTTPHeaderField: "Origin")
                            req.setValue("https://www.youtube.com", forHTTPHeaderField: "Referer")
                            req.setValue(RequestFactory.defaultAcceptLanguage, forHTTPHeaderField: "Accept-Language")
                            var cookie = RequestFactory.cookieHeaderValue(hl: "en", gl: "US")
                            if let visitor = cfg["VISITOR_DATA"] as? String, !visitor.isEmpty {
                                cookie += "; VISITOR_INFO1_LIVE=\(visitor)"
                                req.setValue(visitor, forHTTPHeaderField: "X-Goog-Visitor-Id")
                            }
                            req.setValue(cookie, forHTTPHeaderField: "Cookie")
                            let body: [String: Any] = [
                                "context": forcedCtx,
                                "continuation": token,
                                "contentCheckOk": true,
                                "racyCheckOk": true
                            ]
                            req.httpBody = try? JSONSerialization.data(withJSONObject: body)
                            do {
                                let (data, resp) = try await URLSession.shared.data(for: req)
                                if let http = resp as? HTTPURLResponse { print("🛰️ youtubei(cont) status=\(http.statusCode) bytes=\(data.count)") }
                                if let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] { return root }
                                return nil
                            } catch {
                                print("⚠️ youtubei continuation error: \(error)")
                                return nil
                            }
                        }

                        // Helper: collect continuation tokens from an arbitrary node
                        func collectContinuations(in any: Any, into out: inout [String]) {
                            if let d = any as? [String: Any] {
                                if let next = ((d["continuations"] as? [[String: Any]])?.first? ["nextContinuationData"] as? [String: Any])? ["continuation"] as? String {
                                    out.append(next)
                                }
                                if let token = ((d["continuationEndpoint"] as? [String: Any])? ["continuationCommand"] as? [String: Any])? ["token"] as? String {
                                    out.append(token)
                                }
                                if let cmds = d["onResponseReceivedCommands"] as? [Any] {
                                    for c in cmds { collectContinuations(in: c, into: &out) }
                                }
                                for v in d.values { collectContinuations(in: v, into: &out) }
                            } else if let a = any as? [Any] {
                                for v in a { collectContinuations(in: v, into: &out) }
                            }
                        }

                        // Try direct playlist params first
                        let defaultSp = "EgIQAw==" // Playlists
                        if let rootPl = await youtubeiPost(defaultSp) {
                            let alts = collectPlaylistRenderers(from: rootPl)
                            print("🧩 playlist youtubei collect count=\(alts.count)")
                            if !alts.isEmpty { rendererDicts = alts }
                            if rendererDicts.isEmpty {
                                let cands = collectPlaylistCandidates(from: rootPl)
                                print("🧩 playlist youtubei candidate collect=\(cands.count)")
                                if !cands.isEmpty { rendererDicts = cands }
                            }
                            // If empty, try fetching a couple of continuation pages
                            if rendererDicts.isEmpty {
                                var tokens: [String] = []
                                collectContinuations(in: rootPl, into: &tokens)
                                tokens = Array(Set(tokens))
                                var fetched = 0
                                for t in tokens.prefix(3) { // allow a bit deeper for playlists
                                    if let contRoot = await youtubeiContinuation(t) {
                                        let more = collectPlaylistRenderers(from: contRoot)
                                        print("🧩 playlist youtubei(cont) collect count+=\(more.count)")
                                        if !more.isEmpty { rendererDicts.append(contentsOf: more) }
                                        if more.isEmpty {
                                            let moreCands = collectPlaylistCandidates(from: contRoot)
                                            print("🧩 playlist youtubei(cont) candidate collect+=\(moreCands.count)")
                                            if !moreCands.isEmpty { rendererDicts.append(contentsOf: moreCands) }
                                        }
                                        fetched += 1
                                    }
                                }
                            }
                        }
                        // If still empty, try unfiltered to discover chip param for Playlists
                        if rendererDicts.isEmpty, let rootNoFilter = await youtubeiPost(nil) {
                            // First, see if unfiltered results already contain playlist renderers
                            let mixed = collectPlaylistRenderers(from: rootNoFilter)
                            print("🧩 playlist youtubei(unfiltered) collect count=\(mixed.count)")
                            if !mixed.isEmpty { rendererDicts = mixed }
                            if rendererDicts.isEmpty {
                                let cands = collectPlaylistCandidates(from: rootNoFilter)
                                print("🧩 playlist youtubei(unfiltered) candidate collect=\(cands.count)")
                                if !cands.isEmpty { rendererDicts = cands }
                            }

                            func findChipParam(_ any: Any) -> String? {
                                if let d = any as? [String: Any] {
                                    if let chip = d["chipCloudChipRenderer"] as? [String: Any] {
                                        let text = ((chip["text"] as? [String: Any])? ["simpleText"] as? String)
                                          ?? (((chip["text"] as? [String: Any])? ["runs"] as? [[String: Any]])?.first? ["text"] as? String)
                                        if let t = text?.lowercased(), t.contains("playlist") {
                                            if let p = (((chip["navigationEndpoint"] as? [String: Any])? ["searchEndpoint"] as? [String: Any])? ["params"] as? String) {
                                                return p
                                            }
                                        }
                                    }
                                    for v in d.values { if let p = findChipParam(v) { return p } }
                                } else if let a = any as? [Any] {
                                    for v in a { if let p = findChipParam(v) { return p } }
                                }
                                return nil
                            }
                            if let p = findChipParam(rootNoFilter) {
                                print("🔎 youtubei discovered playlist sp from chips: \(p)")
                                if let rootRetry = await youtubeiPost(p) {
                                    let alts = collectPlaylistRenderers(from: rootRetry)
                                    print("🧩 playlist youtubei(chip) collect count=\(alts.count)")
                                    if !alts.isEmpty { rendererDicts = alts }
                                    if rendererDicts.isEmpty {
                                        var tokens: [String] = []
                                        collectContinuations(in: rootRetry, into: &tokens)
                                        tokens = Array(Set(tokens))
                                        for t in tokens.prefix(3) {
                                            if let contRoot = await youtubeiContinuation(t) {
                                                let more = collectPlaylistRenderers(from: contRoot)
                                                print("🧩 playlist youtubei(chip,cont) collect count+=\(more.count)")
                                                if !more.isEmpty { rendererDicts.append(contentsOf: more) }
                                                if more.isEmpty {
                                                    let moreCands = collectPlaylistCandidates(from: contRoot)
                                                    print("🧩 playlist youtubei(chip,cont) candidate collect+=\(moreCands.count)")
                                                    if !moreCands.isEmpty { rendererDicts.append(contentsOf: moreCands) }
                                                }
                                            }
                                        }
                                    }
                                }
                            } else {
                                print("ℹ️ youtubei chips did not expose a 'Playlists' param")
                            }
                        }
                    }
                }
            }
        }

    var results: [YouTubePlaylist] = []
        // Available local example covers (without extension)
        let exampleCoverPool = ["playlist", "playlist2", "playlist3", "playlist4"]
        func randomCoverName() -> String? { exampleCoverPool.randomElement() }
        for pr in rendererDicts {
            let playlistId = (pr["playlistId"] as? String)
                ?? ((pr["navigationEndpoint"] as? [String: Any])? ["watchEndpoint"] as? [String: Any])? ["playlistId"] as? String
                ?? ""
            guard !playlistId.isEmpty else { continue }
            // Title may be simpleText or runs
            let titleSimple = (pr["title"] as? [String: Any])? ["simpleText"] as? String
            let titleRuns = ((pr["title"] as? [String: Any])? ["runs"] as? [[String: Any]])?.first? ["text"] as? String
            let headerSimple = (pr["header"] as? [String: Any])? ["simpleText"] as? String
            let headerRuns = ((pr["header"] as? [String: Any])? ["runs"] as? [[String: Any]])?.first? ["text"] as? String
            let ownerRuns = ((pr["shortBylineText"] as? [String: Any])? ["runs"] as? [[String: Any]])?.first? ["text"] as? String
            // Some playlist cards use accessibility label instead of title
            let accessibilityLabel = ((pr["title"] as? [String: Any])? ["accessibility"] as? [String: Any])? ["accessibilityData"] as? [String: Any]
            let accessibilityText = (accessibilityLabel? ["label"] as? String)
            let candidateTitle = titleSimple ?? titleRuns ?? headerSimple ?? headerRuns ?? accessibilityText ?? ownerRuns ?? ""
            var title = ParsingUtils.decodeHTMLEntities(candidateTitle).trimmingCharacters(in: .whitespacesAndNewlines)
            if title.isEmpty { title = "Playlist" }
            // Description snippet if present
            let descRuns = ((pr["descriptionSnippet"] as? [String: Any])? ["runs"] as? [[String: Any]])?.compactMap { $0["text"] as? String }.joined()
            let description = (descRuns ?? "")
            // Thumbnail
            var thumb = (((pr["thumbnails"] as? [String: Any])? ["thumbnails"] as? [[String: Any]])?.last? ["url"] as? String) ?? ""
            if thumb.isEmpty, let thumbs = ((pr["thumbnail"] as? [String: Any])? ["thumbnails"] as? [[String: Any]]) { thumb = thumbs.last? ["url"] as? String ?? "" }
            thumb = ParsingUtils.normalizeURL(thumb)
            // Video count (best-effort)
            let videoCountText = ((pr["videoCountText"] as? [String: Any])? ["simpleText"] as? String)
                ?? ((pr["videoCountShortText"] as? [String: Any])? ["simpleText"] as? String)
                ?? (pr["videoCount"] as? String)
                ?? ""
            let videoCount = approxNumberFromText(videoCountText) ?? 0

            let p = YouTubePlaylist(
                id: playlistId,
                title: title,
                description: description,
                thumbnailURL: thumb,
                videoCount: videoCount,
                videoIds: nil,
                // If remote thumbnail is missing, assign a random local example cover as a nice fallback
                coverName: thumb.isEmpty ? randomCoverName() : nil,
                customCoverPath: nil
            )
            results.append(p)
        }

        // Debug hint to trace result counts during QA
        print("🔎 Playlist search '\(query)' -> count=\(results.count)")
        // Defensive: ensure titles are not empty and try to enrich placeholders with real playlist titles
        var sanitized: [YouTubePlaylist] = results.map { p in
            let t = p.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.isEmpty { return YouTubePlaylist(id: p.id, title: "Playlist", description: p.description, thumbnailURL: p.thumbnailURL, videoCount: p.videoCount, videoIds: p.videoIds, coverName: p.coverName, customCoverPath: p.customCoverPath) }
            return p
        }

        // Enrich up to a few items that still have the generic title "Playlist" by scraping the playlist page
        func extractTitle(from any: Any) -> String? {
            if let d = any as? [String: Any] {
                // metadata.playlistMetadataRenderer.title
                if let meta = d["playlistMetadataRenderer"] as? [String: Any], let t = meta["title"] as? String { return t }
                if let primary = d["playlistSidebarPrimaryInfoRenderer"] as? [String: Any] {
                    if let simple = (primary["title"] as? [String: Any])? ["simpleText"] as? String { return simple }
                    if let runs = (primary["title"] as? [String: Any])? ["runs"] as? [[String: Any]] {
                        let joined = runs.compactMap { $0["text"] as? String }.joined()
                        if !joined.isEmpty { return joined }
                    }
                }
                for v in d.values { if let t = extractTitle(from: v) { return t } }
            } else if let a = any as? [Any] {
                for v in a { if let t = extractTitle(from: v) { return t } }
            }
            return nil
        }

        func fetchRealTitle(playlistId: String) async -> String? {
            let metaKey = CacheKey("playlist:meta:title:id=\(playlistId)")
            if let cached: String = await GlobalCaches.json.get(key: metaKey, type: String.self), !cached.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return cached
            }
            let urlString = "https://www.youtube.com/playlist?list=\(playlistId)&hl=en&persist_hl=1&gl=US&persist_gl=1"
            guard let url = URL(string: urlString) else { return nil }
            var req = RequestFactory.makeYouTubeHTMLRequest(url: url, hl: "en", gl: "US")
            do {
                let (data, _) = try await URLSession.shared.data(for: req)
                if let html = String(data: data, encoding: .utf8), let root = ParsingUtils.extractInitialDataDict(html: html) {
                    if let t = extractTitle(from: root) {
                        let decoded = ParsingUtils.decodeHTMLEntities(t).trimmingCharacters(in: .whitespacesAndNewlines)
                        if !decoded.isEmpty {
                            // Playlist gerçek başlık meta’sını daha uzun süre tut: 48 saat
                            await GlobalCaches.json.set(key: metaKey, value: decoded, ttl: CacheTTL.oneDay * 2)
                            return decoded
                        }
                    }
                }
            } catch {
                print("⚠️ fetchRealTitle error for \(playlistId): \(error)")
            }
            return nil
        }

        // Enrich many placeholders, but do it in bounded parallelism
        let placeholderIndexes: [Int] = sanitized.enumerated()
            .filter { (_, p) in p.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "playlist" }
            .map { $0.offset }
        if !placeholderIndexes.isEmpty {
            // Cap to a reasonable number to keep search responsive
            let toFix = Array(placeholderIndexes.prefix(48))
            await withTaskGroup(of: (Int, String?).self) { group in
                for idx in toFix {
                    let pid = sanitized[idx].id
                    group.addTask {
                        let real = await fetchRealTitle(playlistId: pid)
                        return (idx, real)
                    }
                }
                for await (idx, real) in group {
                    if let real = real, !real.isEmpty {
                        let p = sanitized[idx]
                        let enriched = YouTubePlaylist(id: p.id, title: real, description: p.description, thumbnailURL: p.thumbnailURL, videoCount: p.videoCount, videoIds: p.videoIds, coverName: p.coverName, customCoverPath: p.customCoverPath)
                        sanitized[idx] = enriched
                    }
                }
            }
        }

        await GlobalCaches.json.set(key: cacheKey, value: sanitized, ttl: CacheTTL.sixHours)
        return sanitized
    }

    // Fetch playlist videos by id, growing as needed up to `limit` using youtubei continuations.
    static func fetchVideos(playlistId: String, limit: Int = 25) async throws -> [YouTubeVideo] {
        // Cache key for playlist items (stores the largest discovered list so far)
        let cacheKey = CacheKey("playlist:videos:id=\(playlistId)|hl=en|gl=US")

        // If we already have enough cached items, serve from cache; otherwise we'll try to extend it.
        var items: [YouTubeVideo] = []
        if let cached: [YouTubeVideo] = await GlobalCaches.json.get(key: cacheKey, type: [YouTubeVideo].self), !cached.isEmpty {
            if cached.count >= limit { return Array(cached.prefix(limit)) }
            items = cached
        }
        let urlString = "https://www.youtube.com/playlist?list=\(playlistId)&hl=en&persist_hl=1&gl=US&persist_gl=1"
    guard let url = URL(string: urlString) else { return [] }
    var req = RequestFactory.makeYouTubeHTMLRequest(url: url, hl: "en", gl: "US")
        let (data, _) = try await URLSession.shared.data(for: req)
        guard let html = String(data: data, encoding: .utf8) else { throw LocalError.badHTML }

    // We'll append into `items` (may already contain some cached entries)
    var seenIds = Set(items.map { $0.id })

        // Recursive scan for all playlistVideoRenderer nodes (and playlistPanelVideoRenderer)
        func collectPlaylistVideos(in any: Any) {
            if let dict = any as? [String: Any] {
                if let pvr = dict["playlistVideoRenderer"] as? [String: Any] {
                    if let v = parsePlaylistVideoRenderer(pvr), !seenIds.contains(v.id) { items.append(v); seenIds.insert(v.id) }
                }
                if let ppr = dict["playlistPanelVideoRenderer"] as? [String: Any] {
                    if let v = parsePlaylistVideoRenderer(ppr), !seenIds.contains(v.id) { items.append(v); seenIds.insert(v.id) }
                }
                for v in dict.values { collectPlaylistVideos(in: v) }
            } else if let arr = any as? [Any] {
                for v in arr { collectPlaylistVideos(in: v) }
            }
        }
        // initial HTML'den hem ilk videoları hem de (birazdan) continuation token'larını kullanacağız
        var initialRoot: [String: Any]? = nil
        if let root = ParsingUtils.extractInitialDataDict(html: html) {
            initialRoot = root
            collectPlaylistVideos(in: root)
        }

        // Helper to collect continuation tokens from a youtubei response (playlist browse)
        // Covers multiple layouts: nextContinuationData, continuationEndpoint->continuationCommand->token, raw "continuation" keys, etc.
        func collectContinuationTokens(in any: Any, into out: inout [String]) {
            if let d = any as? [String: Any] {
                // Common: {"continuation":"TOKEN"}
                if let cont = d["continuation"] as? String, !cont.isEmpty { out.append(cont) }
                // Common: {"nextContinuationData":{"continuation":"TOKEN"}}
                if let next = d["nextContinuationData"] as? [String: Any], let t = next["continuation"] as? String, !t.isEmpty { out.append(t) }
        // Also seen: {"reloadContinuationData":{"continuation":"TOKEN"}}
        if let reload = d["reloadContinuationData"] as? [String: Any], let t = reload["continuation"] as? String, !t.isEmpty { out.append(t) }
                // Continuation item renderer path: {"continuationEndpoint":{"continuationCommand":{"token":"TOKEN"}}}
                if let endpoint = d["continuationEndpoint"] as? [String: Any],
                   let cmd = endpoint["continuationCommand"] as? [String: Any],
                   let token = cmd["token"] as? String, !token.isEmpty {
                    out.append(token)
                }
                // Some responses expose continuationCommand directly (e.g., inside buttonRenderer/command)
                if let cmd = d["continuationCommand"] as? [String: Any], let token = cmd["token"] as? String, !token.isEmpty {
                    out.append(token)
                }
                // Commands array variant
                if let cmds = d["onResponseReceivedCommands"] as? [Any] {
                    for c in cmds { collectContinuationTokens(in: c, into: &out) }
                }
                // Some responses embed actions/endpoints arrays – recurse all values
                for v in d.values { collectContinuationTokens(in: v, into: &out) }
            } else if let a = any as? [Any] {
                for v in a { collectContinuationTokens(in: v, into: &out) }
            }
        }

        // Try youtubei browse and follow continuations until we hit `limit` (or we run out of pages)
        if let cfg = ParsingUtils.extractYtConfig(html: html) {
            let apiKey = cfg["INNERTUBE_API_KEY"] as? String
            var context = cfg["INNERTUBE_CONTEXT"] as? [String: Any]
            if context == nil {
                context = ["client": [
                    "clientName": "WEB",
                    "clientVersion": "2.20240101.00.00",
                    "hl": "en",
                    "gl": "US"
                ]]
            }
            if let apiKey = apiKey, var ctx = context, let baseURL = URL(string: "https://www.youtube.com/youtubei/v1/browse?key=\(apiKey)") {
                if var client = ctx["client"] as? [String: Any] {
                    client["hl"] = "en"
                    client["gl"] = "US"
                    // Inject visitorData if present to stabilize continuations
                    if let visitor = cfg["VISITOR_DATA"] as? String, !visitor.isEmpty {
                        client["visitorData"] = visitor
                    }
                    // Ensure clientName/Version are present
                    if client["clientName"] == nil { client["clientName"] = (cfg["INNERTUBE_CLIENT_NAME"] as? String) ?? "WEB" }
                    if client["clientVersion"] == nil { client["clientVersion"] = (cfg["INNERTUBE_CLIENT_VERSION"] as? String) ?? "2.20240101.00.00" }
                    // Provide originalUrl to better anchor browse session
                    client["originalUrl"] = "https://www.youtube.com/playlist?list=\(playlistId)&hl=en&gl=US"
                    // Provide timezone context to reduce variability
                    client["timeZone"] = TimeZone.current.identifier
                    client["utcOffsetMinutes"] = TimeZone.current.secondsFromGMT() / 60
                    ctx["client"] = client
                }
                // Add optional request/user sections to align with WEB payloads
                if ctx["request"] == nil { ctx["request"] = ["useSsl": true] }
                if ctx["user"] == nil { ctx["user"] = ["lockedSafetyMode": false] }

                // Mutable per-request context bits we may update from responses
                var currentVisitor: String? = (ctx["client"] as? [String: Any])? ["visitorData"] as? String
                var clickTrackingParams: String? = nil

                func makeRequest(body: [String: Any]) async -> [String: Any]? {
                    var r = URLRequest(url: baseURL)
                    r.httpMethod = "POST"
                    r.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
                    r.setValue("application/json", forHTTPHeaderField: "Accept")
                    r.setValue(RequestFactory.defaultUserAgent, forHTTPHeaderField: "User-Agent")
                    // Provide youtube client headers similar to desktop WEB
                    let clientNameHeader: String = {
                        let raw = (cfg["INNERTUBE_CLIENT_NAME"] as? String)?.uppercased() ?? "WEB"
                        return raw == "WEB" ? "1" : (raw.contains("ANDROID") ? "3" : "1")
                    }()
                    r.setValue(clientNameHeader, forHTTPHeaderField: "X-YouTube-Client-Name")
                    if let v = (cfg["INNERTUBE_CLIENT_VERSION"] as? String) ?? (ctx["client"] as? [String: Any])? ["clientVersion"] as? String {
                        r.setValue(v, forHTTPHeaderField: "X-YouTube-Client-Version")
                    }
                    r.setValue("https://www.youtube.com", forHTTPHeaderField: "Origin")
                    r.setValue("https://www.youtube.com", forHTTPHeaderField: "Referer")
                    r.setValue(RequestFactory.defaultAcceptLanguage, forHTTPHeaderField: "Accept-Language")
                    var cookie = RequestFactory.cookieHeaderValue(hl: "en", gl: "US")
                    if let visitor = currentVisitor ?? (cfg["VISITOR_DATA"] as? String), !visitor.isEmpty {
                        cookie += "; VISITOR_INFO1_LIVE=\(visitor)"
                        r.setValue(visitor, forHTTPHeaderField: "X-Goog-Visitor-Id")
                    }
                    r.setValue(cookie, forHTTPHeaderField: "Cookie")
                    r.httpBody = try? JSONSerialization.data(withJSONObject: body)
                    if let (d, resp) = try? await URLSession.shared.data(for: r) {
                        if let http = resp as? HTTPURLResponse { print("🛰️ youtubei(browse) status=\(http.statusCode) bytes=\(d.count)") }
                        if var root = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
                            // Capture visitorData/clickTracking for subsequent calls
                            if let rc = root["responseContext"] as? [String: Any] {
                                if let v = rc["visitorData"] as? String, !v.isEmpty { currentVisitor = v }
                                if clickTrackingParams == nil,
                                   let ct = (rc["webResponseContextExtensionData"] as? [String: Any])? ["ytConfigData"] as? [String: Any],
                                   let p = ct["serializedExperimentFlags"] as? String, !p.isEmpty {
                                    // Not the usual field; keep for diagnostics
                                    _ = p
                                }
                            }
                            if clickTrackingParams == nil {
                                // Try alternate placements
                                if let ct = (root["clickTracking"] as? [String: Any])? ["clickTrackingParams"] as? String, !ct.isEmpty {
                                    clickTrackingParams = ct
                                } else if let ct = (root["trackingParams"] as? String), !ct.isEmpty {
                                    clickTrackingParams = ct
                                }
                            }
                            return root
                        }
                    }
                    return nil
                }

                // Same as makeRequest but targets youtubei/v1/next (used as a fallback for some continuation chains)
                func makeNextRequest(body: [String: Any]) async -> [String: Any]? {
                    guard let nextURL = URL(string: "https://www.youtube.com/youtubei/v1/next?key=\(apiKey)") else { return nil }
                    var r = URLRequest(url: nextURL)
                    r.httpMethod = "POST"
                    r.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
                    r.setValue("application/json", forHTTPHeaderField: "Accept")
                    r.setValue(RequestFactory.defaultUserAgent, forHTTPHeaderField: "User-Agent")
                    let clientNameHeader: String = {
                        let raw = (cfg["INNERTUBE_CLIENT_NAME"] as? String)?.uppercased() ?? "WEB"
                        return raw == "WEB" ? "1" : (raw.contains("ANDROID") ? "3" : "1")
                    }()
                    r.setValue(clientNameHeader, forHTTPHeaderField: "X-YouTube-Client-Name")
                    if let v = (cfg["INNERTUBE_CLIENT_VERSION"] as? String) ?? (ctx["client"] as? [String: Any])? ["clientVersion"] as? String {
                        r.setValue(v, forHTTPHeaderField: "X-YouTube-Client-Version")
                    }
                    r.setValue("https://www.youtube.com", forHTTPHeaderField: "Origin")
                    r.setValue("https://www.youtube.com", forHTTPHeaderField: "Referer")
                    r.setValue(RequestFactory.defaultAcceptLanguage, forHTTPHeaderField: "Accept-Language")
                    var cookie = RequestFactory.cookieHeaderValue(hl: "en", gl: "US")
                    if let visitor = currentVisitor ?? (cfg["VISITOR_DATA"] as? String), !visitor.isEmpty {
                        cookie += "; VISITOR_INFO1_LIVE=\(visitor)"
                        r.setValue(visitor, forHTTPHeaderField: "X-Goog-Visitor-Id")
                    }
                    r.setValue(cookie, forHTTPHeaderField: "Cookie")
                    r.httpBody = try? JSONSerialization.data(withJSONObject: body)
                    if let (d, resp) = try? await URLSession.shared.data(for: r) {
                        if let http = resp as? HTTPURLResponse { print("🛰️ youtubei(next) status=\(http.statusCode) bytes=\(d.count)") }
                        if let root = try? JSONSerialization.jsonObject(with: d) as? [String: Any] { return root }
                    }
                    return nil
                }

                // Explicitly parse continuation responses for playlist items and next tokens
                func extractItemsAndTokens(from root: [String: Any], itemsAdded: inout Int, tokens outTokens: inout [String]) {
                    func handleContinuationItems(_ arr: [[String: Any]]) {
                        for it in arr {
                            if let plc = it["playlistVideoListContinuation"] as? [String: Any] {
                                if let contents = plc["contents"] as? [[String: Any]] {
                                    for c in contents {
                                        if let pvr = c["playlistVideoRenderer"] as? [String: Any] {
                                            if let v = parsePlaylistVideoRenderer(pvr), !seenIds.contains(v.id) { items.append(v); seenIds.insert(v.id); itemsAdded += 1 }
                                        }
                                        if let ppr = c["playlistPanelVideoRenderer"] as? [String: Any] {
                                            if let v = parsePlaylistVideoRenderer(ppr), !seenIds.contains(v.id) { items.append(v); seenIds.insert(v.id); itemsAdded += 1 }
                                        }
                                    }
                                }
                                if let conts = plc["continuations"] as? [[String: Any]] {
                                    for c in conts {
                                        if let t = ((c["nextContinuationData"] as? [String: Any])? ["continuation"] as? String), !t.isEmpty { outTokens.append(t) }
                                        if let t = ((c["reloadContinuationData"] as? [String: Any])? ["continuation"] as? String), !t.isEmpty { outTokens.append(t) }
                                    }
                                }
                            }
                            // Some chains use playlistPanelVideoListContinuation instead
                            if let plc2 = it["playlistPanelVideoListContinuation"] as? [String: Any] {
                                if let contents = plc2["contents"] as? [[String: Any]] {
                                    for c in contents {
                                        if let pvr = c["playlistVideoRenderer"] as? [String: Any] {
                                            if let v = parsePlaylistVideoRenderer(pvr), !seenIds.contains(v.id) { items.append(v); seenIds.insert(v.id); itemsAdded += 1 }
                                        }
                                        if let ppr = c["playlistPanelVideoRenderer"] as? [String: Any] {
                                            if let v = parsePlaylistVideoRenderer(ppr), !seenIds.contains(v.id) { items.append(v); seenIds.insert(v.id); itemsAdded += 1 }
                                        }
                                    }
                                }
                                if let conts = plc2["continuations"] as? [[String: Any]] {
                                    for c in conts {
                                        if let t = ((c["nextContinuationData"] as? [String: Any])? ["continuation"] as? String), !t.isEmpty { outTokens.append(t) }
                                        if let t = ((c["reloadContinuationData"] as? [String: Any])? ["continuation"] as? String), !t.isEmpty { outTokens.append(t) }
                                    }
                                }
                            }
                            if let pvr = it["playlistVideoRenderer"] as? [String: Any] {
                                if let v = parsePlaylistVideoRenderer(pvr), !seenIds.contains(v.id) { items.append(v); seenIds.insert(v.id); itemsAdded += 1 }
                            }
                            if let ppr = it["playlistPanelVideoRenderer"] as? [String: Any] {
                                if let v = parsePlaylistVideoRenderer(ppr), !seenIds.contains(v.id) { items.append(v); seenIds.insert(v.id); itemsAdded += 1 }
                            }
                            if let cir = it["continuationItemRenderer"] as? [String: Any] {
                                if let t = ((cir["continuationEndpoint"] as? [String: Any])? ["continuationCommand"] as? [String: Any])? ["token"] as? String, !t.isEmpty {
                                    outTokens.append(t)
                                }
                            }
                        }
                    }
                    // Actions variant
                    if let actions = root["onResponseReceivedActions"] as? [[String: Any]] {
                        for a in actions {
                            if let app = a["appendContinuationItemsAction"] as? [String: Any], let arr = app["continuationItems"] as? [[String: Any]] {
                                handleContinuationItems(arr)
                            }
                            if let rel = a["reloadContinuationItemsCommand"] as? [String: Any], let arr = rel["continuationItems"] as? [[String: Any]] {
                                handleContinuationItems(arr)
                            }
                        }
                    }
                    // Endpoints variant
                    if let endpoints = root["onResponseReceivedEndpoints"] as? [[String: Any]] {
                        for e in endpoints {
                            if let app = e["appendContinuationItemsAction"] as? [String: Any], let arr = app["continuationItems"] as? [[String: Any]] {
                                handleContinuationItems(arr)
                            }
                            if let rel = e["reloadContinuationItemsCommand"] as? [String: Any], let arr = rel["continuationItems"] as? [[String: Any]] {
                                handleContinuationItems(arr)
                            }
                        }
                    }
                    // Commands variant (observed on some playlist continuations)
                    if let commands = root["onResponseReceivedCommands"] as? [[String: Any]] {
                        for c in commands {
                            if let app = c["appendContinuationItemsAction"] as? [String: Any], let arr = app["continuationItems"] as? [[String: Any]] {
                                handleContinuationItems(arr)
                            }
                            if let rel = c["reloadContinuationItemsCommand"] as? [String: Any], let arr = rel["continuationItems"] as? [[String: Any]] {
                                handleContinuationItems(arr)
                            }
                        }
                    }
                }

                // Initial browse to seed items and tokens (even if HTML already yielded some)
                if items.count < limit {
                    // Try playlist params variants to unlock continuations
                    let paramCandidates: [String?] = ["OAE=", "OAHAAQ", nil]
                    var pickedRoot: [String: Any]? = nil
                    var pickedParam: String? = nil
                    for candidate in paramCandidates {
                        let body: [String: Any] = [
                            // Enrich context with latest clickTracking/visitor state
                            "context": {
                                var c = ctx
                                if var client = c["client"] as? [String: Any] {
                                    if let v = currentVisitor, !v.isEmpty { client["visitorData"] = v }
                                    c["client"] = client
                                }
                                if let p = clickTrackingParams, !p.isEmpty { c["clickTracking"] = ["clickTrackingParams": p] }
                                return c
                            }(),
                            "browseId": "VL" + playlistId,
                            "contentCheckOk": true,
                            "racyCheckOk": true
                        ].merging(candidate != nil ? ["params": candidate!] : [:]) { $1 }
                        if let root = await makeRequest(body: body) {
                            // collect a quick token hint to decide if this variant works
                            var tempTokens: [String] = []
                            collectContinuationTokens(in: root, into: &tempTokens)
                            if !tempTokens.isEmpty || pickedRoot == nil {
                                pickedRoot = root
                                pickedParam = candidate
                                // Prefer the first that yields tokens
                                if !tempTokens.isEmpty { break }
                            }
                        }
                    }
                    if let root = pickedRoot {
                        print("🧭 initial browse using params=\(pickedParam ?? "<none>")")
                        collectPlaylistVideos(in: root)
                        print("📦 playlist items after initial browse=\(items.count)")
            var tokens: [String] = []
            // 0) initial HTML'de bulunan continuations (varsa) ile kuyruğu tohumla
            if let initRoot = initialRoot { collectContinuationTokens(in: initRoot, into: &tokens) }
            // 1) browse cevabındaki continuations
                        collectContinuationTokens(in: root, into: &tokens)
                        if !tokens.isEmpty { print("🔗 initial tokens found=\(tokens.count)") } else { print("🔗 initial tokens found=0") }
            // De-duplicate while preserving order (some chains require order)
                        var queue: [String] = []
                        var seenTok = Set<String>()
                        for t in tokens { if seenTok.insert(t).inserted { queue.append(t) } }
                        var fetchedPages = 0
                        // Follow up to a reasonable number of continuation pages
            while items.count < limit, let token = (!queue.isEmpty ? queue.removeFirst() : nil), fetchedPages < 120 {
                            let cBody: [String: Any] = [
                                "context": {
                                    var c = ctx
                                    if var client = c["client"] as? [String: Any] {
                                        if let v = currentVisitor, !v.isEmpty { client["visitorData"] = v }
                                        c["client"] = client
                                    }
                                    if let p = clickTrackingParams, !p.isEmpty { c["clickTracking"] = ["clickTrackingParams": p] }
                                    return c
                                }(),
                                "continuation": token,
                                "contentCheckOk": true,
                                "racyCheckOk": true
                            ]
                            if let contRoot = await makeRequest(body: cBody) {
                                fetchedPages += 1
                                var added = 0
                                // First, explicit extraction from actions/endpoints blocks
                                var more: [String] = []
                                extractItemsAndTokens(from: contRoot, itemsAdded: &added, tokens: &more)
                                // Fallback: generic recursive scan for both items and tokens
                                if added == 0 { collectPlaylistVideos(in: contRoot) }
                                collectContinuationTokens(in: contRoot, into: &more)
                                print("📦 playlist items after page #\(fetchedPages)=\(items.count) (added=\(added), newTokens=\(more.count), queue=\(queue.count))")
                                // If browse continuation yielded nothing, try next endpoint once for this token
                                if added == 0 && more.isEmpty {
                                    if let nextRoot = await makeNextRequest(body: cBody) {
                                        var addedNext = 0
                                        var moreNext: [String] = []
                                        extractItemsAndTokens(from: nextRoot, itemsAdded: &addedNext, tokens: &moreNext)
                                        if addedNext == 0 { collectPlaylistVideos(in: nextRoot) }
                                        collectContinuationTokens(in: nextRoot, into: &moreNext)
                                        print("🔁 fallback(next) page #\(fetchedPages) -> +items=\(addedNext), +tokens=\(moreNext.count)")
                                        if addedNext > 0 { added += addedNext }
                                        if !moreNext.isEmpty { more.append(contentsOf: moreNext) }
                                    }
                                }
                                if !more.isEmpty {
                                    // Append new tokens preserving order and avoiding duplicates
                                    for t in more { if !seenTok.contains(t) { seenTok.insert(t); queue.append(t) } }
                                }
                                // Try to update clickTracking/visitor from continuation responses as well
                                if let rc = contRoot["responseContext"] as? [String: Any] {
                                    if let v = rc["visitorData"] as? String, !v.isEmpty { currentVisitor = v }
                                }
                                if clickTrackingParams == nil {
                                    if let ct = (contRoot["clickTracking"] as? [String: Any])? ["clickTrackingParams"] as? String, !ct.isEmpty {
                                        clickTrackingParams = ct
                                    } else if let tp = contRoot["trackingParams"] as? String, !tp.isEmpty {
                                        clickTrackingParams = tp
                                    }
                                }
                            } else {
                                break
                            }
                        }
                    }
                }
            }
        }

        // Store the full discovered list in cache so subsequent larger limits can grow without refetching
    // Playlist videoları için cache süresi: 48 saat (önceden 6 saatti)
    await GlobalCaches.json.set(key: cacheKey, value: items, ttl: CacheTTL.oneDay * 2)
        // Return only the requested slice for the current call
        return Array(items.prefix(limit))
    }

    private static func parsePlaylistVideoRenderer(_ pvr: [String: Any]) -> YouTubeVideo? {
        guard let id = pvr["videoId"] as? String else { return nil }
        // Title: prefer simpleText, then runs
        let titleDict = pvr["title"] as? [String: Any]
        let titleSimple = titleDict? ["simpleText"] as? String
        let titleRuns = (titleDict? ["runs"] as? [[String: Any]])
        let title = (titleSimple ?? titleRuns?.first? ["text"] as? String ?? "")
        // Channel: shortBylineText or longBylineText, simpleText or runs
        let bylineDict = (pvr["shortBylineText"] as? [String: Any]) ?? (pvr["longBylineText"] as? [String: Any])
        let bylineSimple = bylineDict? ["simpleText"] as? String
        let bylineRuns = (bylineDict? ["runs"] as? [[String: Any]])
        let channelTitle = (bylineSimple ?? bylineRuns?.first? ["text"] as? String ?? "")
        let channelBrowseId = (((bylineRuns?.first? ["navigationEndpoint"] as? [String: Any])? ["browseEndpoint"] as? [String: Any])? ["browseId"] as? String)
            ?? ""
    var thumb = youtubeThumbnailURL(id, quality: .mqdefault)
        if let ths = ((pvr["thumbnail"] as? [String: Any])? ["thumbnails"] as? [[String: Any]]), let u = ths.last? ["url"] as? String { thumb = ParsingUtils.normalizeURL(u) }
        // Duration if available
        var durationText = ""
        var durationSeconds: Int? = nil
        if let lt = pvr["lengthText"] as? [String: Any] {
            if let simple = lt["simpleText"] as? String { durationText = simple }
            else if let runs = lt["runs"] as? [[String: Any]], let t = runs.first? ["text"] as? String { durationText = t }
        }
        if let lenStr = (pvr["lengthSeconds"] as? String) ?? (pvr["lengthSeconds"] as? NSNumber)?.stringValue { durationSeconds = Int(lenStr) }
        return YouTubeVideo(
            id: id,
            title: title,
            channelTitle: channelTitle,
            channelId: channelBrowseId,
            viewCount: "",
            publishedAt: "",
            publishedAtISO: nil,
            thumbnailURL: thumb,
            description: "",
            channelThumbnailURL: "",
            likeCount: "0",
            durationText: durationText,
            durationSeconds: durationSeconds
        )
    }
}
