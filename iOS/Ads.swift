import SwiftUI
import GoogleMobileAds
import UserMessagingPlatform

enum AdConfig {
    /// Google's TEST banner ID. Replace with your own banner ad unit ID from AdMob before release.
    static let bannerUnitID = "ca-app-pub-3940256099942544/2435281174"
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

/// A banner along the bottom of the screen. Hidden once ads are removed.
struct AdBanner: View {
    @EnvironmentObject var ads: AdsManager
    @EnvironmentObject var store: Store

    var body: some View {
        if ads.canShowAds && !store.adsRemoved {
            let size = currentOrientationAnchoredAdaptiveBanner(width: UIScreen.main.bounds.width)
            BannerAdView(adSize: size)
                .frame(height: size.size.height)
                .background(.bar)
        }
    }
}

private struct BannerAdView: UIViewRepresentable {
    let adSize: AdSize

    func makeUIView(context: Context) -> BannerView {
        let banner = BannerView(adSize: adSize)
        banner.adUnitID = AdConfig.bannerUnitID
        banner.rootViewController = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow?.rootViewController }
            .first
        banner.load(Request())
        return banner
    }

    func updateUIView(_ uiView: BannerView, context: Context) {}
}
