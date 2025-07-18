import Foundation
import WebKit
import AuthenticationServices

@objcMembers
public class POPPopupBridge: NSObject, WKScriptMessageHandler {

    /// Exposed for testing
    var returnedWithURL: Bool = false
    
    static var analyticsService: AnalyticsServiceable = AnalyticsService()
    
    // MARK: - Private Properties
    
    private let messageHandlerName = "POPPopupBridge"
    private let hostName = "popupbridgev1"
    private let sessionID = UUID().uuidString.replacingOccurrences(of: "-", with: "")
    private let webView: WKWebView
    private let application: URLOpener = UIApplication.shared
    
    private var webAuthenticationSession: WebAuthenticationSession = WebAuthenticationSession()
    private var returnBlock: ((URL) -> Void)? = nil
    
    // MARK: - Initializers
        
    /// Initialize a Popup Bridge.
    /// - Parameters:
    ///   - webView: The web view to add a script message handler to. Do not change the web view's configuration or user content controller after initializing Popup Bridge.
    ///   - prefersEphemeralWebBrowserSession: A Boolean that, when true, requests that the browser does not share cookies
    ///   or other browsing data between the authenthication session and the user’s normal browser session.
    ///   Defaults to `true`.
    public init(webView: WKWebView, prefersEphemeralWebBrowserSession: Bool = true) {
        self.webView = webView
        
        super.init()

        configureWebView()
        webAuthenticationSession.prefersEphemeralWebBrowserSession = prefersEphemeralWebBrowserSession
                
        returnBlock = { [weak self] url in
            guard let script = self?.constructJavaScriptCompletionResult(returnURL: url) else {
                return
            }

            self?.injectWebView(webView: webView, withJavaScript: script)
            return
        }
    }

    /// Exposed for testing
    convenience init(
        webView: WKWebView,
        webAuthenticationSession: WebAuthenticationSession
    ) {
        self.init(webView: webView)
        self.webAuthenticationSession = webAuthenticationSession
    }
    
    deinit {
        webView.configuration.userContentController.removeAllScriptMessageHandlers()
    }
    
    // MARK: - Internal Methods

    /// Exposed for testing
    /// 
    /// Constructs custom JavaScript to be injected into the merchant's WKWebView, based on redirectURL details from the SFSafariViewController pop-up result.
    /// - Parameter url: returnURL from the result of the ASWebAuthenticationSession.
    /// - Returns: JavaScript formatted completion.
    func constructJavaScriptCompletionResult(returnURL: URL) -> String? {
        guard let urlComponents = URLComponents(url: returnURL, resolvingAgainstBaseURL: false),
              urlComponents.scheme?.caseInsensitiveCompare(PopupBridgeConstants.callbackURLScheme) == .orderedSame,
              urlComponents.host?.caseInsensitiveCompare(hostName) == .orderedSame
        else {
            return nil
        }

        let queryItems = urlComponents.queryItems?.reduce(into: [:]) { partialResult, queryItem in
            partialResult[queryItem.name] = queryItem.value
        }

        let payload = URLDetailsPayload(
            path: urlComponents.path,
            queryItems: queryItems ?? [:],
            hash: urlComponents.fragment
        )

        if let payloadData = try? JSONEncoder().encode(payload),
           let payload = String(data: payloadData, encoding: .utf8) {
            Self.analyticsService.sendAnalyticsEvent(PopupBridgeAnalytics.succeeded, sessionID: sessionID)
            return "window.popupBridge.onComplete(null, \(payload));"
        } else {
            let errorMessage = "Failed to parse query items from return URL."
            let errorResponse = "new Error(\"\(errorMessage)\")"
            Self.analyticsService.sendAnalyticsEvent(PopupBridgeAnalytics.failed, sessionID: sessionID)
            return "window.popupBridge.onComplete(\(errorResponse), null);"
        }
    }
    
    /// Injects custom JavaScript into the merchant's webpage.
    /// - Parameter scheme: the url scheme provided by the merchant
    private func configureWebView() {
        Self.analyticsService.sendAnalyticsEvent(PopupBridgeAnalytics.started, sessionID: sessionID)
        webView.configuration.userContentController.add(
            WebViewScriptHandler(proxy: self),
            name: messageHandlerName
        )
        
        let javascript = PopupBridgeUserScript(
            scheme: PopupBridgeConstants.callbackURLScheme,
            scriptMessageHandlerName: messageHandlerName,
            host: hostName,
            isVenmoInstalled: application.isVenmoAppInstalled()
        ).rawJavascript
        
        let script = WKUserScript(
            source: javascript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        
        webView.configuration.userContentController.addUserScript(script)
    }

    private func injectWebView(webView: WKWebView, withJavaScript script: String) {
        webView.evaluateJavaScript(script) { _, error in
            if let error {
                NSLog("Error: PopupBridge requires onComplete callback. Details: %@", error.localizedDescription)
            }
        }
    }
    
    // MARK: - WKScriptMessageHandler conformance
    
    /// :nodoc: This method is not covered by Semantic Versioning. Do not use.
    ///
    /// Called when the webpage sends a JavaScript message back to the native app
    public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == messageHandlerName {
            guard let jsonData = try? JSONSerialization.data(withJSONObject: message.body),
                  let script = try? JSONDecoder().decode(WebViewMessage.self, from: jsonData) else {
                return
            }
            
            if let urlString = script.url, let url = URL(string: urlString) {
                webAuthenticationSession.start(url: url, context: self) { url, _ in
                    if let url, let returnBlock = self.returnBlock {
                        self.returnedWithURL = true
                        returnBlock(url)
                        return
                    }
                } sessionDidCancel: { [self] in
                    let script = """
                        if (typeof window.popupBridge.onCancel === 'function') {\
                            window.popupBridge.onCancel();\
                        } else {\
                            window.popupBridge.onComplete(null, null);\
                        }
                    """
                    
                    Self.analyticsService.sendAnalyticsEvent(PopupBridgeAnalytics.canceled, sessionID: sessionID)
                    
                    injectWebView(webView: webView, withJavaScript: script)
                    return
                }
            }
        }
    }
}

// MARK: - ASWebAuthenticationPresentationContextProviding conformance

extension POPPopupBridge: ASWebAuthenticationPresentationContextProviding {

    public func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let firstScene = UIApplication.shared.connectedScenes.first as? UIWindowScene
        let window = firstScene?.windows.first { $0.isKeyWindow }
        return window ?? ASPresentationAnchor()
    }
}
