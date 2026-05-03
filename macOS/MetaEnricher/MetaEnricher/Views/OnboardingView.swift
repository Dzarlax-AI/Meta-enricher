import SwiftUI

struct OnboardingView: View {
    @Environment(AppState.self) private var appState
    @State private var step: OnboardingStep = .welcome

    enum OnboardingStep {
        case welcome, metaEnricher, custom, done
    }

    var body: some View {
        ZStack {
            switch step {
            case .welcome:   welcomeStep
            case .metaEnricher: metaEnricherStep
            case .custom:    customStep
            case .done:      doneStep
            }
        }
        .frame(width: 640, height: 480)
        .animation(.easeInOut(duration: 0.25), value: step)
    }

    // MARK: - Welcome

    private var welcomeStep: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 20) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 100, height: 100)
                    .shadow(color: .black.opacity(0.18), radius: 24, y: 8)

                VStack(spacing: 8) {
                    Text("MetaEnricher")
                        .font(.largeTitle.bold())

                    Text("AI-powered metadata for your photo library.\nEnrich, organize, and publish — from one place.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 400)
                }

                VStack(alignment: .leading, spacing: 10) {
                    OnboardingFeatureRow(icon: "sparkles",        text: "AI fills in title, description, keywords and location")
                    OnboardingFeatureRow(icon: "tag.fill",        text: "Writes IPTC, XMP and legacy EXIF tags via exiftool")
                    OnboardingFeatureRow(icon: "folder.fill",     text: "Organized session library — always know where your photos are")
                }
                .padding(.top, 4)
            }

            Spacer(minLength: 12)

            Divider()

            VStack(spacing: 12) {
                Text("How do you want to organize your photos?")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.top, 18)

                HStack(spacing: 14) {
                    SchemaOptionCard(
                        icon: "folder.badge.gearshape",
                        title: "MetaEnricher schema",
                        subtitle: "Structured folder layout — RAW, JPEG, Edited export",
                        recommended: true
                    ) {
                        withAnimation { step = .metaEnricher }
                    }

                    SchemaOptionCard(
                        icon: "folder.badge.person.crop",
                        title: "My own structure",
                        subtitle: "Already have a library — just point to your picks folder",
                        recommended: false
                    ) {
                        withAnimation { step = .custom }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 22)
            }
        }
    }

    // MARK: - MetaEnricher Schema Step

    @State private var rootPath = ""

    private var metaEnricherStep: some View {
        VStack(spacing: 0) {
            stepHeader(title: "MetaEnricher folder structure", icon: "folder.badge.gearshape")

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Your library will be organized like this:")
                        .foregroundStyle(.secondary)

                    SchemaPreview()

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Workflow")
                            .font(.headline)
                        VStack(alignment: .leading, spacing: 8) {
                            WorkflowStep(n: "1", text: "Import from SD card → files go to **RAW/** and **JPEG/**")
                            WorkflowStep(n: "2", text: "Edit your picks in Lightroom or any editor")
                            WorkflowStep(n: "3", text: "Export picks to **Edited export/** folder")
                            WorkflowStep(n: "4", text: "Open MetaEnricher → enrich metadata with AI → publish")
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Choose your library root folder")
                            .font(.headline)
                        HStack {
                            Text(rootPath.isEmpty ? "Not chosen" : rootPath)
                                .foregroundStyle(rootPath.isEmpty ? .secondary : .primary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Button("Browse…") { browseRoot() }
                                .buttonStyle(.bordered)
                        }
                        .padding(10)
                        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding(24)
            }

            Divider()

            HStack {
                Button("Back") { withAnimation { step = .welcome } }
                    .buttonStyle(.bordered)
                Spacer()
                Button("Get Started") {
                    finishMetaEnricher()
                }
                .buttonStyle(.borderedProminent)
                .disabled(rootPath.isEmpty)
            }
            .padding(20)
        }
        .onAppear {
            if rootPath.isEmpty, let existing = appState.cameraRoot?.path {
                rootPath = existing
            }
        }
    }

    // MARK: - Custom Schema Step

    @State private var libraryPath  = ""
    @State private var picksFolderName = "Edited export"

    private let commonPicksNames = ["Edited export", "Export", "Picks", "Finals", "Selected", "Published", "_picks"]

    private var customStep: some View {
        VStack(spacing: 0) {
            stepHeader(title: "Your existing library", icon: "folder.badge.person.crop")

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("We'll scan your library and look for a **subfolder with your picks** inside each session folder — whatever your folder structure is.")
                        .foregroundStyle(.secondary)

                    folderRow(
                        label: "Photo library root",
                        detail: "The top-level folder containing all your sessions",
                        path: $libraryPath,
                        browse: browseLibrary
                    )

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Picks subfolder name")
                            .font(.headline)
                        Text("Name of the subfolder inside each session that contains your picks. Works at any nesting level.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        TextField("e.g. Edited export, Export, Picks…", text: $picksFolderName)
                            .textFieldStyle(.roundedBorder)

                        // Quick suggestions
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(commonPicksNames, id: \.self) { name in
                                    Button(name) { picksFolderName = name }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                        .tint(picksFolderName == name ? .accentColor : nil)
                                }
                            }
                        }

                        // Live preview
                        if !libraryPath.isEmpty {
                            CustomSchemaPreview(rootPath: libraryPath, picksFolderName: picksFolderName)
                        }
                    }

                    HStack(spacing: 8) {
                        Image(systemName: "info.circle")
                            .foregroundStyle(.secondary)
                        Text("No picks subfolder? Leave blank — photos with rating ≥ 1 ★ will be treated as picks.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(24)
            }

            Divider()

            HStack {
                Button("Back") { withAnimation { step = .welcome } }
                    .buttonStyle(.bordered)
                Spacer()
                Button("Get Started") {
                    finishCustom()
                }
                .buttonStyle(.borderedProminent)
                .disabled(libraryPath.isEmpty)
            }
            .padding(20)
        }
    }

    // MARK: - Done Step

    private var doneStep: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 16) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(.green)
                    .symbolRenderingMode(.hierarchical)

                VStack(spacing: 8) {
                    Text("All set.")
                        .font(.largeTitle.bold())

                    Text("Your library is ready. MetaEnricher will scan your sessions\nand load them in the sidebar.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 380)
                }
            }

            Spacer()

            Button("Open Library") {
                completeOnboarding()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.bottom, 44)
        }
    }

    // MARK: - Helpers

    private func stepHeader(title: String, icon: String) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(Color.appAmber)
            Text(title)
                .font(.title2)
                .fontWeight(.semibold)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding([.horizontal, .top], 24)
        .padding(.bottom, 16)
    }

    private func folderRow(label: String, detail: String, path: Binding<String>, browse: @escaping () -> Void, optional: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label).font(.headline)
                if optional {
                    Text("optional").font(.caption).foregroundStyle(.secondary)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.fill.tertiary, in: Capsule())
                }
            }
            Text(detail).font(.caption).foregroundStyle(.secondary)
            HStack {
                Text(path.wrappedValue.isEmpty ? "Not chosen" : path.wrappedValue)
                    .foregroundStyle(path.wrappedValue.isEmpty ? .secondary : .primary)
                    .lineLimit(1).truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("Browse…") { browse() }.buttonStyle(.bordered)
            }
            .padding(10)
            .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func browseRoot() {
        if let url = openPanel(message: "Choose your photo library root folder") {
            rootPath = url.path
        }
    }

    private func browseLibrary() {
        if let url = openPanel(message: "Choose your photo library root folder") {
            libraryPath = url.path
            // Auto-detect picks folder name from existing structure
            let detected = ImportService.shared.detectPicksFolderName(in: url)
            if let detected { picksFolderName = detected }
        }
    }

    private func openPanel(message: String) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = message
        panel.prompt = "Select"
        return panel.runModal() == .OK ? panel.url : nil
    }

    private func finishMetaEnricher() {
        appState.librarySchema = .metaEnricher
        appState.cameraRoot = URL(filePath: rootPath)
        UserDefaults.standard.set(LibrarySchema.metaEnricher.rawValue, forKey: "librarySchema")
        withAnimation { step = .done }
    }

    private func finishCustom() {
        appState.librarySchema = .custom
        appState.cameraRoot = URL(filePath: libraryPath)
        appState.picksFolderName = picksFolderName.trimmingCharacters(in: .whitespaces)
        UserDefaults.standard.set(LibrarySchema.custom.rawValue, forKey: "librarySchema")
        UserDefaults.standard.set(appState.picksFolderName, forKey: "picksFolderName")
        withAnimation { step = .done }
    }

    private func completeOnboarding() {
        appState.hasCompletedOnboarding = true
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
    }
}

