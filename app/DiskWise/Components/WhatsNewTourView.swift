import AppKit
import SwiftUI

struct WhatsNewPage: Identifiable {
    let id: String
    let icon: String
    let title: String
    let message: String
    let bullets: [String]
}

enum WhatsNewContent {
    static func pages(for version: String) -> [WhatsNewPage] {
        switch version {
        case "0.5.10":
            return v0510Pages
        case "0.5.9":
            return v059Pages
        case "0.5.8":
            return v058Pages
        case "0.5.7":
            return v057Pages
        case "0.5.6":
            return v056Pages
        case "0.5.5":
            return v055Pages
        case "0.5.4":
            return v054Pages
        case "0.3.0":
            return v030Pages
        case "0.2.4":
            return v024Pages
        case "0.2.3":
            return v023Pages
        case "0.2.2":
            return v022Pages
        case "0.2.1":
            return v021Pages
        case "0.2.0":
            return v020Pages
        case "0.1.8":
            return v018Pages
        case "0.1.7":
            return v017Pages
        case "0.1.6":
            return v016Pages
        case "0.1.5":
            return v015Pages
        case "0.1.4":
            return v014Pages
        case "0.1.3":
            return v013Pages
        case "0.1.2":
            return v012Pages
        default:
            return genericPages(version: version)
        }
    }

    private static let v0510Pages: [WhatsNewPage] = [
        WhatsNewPage(
            id: "scoped-charts",
            icon: "chart.pie",
            title: "Charts for the selected drive only",
            message: "Storage pie charts and category breakdowns now appear only after the drive selected in the sidebar has been scanned.",
            bullets: [
                "Unscanned external drives show a scan prompt instead of another volume's results",
                "Maintenance and duplicate actions follow the same per-drive rule",
            ]
        ),
        WhatsNewPage(
            id: "score-formula",
            icon: "heart.text.square",
            title: "Transparent health score",
            message: "System Status explains the Good, Fair, and Poor rating scale and shows the weighted formula behind your score.",
            bullets: [
                "Rating legend highlights your current label, e.g. Fair (40–69)",
                "Step-by-step CPU, memory, and disk contribution math",
            ]
        ),
    ]

    private static let v059Pages: [WhatsNewPage] = [
        WhatsNewPage(
            id: "health-explanation",
            icon: "heart.text.square",
            title: "Understand your health score",
            message: "The System Status tab now explains what Fair, Good, or Poor means — with CPU, memory, and disk breakdowns and practical suggestions.",
            bullets: [
                "See component scores and how each resource affects the overall rating",
                "Load average and memory context spelled out in plain language",
                "Actionable tips when disk, memory, or CPU pressure is high",
            ]
        ),
        WhatsNewPage(
            id: "process-context",
            icon: "app.dashed",
            title: "Smarter process lists and details",
            message: "Top CPU and Top Memory only highlight processes using significant resources. Tap any process for a rich explanation of what it is and who started it.",
            bullets: [
                "Idle-state summaries when nothing is consuming significant CPU or memory",
                "Process category, parent app, command line, and known system descriptions",
                "App icons and role summaries for shells, agents, and user apps",
            ]
        ),
    ]

    private static let v058Pages: [WhatsNewPage] = [
        WhatsNewPage(
            id: "system-status-tab",
            icon: "heart.text.square",
            title: "System Status tab",
            message: "Inspect live CPU, memory, disk, and uptime from a dedicated toolbar tab with your Mac's health score at a glance.",
            bullets: [
                "Side-by-side top CPU and top memory process lists",
                "Load average, cores, and memory breakdown in one place",
                "Refresh on demand while the tab is open",
            ]
        ),
        WhatsNewPage(
            id: "process-inspect",
            icon: "app.dashed",
            title: "Inspect and quit processes",
            message: "Tap any process to open a detail sheet with PID, owner, bundle ID, and executable path.",
            bullets: [
                "Quit or force quit with confirmation",
                "Protected system processes cannot be terminated from DiskWise",
                "Menu bar health badge shares the same live monitor",
            ]
        ),
    ]

