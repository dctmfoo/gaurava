import SwiftUI

struct ShareJourneyEntryCard: View {
    let snapshot: DashboardSnapshot
    let openComposer: () -> Void

    var body: some View {
        Button(action: openComposer) {
            HealthCard(tint: AppTheme.primary, cornerRadius: 28, padding: 18) {
                HStack(alignment: .center, spacing: 14) {
                    Image(systemName: AppSymbol.Action.share)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(AppTheme.primary)
                        .frame(width: 48, height: 48)
                        .background(AppTheme.primary.opacity(0.14), in: Circle())

                    VStack(alignment: .leading, spacing: 5) {
                        Text(appLocalizedValue("Share Journey"))
                            .font(AppFont.cardTitle)
                            .foregroundStyle(AppTheme.ink)
                        Text(detailText)
                            .font(AppFont.body)
                            .foregroundStyle(AppTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 8)

                    Image(systemName: AppSymbol.Action.disclosure)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(AppTheme.muted)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(snapshot.weights.isEmpty)
        .opacity(snapshot.weights.isEmpty ? 0.72 : 1)
        .accessibilityIdentifier("share-journey-entry")
        .accessibilityHint(snapshot.weights.isEmpty ? appLocalizedValue("Add a weight entry before creating a share card.") : appLocalizedValue("Opens journey card options."))
    }

    private var detailText: String {
        if snapshot.weights.isEmpty {
            return appLocalizedValue("Add a weight entry to create a card.")
        }
        return appLocalizedValue("\(snapshot.weights.count) weights - \(ShareCardSnapshot(dashboard: snapshot).weekCount) weeks")
    }
}

struct ShareJourneyComposerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let snapshot: DashboardSnapshot

    @AppStorage("shareCardTemplate") private var templateRawValue = ShareCardTemplate.story.rawValue
    @AppStorage("shareCardColorScheme") private var colorSchemeRawValue = ShareCardColorScheme.light.rawValue
    @AppStorage("shareCardPrivacy") private var privacyRawValue = ShareCardPrivacyMode.exact.rawValue
    @AppStorage("shareCardDates") private var dateVisibilityRawValue = ShareCardDateVisibility.show.rawValue
    @AppStorage("shareCardWeightUnit") private var unitRawValue = ShareCardWeightUnit.kg.rawValue

    @State private var renderedAsset: ShareCardRenderedAsset?
    @State private var isRendering = false
    @State private var isSaving = false
    @State private var statusMessage: ShareCardStatusMessage?

    var body: some View {
        NavigationStack {
            Group {
                if snapshot.weights.isEmpty {
                    ContentUnavailableView(
                        appLocalizedValue("No Weight Entries"),
                        systemImage: AppSymbol.Health.weight,
                        description: Text(appLocalizedValue("Add a weight checkpoint before creating a journey card."))
                    )
                    .foregroundStyle(AppTheme.muted)
                    .padding(20)
                } else {
                    GeometryReader { proxy in
                        let previewHeight = ShareComposerFixedStudio.previewHeight(for: proxy.size.height)

                        ViewThatFits(in: .vertical) {
                            ShareComposerFixedStudio(
                                renderedAsset: renderedAsset,
                                isRendering: isRendering,
                                message: statusMessage,
                                previewHeight: previewHeight,
                                template: templateBinding,
                                privacy: privacyBinding,
                                dates: dateVisibilityBinding,
                                unit: unitBinding,
                                colorScheme: colorSchemeBinding,
                                isSaving: isSaving,
                                saveToPhotos: saveToPhotos
                            )
                            .padding(20)

                            ScrollView {
                                ShareComposerFixedStudio(
                                    renderedAsset: renderedAsset,
                                    isRendering: isRendering,
                                    message: statusMessage,
                                    previewHeight: previewHeight,
                                    template: templateBinding,
                                    privacy: privacyBinding,
                                    dates: dateVisibilityBinding,
                                    unit: unitBinding,
                                    colorScheme: colorSchemeBinding,
                                    isSaving: isSaving,
                                    saveToPhotos: saveToPhotos
                                )
                                .padding(20)
                                .padding(.bottom, 24)
                            }
                        }
                    }
                }
            }
            .background(AppBackground())
            .navigationTitle(appLocalizedValue("Share Journey"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(appLocalizedValue("Done"), action: dismiss.callAsFunction)
                }
            }
        }
        .task(id: renderKey) {
            await renderCard()
        }
        .onAppear(perform: seedDefaultsIfNeeded)
    }

    private var configuration: ShareCardConfiguration {
        ShareCardConfiguration(
            template: selectedTemplate,
            colorScheme: selectedColorScheme,
            privacyMode: selectedPrivacyMode,
            dateVisibility: selectedDateVisibility,
            unit: selectedUnit
        )
    }

    private var selectedTemplate: ShareCardTemplate {
        ShareCardTemplate(rawValue: templateRawValue) ?? .story
    }

    private var selectedColorScheme: ShareCardColorScheme {
        ShareCardColorScheme(rawValue: colorSchemeRawValue) ?? ShareCardColorScheme.defaultValue(from: snapshot.preferences.theme)
    }

    private var selectedPrivacyMode: ShareCardPrivacyMode {
        ShareCardPrivacyMode(rawValue: privacyRawValue) ?? .exact
    }

    private var selectedDateVisibility: ShareCardDateVisibility {
        ShareCardDateVisibility(rawValue: dateVisibilityRawValue) ?? .show
    }

    private var selectedUnit: ShareCardWeightUnit {
        ShareCardWeightUnit(rawValue: unitRawValue) ?? ShareCardWeightUnit.defaultValue(from: snapshot.preferences.weightUnit)
    }

    private var renderKey: ShareCardRenderKey {
        ShareCardRenderKey(configuration: configuration, fingerprint: ShareCardSnapshot(dashboard: snapshot).fingerprint)
    }

    private var templateBinding: Binding<ShareCardTemplate> {
        Binding(
            get: { selectedTemplate },
            set: { templateRawValue = $0.rawValue }
        )
    }

    private var colorSchemeBinding: Binding<ShareCardColorScheme> {
        Binding(
            get: { selectedColorScheme },
            set: { colorSchemeRawValue = $0.rawValue }
        )
    }

    private var privacyBinding: Binding<ShareCardPrivacyMode> {
        Binding(
            get: { selectedPrivacyMode },
            set: { privacyRawValue = $0.rawValue }
        )
    }

    private var dateVisibilityBinding: Binding<ShareCardDateVisibility> {
        Binding(
            get: { selectedDateVisibility },
            set: { dateVisibilityRawValue = $0.rawValue }
        )
    }

    private var unitBinding: Binding<ShareCardWeightUnit> {
        Binding(
            get: { selectedUnit },
            set: { unitRawValue = $0.rawValue }
        )
    }

    private func seedDefaultsIfNeeded() {
        if ShareCardTemplate(rawValue: templateRawValue) == nil {
            templateRawValue = ShareCardTemplate.story.rawValue
        }
        if ShareCardColorScheme(rawValue: colorSchemeRawValue) == nil {
            colorSchemeRawValue = ShareCardColorScheme.defaultValue(from: snapshot.preferences.theme).rawValue
        }
        if ShareCardWeightUnit(rawValue: unitRawValue) == nil {
            unitRawValue = ShareCardWeightUnit.defaultValue(from: snapshot.preferences.weightUnit).rawValue
        }
    }

    @MainActor
    private func renderCard() async {
        guard !snapshot.weights.isEmpty else {
            renderedAsset = nil
            return
        }

        isRendering = true
        statusMessage = nil

        do {
            renderedAsset = try ShareCardRenderer.render(dashboard: snapshot, configuration: configuration)
        } catch {
            renderedAsset = nil
            statusMessage = ShareCardStatusMessage(text: error.localizedDescription, isError: true)
        }

        isRendering = false
    }

    private func saveToPhotos() {
        Task {
            await savePreparedCardToPhotos()
        }
    }

    @MainActor
    private func savePreparedCardToPhotos() async {
        let asset: ShareCardRenderedAsset
        if let renderedAsset {
            asset = renderedAsset
        } else {
            await renderCard()
            guard let renderedAsset else { return }
            asset = renderedAsset
        }

        isSaving = true
        statusMessage = nil

        do {
            try await ShareCardPhotoLibrarySaver.savePNGData(asset.pngData)
            statusMessage = ShareCardStatusMessage(text: appLocalizedValue("Saved to Photos."), isError: false)
        } catch {
            statusMessage = ShareCardStatusMessage(text: error.localizedDescription, isError: true)
        }

        isSaving = false
    }
}

private struct ShareComposerFixedStudio: View {
    let renderedAsset: ShareCardRenderedAsset?
    let isRendering: Bool
    let message: ShareCardStatusMessage?
    let previewHeight: CGFloat
    @Binding var template: ShareCardTemplate
    @Binding var privacy: ShareCardPrivacyMode
    @Binding var dates: ShareCardDateVisibility
    @Binding var unit: ShareCardWeightUnit
    @Binding var colorScheme: ShareCardColorScheme
    let isSaving: Bool
    let saveToPhotos: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ShareCardPreviewPanel(
                renderedAsset: renderedAsset,
                isRendering: isRendering,
                message: message,
                previewHeight: previewHeight
            )

            ShareTemplatePicker(selection: $template)

            ShareCardOptionsPanel(
                privacy: $privacy,
                dates: $dates,
                unit: $unit,
                colorScheme: $colorScheme
            )

            ShareExportActions(
                renderedAsset: renderedAsset,
                isRendering: isRendering,
                isSaving: isSaving,
                saveToPhotos: saveToPhotos
            )
        }
    }

    static func previewHeight(for availableHeight: CGFloat) -> CGFloat {
        min(246, max(176, availableHeight - 408))
    }
}

private struct ShareCardPreviewPanel: View {
    let renderedAsset: ShareCardRenderedAsset?
    let isRendering: Bool
    let message: ShareCardStatusMessage?
    let previewHeight: CGFloat

