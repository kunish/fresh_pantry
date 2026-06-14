import SwiftUI
import WebKit

/// 在 App 内(半屏 sheet)内嵌播放菜谱视频外链。`Recipe.videoUrl` 存的是 B站
/// **观看页** URL(非媒体直链),要靠 WebKit 引擎加载并运行其页面 JS 才能取流,
/// 故用 `WKWebView` 而非 `AVPlayer`(直链方案走不通)。视频本身不下载、不托管,
/// 仅以外链网页播放——与旧 `SafariView` 同源,只是从「跳出系统 Safari」改为
/// 「留在 App 内」,做菜时不打断库存主流程。
struct WebVideoView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        // 内联播放(不强制全屏接管)+ 点按即播,免去额外的用户手势门槛。
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.allowsBackForwardNavigationGestures = false
        webView.load(URLRequest(url: url))
        return webView
    }

    /// `url` 由 `.sheet(item:)` 驱动——每次呈现都重建本视图,故无需在此 reload。
    func updateUIView(_ webView: WKWebView, context: Context) {}
}
