//
//  CacheStore.swift
//  Swifttube
//
//  Composite cache: in-memory + disk. Thread-safe with Swift actors.
//
/*
 File Overview (EN)
 Purpose: Lightweight key-value cache for transient data like thumbnails, search/related results.
 Key Responsibilities:
 - In-memory and optional disk-backed caching with TTL
 - Thread-safe get/set/evict operations and simple namespacing
 - Helps reduce repeated scraping/network calls
 Used By: Local* adapters, PlaylistCoverService, and other services needing memoization.

 Dosya Özeti (TR)
 Amacı: Küçük ömürlü veriler (küçük görseller, arama/ilgili sonuçları gibi) için hafif anahtar-değer önbelleği.
 Ana Sorumluluklar:
 - Bellek içi ve isteğe bağlı disk destekli önbellekleme ve TTL
 - İş parçacığı güvenli get/set/sil işlemleri ve basit ad alanları
 - Tekrarlayan kazıma/ağ çağrılarını azaltmaya yardımcı olur
 Nerede Kullanılır: Local* adaptörleri, PlaylistCoverService ve bellekleme gerektiren diğer servisler.
*/


import Foundation
import AppKit

actor MemoryCache<Value: AnyObject> {
    private let cache = NSCache<NSString, Value>()
    init(totalCostLimit: Int) { cache.totalCostLimit = totalCostLimit }
    func get(_ key: String) -> Value? { cache.object(forKey: key as NSString) }
    func set(_ key: String, value: Value, cost: Int = 1) { cache.setObject(value, forKey: key as NSString, cost: cost) }
    func removeAll() { cache.removeAllObjects() }
}

actor DiskCache {
    private let baseURL: URL
    init(folderName: String) {
        let fm = FileManager.default
        let appSupport = try! fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
    baseURL = appSupport.appendingPathComponent("Swifttube/Cache/\(folderName)", isDirectory: true)
        try? fm.createDirectory(at: baseURL, withIntermediateDirectories: true)
    }
    func url(for filename: String) -> URL { baseURL.appendingPathComponent(filename) }
    func write(_ data: Data, filename: String) async throws {
        let fm = FileManager.default
        let tmp = url(for: filename + ".tmp")
        let final = url(for: filename)
        try data.write(to: tmp, options: .atomic)
        if fm.fileExists(atPath: final.path) { try fm.removeItem(at: final) }
        try fm.moveItem(at: tmp, to: final)
    }
    func read(_ filename: String) async throws -> Data {
        let u = url(for: filename)
        return try Data(contentsOf: u)
    }
    func remove(_ filename: String) async {
        let fm = FileManager.default
        let u = url(for: filename)
        _ = try? fm.removeItem(at: u)
    }
    func removeAll() async {
        let fm = FileManager.default
        _ = try? fm.removeItem(at: baseURL)
        try? fm.createDirectory(at: baseURL, withIntermediateDirectories: true)
    }
}

actor JsonCacheStore {
    private let memory = MemoryCache<NSData>(totalCostLimit: 64 * 1024 * 1024)
    private let disk = DiskCache(folderName: "json")

    func get<T: Codable>(key: CacheKey, type: T.Type) async -> T? {
        let file = key.hashedFilename()
        if let mem = await memory.get(file) as Data?,
           let env = try? JSONDecoder().decode(CacheEnvelope<T>.self, from: mem), env.expiry > Date() {
            return env.value
        }
        if let data = try? await disk.read(file),
           let env = try? JSONDecoder().decode(CacheEnvelope<T>.self, from: data) {
            if env.expiry > Date() {
                await memory.set(file, value: data as NSData, cost: data.count)
                return env.value
            } else {
                await disk.remove(file)
            }
        }
        return nil
    }

    func set<T: Codable>(key: CacheKey, value: T, ttl: TimeInterval) async {
        let file = key.hashedFilename()
        let env = CacheEnvelope(value: value, expiry: CachePolicy.expiryDate(ttl: ttl))
        guard let data = try? JSONEncoder().encode(env) else { return }
        await memory.set(file, value: data as NSData, cost: data.count)
        try? await disk.write(data, filename: file)
    }

    func clear() async { await memory.removeAll(); await disk.removeAll() }
}

actor ImageCacheStore {
    private let memory = MemoryCache<NSImage>(totalCostLimit: 128 * 1024 * 1024)
    private let disk = DiskCache(folderName: "images")

    func get(urlString: String) async -> NSImage? {
        let key = CacheKey(urlString).hashedFilename(extension: "img")
        if let img = await memory.get(key) { return img }
        if let data = try? await disk.read(key), let img = NSImage(data: data) {
            await memory.set(key, value: img, cost: Int(data.count))
            return img
        }
        return nil
    }

    func set(urlString: String, data: Data) async -> NSImage? {
        let key = CacheKey(urlString).hashedFilename(extension: "img")
        guard let img = NSImage(data: data) else { return nil }
        await memory.set(key, value: img, cost: data.count)
        try? await disk.write(data, filename: key)
        return img
    }

    func clear() async { await memory.removeAll(); await disk.removeAll() }
}

enum GlobalCaches {
    static let json = JsonCacheStore()
    static let images = ImageCacheStore()
}
