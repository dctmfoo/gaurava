import SwiftUI

struct ShareJourneyCardView: View {
    let snapshot: ShareCardSnapshot
    let configuration: ShareCardConfiguration

    var body: some View {
        Group {
            switch configuration.template {
            case .milestone:
                ShareMilestoneTemplate(snapshot: snapshot, configuration: configuration)
            case .dataSheet:
                ShareDataSheetTemplate(snapshot: snapshot, configuration: configuration)
            case .story:
                ShareStoryTemplate(snapshot: snapshot, configuration: configuration)
            }
        }
        .frame(width: configuration.template.canvas.points.width, height: configuration.template.canvas.points.height)
        .background(ShareCardBackground())
        .clipped()
        .dynamicTypeSize(.medium)
    }
}

private struct ShareMilestoneTemplate: View {
    let snapshot: ShareCardSnapshot
    let configuration: ShareCardConfiguration

    var body: some View {
        let formatter = ShareCardFormatter(snapshot: snapshot, configuration: configuration)

        // The headline already states progress ("60% of the way to goal"), so in
        // percent mode lead the tiles with the goal target rather than a "% of
        // start" current that just mirrors the loss. Exact mode keeps Current.
        let percentOnly = configuration.privacyMode == .percentOnly
        let firstTileTitle = percentOnly ? appLocalizedValue("Goal") : appLocalizedValue("Current")
        let firstTileValue = percentOnly ? formatter.goalTarget() : formatter.weight(snapshot.currentWeightKg)
        let firstTileTint = percentOnly ? AppTheme.weight : AppTheme.success

        VStack(alignment: .leading, spacing: 14) {
            ShareCardHeader(weekCount: snapshot.weekCount)

            ShareCardPanel(cornerRadius: 24, padding: 18) {
                VStack(alignment: .leading, spacing: 7) {
                    ShareCardEyebrow(appLocalizedValue("Milestone"))
                    Text(formatter.loss())
                        .font(.system(size: 62, weight: .heavy, design: .serif))
                        .foregroundStyle(AppTheme.success)
                        .lineLimit(1)
                        .minimumScaleFactor(0.62)
                    Text(milestoneLine)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.78)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
            .frame(height: 172)

            HStack(spacing: 8) {
                ShareCardMetricTile(title: firstTileTitle, value: firstTileValue, tint: firstTileTint)
                ShareCardMetricTile(title: appLocalizedValue("Weekly"), value: formatter.weeklyAverage(), tint: AppTheme.medication)
            }
            .frame(height: 72)

            ShareCardPanel(cornerRadius: 22, padding: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(appLocalizedValue("Weight trend"))
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(AppTheme.textSecondary)
                        Spacer()
                        Text(appLocalizedValue("Week \(snapshot.weekCount)"))
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(AppTheme.textTertiary)
                    }

                    ShareWeightTrendChart(snapshot: snapshot, configuration: configuration, style: .compact)
                }
            }
            .frame(height: 230)

            ShareDosePathView(snapshot: snapshot, compact: true)

            Spacer(minLength: 8)
            ShareCardFooter()
        }
        .padding(24)
    }

    private var milestoneLine: String {
        if let progress = snapshot.progressToGoal {
            return appLocalizedValue("\(Int((progress * 100).rounded()))% of the way to goal")
        }
        if let currentDose = snapshot.currentDoseMg {
            return appLocalizedValue("Current dose \(doseText(currentDose))")
        }
        return appLocalizedValue("Week \(snapshot.weekCount)")
    }
}

private struct ShareDataSheetTemplate: View {
    let snapshot: ShareCardSnapshot
    let configuration: ShareCardConfiguration

