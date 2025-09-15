/*
 Overview / Genel Bakış
 EN: Placeholder page for locally sourced videos (deprecated).
 TR: Yerel videolar için yer tutucu sayfa (kullanımdan kalktı).
*/

import SwiftUI

struct LocalVideoPageView: View {
    let videoId: String
    @ObservedObject var youtubeAPI: YouTubeAPIService

    var body: some View {
        Text("LocalVideoPageView deprecated")
    }
}