    private static let v057Pages: [WhatsNewPage] = [
        WhatsNewPage(
            id: "terminal-tail",
            icon: "terminal",
            title: "One-click scan log in Terminal",
            message: "Open in Terminal now brings Terminal to the front and starts tail -f on the verbose scan log automatically.",
            bullets: [
                "No copy-paste — tail -f runs as soon as Terminal opens",
                "Prominent button on the Scanning tab log panel",
                "Copy command remains available if you prefer a custom shell",
            ]
        ),
        WhatsNewPage(
            id: "ai-formatting",
            icon: "text.bubble",
            title: "Clearer AI Analysis replies",
            message: "Chat responses now preserve line breaks and format sections, bullets, and numbered steps so long answers are easier to follow.",
            bullets: [
                "Paragraph breaks and headings render correctly in the chat bubble",
                "Recommendations and cleanup lists appear on separate lines",
                "Rule-based fallback answers use structured Markdown",
            ]
        ),
    ]

    private static let v056Pages: [WhatsNewPage] = [
        WhatsNewPage(
            id: "scan-format",
            icon: "arrow.triangle.2.circlepath",
            title: "Faster saved scans in 0.5.6",
            message: "DiskWise now stores an optimised launch snapshot so saved scans reload quickly, and clears incompatible data from earlier versions on first launch.",
            bullets: [
                "First launch after updating clears old saved-scan data automatically with a highlighted progress message",
                "Completed scans build a compact snapshot for instant reload on the next startup",
                "Uninterrupted startup loading applies your saved scan automatically — no extra prompt",
            ]
        ),
        WhatsNewPage(
            id: "startup-health",
            icon: "heart.text.square",
            title: "Menu bar health during startup",
            message: "System health profiling now runs on the startup splash, so the menu bar score appears as soon as DiskWise opens.",
            bullets: [
                "CPU, memory, and disk scoring run before the main window appears",
                "Process profiling moved off the saved-scan prompt path",
                "Skip loading a saved scan during startup if you want to choose later",
            ]
        ),
    ]

    private static let v055Pages: [WhatsNewPage] = [
        WhatsNewPage(
            id: "startup",
            icon: "hare.fill",
            title: "Snappier first launch after updating",
            message: "DiskWise now finishes all heavy startup work on the splash screen before What's New appears, so Continue should feel instant.",
            bullets: [
                "Saved scans, AI provider checks, and suggestions preload with visible progress steps",
                "The main window stays empty until you dismiss What's New — no tabs building behind the overlay",
                "Skip loading a saved scan after 3 seconds and finish opening in the background",
            ]
        ),
    ]

    private static let v054Pages: [WhatsNewPage] = [
        WhatsNewPage(
            id: "scan-tabs",
            icon: "rectangle.split.3x1",
            title: "Per-drive tabs for scan workflow",
            message: "Each drive now has its own Scanning, Results, Recommendations, and AI Analysis tabs so long scans no longer block the rest of the app.",
            bullets: [
                "Scanning tab shows progress and a copyable tail -f command for live logs in Terminal",
                "Results tab opens automatically when a scan finishes",
                "Recommendations and AI Analysis live in dedicated tabs instead of one crowded overview",
            ]
        ),
        WhatsNewPage(
            id: "scan-performance",
            icon: "arrow.triangle.2.circlepath",
            title: "Faster, more responsive scans",
            message: "Scan progress is polled periodically instead of streaming into the UI, which keeps DiskWise responsive during large volume scans.",
            bullets: [
                "Unchanged folders are skipped on rescans using cached folder timestamps in SQLite",
                "Incremental cache reuses prior index data when a directory has not changed",
                "Mid-scan database refreshes removed to eliminate beach-ball stalls",
            ]
        ),
        WhatsNewPage(
            id: "menu-bar",
            icon: "heart.text.square",
            title: "Clearer menu bar system status",
            message: "The health score popover now lists real application names for top CPU and memory processes.",
            bullets: [
                "Names resolve from the app bundle, executable path, and process metadata",
                "Long names truncate with a leading … so the recognizable tail stays visible",
                "Hover a row to see the full process name",
            ]
        ),
    ]

