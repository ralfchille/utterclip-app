import AppIntents
import SwiftUI
import WidgetKit

/// Deep link the app answers by starting a recording (see `ContentView`'s `onOpenURL`).
private let recordURL = URL(string: "utterclip://record")!

/// Opens Utterclip straight into a recording — the action behind the Control Center /
/// Lock Screen / Action button control.
struct StartRecordingIntent: AppIntent {
    static let title: LocalizedStringResource = "Start dictating"
    static let description = IntentDescription("Opens Utterclip and starts recording.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(recordURL))
    }
}

/// The round button: Control Center, Lock Screen, Action button.
struct RecordControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.ralfchille.voicer.record-control") {
            ControlWidgetButton(action: StartRecordingIntent()) {
                Label("Dictate", systemImage: "mic.fill")
            }
        }
        .displayName("Dictate")
        .description("Start a new dictation in Utterclip.")
    }
}

/// Home Screen (small) and Lock Screen (circular) widget: a mic that deep-links into recording.
struct RecordWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.ralfchille.voicer.record-widget", provider: Provider()) { _ in
            RecordWidgetView()
                .widgetURL(recordURL)
        }
        .configurationDisplayName("Dictate")
        .description("Tap to start a new dictation.")
        .supportedFamilies([.systemSmall, .accessoryCircular])
    }

    struct Entry: TimelineEntry {
        let date: Date
    }

    /// Static content — the widget never needs to refresh.
    struct Provider: TimelineProvider {
        func placeholder(in context: Context) -> Entry { Entry(date: .now) }

        func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
            completion(Entry(date: .now))
        }

        func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
            completion(Timeline(entries: [Entry(date: .now)], policy: .never))
        }
    }
}

/// The app's waveform-"a" mark on the monochrome record-button circle. The mark ships as
/// a template image so it tints: inverted on the black circle, system-tinted on the Lock Screen.
///
/// Keep the asset small: WidgetKit archives the image's *source pixels*, and the Lock Screen
/// family rejects anything over ~475×432 px ("image too large") — one oversized rendition
/// fails the whole extension and iOS then refuses to reload it for 24 hours. The imageset
/// holds 1x/2x/3x renditions of the 48 pt drawing size (46×48 … 137×144 px).
struct RecordWidgetView: View {
    @Environment(\.widgetFamily) private var family

    private var mark: some View {
        Image("UtterclipMark")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            // Placeholder renders (gallery while loading) redact images to a gray box;
            // the mark is static branding, so show it as-is.
            .unredacted()
    }

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                mark.padding(12)
            }
            .containerBackground(for: .widget) { Color.clear }
        default:
            VStack(spacing: 10) {
                mark
                    .frame(width: 34, height: 34)
                    .foregroundStyle(Color(.systemBackground))
                    .frame(width: 72, height: 72)
                    .background(Circle().fill(.primary))
                Text("Dictate")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .containerBackground(for: .widget) { Color(.systemBackground) }
        }
    }
}

@main
struct UtterclipWidgets: WidgetBundle {
    var body: some Widget {
        RecordWidget()
        RecordControl()
    }
}
