import XCTest
import WebKit
@testable import PopupBridge

final class PopupBridge_UnitTests: XCTestCase, WKNavigationDelegate {

    let scriptMessageHandlerName: String = "POPPopupBridge"
    let returnURL: String = "com.braintreepayments.popupbridgeexample"
    let mockWebAuthenticationSession = MockWebAuthenticationSession()
    let mockAnalyticsService = MockAnalyticsService()

    var webViewReadyBlock: (Void)?

    func testInit_addsUserScript() {
        let webView = WKWebView()

        XCTAssertEqual(webView.configuration.userContentController.userScripts.count, 0)

        let _ = POPPopupBridge(webView: webView)

        XCTAssertEqual(webView.configuration.userContentController.userScripts.count, 1)

        let userScript = webView.configuration.userContentController.userScripts[0]

        XCTAssertEqual(userScript.injectionTime, WKUserScriptInjectionTime.atDocumentStart)
        XCTAssertFalse(userScript.isForMainFrameOnly)
    }


    func testInit_addsScriptMessageHandler() {
        let configuration = WKWebViewConfiguration()
        let mockUserContentController = MockUserContentController()

        configuration.userContentController = mockUserContentController

        let webView = WKWebView(frame: CGRect(), configuration: configuration)
        let _ = POPPopupBridge(webView: webView)

        XCTAssertNotNil(mockUserContentController.scriptMessageHandler as? WebViewScriptHandler)
        XCTAssertEqual(mockUserContentController.name, scriptMessageHandlerName)
    }

    func testReceiveScriptMessage_whenMessageContainsURL_startsWebAuthenticationSession() {
        let stubMessageBody: [String: String] = ["url": "http://example.com/?hello=world"]
        let stubMessageName = scriptMessageHandlerName
        let stubMessage = MockScriptMessage()
        stubMessage.body = stubMessageBody
        stubMessage.name = stubMessageName

        let configuration = WKWebViewConfiguration()
        let mockUserContentController = MockUserContentController()

        configuration.userContentController = mockUserContentController

        let webView = WKWebView(frame: CGRect(), configuration: configuration)
        let pub = POPPopupBridge(
            webView: webView,
            webAuthenticationSession: mockWebAuthenticationSession
        )

        mockWebAuthenticationSession.cannedResponseURL = URL(string: "http://example.com/?hello=world")
        pub.userContentController(WKUserContentController(), didReceive: stubMessage)

        XCTAssertTrue(pub.returnedWithURL)
    }

    func testReceiveScriptMessage_whenMessageContainsURL_informsDelegateThatURLWillBeLoaded() {
        let stubMessageBody: [String?: Any?] = [:]
        let stubMessageName = scriptMessageHandlerName
        let stubMessage = MockScriptMessage()
        stubMessage.body = stubMessageBody
        stubMessage.name = stubMessageName

        let configuration = WKWebViewConfiguration()
        let mockUserContentController = MockUserContentController()

        configuration.userContentController = mockUserContentController

        let webView = WKWebView(frame: CGRect(), configuration: configuration)
        let pub = POPPopupBridge(webView: webView)

        pub.userContentController(WKUserContentController(), didReceive: stubMessage)
    }

    func testReceiveScriptMessage_whenMessageNameIsNotScriptMessageHandlerName_doesNotRequestPresentationOfViewControllers() {
        let stubMessageBody: [String: String] = ["url": "http://example.com/?hello=world"]
        let stubMessageName = "foo"
        let stubMessage = MockScriptMessage()
        stubMessage.body = stubMessageBody
        stubMessage.name = stubMessageName

        let configuration = WKWebViewConfiguration()
        let mockUserContentController = MockUserContentController()

        configuration.userContentController = mockUserContentController

        let webView = WKWebView(frame: CGRect(), configuration: configuration)
        let pub = POPPopupBridge(webView: webView)

        pub.userContentController(WKUserContentController(), didReceive: stubMessage)
    }

