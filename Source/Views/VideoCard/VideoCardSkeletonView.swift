/*
 File Overview (EN)
 Purpose: Skeleton placeholder views for video cards to improve perceived performance during loads.
 Key Responsibilities:
 - Render shimmer placeholders matching the card layout
 - Keep shapes/lightweight to avoid layout shifts
 - Integrate with grid/list while data loads
 Used By: Home and search grids.

 Dosya Özeti (TR)
 Amacı: Yüklemeler sırasında algılanan performansı artırmak için video kartlarına yönelik iskelet yer tutucu görünümler.
 Ana Sorumluluklar:
 - Kart yerleşimine uygun parıltı (shimmer) yer tutucular çizmek
 - Yer değiştirmeleri önlemek için hafif ve sabit şekiller kullanmak
 - Veri yüklenirken grid/liste ile entegre olmak
 Nerede Kullanılır: Ana ve arama gridleri.
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
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: 20)
                    .shimmering()
                    .cornerRadius(4)
                
                Rectangle()
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
