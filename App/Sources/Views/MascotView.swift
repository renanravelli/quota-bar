import QuotaBarCore
import SwiftUI

struct MascotView: View {
    let expression: MascotExpression

    var body: some View {
        if let image = MascotAsset.image(for: expression) {
            Image(nsImage: image)
                .interpolation(.none)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 48, height: 48)
                .accessibilityHidden(true)
        }
    }
}