    func testPopupBridge_whenDoneButtonTappedOnSafariViewController_callsOnCancelOrOnCompleteWithNoPayloadOrError() {
        let stubMessageBody: [String: String] = ["url": "http://example.com/?hello=world"]
        let stubMessageName = scriptMessageHandlerName
        let stubMessage = MockScriptMessage()
        stubMessage.body = stubMessageBody
        stubMessage.name = stubMessageName

        let configuration = WKWebViewConfiguration()
        let mockUserContentController = MockUserContentController()

        configuration.userContentController = mockUserContentController

        let webView = WKWebView(frame: CGRect(), configuration: configuration)
        let pub = POPPopupBridge(webView: webView)

        pub.userContentController(WKUserContentController(), didReceive: stubMessage)

        webView.evaluateJavaScript("""
        "if (typeof window.popupBridge.onCancel === 'function') {"
        "  window.popupBridge.onCancel();"
        "} else {"
        "  window.popupBridge.onComplete(null, null);"
        "}"
        """)
    }

    func testConstructJavaScriptCompletionResult_whenReturnURLHasQueryParams_passesPayloadWithQueryItemsToWebView() {
        let stubMessageBody: [String: String] = ["url": "http://example.com/?hello=world"]
        let stubMessageName = scriptMessageHandlerName
        let stubMessage = MockScriptMessage()
        stubMessage.body = stubMessageBody
        stubMessage.name = stubMessageName

        let configuration = WKWebViewConfiguration()
        let mockUserContentController = MockUserContentController()

        configuration.userContentController = mockUserContentController

        let webView = WKWebView(frame: CGRect(), configuration: configuration)
        let pub = POPPopupBridge(
            webView: webView,
            webAuthenticationSession: mockWebAuthenticationSession
        )
        let mockURL = URL(string: "sdk.ios.popup-bridge://popupbridgev1/return?something=foo&other=bar")!
        mockWebAuthenticationSession.cannedResponseURL = mockURL

        let expectedResult = "window.popupBridge.onComplete(null, {\"path\":\"\\/return\",\"queryItems\":{\"other\":\"bar\",\"something\":\"foo\"}});"
        let result = pub.constructJavaScriptCompletionResult(returnURL: mockURL)

        let expectedJSON = extractJSON(from: expectedResult)
        let actualJSON = extractJSON(from: result!)
        
        XCTAssertEqual(actualJSON, expectedJSON)
    }

    func testConstructJavaScriptCompletionResult_whenReturnURLHasNoQueryParams_passesPayloadWithNoQueryItemsToWebView() {
        let stubMessageBody: [String: String] = ["url": "http://example.com/?hello=world"]
        let stubMessageName = scriptMessageHandlerName
        let stubMessage = MockScriptMessage()
        stubMessage.body = stubMessageBody
        stubMessage.name = stubMessageName

        let configuration = WKWebViewConfiguration()
        let mockUserContentController = MockUserContentController()

        configuration.userContentController = mockUserContentController

        let webView = WKWebView(frame: CGRect(), configuration: configuration)
        let pub = POPPopupBridge(
            webView: webView,
            webAuthenticationSession: mockWebAuthenticationSession
        )
        let mockURL = URL(string: "sdk.ios.popup-bridge://popupbridgev1/return")!
        mockWebAuthenticationSession.cannedResponseURL = mockURL

        let expectedResult = "window.popupBridge.onComplete(null, {\"path\":\"\\/return\",\"queryItems\":{}});"
        let result = pub.constructJavaScriptCompletionResult(returnURL: mockURL)

        let expectedJSON = extractJSON(from: expectedResult)
        let actualJSON = extractJSON(from: result!)
        
        XCTAssertEqual(actualJSON, expectedJSON)
    }