// MARK: - Onboarding Feature Row

private struct OnboardingFeatureRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.appAmber)
                .frame(width: 28)

            Text(text)
                .font(.callout)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Schema Option Card

private struct SchemaOptionCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let recommended: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    Image(systemName: icon)
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(Color.appAmber)

                    Spacer()

                    if recommended {
                        Text("Recommended")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color.appAmber)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.appAmber.opacity(0.12), in: Capsule())
                    }
                }
                .padding(.bottom, 14)

                Text(title)
                    .font(.headline)
                    .multilineTextAlignment(.leading)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)

                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
            .background(.fill.tertiary)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        isHovered ? Color.appAmber : Color.appAmber.opacity(0),
                        lineWidth: 1.5
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.12), value: isHovered)
    }
}

// MARK: - Schema Preview

private struct SchemaPreview: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                FolderRow(name: "📁 ~/Photos",                depth: 0, bold: true)
                FolderRow(name: "📁 2026",                    depth: 1)
                FolderRow(name: "📁 2026-03-01 Belgrade",     depth: 2)
                FolderRow(name: "📁 RAW",                     depth: 3, color: .secondary)
                FolderRow(name: "📁 JPEG",                    depth: 3, color: .orange)
                FolderRow(name: "📁 Edited export",           depth: 3, color: Color.appAmber, note: "← picks")
                FolderRow(name: "📁 2026-03-07",              depth: 2)
                FolderRow(name: "📁 RAW",                     depth: 3, color: .secondary)
                FolderRow(name: "📁 JPEG",                    depth: 3, color: .orange)
                FolderRow(name: "📁 Edited export",           depth: 3, color: Color.appAmber, note: "← picks")
            }
            .padding(12)
            .background(.fill.secondary, in: RoundedRectangle(cornerRadius: 8))
            .font(.system(.caption, design: .monospaced))

            VStack(alignment: .leading, spacing: 6) {
                LegendRow(color: .secondary, label: "RAW/",
                    detail: "Original RAW files from camera — never touched")
                LegendRow(color: .orange, label: "JPEG/",
                    detail: "JPEG originals — backup copies straight from card")
                LegendRow(color: Color.appAmber, label: "Edited export/",
                    detail: "Your picks after editing — MetaEnricher enriches these, you publish from here")
            }
        }
    }
}

