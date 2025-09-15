/*
 Overview / Genel Bakış
 EN: Skeleton placeholders for cards to smooth loading states.
 TR: Yükleme durumlarını yumuşatmak için kart iskelet yer tutucuları.
*/

import SwiftUI

// Video Card Skeleton - Loading state
struct VideoCardSkeletonView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Rectangle()
                .fill(Color.gray.opacity(0.2))
                .aspectRatio(16/9, contentMode: .fill)
                .shimmering()
                .cornerRadius(12)
            
            VStack(alignment: .leading, spacing: 8) {
                Rectangle() // EN: Title line placeholder. TR: Başlık satırı yer tutucu.
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: 20)
                    .shimmering()
                    .cornerRadius(4)
                
                Rectangle() // EN: Meta line placeholder. TR: Meta satırı yer tutucu.
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: 16)
                    .frame(maxWidth: 140)
                    .shimmering()
                    .cornerRadius(4)
            }
            .padding(.horizontal, 4)
        }
        .cornerRadius(12)
    }
}