    func testConstructJavaScriptCompletionResult_whenReturnURLHasURLFragment_passesPayloadWithHashToWebView() {
        let stubMessageBody: [String: String] = ["url": "http://example.com/?hello=world"]
        let stubMessageName = scriptMessageHandlerName
        let stubMessage = MockScriptMessage()
        stubMessage.body = stubMessageBody
        stubMessage.name = stubMessageName

        let pub = POPPopupBridge(
            webView: WKWebView(),
            webAuthenticationSession: mockWebAuthenticationSession
        )

        pub.userContentController(WKUserContentController(), didReceive: stubMessage)

        let mockURL = URL(string: "sdk.ios.popup-bridge://popupbridgev1/return#something=foo&other=bar")!
        mockWebAuthenticationSession.cannedResponseURL = mockURL

        let expectedResult = "window.popupBridge.onComplete(null, {\"path\":\"\\/return\",\"hash\":\"something=foo&other=bar\",\"queryItems\":{}});"
        let result = pub.constructJavaScriptCompletionResult(returnURL: mockURL)

        let expectedJSON = extractJSON(from: expectedResult)
        let actualJSON = extractJSON(from: result!)
        
        XCTAssertEqual(actualJSON, expectedJSON)
    }

    func testConstructJavaScriptCompletionResult_whenReturnURLHasNoURLFragment_passesPayloadWithNilHashToWebView() {
        let stubMessageBody: [String: String] = ["url": "http://example.com/?hello=world"]
        let stubMessageName = scriptMessageHandlerName
        let stubMessage = MockScriptMessage()
        stubMessage.body = stubMessageBody
        stubMessage.name = stubMessageName

        let pub = POPPopupBridge(
            webView: WKWebView(),
            webAuthenticationSession: mockWebAuthenticationSession
        )

        pub.userContentController(WKUserContentController(), didReceive: stubMessage)

        let mockURL = URL(string: "sdk.ios.popup-bridge://popupbridgev1/return")!
        mockWebAuthenticationSession.cannedResponseURL = mockURL

        let expectedResult = "window.popupBridge.onComplete(null, {\"path\":\"\\/return\",\"queryItems\":{}});"
        let result = pub.constructJavaScriptCompletionResult(returnURL: mockURL)

        let expectedJSON = extractJSON(from: expectedResult)
        let actualJSON = extractJSON(from: result!)
        
        XCTAssertEqual(actualJSON, expectedJSON)
    }

    func testConstructJavaScriptCompletionResult_whenReturnURLDoesNotMatchScheme_returnsFalseAndDoesNotCallOnComplete() {
        let stubMessageBody: [String: String] = ["url": "http://example.com/?hello=world"]
        let stubMessageName = scriptMessageHandlerName
        let stubMessage = MockScriptMessage()
        stubMessage.body = stubMessageBody
        stubMessage.name = stubMessageName

        let pub = POPPopupBridge(webView: WKWebView())
        pub.userContentController(WKUserContentController(), didReceive: stubMessage)

        let result = pub.constructJavaScriptCompletionResult(returnURL: URL(string: "not.the.right.scheme://popupbridgev1/return?something=foo")!)
        XCTAssertNil(result)
    }

    func testConstructJavaScriptCompletionResult_whenReturnURLDoesNotMatchHost_returnsFalseAndDoesNotCallOnComplete() {
        let stubMessageBody: [String: String] = ["url": "http://example.com/?hello=world"]
        let stubMessageName = scriptMessageHandlerName
        let stubMessage = MockScriptMessage()
        stubMessage.body = stubMessageBody
        stubMessage.name = stubMessageName

        let pub = POPPopupBridge(webView: WKWebView())
        pub.userContentController(WKUserContentController(), didReceive: stubMessage)

        let result = pub.constructJavaScriptCompletionResult(returnURL: URL(string: "sdk.ios.popup-bridge://popupbridgev2/return?something=foo")!)
        XCTAssertNil(result)
    }