private struct LegendRow: View {
    let color: Color
    let label: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.caption.weight(.semibold).monospaced())
                .foregroundStyle(color)
                .frame(width: 110, alignment: .leading)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct FolderRow: View {
    let name: String
    let depth: Int
    var bold = false
    var color: Color = .primary
    var note: String? = nil

    var body: some View {
        HStack(spacing: 4) {
            Text(String(repeating: "  ", count: depth))
            Text(name)
                .fontWeight(bold ? .semibold : .regular)
                .foregroundStyle(color)
            if let note {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Workflow Step

private struct WorkflowStep: View {
    let n: String
    let text: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(n)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(Color.appAmber, in: Circle())
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Custom Schema Preview

private struct CustomSchemaPreview: View {
    let rootPath: String
    let picksFolderName: String

    private var exampleStructure: [(String, Bool)] {
        let name = picksFolderName.isEmpty ? "…" : picksFolderName
        return [
            ("📁 \(URL(filePath: rootPath).lastPathComponent)", false),
            ("  📁 2026", false),
            ("    📁 2026-03-01", false),
            ("      📁 \(name)", true),
            ("    📁 2026-03-07 Berlin", false),
            ("      📁 \(name)", true),
            ("  📁 2025/03", false),
            ("    📁 \(name)", true),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Preview — picks found at any nesting level:")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.bottom, 2)

            ForEach(exampleStructure, id: \.0) { (line, isPicks) in
                Text(line)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(isPicks ? Color.appAmber : Color.primary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 8))
    }
}