    var body: some View {
        HealthCard(tint: AppTheme.primary, cornerRadius: 28, padding: 14) {
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(AppTheme.cardElevated.opacity(0.72))

                    if let renderedAsset {
                        Image(uiImage: renderedAsset.image)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                            .shadow(color: AppTheme.shadow, radius: 14, x: 0, y: 8)
                            .padding(4)
                    } else {
                        ProgressView()
                            .tint(AppTheme.primary)
                    }

                    if isRendering {
                        ProgressView()
                            .tint(AppTheme.primary)
                            .padding(18)
                            .background(.thinMaterial, in: Circle())
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: previewHeight)

                Text(message?.text ?? " ")
                    .font(AppFont.bodyStrong)
                    .foregroundStyle((message?.isError ?? false) ? AppTheme.rose : AppTheme.success)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                    .frame(maxWidth: .infinity, minHeight: 20, alignment: .leading)
                    .opacity(message == nil ? 0 : 1)
            }
        }
        .accessibilityIdentifier("share-card-preview")
    }
}

private struct ShareTemplatePicker: View {
    @Binding var selection: ShareCardTemplate

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(appLocalizedValue("Card Style"))
                .font(AppFont.bodyStrong)
                .textCase(.uppercase)
                .foregroundStyle(AppTheme.muted)
                .padding(.horizontal, 4)

