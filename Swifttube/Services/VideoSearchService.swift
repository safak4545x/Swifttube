/*
 File Overview (EN)
 Purpose: Local-only video search via scraping adapters, including filter augmentation, shorts classification, and language filtering.
 Key Responsibilities:
 - Execute local search and manage loading/error/UI flags on YouTubeAPIService
 - Augment queries with active filters and classify results into videos vs shorts
 - Supplement shorts when scarce and fetch channel avatars
 - Detect language using NaturalLanguage and filter to target locale
 Used By: Search UI flows on the Home page and related views.

 Dosya Özeti (TR)
 Amacı: Scrape tabanlı adaptörlerle tamamen yerel video araması; filtre zenginleştirme, Shorts sınıflandırması ve dil filtrelemesi içerir.
 Ana Sorumluluklar:
 - Yerel aramayı çalıştırmak ve YouTubeAPIService üzerinde yükleniyor/hata/UI durumlarını yönetmek
 - Aktif filtreleri sorguya eklemek ve sonuçları video vs shorts olarak sınıflandırmak
 - Azsa Shorts takviyesi yapmak ve kanal avatarlarını çekmek
 - NaturalLanguage ile dil tespiti yapıp hedef yerel ayara göre filtrelemek
 Nerede Kullanılır: Ana sayfadaki arama akışları ve ilgili görünümler.
*/


import Foundation
import NaturalLanguage

extension YouTubeAPIService {
    
    // Video arama fonksiyonu
    func searchVideos(query: String) {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            print("❌ Arama sorgusu boş")
            return
        }
        
