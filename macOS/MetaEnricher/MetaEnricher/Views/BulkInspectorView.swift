import SwiftUI

struct BulkInspectorView: View {
    @Environment(AppState.self) private var appState
    let onEnrich: (Set<EnrichField>) async -> Void

    @State private var enrichFields: Set<EnrichField> = Set(EnrichField.allCases)
    @State private var isEnriching = false

    private var selectedCount: Int { appState.selectedPhotoIDs.count }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                Divider()
                enrichmentSection
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.appAmber.opacity(0.12))
                    .frame(width: 44, height: 44)
                Image(systemName: "photo.stack.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Color.appAmber)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("\(selectedCount) photos selected")
                    .font(.headline)
                Text("Bulk operations")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                appState.selectedPhotoIDs = []
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .help("Deselect all")
        }
        .padding(16)
    }

    // MARK: - Enrichment Section

    private var enrichmentSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("AI Enrichment", icon: "sparkles")

            VStack(spacing: 0) {
                ForEach(EnrichField.allCases, id: \.self) { field in
                    fieldToggleRow(field)
                    if field != EnrichField.allCases.last {
                        Divider().padding(.leading, 40)
                    }
                }

                Divider().padding(.leading, 0)

                // Select all / none row
                HStack {
                    Button("Select All") { enrichFields = Set(EnrichField.allCases) }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.appAmber)
                        .font(.caption)
                    Spacer()
                    Button("None") { enrichFields = [] }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.appAmber)
                        .font(.caption)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .background(.fill.quinary, in: RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 12)
            .padding(.bottom, 12)

            // Enrich button
            VStack(spacing: 6) {
                Button {
                    isEnriching = true
                    Task {
                        await onEnrich(enrichFields)
                        isEnriching = false
                    }
                } label: {
                    if isEnriching {
                        HStack(spacing: 6) {
                            ProgressView().scaleEffect(0.8)
                            Text("Enriching \(appState.enrichingIDs.count) photo\(appState.enrichingIDs.count == 1 ? "" : "s")…")
                        }
                        .frame(maxWidth: .infinity)
                    } else {
                        Label(
                            enrichFields.count == EnrichField.allCases.count
                                ? "Enrich All Fields"
                                : "Enrich \(enrichFields.count) field\(enrichFields.count == 1 ? "" : "s")",
                            systemImage: "sparkles"
                        )
                        .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(enrichFields.isEmpty || isEnriching)
                .onChange(of: appState.enrichingIDs.isEmpty) { _, isEmpty in
                    if isEmpty { isEnriching = false }
                }

                Text("\(selectedCount) photos will be processed sequentially")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 16)
        }
    }

    // MARK: - Field Toggle Row

    private func fieldToggleRow(_ field: EnrichField) -> some View {
        let isSelected = enrichFields.contains(field)
        return HStack(spacing: 10) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 16))
                .foregroundStyle(isSelected ? Color.appAmber : Color.secondary.opacity(0.4))
                .frame(width: 20)

            Text(field.displayName)
                .font(.callout)
                .foregroundStyle(isSelected ? .primary : .secondary)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.1)) {
                if isSelected { enrichFields.remove(field) } else { enrichFields.insert(field) }
            }
        }
    }

    // MARK: - Section Header

    private func sectionHeader(_ title: String, icon: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Color.appAmber)
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(0.6)
        }
        .padding(.horizontal, 12)
        .padding(.top, 16)
        .padding(.bottom, 6)
    }
}
