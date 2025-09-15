/*
 File Overview (EN)
 Purpose: Utilities for video-specific operations. Currently includes ISO8601 duration parsing into seconds.
 Key Responsibilities:
 - Parse strings like PT1H02M03S into total seconds
 Used By: Services/UI that need numeric duration for layout or labels.

 Dosya Özeti (TR)
 Amacı: Video odaklı yardımcılar. Şu an ISO8601 süre metnini saniyeye çevirir.
 Ana Sorumluluklar:
 - PT1H02M03S gibi metinleri toplam saniyeye dönüştürmek
 Nerede Kullanılır: Süreyi sayısal olarak kullanan servis/arayüzler.
*/

import Foundation

// Video süresini saniye cinsinden parse eden fonksiyon
func parseDuration(_ duration: String) -> Int {
    // ISO 8601 format: PT4M13S (4 dakika 13 saniye)
    var totalSeconds = 0
    let pattern = #"PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?"#
    
    if let regex = try? NSRegularExpression(pattern: pattern),
       let match = regex.firstMatch(in: duration, range: NSRange(duration.startIndex..., in: duration)) {
        
        // Saat
        if let hoursRange = Range(match.range(at: 1), in: duration),
           let hours = Int(duration[hoursRange]) {
            totalSeconds += hours * 3600
        }
        
        // Dakika
        if let minutesRange = Range(match.range(at: 2), in: duration),
           let minutes = Int(duration[minutesRange]) {
            totalSeconds += minutes * 60
        }
        
        // Saniye
        if let secondsRange = Range(match.range(at: 3), in: duration),
           let seconds = Int(duration[secondsRange]) {
            totalSeconds += seconds
        }
    }
    
    return totalSeconds
}