    private static let v030Pages: [WhatsNewPage] = [
        WhatsNewPage(
            id: "welcome",
            icon: "sparkles",
            title: "Welcome to DiskWise 0.3",
            message: "A major update: DiskWise is now a three-phase storage consultant — not just a scan-and-duplicate pipeline.",
            bullets: [
                "Phase 1: Identify disk usage on APFS volumes",
                "Phase 2: Analyze into safe, review-first, and personal buckets",
                "Phase 3: Take action via individual Maintenance tools",
            ]
        ),
        WhatsNewPage(
            id: "duplicates",
            icon: "doc.on.doc",
            title: "Duplicates on demand",
            message: "Duplicate detection now lives in the Duplicates tab only — run it when you need it.",
            bullets: [
                "Main scan focuses on usage identification and action planning",
                "Open Duplicates → Find Duplicates to fingerprint files",
            ]
        ),
        WhatsNewPage(
            id: "maintenance",
            icon: "wrench.and.screwdriver.fill",
            title: "Individual maintenance actions",
            message: "Every cleanup category has its own menu — App Caches, node_modules, APFS Snapshots, and more.",
            bullets: [
                "Thin APFS snapshots when deletions don't free space",
                "Rebuild your storage index after updating for best results",
            ]
        ),
    ]

    private static let v024Pages: [WhatsNewPage] = [
        WhatsNewPage(
            id: "welcome",
            icon: "hare.fill",
            title: "Welcome to DiskWise 0.2.4",
            message: "Startup and What's New should feel snappier after updating.",
            bullets: [
                "Heavy storage analysis runs in the background after overlays close",
                "Update checks wait until the main window is ready",
                "Continue after What's New should no longer beach-ball the app",
            ]
        ),
    ]

    private static let v023Pages: [WhatsNewPage] = [
        WhatsNewPage(
            id: "welcome",
            icon: "internaldrive.fill",
            title: "Welcome to DiskWise 0.2.3",
            message: "Full-volume scans now map much more of your used storage.",
            bullets: [
                "Scans the Data volume where your files actually live (not the sealed system snapshot)",
                "Uses disk usage totals for protected folders File Manager cannot list",
                "Rescan Macintosh HD after updating — old scan data will not refresh automatically",
            ]
        ),
    ]

    private static let v022Pages: [WhatsNewPage] = [
        WhatsNewPage(
            id: "welcome",
            icon: "sparkles",
            title: "Welcome to DiskWise 0.2.2",
            message: "DiskWise now checks for updates when you open the app.",
            bullets: [
                "If a newer version is available, you'll be prompted to install",
                "Manual check remains in the menu: Check for Updates…",
            ]
        ),
    ]

    private static let v021Pages: [WhatsNewPage] = [
        WhatsNewPage(
            id: "welcome",
            icon: "sparkles",
            title: "Welcome to DiskWise 0.2.1",
            message: "Scans now account for app bundles and show how much space is still unmapped.",
            bullets: []
        ),
        WhatsNewPage(
            id: "apps",
            icon: "app.fill",
            title: "Applications are counted correctly",
            message: "Apps like Xcode and Chrome are sized as a whole instead of showing as empty folders.",
            bullets: [
                "Rescan your drive to refresh totals",
                "Applications should appear as a major category",
            ]
        ),
        WhatsNewPage(
            id: "gap",
            icon: "questionmark.folder",
            title: "See unmapped storage",
            message: "If indexed space is still below Used, DiskWise shows a Not Indexed card with next steps.",
            bullets: []
        ),
    ]

    private static let v020Pages: [WhatsNewPage] = [
        WhatsNewPage(
            id: "welcome",
            icon: "sparkles",
            title: "Welcome to DiskWise 0.2.0",
            message: "Faster scans, smoother permissions, and clearer control over how DiskWise indexes your drives.",
            bullets: []
        ),
        WhatsNewPage(
            id: "scan-mode",
            icon: "hare.fill",
            title: "Fast and Deep scan modes",
            message: "Choose how Step 1 indexes your drive in Settings.",
            bullets: [
                "Fast — sizes node_modules, vendor, .venv, and similar folders in one step",
                "Deep — indexes every file for maximum detail",
                "Balanced preset uses Fast scan by default",
            ]
        ),
        WhatsNewPage(
            id: "fda",
            icon: "lock.shield",
            title: "Easier Full Disk Access",
            message: "DiskWise now appears automatically in the Full Disk Access list — just enable the toggle.",
            bullets: [
                "No more manual + button for installed releases",
                "Scanning resumes automatically after you grant access",
            ]
        ),
    ]

