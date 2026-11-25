import SwiftUI
import GoogleMobileAds
import UserMessagingPlatform

enum AdConfig {
    /// Banner ad unit for Firefighters Fitness Test (AdMob).
    static let bannerUnitID = "ca-app-pub-3118245182829166/1384482747"
}

/// Asks for ad consent (required in the UK and EU), then starts AdMob.
@MainActor
final class AdsManager: ObservableObject {
    @Published private(set) var canShowAds = false
    @Published private(set) var privacyOptionsRequired = false
    private var started = false
    private var prepared = false

    func prepare() {
        guard !prepared else { return }
        prepared = true
        // Consent given in an earlier session lets ads start straight away.
        startIfAllowed()
        ConsentInformation.shared.requestConsentInfoUpdate(with: RequestParameters()) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                try? await ConsentForm.loadAndPresentIfRequired(from: nil)
                self.privacyOptionsRequired =
                    ConsentInformation.shared.privacyOptionsRequirementStatus == .required
                self.startIfAllowed()
            }
        }
    }

    func showPrivacyOptions() {
        Task { try? await ConsentForm.presentPrivacyOptionsForm(from: nil) }
    }

    private func startIfAllowed() {
        guard ConsentInformation.shared.canRequestAds, !started else { return }
        started = true
        MobileAds.shared.start(completionHandler: nil)
        canShowAds = true
    }
}

/// A banner along the bottom of the screen. It only takes up space once an advert
/// has actually loaded, so users never see an empty strip. Hidden once ads are removed.
struct AdBanner: View {
    @EnvironmentObject var ads: AdsManager
    @EnvironmentObject var store: Store
    @State private var loaded = false

    var body: some View {
        if ads.canShowAds && !store.adsRemoved {
            let size = currentOrientationAnchoredAdaptiveBanner(width: UIScreen.main.bounds.width)
            BannerAdView(adSize: size, loaded: $loaded)
                .frame(height: loaded ? size.size.height : 1)
                .opacity(loaded ? 1 : 0)
                .background(loaded ? AnyShapeStyle(.bar) : AnyShapeStyle(.clear))
        }
    }
}

private struct BannerAdView: UIViewRepresentable {
    let adSize: AdSize
    @Binding var loaded: Bool

    func makeCoordinator() -> Coordinator { Coordinator(loaded: $loaded) }

    func makeUIView(context: Context) -> BannerView {
        let banner = BannerView(adSize: adSize)
        banner.adUnitID = AdConfig.bannerUnitID
        banner.delegate = context.coordinator
        banner.rootViewController = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow?.rootViewController }
            .first
        banner.load(Request())
        return banner
    }

    func updateUIView(_ uiView: BannerView, context: Context) {}

    final class Coordinator: NSObject, BannerViewDelegate {
        private var loaded: Binding<Bool>
        init(loaded: Binding<Bool>) { self.loaded = loaded }

        func bannerViewDidReceiveAd(_ bannerView: BannerView) {
            DispatchQueue.main.async { self.loaded.wrappedValue = true }
        }

        func bannerView(_ bannerView: BannerView, didFailToReceiveAdWithError error: Error) {
            DispatchQueue.main.async { self.loaded.wrappedValue = false }
        }
    }
}