    var body: some View {
        let formatter = ShareCardFormatter(snapshot: snapshot, configuration: configuration)

        // Percent mode frames the whole row as loss-from-start + progress, the
        // way weight-loss/GLP-1 progress is actually talked about. "% of starting
        // weight remaining" (Start 100% / Current 83.2% / Goal 72.1%) just
        // restated the loss in reverse and read wrong. Exact mode keeps the real
        // Start / Current / Goal weights, which are intuitive on their own.
        let percentOnly = configuration.privacyMode == .percentOnly
        let leadTitle = percentOnly ? appLocalizedValue("Lost") : appLocalizedValue("Start")
        let leadValue = percentOnly ? formatter.loss() : formatter.weight(snapshot.startWeightKg)
        let midTitle = percentOnly ? appLocalizedValue("Progress") : appLocalizedValue("Current")
        let midValue = percentOnly ? formatter.progressToGoalText() : formatter.weight(snapshot.currentWeightKg)

        VStack(alignment: .leading, spacing: 12) {
            ShareCardHeader(weekCount: snapshot.weekCount, trailing: appLocalizedValue("Data sheet"))

            HStack(spacing: 7) {
                ShareCardMetricTile(title: leadTitle, value: leadValue, tint: AppTheme.textPrimary, compact: true)
                ShareCardMetricTile(title: midTitle, value: midValue, tint: AppTheme.success, compact: true)
                ShareCardMetricTile(title: appLocalizedValue("Goal"), value: formatter.goalTarget(), tint: AppTheme.weight, compact: true)
            }
            .frame(height: 62)

            ShareCardPanel(cornerRadius: 16, padding: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(appLocalizedValue("Weight x dose"))
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(AppTheme.textSecondary)
                        Spacer()
                        Text(formatter.loss())
                            .font(.system(size: 11, weight: .heavy, design: .serif))
                            .foregroundStyle(AppTheme.success)
                    }
                    ShareWeightTrendChart(snapshot: snapshot, configuration: configuration, style: .compact)
                }
            }
            .frame(height: 224)

            HStack(spacing: 7) {
                ShareCardMetricTile(title: appLocalizedValue("BMI"), value: bmiText, tint: AppTheme.primary, compact: true)
                ShareCardMetricTile(title: appLocalizedValue("Weekly"), value: formatter.weeklyAverage(), tint: AppTheme.medication, compact: true)
            }
            .frame(height: 62)

            HStack(spacing: 7) {
                ShareCardMetricTile(title: appLocalizedValue("Weeks"), value: appLocalizedValue("\(snapshot.weekCount)"), tint: AppTheme.primary, compact: true)
                ShareCardMetricTile(title: appLocalizedValue("Dose"), value: doseText(snapshot.currentDoseMg), tint: doseColor(snapshot.currentDoseMg), compact: true)
            }
            .frame(height: 62)

            ShareDosePathView(snapshot: snapshot)

            Spacer(minLength: 8)
            ShareCardFooter()
        }
        .padding(24)
    }

    private var bmiText: String {
        guard let bmi = snapshot.bmi else { return appLocalizedValue("--") }
        return appLocalizedValue("\(bmi.formatted(.number.precision(.fractionLength(1))))")
    }
}

private struct ShareStoryTemplate: View {
    let snapshot: ShareCardSnapshot
    let configuration: ShareCardConfiguration

    var body: some View {
        let formatter = ShareCardFormatter(snapshot: snapshot, configuration: configuration)

        VStack(alignment: .leading, spacing: 16) {
            ShareCardHeader(weekCount: snapshot.weekCount)

            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    ShareCardEyebrow(appLocalizedValue("Story"))
                    Text(formatter.loss())
                        .font(.system(size: 56, weight: .heavy, design: .serif))
                        .foregroundStyle(AppTheme.success)
                        .lineLimit(1)
                        .minimumScaleFactor(0.64)
                    Text(storySubtitle(formatter: formatter))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.78)
                }

                Spacer(minLength: 8)

                if let progress = snapshot.progressToGoal {
                    ShareCardProgressRing(progress: progress)
                        .frame(width: 82, height: 82)
                }
            }
            .frame(minHeight: 122)

            ShareCardPanel(cornerRadius: 22, padding: 12) {
                ShareWeightTrendChart(snapshot: snapshot, configuration: configuration, style: .standard)
            }
            .frame(height: 252)

            HStack(spacing: 8) {
                ShareCardMetricTile(title: appLocalizedValue("Weeks"), value: appLocalizedValue("\(snapshot.weekCount)"), tint: AppTheme.primary)
                ShareCardMetricTile(title: appLocalizedValue("Dose"), value: doseText(snapshot.currentDoseMg), tint: doseColor(snapshot.currentDoseMg))
                ShareCardMetricTile(title: appLocalizedValue("Goal"), value: formatter.goalTarget(), tint: AppTheme.weight)
            }
            .frame(height: 66)

            ShareDosePathView(snapshot: snapshot)

            Spacer(minLength: 8)
            ShareCardFooter()
        }
        .padding(24)
    }

    private func storySubtitle(formatter: ShareCardFormatter) -> String {
        if let progress = snapshot.progressToGoal {
            return appLocalizedValue("\(Int((progress * 100).rounded()))% toward goal - \(formatter.weeklyAverageSentenceValue()) average")
        }
        return appLocalizedValue("\(formatter.weeklyAverageSentenceValue()) average")
    }
}