            HStack(spacing: 8) {
                ForEach(ShareCardTemplate.allCases) { template in
                    Button {
                        selection = template
                    } label: {
                        ShareTemplateOption(template: template, isSelected: selection == template)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("share-card-template-\(template.rawValue)")
                    .accessibilityLabel(template.title)
                    .accessibilityHint(template.subtitle)
                }
            }
        }
    }
}

private struct ShareTemplateOption: View {
    let template: ShareCardTemplate
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 5) {
            Image(systemName: template.systemImage)
                .font(.callout.weight(.bold))
                .foregroundStyle(isSelected ? AppTheme.accentForeground : AppTheme.primary)
                .frame(width: 28, height: 28)
                .background((isSelected ? AppTheme.accentForeground.opacity(0.16) : AppTheme.primary.opacity(0.14)), in: Circle())

            Text(template.title)
                .font(AppFont.micro)
                .foregroundStyle(isSelected ? AppTheme.accentForeground : AppTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.68)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 58)
        .background(isSelected ? AppTheme.primary : AppTheme.cardElevated.opacity(0.86), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(isSelected ? AppTheme.primary : AppTheme.stroke, lineWidth: 1)
        )
    }
}

private struct ShareCardOptionsPanel: View {
    @Binding var privacy: ShareCardPrivacyMode
    @Binding var dates: ShareCardDateVisibility
    @Binding var unit: ShareCardWeightUnit
    @Binding var colorScheme: ShareCardColorScheme
    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(appLocalizedValue("Card Options"))
                .font(AppFont.bodyStrong)
                .textCase(.uppercase)
                .foregroundStyle(AppTheme.muted)
                .padding(.horizontal, 4)

