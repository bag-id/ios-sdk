import SwiftUI
import UIKit

/// Illustration for the managed-flow scan hint (learn-how slide 2).
/// Uses UIKit so the full-color PNG is not flattened by SwiftUI `foregroundStyle` on ancestors.
struct BagIdDiscoverabilityIllustration: View {
    private let maxWidth: CGFloat = 160

    var body: some View {
        BagIdDiscoverabilityIllustrationRepresentable()
            .frame(width: maxWidth, height: maxWidth * 0.94)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .accessibilityHidden(true)
    }
}

private struct BagIdDiscoverabilityIllustrationRepresentable: UIViewRepresentable {
    private let maxWidth: CGFloat = 160

    func makeUIView(context: Context) -> UIImageView {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.backgroundColor = .clear
        imageView.clipsToBounds = true
        imageView.image = Self.loadImage()
        imageView.setContentHuggingPriority(.required, for: .horizontal)
        imageView.setContentHuggingPriority(.required, for: .vertical)
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        return imageView
    }

    func updateUIView(_ uiView: UIImageView, context: Context) {
        uiView.image = Self.loadImage()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIImageView, context: Context) -> CGSize? {
        let width = min(proposal.width ?? maxWidth, maxWidth)
        guard let image = uiView.image, image.size.width > 0 else {
            return CGSize(width: width, height: width * 0.94)
        }
        let height = width * (image.size.height / image.size.width)
        return CGSize(width: width, height: height)
    }

    private static func loadImage() -> UIImage? {
        for bundle in [Bundle.module, Bundle.main] {
            if let image = UIImage(named: "bagid_discoverability_hint", in: bundle, compatibleWith: nil) {
                return image
            }
            if let url = bundle.url(forResource: "bagid_discoverability_hint", withExtension: "png"),
               let data = try? Data(contentsOf: url),
               let image = UIImage(data: data) {
                return image
            }
        }
        return nil
    }
}