        print("🔍 Video aranıyor: \(query)")
    isLoadingVideos = true
    isLoading = isLoadingVideos || isLoadingShorts
        error = nil
        currentSearchQuery = query
        isShowingSearchResults = true
        // Tamamen yerel mod: web sayfasından arama sonuçlarını çıkar
    Task { [weak self] in
            guard let self = self else { return }
            do {
        let locale = self.currentLocaleParams()
        let results = try await LocalSearchAdapter.search(query: query, hl: locale.hl, gl: locale.gl)
                // Bölge seçiliyse, seçilen dil öncelikli olacak şekilde sonuçları diline göre filtrele.
                // Not: TR dışı bölgelerde tespit edilen Türkçe içerikleri ele.
                let filtered: [YouTubeVideo] = {
                    if locale.gl == nil { return results }
                    return results.filter { self.isVideoInTargetLanguage($0, targetHL: locale.hl) }
                }()
                // Daha kapsamlı Shorts tespiti (title + description)
                var shorts: [YouTubeVideo] = []
                var normal: [YouTubeVideo] = []
                for v in filtered {
                    // 1dk altı videoları her zaman Shorts olarak sınıflandır
                    if isUnderOneMinute(v) || isShortCandidate(v) { shorts.append(v) } else { normal.append(v) }
                }
                // Swift 6 uyumluluğu: değişkenleri immutable kopyalara al
                let classifiedNormal = normal
                let classifiedShorts = shorts
                await MainActor.run { [classifiedNormal, classifiedShorts] in
                    // Kullanıcı bu arama tamamlanmadan önce arama kutusunu temizlediyse veya yeni bir arama başlattıysa sonuçları yok say.
                    guard self.isShowingSearchResults, self.currentSearchQuery == query else {
                        print("⏭️ Stale arama sonucu yok sayıldı query=\(query) current=\(self.currentSearchQuery)")
                        // Eğer artık herhangi bir arama gösterilmiyorsa (kullanıcı temizledi / normal moda döndü)
                        // ve loading hâlâ bu eski aramadan dolayı true ise spinner'ı söndür.
                        if !self.isShowingSearchResults {
                            self.isLoadingVideos = false
                            self.isLoading = self.isLoadingVideos || self.isLoadingShorts
                        }
                        return
                    }
                    self.videos = classifiedNormal
                    self.shortsVideos = classifiedShorts
                    self.isLoadingVideos = false
                    self.isLoading = self.isLoadingVideos || self.isLoadingShorts
                    // Kanal avatarlarını yerel olarak zenginleştir
                    if !classifiedNormal.isEmpty { self.fetchChannelThumbnails(for: classifiedNormal) }
                    if !classifiedShorts.isEmpty { self.fetchChannelThumbnails(for: classifiedShorts, isShorts: true) }
                }
                // Shorts takviyesi yalnızca hâlâ geçerli arama ise yapılmalı
                if await MainActor.run(body: { self.isShowingSearchResults && self.currentSearchQuery == query }) {
                    if shorts.count < 6 {
                        await self.supplementShorts(minCount: 6, target: 12)
                    }
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    self.isLoadingVideos = false
                    self.isLoading = self.isLoadingVideos || self.isLoadingShorts
                }
            }
        }
    }
    
    // Seçili filtrelere göre sorguyu zenginleştirip yeniden arama yap
    func searchWithActiveFilters() {
        let base = currentSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty else { return }
        var augmented = base
        switch activeDateFilter {
        case .lastHour: augmented += " uploaded in last hour"
        case .today: augmented += " uploaded today"
        case .thisWeek: augmented += " uploaded this week"
        case .thisMonth: augmented += " uploaded this month"
        case .thisYear: augmented += " uploaded this year"
        case .none: break
        }
        switch activeDurationFilter {
        case .under4: augmented += " short video under 4 minutes"
        case .fourToTen: augmented += " video 4 to 10 minutes"
        case .tenToThirty: augmented += " video 10 to 30 minutes"
        case .thirtyToSixty: augmented += " video 30 to 60 minutes"
        case .overSixty: augmented += " long video over 60 minutes"
        case .none: break
        }
        print("🔎 Filtered search: base=\(base) -> augmented=\(augmented)")
        searchVideos(query: augmented)
    }
    // Eski uzaktan arama kodu tamamen kaldırıldı. LocalSearchAdapter kullanılıyor.
    
    // Ek Shorts takviyesi: mevcut arama sonuçları az ise rastgele query'lerle doldur
    fileprivate func supplementShorts(minCount: Int = 6, target: Int = 12) async {
        // Ana sonuçlar gösterilirken kullanıcı deneyimini bozmayalım
        if shortsVideos.count >= minCount { return }
        // Eğer bir arama sorgusu aktifse ona göre varyasyon üret, değilse generic liste kullan
    let baseQueries: [String]
        let activeQuery = currentSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if isShowingSearchResults && !activeQuery.isEmpty {
            baseQueries = [
                "\(activeQuery) shorts",
                "\(activeQuery) #shorts",
                "\(activeQuery) short",
                "#shorts \(activeQuery)",
                "short \(activeQuery)"
            ]
        } else {
            baseQueries = ["shorts", "#shorts", "funny short", "gaming short", "music short", "trend shorts"]
        }
    let queries = baseQueries
        var added: [YouTubeVideo] = []
        var seen = Set(shortsVideos.map { $0.id })
        let locale = self.currentLocaleParams()
        for q in queries.shuffled() {
            if shortsVideos.count + added.count >= target { break }
            if let items = try? await LocalSearchAdapter.search(query: q, hl: locale.hl, gl: locale.gl) {
        for v in items where isShortCandidate(v) && !seen.contains(v.id) && isVideoInTargetLanguage(v, targetHL: locale.hl) {
                    added.append(v)
                    seen.insert(v.id)
                    if shortsVideos.count + added.count >= target { break }
                }
            }
        }
        if !added.isEmpty {
            await MainActor.run { [added] in
                // Append & shuffle hafif rastgelelik için
                self.shortsVideos.append(contentsOf: added)
                self.shortsVideos.shuffle()
                self.fetchChannelThumbnails(for: added, isShorts: true)
            }
        }
    }
    
    // Shorts tespit kriterleri tek yerde
    fileprivate func isShortCandidate(_ v: YouTubeVideo) -> Bool {
        let t = v.title.lowercased()
        let d = v.description.lowercased()
        // Başlık veya açıklama içinde short / #short / #shorts varyasyonları
        if t.contains("#short") || t.contains("shorts") || t.contains(" short ") || t.hasSuffix(" short") || t.hasSuffix(" shorts") { return true }
        if d.contains("#short") || d.contains("shorts") { return true }
        // Ek: Başlık çok kısa ve hashtag ağırlıklı ise (heuristic)
        if t.count < 40 && (t.contains("#") && (t.contains("short") || t.contains("trend"))) { return true }
        return false
    }

    // Aktif arama sorgusuna göre Shorts listesini tamamen yenile
    func refreshSearchShorts(replace: Bool = true, maxCount: Int = 20) {
        let activeQuery = currentSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isShowingSearchResults, !activeQuery.isEmpty else {
            // Arama yoksa normal random shorts
            // Refresh butonu tetiklediğinde fullscreen overlay göstermeyelim
            fetchShortsVideos(suppressOverlay: true)
            return
        }
        print("🔄 Refresh search shorts for query=\(activeQuery)")
        Task {
            await MainActor.run {
                self.isLoadingShorts = true
                self.isLoading = self.isLoadingVideos || self.isLoadingShorts
            }
            var collected: [YouTubeVideo] = []
            var seen = Set<String>()
            if !replace { seen = Set(shortsVideos.map { $0.id }) }
        let variants = [
                "\(activeQuery) shorts",
                "\(activeQuery) #shorts",
                "#shorts \(activeQuery)",
                "\(activeQuery) short",
                "short \(activeQuery)"
            ]
        for q in variants {
                do {
            let locale = self.currentLocaleParams()
            let items = try await LocalSearchAdapter.search(query: q, hl: locale.hl, gl: locale.gl)
            for v in items where isShortCandidate(v) && !seen.contains(v.id) && isVideoInTargetLanguage(v, targetHL: locale.hl) {
                        collected.append(v)
                        seen.insert(v.id)
                        if collected.count >= maxCount { break }
                    }
                    if collected.count >= maxCount { break }
                } catch {
                    print("⚠️ search shorts variant failed q=\(q): \(error)")
                }
            }
            if collected.isEmpty { print("ℹ️ No new shorts collected for query=\(activeQuery)") }
            let snapshot = collected
            await MainActor.run { [snapshot] in
                if replace && !snapshot.isEmpty {
                    self.shortsVideos = snapshot.shuffled()
                } else if !replace && !snapshot.isEmpty {
                    self.shortsVideos.append(contentsOf: snapshot)
                    // Uniq koruma
                    let ordered = self.shortsVideos
                    var seenIds = Set<String>()
                    self.shortsVideos = ordered.filter { seenIds.insert($0.id).inserted }
                }
                if !self.shortsVideos.isEmpty { self.fetchChannelThumbnails(for: self.shortsVideos, isShorts: true) }
                self.isLoadingShorts = false
                self.isLoading = self.isLoadingVideos || self.isLoadingShorts
            }
        }
    }
}

// Yardımcı partition fonksiyonu
private extension Array {
    func partitioned(by belongsInSecond: (Element) -> Bool) -> ([Element], [Element]) {
        var first: [Element] = []
        var second: [Element] = []
        for el in self {
            if belongsInSecond(el) {
                second.append(el)
            } else {
                first.append(el)
            }
        }
        return (second, first) // burada (shorts, normal) için çağırırken sıraya dikkat;
    }
}

// MARK: - Language filtering helpers
extension YouTubeAPIService {
    fileprivate func detectLanguageCode(for text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let r = NLLanguageRecognizer()
        r.processString(trimmed)
        return r.dominantLanguage?.rawValue
    }

    fileprivate func isVideoInTargetLanguage(_ v: YouTubeVideo, targetHL: String) -> Bool {
        // Combine title + description for better detection
        let combined = v.title + "\n" + v.description
        guard let code = detectLanguageCode(for: combined) else { return true }
        // Strict rule: if region language is not Turkish, drop Turkish-detected items
        if targetHL != "tr" && code == "tr" { return false }
        // Prefer exact match; allow English as a common fallback
        if code == targetHL { return true }
        if code == "en" { return true }
        // Otherwise, keep only if it matches target language
        return code == targetHL
    }
}