private struct ShareCardBackground: View {
    var body: some View {
        ZStack {
            // Matches the app's calm backdrop: a soft vertical wash from the
            // brand-green page tone to a clean warm near-white, plus one faint top
            // glow. No green->tan fade and no tri-color tint smear.
            LinearGradient(
                colors: [AppTheme.pageBackgroundTop, AppTheme.healthSurface],
                startPoint: .top,
                endPoint: .bottom
            )
            RadialGradient(
                colors: [AppTheme.primary.opacity(0.10), .clear],
                center: .top,
                startRadius: 0,
                endRadius: 720
            )
        }
    }
}

private struct ShareCardHeader: View {
    let weekCount: Int
    var trailing: String?

    var body: some View {
        HStack {
            Spacer()

            // Branding lives once, in the footer ("Tracked with Gaurava"). The header
            // top-right pill carries context only (week / template label).
            ShareCardPill(
                text: trailing ?? appLocalizedValue("Week \(weekCount)"),
                tint: AppTheme.primary
            )
        }
    }
}

private struct ShareCardFooter: View {
    var body: some View {
        HStack(spacing: 6) {
            GauravaBrandMark()
                .frame(width: 18, height: 18)
            Text(appLocalizedValue("Tracked with Gaurava"))
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(AppTheme.textTertiary)
        }
    }
}

private struct ShareCardPanel<Content: View>: View {
    let cornerRadius: CGFloat
    let padding: CGFloat
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(AppTheme.healthSurface, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(AppTheme.separator, lineWidth: 1)
            )
            .shadow(color: AppTheme.shadow.opacity(0.46), radius: 12, x: 0, y: 6)
    }
}

private struct ShareCardMetricTile: View {
    let title: String
    let value: String
    let tint: Color
    var compact = false

    var body: some View {
        ShareCardPanel(cornerRadius: compact ? 14 : 16, padding: compact ? 8 : 10) {
            VStack(alignment: .center, spacing: compact ? 3 : 4) {
                Text(value)
                    .font(.system(size: compact ? 16 : 20, weight: .heavy, design: .serif))
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.52)
                Text(title)
                    .font(.system(size: compact ? 9 : 10, weight: .bold))
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }
}

private struct ShareDosePathView: View {
    let snapshot: ShareCardSnapshot
    var compact = false

    var body: some View {
        HStack(spacing: compact ? 5 : 6) {
            Text(appLocalizedValue("Dose path"))
                .font(.system(size: compact ? 9 : 10, weight: .heavy))
                .textCase(.uppercase)
                .foregroundStyle(AppTheme.textTertiary)

            ForEach(snapshot.doseSteps.prefix(compact ? 4 : 5)) { step in
                ShareCardPill(
                    text: doseText(step.doseMg),
                    tint: doseColor(step.doseMg),
                    isCurrent: step.doseMg == snapshot.currentDoseMg
                )
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.78)
    }
}

private struct ShareCardPill: View {
    let text: String
    let tint: Color
    var isCurrent = false

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(tint)
                .frame(width: 7, height: 7)
            Text(isCurrent ? appLocalizedValue("\(text) now") : text)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(AppTheme.textPrimary)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(tint.opacity(isCurrent ? 0.20 : 0.12), in: Capsule())
        .overlay(Capsule().stroke(tint.opacity(isCurrent ? 0.54 : 0.22), lineWidth: 1))
    }
}

private struct ShareCardProgressRing: View {
    let progress: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(AppTheme.primary.opacity(0.16), lineWidth: 8)
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(AppTheme.primary, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(appLocalizedValue("\(Int((min(max(progress, 0), 1) * 100).rounded()))%"))
                .font(.system(size: 18, weight: .heavy, design: .serif))
                .foregroundStyle(AppTheme.textPrimary)
        }
    }
}

private struct ShareCardEyebrow: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .heavy))
            .textCase(.uppercase)
            .foregroundStyle(AppTheme.textSecondary)
            .tracking(0.4)
    }
}