    private static let v018Pages: [WhatsNewPage] = [
        WhatsNewPage(
            id: "welcome",
            icon: "sparkles",
            title: "Welcome to DiskWise 0.1.8",
            message: "Scanning is easier from the sidebar — full drive or just one folder.",
            bullets: []
        ),
        WhatsNewPage(
            id: "scan",
            icon: "arrow.triangle.2.circlepath",
            title: "Scan from the sidebar",
            message: "Select a drive to reveal a scan button on its row, or use Actions.",
            bullets: [
                "Shows Scan until the drive is indexed, then Rescan",
                "Scan Folder… picks a subtree without re-indexing the whole volume",
                "Right-click any drive for Scan, Scan Folder, or Eject",
            ]
        ),
    ]

    private static let v017Pages: [WhatsNewPage] = [
        WhatsNewPage(
            id: "welcome",
            icon: "sparkles",
            title: "Welcome to DiskWise 0.1.7",
            message: "External drives are easier to manage from the sidebar.",
            bullets: []
        ),
        WhatsNewPage(
            id: "eject",
            icon: "eject.fill",
            title: "Eject external drives",
            message: "Each external volume in the sidebar now has a visible eject button.",
            bullets: [
                "Click the eject icon on the drive row",
                "Disabled while that drive is scanning",
                "Right-click and Actions → Eject still work too",
            ]
        ),
    ]

    private static let v016Pages: [WhatsNewPage] = [
        WhatsNewPage(
            id: "welcome",
            icon: "sparkles",
            title: "Welcome to DiskWise 0.1.6",
            message: "First launch after updating is faster and clearer — you’ll see what DiskWise is doing instead of a long bouncing Dock icon.",
            bullets: []
        ),
        WhatsNewPage(
            id: "startup",
            icon: "arrow.triangle.2.circlepath",
            title: "Startup splash after updates",
            message: "DiskWise now shows a setup screen on launch with live progress:",
            bullets: [
                "Database updates and saved scan loading run in the background",
                "Step-by-step checklist: database, drives, scans, permissions",
                "Recommendations load after the main window is ready",
            ]
        ),
    ]

    private static let v015Pages: [WhatsNewPage] = [
        WhatsNewPage(
            id: "welcome",
            icon: "sparkles",
            title: "Welcome to DiskWise 0.1.5",
            message: "This update adds a detailed About panel, sidebar Settings, and serves Sparkle updates through the registry API.",
            bullets: []
        ),
        WhatsNewPage(
            id: "about",
            icon: "info.circle",
            title: "About DiskWise",
            message: "DiskWise → About DiskWise shows release notes and your current configuration.",
            bullets: [
                "What’s new for this version",
                "Scan limits, presets, and update feed details",
            ]
        ),
        WhatsNewPage(
            id: "settings",
            icon: "gearshape",
            title: "Settings in the sidebar",
            message: "Open Settings from the Actions section below View Duplicates, or use ⌘,.",
            bullets: []
        ),
    ]

    private static let v014Pages: [WhatsNewPage] = [
        WhatsNewPage(
            id: "welcome",
            icon: "sparkles",
            title: "Welcome to DiskWise 0.1.4",
            message: "This update adds scan performance controls, a What’s New splash, a refreshed app icon, and website download fixes.",
            bullets: []
        ),
        WhatsNewPage(
            id: "settings",
            icon: "slider.horizontal.3",
            title: "Scan performance settings",
            message: "Choose how many files DiskWise checks after indexing.",
            bullets: [
                "Duplicate detection limit — largest files compared in Step 2",
                "Analysis limit — largest files sampled for recommendations in Step 3",
                "Open DiskWise → Settings (⌘,) any time to adjust presets",
            ]
        ),
        WhatsNewPage(
            id: "splash",
            icon: "rectangle.on.rectangle.angled",
            title: "What’s New splash",
            message: "After updating, a release-notes splash summarizes improvements before you continue.",
            bullets: [
                "Shown once per version",
                "Jump to Settings directly from the splash when relevant",
            ]
        ),
        WhatsNewPage(
            id: "icon",
            icon: "app.dashed",
            title: "Refreshed app icon",
            message: "The Dock icon now matches the website artwork — no more dark rounded box behind the logo.",
            bullets: []
        ),
        WhatsNewPage(
            id: "overview",
            icon: "chart.pie",
            title: "Smarter post-scan navigation",
            message: "When a scan finishes with no duplicates, DiskWise stays on Overview instead of opening Duplicates.",
            bullets: []
        ),
    ]

