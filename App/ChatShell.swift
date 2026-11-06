import SwiftUI
import UIKit
import WebKit

/// The whole-screen chat. The page always comes from the server, so front-end changes reach the phone
/// without a reinstall. Two fingers double-tapping anywhere opens the native settings.
struct RootView: View {
    @ObservedObject var model: AppModel
    @State private var showSettings = false
    @State private var loadError: String?
    @State private var reloads = 0

    var body: some View {
        ZStack {
            if let url = model.chatURL {
                ChatWebView(url: url, reloads: reloads,
                            onSettings: { showSettings = true },
                            onError: { loadError = $0 })
                    .ignoresSafeArea()
                if let loadError {
                    VStack(spacing: 14) {
                        Text("没连上小窝").font(.headline)
                        Text(loadError).font(.footnote).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button("再试一次") {
                            self.loadError = nil
                            reloads += 1
                        }.buttonStyle(.borderedProminent)
                        Button("设置") { showSettings = true }
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.systemBackground))
                }
            } else {
                ContentView(model: model)
            }
        }
        .sheet(isPresented: $showSettings) { ContentView(model: model) }
    }
}

struct ChatWebView: UIViewRepresentable {
    let url: URL
    let reloads: Int
    let onSettings: () -> Void
    let onError: (String?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(home: url, onSettings: onSettings, onError: onError) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.applicationNameForUserAgent = "XiaoyanShell/1"
        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator
        web.uiDelegate = context.coordinator
        web.isOpaque = false
        web.backgroundColor = UIColor(red: 0.98, green: 0.965, blue: 0.945, alpha: 1)
        web.scrollView.contentInsetAdjustmentBehavior = .never
        web.scrollView.bounces = false

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.openSettings))
        tap.numberOfTouchesRequired = 2
        tap.numberOfTapsRequired = 2
        tap.cancelsTouchesInView = false
        tap.delegate = context.coordinator
        web.addGestureRecognizer(tap)

        web.load(URLRequest(url: url))
        context.coordinator.seenReloads = reloads
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {
        guard context.coordinator.seenReloads != reloads else { return }
        context.coordinator.seenReloads = reloads
        web.load(URLRequest(url: url))
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate,
                             UIGestureRecognizerDelegate {
        private let home: URL
        private let onSettings: () -> Void
        private let onError: (String?) -> Void
        private var downloadedFile: URL?
        var seenReloads = 0

        init(home: URL, onSettings: @escaping () -> Void, onError: @escaping (String?) -> Void) {
            self.home = home
            self.onSettings = onSettings
            self.onError = onError
        }

        @objc func openSettings() { onSettings() }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

        private var topController: UIViewController? {
            let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
            var top = scene?.windows.first(where: \.isKeyWindow)?.rootViewController
            while let next = top?.presentedViewController { top = next }
            return top
        }

        // MARK: Navigation

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if action.shouldPerformDownload { decisionHandler(.download); return }
            guard let target = action.request.url, let scheme = target.scheme?.lowercased() else {
                decisionHandler(.allow); return
            }
            let web = scheme == "http" || scheme == "https"
            let local = scheme == "about" || scheme == "blob" || scheme == "data"
            let leaving = web && target.host != home.host
                && action.targetFrame?.isMainFrame == true && action.navigationType == .linkActivated
            if leaving || (!web && !local) {
                UIApplication.shared.open(target)
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse,
                     decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
            decisionHandler(response.canShowMIMEType ? .allow : .download)
        }

        func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
            download.delegate = self
        }

        func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
            download.delegate = self
        }

        func download(_ download: WKDownload, decideDestinationUsing response: URLResponse,
                      suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
            let file = FileManager.default.temporaryDirectory.appendingPathComponent(suggestedFilename)
            try? FileManager.default.removeItem(at: file)
            downloadedFile = file
            completionHandler(file)
        }

        func downloadDidFinish(_ download: WKDownload) {
            guard let file = downloadedFile else { return }
            topController?.present(UIActivityViewController(activityItems: [file], applicationActivities: nil),
                                   animated: true)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { onError(nil) }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            report(error)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
                     withError error: Error) {
            report(error)
        }

        private func report(_ error: Error) {
            guard (error as NSError).code != NSURLErrorCancelled else { return }
            onError(error.localizedDescription)
        }

        /// iOS may kill the page's process in the background, which would leave a blank screen.
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            webView.load(URLRequest(url: home))
        }

        // MARK: Page dialogs, microphone, new windows

        func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                     initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
            let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "好", style: .default) { _ in completionHandler() })
            guard let top = topController else { completionHandler(); return }
            top.present(alert, animated: true)
        }

        func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                     initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
            let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in completionHandler(false) })
            alert.addAction(UIAlertAction(title: "好", style: .default) { _ in completionHandler(true) })
            guard let top = topController else { completionHandler(false); return }
            top.present(alert, animated: true)
        }

        func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String,
                     defaultText: String?, initiatedByFrame frame: WKFrameInfo,
                     completionHandler: @escaping (String?) -> Void) {
            let alert = UIAlertController(title: nil, message: prompt, preferredStyle: .alert)
            alert.addTextField { $0.text = defaultText }
            alert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in completionHandler(nil) })
            alert.addAction(UIAlertAction(title: "好", style: .default) { _ in
                completionHandler(alert.textFields?.first?.text)
            })
            guard let top = topController else { completionHandler(nil); return }
            top.present(alert, animated: true)
        }

        func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                     initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
                     decisionHandler: @escaping (WKPermissionDecision) -> Void) {
            decisionHandler(origin.host == home.host ? .grant : .prompt)
        }

        /// window.open and target=_blank: websites go to Safari, pages the app builds itself open in a sheet.
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let target = action.request.url, let scheme = target.scheme?.lowercased(),
               scheme == "http" || scheme == "https" {
                if target.host == home.host { webView.load(action.request) } else { UIApplication.shared.open(target) }
                return nil
            }
            let popup = WKWebView(frame: .zero, configuration: configuration)
            popup.navigationDelegate = self
            popup.uiDelegate = self
            let page = UIViewController()
            page.view = popup
            topController?.present(page, animated: true)
            return popup
        }

        func webViewDidClose(_ webView: WKWebView) {
            topController?.dismiss(animated: true)
        }
    }
}
