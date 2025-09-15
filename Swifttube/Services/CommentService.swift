

/*
 File Overview (EN)
 Purpose: Fetch top-level comments and replies via YouTube Data API v3; cache pages and merge into UI state.
 Key Responsibilities:
 - Call commentThreads.list and comments.list with pagination
 - Parse snippets into internal YouTubeComment models and attach replies
 - Cache results per-URL for short periods to reduce repeat calls
 Used By: Video detail page comments and replies expanders.

 Dosya Özeti (TR)
 Amacı: YouTube Data API v3 ile üst seviye yorumları ve yanıtları çekmek; sayfaları önbelleğe almak ve UI durumuna eklemek.
 Ana Sorumluluklar:
 - commentThreads.list ve comments.list uç noktalarıyla sayfalama destekli istekler yapmak
 - Snippet’leri iç YouTubeComment modellerine ayrıştırıp yanıtlara eklemek
 - Yinelenen çağrıları azaltmak için URL başına kısa süreli önbellek kullanmak
 Nerede Kullanılır: Video detay sayfasındaki yorumlar ve yanıt genişleticiler.
*/

import Foundation

// MARK: - Comment Service (YouTube Data API v3)
// Local scraper kaldırıldı; yalnızca resmi API kullanılıyor.
// Gerekli alanlar: Settings > API Key girilmeli. Yoksa fetch işlemleri yapılmaz.
extension YouTubeAPIService {
    /// Fetch top-level comments using commentThreads.list
    func fetchComments(videoId: String, append: Bool = false, sortOrder: String = "relevance", pageSize: Int = 50) {
        let apiKey = self.apiKey
        guard !apiKey.isEmpty else {
            print("❌ comments fetch aborted: missing API key")
            return
        }
        let existingToken = append ? self.nextCommentsPageToken : nil
        print("🗨️ [DataAPI] comments fetch start video=\(videoId) append=\(append) pageToken=\(existingToken ?? "nil") order=\(sortOrder)")
        currentCommentsVideoId = videoId
        if !append { comments = [] }
        Task {
            let orderParam = (sortOrder.lowercased().starts(with: "t")) ? "time" : "relevance" // time or relevance
            var components = URLComponents(string: "https://www.googleapis.com/youtube/v3/commentThreads")!
            components.queryItems = [
                .init(name: "part", value: "snippet,replies"),
                .init(name: "videoId", value: videoId),
                .init(name: "maxResults", value: String(min(max(pageSize, 1), 100))),
                .init(name: "order", value: orderParam),
                .init(name: "key", value: apiKey)
            ]
            if let token = existingToken { components.queryItems?.append(.init(name: "pageToken", value: token)) }
            guard let url = components.url else { return }
            do {
                // Cache key per request URL
                let cacheKey = CacheKey("comments:list:url=\(url.absoluteString)")
                if let cached: [YouTubeComment] = await GlobalCaches.json.get(key: cacheKey, type: [YouTubeComment].self), append {
                    await MainActor.run {
                        comments.append(contentsOf: cached)
                    }
                    return
                }
                let (data, resp) = try await URLSession.shared.data(from: url)
                if let http = resp as? HTTPURLResponse, http.statusCode != 200 {
                    let body = String(data: data, encoding: .utf8) ?? "<non-utf8>"
                    if let errJSON = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let errorObj = errJSON["error"] as? [String: Any] {
                        let code = errorObj["code"] as? Int ?? http.statusCode
                        let message = errorObj["message"] as? String ?? "?"
                        print("❌ [DataAPI] comments HTTP status=\(http.statusCode) apiCode=\(code) message=\(message)")
                    } else {
                        print("❌ [DataAPI] comments HTTP status=\(http.statusCode) raw=\(body.prefix(200))")
                    }
                    return
                }
                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    print("❌ [DataAPI] comments parse error JSONSerialization")
                    return
                }
                let nextToken = json["nextPageToken"] as? String
                var newComments: [YouTubeComment] = []
                if let items = json["items"] as? [[String: Any]] {
                    for item in items {
                        if let c = parseCommentThreadItem(item) { newComments.append(c) }
                    }
                }
                await MainActor.run {
                    let added = newComments
                    if append { comments.append(contentsOf: added) } else { comments = added }
                    nextCommentsPageToken = nextToken
                }
                // Cache the page for 30 minutes (only the list; token isn't cached)
                await GlobalCaches.json.set(key: cacheKey, value: newComments, ttl: CacheTTL.thirtyMinutes)
                print("✅ [DataAPI] comments loaded added=\(newComments.count) next=\(nextToken != nil)")
            } catch {
                print("❌ [DataAPI] comments network error=\(error)")
            }
        }
    }

    /// Fetch replies for a given top-level comment (single page for now, can extend with pagination)
    func fetchCommentReplies(commentId: String, pageToken: String? = nil, pageSize: Int = 50) {
        let apiKey = self.apiKey
        guard !apiKey.isEmpty else {
            print("❌ replies fetch aborted: missing API key")
            return
        }
        guard let parentIndex = comments.firstIndex(where: { $0.id == commentId }) else { return }
        print("🗨️ [DataAPI] replies fetch parent=\(commentId) pageToken=\(pageToken ?? "nil")")
        Task {
            var components = URLComponents(string: "https://www.googleapis.com/youtube/v3/comments")!
            components.queryItems = [
                .init(name: "part", value: "snippet"),
                .init(name: "parentId", value: commentId),
                .init(name: "maxResults", value: String(min(max(pageSize, 1), 100))),
                .init(name: "key", value: apiKey)
            ]
            if let pt = pageToken { components.queryItems?.append(.init(name: "pageToken", value: pt)) }
            guard let url = components.url else { return }
            do {
                // Cache key per replies URL
                let cacheKey = CacheKey("replies:list:url=\(url.absoluteString)")
                if let cached: [YouTubeComment] = await GlobalCaches.json.get(key: cacheKey, type: [YouTubeComment].self) {
                    await MainActor.run {
                        comments[parentIndex].replies.append(contentsOf: cached)
                        comments[parentIndex].repliesContinuationToken = pageToken // leave as provided
                    }
                    return
                }
                let (data, resp) = try await URLSession.shared.data(from: url)
                if let http = resp as? HTTPURLResponse, http.statusCode != 200 {
                    let body = String(data: data, encoding: .utf8) ?? "<non-utf8>"
                    if let errJSON = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let errorObj = errJSON["error"] as? [String: Any] {
                        let code = errorObj["code"] as? Int ?? http.statusCode
                        let message = errorObj["message"] as? String ?? "?"
                        print("❌ [DataAPI] replies HTTP status=\(http.statusCode) apiCode=\(code) message=\(message)")
                    } else {
                        print("❌ [DataAPI] replies HTTP status=\(http.statusCode) raw=\(body.prefix(160))")
                    }
                    return
                }
                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    print("❌ [DataAPI] replies parse error")
                    return
                }
                let nextToken = json["nextPageToken"] as? String
                var batch: [YouTubeComment] = []
                if let items = json["items"] as? [[String: Any]] {
                    for item in items {
                        if let snippet = (item["snippet"] as? [String: Any]) {
                            if let reply = buildComment(fromSnippet: snippet, idFallback: item["id"] as? String ?? UUID().uuidString) { batch.append(reply) }
                        }
                    }
                }
                await MainActor.run {
                    let added = batch
                    comments[parentIndex].replies.append(contentsOf: added)
                    // Eğer devam varsa parent comment'in repliesContinuationToken alanına koy
                    comments[parentIndex].repliesContinuationToken = nextToken
                }
                await GlobalCaches.json.set(key: cacheKey, value: batch, ttl: CacheTTL.thirtyMinutes)
                print("✅ [DataAPI] replies loaded added=\(batch.count) next=\(nextToken != nil)")
            } catch {
                print("❌ [DataAPI] replies network error=\(error)")
            }
        }
    }

    // MARK: - Parsing Helpers
    private func parseCommentThreadItem(_ item: [String: Any]) -> YouTubeComment? {
        guard let snippetWrapper = item["snippet"] as? [String: Any],
              let topLevel = snippetWrapper["topLevelComment"] as? [String: Any],
              let topSnippet = topLevel["snippet"] as? [String: Any] else { return nil }
        let top = buildComment(fromSnippet: topSnippet, idFallback: (topLevel["id"] as? String) ?? (item["id"] as? String) ?? UUID().uuidString)
        guard let topComment = top else { return nil }
        // totalReplyCount alanı top-level comment snippet'inde değil wrapper seviyesinde bulunur; buradan al
        if let totalReplyCount = snippetWrapper["totalReplyCount"] as? Int {
            topComment.replyCount = totalReplyCount
        }
        // replies (partial)
        if let replies = item["replies"] as? [String: Any], let replyItems = replies["comments"] as? [[String: Any]] {
            var replyObjs: [YouTubeComment] = []
            for r in replyItems {
                if let rs = r["snippet"] as? [String: Any], let reply = buildComment(fromSnippet: rs, idFallback: r["id"] as? String ?? UUID().uuidString) { replyObjs.append(reply) }
            }
            topComment.replies.append(contentsOf: replyObjs)
            // Eğer totalReplyCount daha büyükse continuation iması
            if topComment.replyCount > replyObjs.count {
                topComment.repliesContinuationToken = nil // İlk replies fetch'inde pageToken kullanılacak
            }
        }
        return topComment
    }

    private func buildComment(fromSnippet s: [String: Any], idFallback: String) -> YouTubeComment? {
        let id = s["id"] as? String ?? idFallback
        let author = s["authorDisplayName"] as? String ?? ""
        let text = (s["textDisplay"] as? String) ?? (s["textOriginal"] as? String) ?? ""
        let authorImage = s["authorProfileImageUrl"] as? String ?? ""
        let likeCount = (s["likeCount"] as? Int) ?? 0
    let publishedAtISO = s["publishedAt"] as? String ?? ""
    // ISO tarihi tek merkezden normalize et (örn: 1 saat önce)
    let (publishedAt, _) = normalizePublishedDisplay(publishedAtISO)
        let replyCount = (s["totalReplyCount"] as? Int) ?? 0
        let isPinned = (s["viewerRating"] as? String) == "liked" // Pinned bilgisi Data API snippet'te yok; approx
        return YouTubeComment(id: id, author: author, text: text, authorImage: authorImage, likeCount: likeCount, publishedAt: publishedAt, replyCount: replyCount, isPinned: isPinned)
    }
}
