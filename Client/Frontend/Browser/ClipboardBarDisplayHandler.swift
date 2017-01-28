
import Foundation
import Shared

public struct UserDefaultClipboardKey {
    public static let KeyLastSavedURL = "KeylastSavedURL"
}

class ClipboardBarDisplayHandler {
    private let clipboardBar: ClipboardBar
    var sessionStarted = true
    var prefs: Prefs
    var isClipboardBarVisible: Bool { return !clipboardBar.hidden }
    var lastDisplayedURL: String? {
        if let value = NSUserDefaults.standardUserDefaults().objectForKey(UserDefaultClipboardKey.KeyLastSavedURL) as? String {
            return value
        }
        return nil
    }
    
    init(clipboardBar: ClipboardBar, prefs: Prefs) {
        self.clipboardBar = clipboardBar
        self.clipboardBar.hidden = true
        self.prefs = prefs
        
        NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(self.SELAppWillEnterForegroundNotification), name: UIApplicationWillEnterForegroundNotification, object: nil)
    }
    
    deinit {
        NSNotificationCenter.defaultCenter().removeObserver(self, name: UIApplicationWillEnterForegroundNotification, object: nil)
    }

    @objc func SELAppWillEnterForegroundNotification() {
        sessionStarted = true
        displayBarIfNecessary()
    }
    
    func hideBar() {
        if !isClipboardBarVisible {
            return
        }
        UIView.animateWithDuration(0.2, delay: 0, options: .BeginFromCurrentState, animations: {
            self.clipboardBar.alpha = 0.0
            }, completion: { _ in
                self.clipboardBar.hidden = true
            }
         )
    }
    
    func saveLastDisplayedURL(url: String?) {
        if let urlString = url {
            NSUserDefaults.standardUserDefaults().setObject(urlString, forKey: UserDefaultClipboardKey.KeyLastSavedURL)
        } else {
            NSUserDefaults.standardUserDefaults().removeObjectForKey(UserDefaultClipboardKey.KeyLastSavedURL)
        }
        NSUserDefaults.standardUserDefaults().synchronize()
    }
    
    //If we already displayed this URL on the previous session
    //We shouldn't display it again
    func wasClipboardURLAlreadyDisplayed() -> Bool {
        guard let clipboardURL = UIPasteboard.generalPasteboard().copiedURL?.absoluteString ,
        let savedURL = lastDisplayedURL else {
            return false
        }
        if clipboardURL == savedURL {
            return true
        }
        return false
    }
    
    func displayBarIfNecessary() {
        let allowClipboard = (prefs.boolForKey(PrefsKeys.KeyClipboardOption) ?? true)
        
        if !sessionStarted || !allowClipboard || UIPasteboard.generalPasteboard().copiedURL == nil || wasClipboardURLAlreadyDisplayed() {
            hideBar()
            return
        }

        clipboardBar.hidden = false
        clipboardBar.alpha = 1.0;
        sessionStarted = false
        clipboardBar.urlString = UIPasteboard.generalPasteboard().copiedURL?.absoluteString
        saveLastDisplayedURL(clipboardBar.urlString)
        let seconds = 10.0
        let popTime = dispatch_time(DISPATCH_TIME_NOW, Int64(seconds * Double(NSEC_PER_SEC)))
        dispatch_after(popTime, dispatch_get_main_queue()) { [weak self] in
            self?.hideBar()
        }
    }
}