    // Consider adding tests for query parameter parsing - multiple values, special characters, encoded, etc.

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if let webViewReadyBlock {
            webViewReadyBlock
        }
    }
    
    private func extractJSON(from jsString: String) -> [String: String]? {
        let pattern = "window\\.popupBridge\\.onComplete\\(null, (.*)\\);"
        let regex = try? NSRegularExpression(pattern: pattern, options: [])
        
        if let match = regex?.firstMatch(in: jsString, options: [], range: NSRange(jsString.startIndex..., in: jsString)),
           let jsonRange = Range(match.range(at: 1), in: jsString) {
            let jsonString = String(jsString[jsonRange])
            
            if let data = jsonString.data(using: .utf8) {
                return (try? JSONSerialization.jsonObject(with: data, options: [])) as? [String: String]
            }
        }
        
        return nil
    }
    
    func testInit_sendsAnalytics() {
        XCTAssertEqual(mockAnalyticsService.eventCount, 0)
        POPPopupBridge.analyticsService = mockAnalyticsService
        
        let _ = POPPopupBridge(
            webView: WKWebView(),
            webAuthenticationSession: mockWebAuthenticationSession
        )
        
        XCTAssertEqual(mockAnalyticsService.eventCount, 1)
        XCTAssertEqual(mockAnalyticsService.lastEventName, PopupBridgeAnalytics.started)
        XCTAssertNotNil(mockAnalyticsService.lastSessionID)
    }
    
    func testConstructJavaScriptCompletionResult_whenReturnURL_sendsAnalytics() {
        XCTAssertEqual(mockAnalyticsService.eventCount, 0)
        let configuration = WKWebViewConfiguration()
        let mockUserContentController = MockUserContentController()

        configuration.userContentController = mockUserContentController

        let webView = WKWebView(frame: CGRect(), configuration: configuration)
        POPPopupBridge.analyticsService = mockAnalyticsService
        let pub = POPPopupBridge(
            webView: webView,
            webAuthenticationSession: mockWebAuthenticationSession
        )
        let mockURL = URL(string: "sdk.ios.popup-bridge://popupbridgev1/return?something=foo&other=bar")!
        mockWebAuthenticationSession.cannedResponseURL = mockURL

        let expectedResult = "window.popupBridge.onComplete(null, {\"path\":\"\\/return\",\"queryItems\":{\"other\":\"bar\",\"something\":\"foo\"}});"
        let result = pub.constructJavaScriptCompletionResult(returnURL: mockURL)

        let expectedJSON = extractJSON(from: expectedResult)
        let actualJSON = extractJSON(from: result!)
        
        XCTAssertEqual(actualJSON, expectedJSON)
        XCTAssertEqual(mockAnalyticsService.eventCount, 2)
        XCTAssertEqual(mockAnalyticsService.lastEventName, PopupBridgeAnalytics.succeeded)
        XCTAssertNotNil(mockAnalyticsService.lastSessionID)
    }
    
    func testPopupBridge_whenCancelButtonTappedOnSafariViewController_sendsAnalytics() {
        XCTAssertEqual(mockAnalyticsService.eventCount, 0)
        let stubMessageBody: [String: String] = ["url": "http://example.com/?hello=world"]
        let stubMessageName = scriptMessageHandlerName
        let stubMessage = MockScriptMessage()
        stubMessage.body = stubMessageBody
        stubMessage.name = stubMessageName

        let configuration = WKWebViewConfiguration()
        let mockUserContentController = MockUserContentController()

        configuration.userContentController = mockUserContentController

        POPPopupBridge.analyticsService = mockAnalyticsService
        let webView = WKWebView(frame: CGRect(), configuration: configuration)
        let pub = POPPopupBridge(
            webView: webView,
            webAuthenticationSession: mockWebAuthenticationSession
        )
        mockWebAuthenticationSession.shouldCancel = true
        pub.userContentController(WKUserContentController(), didReceive: stubMessage)

        webView.evaluateJavaScript("""
        "if (typeof window.popupBridge.onCancel === 'function') {"
        "  window.popupBridge.onCancel();"
        "} else {"
        "  window.popupBridge.onComplete(null, null);"
        "}"
        """)
        
        XCTAssertEqual(mockAnalyticsService.eventCount, 2)
        XCTAssertEqual(mockAnalyticsService.lastEventName, PopupBridgeAnalytics.canceled)
        XCTAssertNotNil(mockAnalyticsService.lastSessionID)
    }
    
    func testPOPPopupBridge_shouldNotLeak() {
        let webView = WKWebView()
        trackForMemoryLeak(instance: POPPopupBridge(
            webView: webView,
            webAuthenticationSession: mockWebAuthenticationSession
        ))
        webView.load(URLRequest(url: URL(string: "some-popup-bridge-example")!))
    }
}
