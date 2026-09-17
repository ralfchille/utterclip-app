#if DEBUG
import AppKit
import UtterclipCore

/// Debug builds only: `open "utterclip://demo"` puts a fixed result on screen — the same text
/// every time, in the same window — so a layout question (line pitch, where the caret lands,
/// what moves when the card turns editable) can be looked at twice and compared. `?edit=1`
/// opens that result for editing, and `?x=&y=` says where the click that opened it landed, in
/// the same top-left coordinates SwiftUI hands the real tap over in.
///
/// For screenshots that have to show a particular dictation — the README's, say — `text=`,
/// `raw=` and `style=` (a style id such as `slack`) replace the fixed text, and `phone=0`
/// dismisses the capsule announcing a dictation from the phone, which would otherwise sit on
/// top of the card. Compiled out of Release.
@MainActor
enum DebugSeed {
    /// Long enough to wrap several times, with a blank line in it: the two places the rendered
    /// text and the editable text have drifted apart before.
    static let text = """
        Ich schaue mir das Vormittag mal alles an. Wie kriegen wir die Entscheidung hin? \
        Sollten wir nochmal darüber in einem kurzen Austausch sprechen?

        Danach melde ich mich nochmal.
        """

    static func handle(_ url: URL) {
        AppDelegate.shared?.showWindow()
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { query.first(where: { $0.name == name })?.value }
        var info: [String: Any] = ["edit": value("edit") == "1", "phone": value("phone") != "0"]
        if let x = value("x").flatMap(Double.init), let y = value("y").flatMap(Double.init) {
            info["point"] = CGPoint(x: x, y: y)
        }
        if let raw = value("raw") { info["raw"] = raw }
        if let style = value("style") { info["style"] = style }
        NotificationCenter.default.post(name: .utterclipDebugResult, object: value("text") ?? text, userInfo: info)
    }
}
#endif