            HealthCard(tint: AppTheme.primary, cornerRadius: 24, padding: 10) {
                LazyVGrid(columns: columns, spacing: 8) {
                    ShareOptionToggleCell(
                        title: appLocalizedValue("Privacy"),
                        value: privacy.title,
                        systemImage: "lock.shield.fill",
                        tint: AppTheme.primary
                    ) {
                        privacy = privacy == .exact ? .percentOnly : .exact
                    }

                    ShareOptionToggleCell(
                        title: appLocalizedValue("Dates"),
                        value: dates.title,
                        systemImage: "calendar",
                        tint: AppTheme.amber
                    ) {
                        dates = dates == .show ? .hide : .show
                    }

                    ShareOptionToggleCell(
                        title: appLocalizedValue("Units"),
                        value: unit.title,
                        systemImage: AppSymbol.Health.weightUnit,
                        tint: AppTheme.weight
                    ) {
                        unit = unit == .kg ? .lb : .kg
                    }

                    ShareOptionToggleCell(
                        title: appLocalizedValue("Appearance"),
                        value: colorScheme.title,
                        systemImage: "paintpalette.fill",
                        tint: AppTheme.medication
                    ) {
                        colorScheme = colorScheme == .light ? .dark : .light
                    }
                }
            }
        }
    }
}

private struct ShareOptionToggleCell: View {
    let title: String
    let value: String
    let systemImage: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(tint)
                    .frame(width: 26, height: 26)
                    .background(tint.opacity(0.14), in: Circle())

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(AppFont.micro)
                        .foregroundStyle(AppTheme.muted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                    Text(value)
                        .font(AppFont.bodyStrong)
                        .foregroundStyle(AppTheme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
            .background(AppTheme.cardElevated.opacity(0.86), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(tint.opacity(0.26), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(appLocalizedValue("\(title), \(value)"))
        .accessibilityHint(appLocalizedValue("Changes \(title.lowercased())."))
    }
}

private struct ShareExportActions: View {
    let renderedAsset: ShareCardRenderedAsset?
    let isRendering: Bool
    let isSaving: Bool
    let saveToPhotos: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: saveToPhotos) {
                Label(isSaving ? appLocalizedValue("Saving") : appLocalizedValue("Save"), systemImage: AppSymbol.Action.saveToPhotos)
                    .font(AppFont.bodyStrong)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .foregroundStyle(AppTheme.accentForeground)
                    .background(AppTheme.success, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(renderedAsset == nil || isRendering || isSaving)
            .accessibilityIdentifier("share-card-save-button")

            if let renderedAsset {
                ShareLink(
                    item: renderedAsset.fileURL,
                    subject: Text(appLocalizedValue("Gaurava journey")),
                    message: Text(appLocalizedValue("A private treatment progress card from Gaurava.")),
                    preview: SharePreview(appLocalizedValue("Gaurava journey"), image: Image(uiImage: renderedAsset.image))
                ) {
                    Label(appLocalizedValue("Share"), systemImage: AppSymbol.Action.share)
                        .font(AppFont.bodyStrong)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .foregroundStyle(AppTheme.accentForeground)
                        .background(AppTheme.primary, in: Capsule())
                }
                .disabled(isRendering)
                .accessibilityIdentifier("share-card-share-button")
            } else {
                Label(appLocalizedValue("Share"), systemImage: AppSymbol.Action.share)
                    .font(AppFont.bodyStrong)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .foregroundStyle(AppTheme.accentForeground.opacity(0.72))
                    .background(AppTheme.primary.opacity(0.48), in: Capsule())
                    .accessibilityIdentifier("share-card-share-button")
            }
        }
    }
}

private struct ShareCardRenderKey: Equatable {
    let configuration: ShareCardConfiguration
    let fingerprint: String
}

private struct ShareCardStatusMessage: Equatable {
    let text: String
    let isError: Bool
}