    private static let v013Pages: [WhatsNewPage] = [
        WhatsNewPage(
            id: "welcome",
            icon: "sparkles",
            title: "Welcome to DiskWise 0.1.3",
            message: "This update focuses on safer cleanup suggestions, better duplicate discovery, and more control over large-drive performance.",
            bullets: []
        ),
        WhatsNewPage(
            id: "cleanup",
            icon: "shield.checkered",
            title: "Safer cleanup recommendations",
            message: "Recommendations are more accurate and cautious:",
            bullets: [
                "Archive Old Videos now lists real video files only",
                "Installer DMGs exclude system folders like Preboot and MobileAsset",
                "Move to Trash reports failures clearly instead of silent no-ops",
            ]
        ),
        WhatsNewPage(
            id: "duplicates",
            icon: "doc.on.doc",
            title: "Easier duplicate cleanup",
            message: "Duplicate detection runs in the background while you review Overview.",
            bullets: [
                "Clearer progress for each duplicate step",
                "Duplicates opens only when duplicate groups are found",
                "Bulk Move to Trash for duplicate groups",
            ]
        ),
        WhatsNewPage(
            id: "support",
            icon: "list.bullet.rectangle",
            title: "Activity Log for support",
            message: "Help → Activity Log lets you copy or save recent scan and cleanup events when reporting issues.",
            bullets: []
        ),
    ]

    private static let v012Pages: [WhatsNewPage] = [
        WhatsNewPage(
            id: "sparkle",
            icon: "arrow.down.circle",
            title: "Welcome to DiskWise 0.1.2",
            message: "DiskWise can now check for updates automatically and install new versions from inside the app.",
            bullets: [
                "Use DiskWise → Check for Updates",
                "Refreshed app icon and website assets",
            ]
        ),
    ]

    private static func genericPages(version: String) -> [WhatsNewPage] {
        [
            WhatsNewPage(
                id: "generic",
                icon: "sparkles",
                title: "What’s new in DiskWise \(version)",
                message: "Thanks for updating. Review your drives again to refresh recommendations with the latest improvements.",
                bullets: []
            ),
        ]
    }
}

struct ReleaseNotesSplashOverlay: View {
    let version: String
    var onOpenSettings: (() -> Void)?
    var onContinue: () -> Void

    private var pages: [WhatsNewPage] {
        WhatsNewContent.pages(for: version)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.48)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                splashHeader

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        ForEach(pages) { page in
                            releaseSection(page)
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.vertical, 20)
                }

                Divider()

                HStack {
                    if pages.contains(where: { $0.id == "settings" }), let onOpenSettings {
                        Button("Open Settings") {
                            onContinue()
                            onOpenSettings()
                        }
                        .buttonStyle(.bordered)
                    }

                    Spacer()

                    Button("Continue") {
                        onContinue()
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                }
                .padding(20)
            }
            .frame(maxWidth: 600, maxHeight: 620)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.3), radius: 32, y: 16)
            .padding(32)
        }
        .transition(.opacity)
        .zIndex(101)
    }

    private var splashHeader: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: .black.opacity(0.2), radius: 8, y: 4)

            Text("What’s New")
                .font(.title.bold())

            Text("DiskWise \(version)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 28)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private func releaseSection(_ page: WhatsNewPage) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(page.title, systemImage: page.icon)
                .font(.headline)
                .labelStyle(.titleAndIcon)

            if !page.message.isEmpty {
                Text(page.message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !page.bullets.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(page.bullets, id: \.self) { bullet in
                        HStack(alignment: .top, spacing: 8) {
                            Text("•")
                                .foregroundStyle(.secondary)
                            Text(bullet)
                                .font(.subheadline)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
