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
