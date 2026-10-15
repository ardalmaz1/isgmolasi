import Foundation

/// Turns a source into a Memory Movie plan, on top of Memory Intelligence — not beside it.
///
/// - Photos: Memory Intelligence chooses them (duplicates out, near-identical shots collapsed,
///   spread across moments, days and shapes, favorites and covers preferred), up to the length's
///   scene cap. Nothing is padded: a small source makes a short film.
/// - Order: the lead opens, the rest follow in the order they were taken (Memory Intelligence's
///   sequence), so time is never scrambled for effect.
/// - Rhythm: section openers and strong photos stay a little longer, supporting shots a little
///   shorter; motion alternates and is restrained; transitions follow what changes (a new day,
///   place, month or year).
/// - Words: the factual title, a few factual section labels, the period at the end.
/// - A user's own photos, or a cut the user edited, are kept exactly — order and all.
///
/// Deterministic: the same library, source and settings give the same plan.
public struct MovieStoryPlanner: Sendable {
    public var library: CreationLibrary
    public var locale: Locale

    public init(library: CreationLibrary, locale: Locale = Locale(identifier: "en_US")) {
        self.library = library
        self.locale = locale
    }

    private var engine: MemoryIntelligenceEngine {
        var engine = MemoryIntelligenceEngine(library: library, locale: locale)
        engine.logsDiagnostics = false
        return engine
    }

    // MARK: - Planning

    /// "Make it for me": Relive chooses the photos, the opening, the order and the edit.
    /// Hand-picked photos (`.photos`) are kept — Relive only orders the edit around them.
    public func plan(source: CreationSource, settings: MovieSettings = MovieSettings()) -> MoviePlan {
        if case .photos(let ids) = source {
            return plan(source: source, photos: ids, cover: nil, settings: settings, isUserCut: true)
        }
        let selection = engine.plan(for: source, target: .general(limit: settings.length.sceneCap))
        let ranked = engine.rankedLeads(selection.selected, target: .general(limit: settings.length.sceneCap))
        // A variation opens on another strong photo; the first choice opens on the lead.
        var lead = selection.lead
        if settings.variation > 0, !ranked.isEmpty {
            lead = ranked[settings.variation % ranked.count]
        }
        let body = selection.selected.filter { $0 != lead }
        let ordered = (lead.map { [$0] } ?? []) + body
        return build(
            source: source,
            ordered: ordered,
            title: selection.title,
            period: selection.period,
            settings: settings,
            isUserCut: false,
            sourceCount: selection.sourceCount,
            duplicatesRemoved: selection.excludedDuplicates.count,
            similarCollapsed: selection.collapsedSimilar.count,
            limitations: selection.limitations
        )
    }

    /// A cut whose photos and order are already decided (hand-picked, or edited by the user):
    /// kept exactly, except photos that can't be shown. `cover`, when given and present, opens.
    public func plan(source: CreationSource, photos: [AssetID], cover: AssetID?, settings: MovieSettings, isUserCut: Bool = true) -> MoviePlan {
        var seen = Set<AssetID>()
        let unique = photos.filter { seen.insert($0).inserted }
        let usable = unique.filter(library.isUsable)
        var ordered = Array(usable.prefix(MovieEligibility.maximumPhotos))
        if let cover, let index = ordered.firstIndex(of: cover), index > 0 {
            ordered.remove(at: index)
            ordered.insert(cover, at: 0)
        }
        let selection = engine.plan(IntelligenceRequest(pool: ordered, target: .general(limit: max(1, ordered.count)), mode: .userSelected))
        var limitations = selection.limitations
        let missing = unique.count - usable.count
        if missing > 0, !limitations.contains(where: { if case .missing = $0 { return true } else { return false } }) {
            limitations.append(.missing(missing))
        }
        return build(
            source: source,
            ordered: ordered,
            title: selection.title,
            period: selection.period,
            settings: settings,
            isUserCut: isUserCut,
            sourceCount: unique.count,
            duplicatesRemoved: 0,
            similarCollapsed: 0,
            limitations: limitations
        )
    }

    // MARK: - Words

    /// Up to three safe opening titles: the factual title, then editorial alternatives that the
    /// shared validator accepted for this movie's facts ("Four days in Kaş.", "Kaş · August 2026").
    func titleVariants(title: FactualTitle, periodLabel: String?, days: [DayKey?], count: Int) -> [String] {
        let primary = title.primary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !primary.isEmpty else { return [] }
        let allDated = !days.isEmpty && !days.contains(nil)
        let sorted = days.compactMap { $0 }.sorted()
        var seenMonths = Set<MonthKey>()
        let months = allDated ? sorted.map { MonthKey(year: $0.year, month: $0.month) }.filter { seenMonths.insert($0).inserted } : []
        let context = EditorialContext(
            surface: .movie,
            language: EditorialLanguage(locale: locale),
            firstDay: allDated ? sorted.first : nil,
            lastDay: allDated ? sorted.last : nil,
            months: months,
            places: title.basis == .place ? [primary] : [],
            tripName: title.basis == .trip ? primary : nil,
            momentName: title.basis == .moment ? primary : nil,
            counts: EditorialContext.Counts(memories: count),
            periodLabel: periodLabel,
            factualTitle: primary,
            knownPhrases: [title.secondary].compactMap { $0 }
        )
        let result = EditorialPipeline.shared.result(for: EditorialRequest(context: context, kind: .title))
        var seen = Set<String>()
        return ([primary] + result.variants)
            .filter { $0 != title.combined && seen.insert($0).inserted }
            .prefix(EditorialPipeline.maximumVariants)
            .map { $0 }
    }

    // MARK: - The edit

    private func build(
        source: CreationSource,
        ordered: [AssetID],
        title: FactualTitle,
        period: PeriodDescriptor,
        settings: MovieSettings,
        isUserCut: Bool,
        sourceCount: Int,
        duplicatesRemoved: Int,
        similarCollapsed: Int,
        limitations: [MemorySelectionPlan.Limitation]
    ) -> MoviePlan {
        let periodLabel = period.isComplete ? period.label(locale: locale, calendar: library.calendar) : nil
        var plan = MoviePlan(
            source: source,
            status: ordered.count >= MovieEligibility.minimumPhotos ? .ready : .insufficient(available: ordered.count, required: MovieEligibility.minimumPhotos),
            settings: settings,
            title: title,
            periodLabel: periodLabel,
            scenes: [],
            isUserCut: isUserCut,
            limitations: limitations,
            sourceCount: sourceCount,
            duplicatesRemoved: duplicatesRemoved,
            similarCollapsed: similarCollapsed
        )
        guard !ordered.isEmpty else { return plan }

        let built = MemoryCandidate.build(ordered, library: library)
        let candidates = Dictionary(uniqueKeysWithValues: built.map { ($0.assetID, $0) })
        // The opening title: Relive's factual title first, then the shared editorial layer's
        // validated alternatives; the user's choice (or own words) wins.
        plan.titleVariants = titleVariants(title: title, periodLabel: periodLabel, days: built.map(\.day), count: ordered.count)
        let opening = (settings.titleChoice ?? EditorialChoice()).resolve(plan.titleVariants)
        plan.openingTitle = opening.text
        plan.openingTitleAuthorship = opening.authorship
        let isReliveFirstChoice = opening.authorship == .relive && opening.text == title.primary
        let sections = Self.sections(ordered.compactMap { candidates[$0] })
        var scenes: [MovieScene] = []
        var previousMotion: MovieMotion?
        var labels = 0
        var lastLabel: String?
        let maxLabels = min(4, max(0, ordered.count / 4))
        let multiSection = Set(sections.map(\.index)).count >= 3

        for (position, id) in ordered.enumerated() {
            let candidate = candidates[id]
            let info = sections[position]
            let isFirst = position == 0
            let isLast = position == ordered.count - 1 && ordered.count > 1
            let role: MovieScene.Role = isFirst ? .opening : isLast ? .closing : info.opensSection ? .sectionOpener : .body
            let aspect = CropMath.sanitizedAspect(library.creationAsset(id)?.aspectRatio ?? library.assets[id]?.aspectRatio ?? 1)
            let framing: MovieFraming = CropMath.cropLoss(imageAspect: aspect, frameAspect: settings.aspect.ratio) <= 0.3 ? .fill : .fit
            let motion = Self.motion(
                role: role,
                framing: framing,
                imageAspect: aspect,
                frameAspect: settings.aspect.ratio,
                hasPeople: (candidate?.faceCount ?? 0) > 0,
                style: settings.style,
                index: position + settings.variation,
                previous: previousMotion
            )
            previousMotion = motion
            let (transition, transitionDuration) = Self.transition(into: role, change: info.change, style: settings.style, indexInSection: info.indexInSection)

            var text: MovieText?
            if settings.showsText {
                if isFirst {
                    if isReliveFirstChoice {
                        text = MovieText(eyebrow: title.secondary ?? (title.basis == .period ? nil : periodLabel), title: title.primary)
                    } else if let openingTitle = opening.text {
                        let eyebrow = periodLabel.flatMap { openingTitle.localizedCaseInsensitiveContains($0) ? nil : $0 }
                        text = MovieText(eyebrow: eyebrow, title: openingTitle)
                    } else if let periodLabel {
                        text = MovieText(title: periodLabel)
                    }
                } else if isLast {
                    text = MovieText(title: periodLabel ?? title.primary, detail: "Made with Relive")
                } else if multiSection, info.opensSection, labels < maxLabels, [.newPlace, .newMonth, .newYear].contains(info.change),
                          let label = sectionLabel(info, title: title), label != lastLabel {
                    text = MovieText(title: label)
                    labels += 1
                    lastLabel = label
                }
            }

            let strong = candidate.map { $0.isFavorite || $0.isUserCover || $0.isMomentCover } ?? false
            scenes.append(MovieScene(
                assetID: id,
                role: role,
                duration: Self.duration(role: role, strong: strong, indexInSection: info.indexInSection, settings: settings),
                motion: motion,
                framing: framing,
                focus: .standard,
                imageAspect: aspect,
                transition: isFirst ? .fadeThroughBlack : transition,
                transitionDuration: isFirst ? MovieTimeline.fadeIn : transitionDuration,
                text: text,
                sectionIndex: info.index
            ))
        }
        plan.scenes = Self.fitted(scenes, to: settings.length)
        return plan
    }

    // MARK: - Sections

    struct SectionInfo: Hashable {
        var index: Int
        var opensSection: Bool
        var indexInSection: Int
        var change: MemorySequence.Transition
        var place: PlaceName?
        var month: MonthKey?
        var year: Int?
    }

    /// Consecutive photos of one moment (or, outside the story, one day) form a section; the
    /// opening photo is its own section 0.
    static func sections(_ candidates: [MemoryCandidate]) -> [SectionInfo] {
        var result: [SectionInfo] = []
        var section = 0
        var indexInSection = 0
        var previous: MemoryCandidate?
        for (position, candidate) in candidates.enumerated() {
            var change = MemorySequence.Transition.none
            var opens = false
            if position == 0 {
                change = .start
                opens = true
            } else if position == 1 || previous.map({ MemorySequencePlanner.sectionKey($0) != MemorySequencePlanner.sectionKey(candidate) }) == true {
                section += 1
                indexInSection = 0
                opens = true
                change = position == 1 ? .start : Self.change(from: previous, to: candidate)
            } else {
                indexInSection += 1
            }
            result.append(SectionInfo(index: section, opensSection: opens, indexInSection: indexInSection, change: change, place: candidate.place, month: candidate.month, year: candidate.day?.year))
            previous = candidate
        }
        return result
    }

    /// The biggest change for a film: a new year, month or place matters more than a new day
    /// (a trip's next stop is a new place even though it is also a new day).
    static func change(from previous: MemoryCandidate?, to next: MemoryCandidate) -> MemorySequence.Transition {
        guard let previous else { return .start }
        if let a = previous.day, let b = next.day {
            if a.year != b.year { return .newYear }
            if a.month != b.month { return .newMonth }
        }
        if let a = previous.place?.comparisonKey, let b = next.place?.comparisonKey, a != b { return .newPlace }
        if let a = previous.day, let b = next.day, a != b { return .newDay }
        if previous.momentID != next.momentID, next.momentID != nil { return .newMoment }
        return .none
    }

    /// "Kaş", "Kaş · August 2025", "September 2025" — what is true of that photo's moment.
    private func sectionLabel(_ info: SectionInfo, title: FactualTitle) -> String? {
        let names = MonthNames(locale: locale, calendar: library.calendar)
        let place = info.place?.name
        let month = info.month.map { "\(names.full($0.month)) \($0.year)" }
        let label: String?
        switch info.change {
        case .newPlace: label = place
        case .newMonth, .newYear: label = [place, month].compactMap { $0 }.joined(separator: " · ").nilIfEmpty
        default: label = nil
        }
        guard let label, label != title.primary, label != title.combined else { return nil }
        return label
    }

    // MARK: - Rhythm

    static func duration(role: MovieScene.Role, strong: Bool, indexInSection: Int, settings: MovieSettings) -> Double {
        let base = settings.length.baseSceneSeconds
        var seconds: Double = switch role {
        case .opening: 3.9
        case .closing: 3.8
        case .sectionOpener: base + 0.5
        case .body: indexInSection >= 2 ? base - 0.3 : base
        }
        if strong, role == .body || role == .sectionOpener { seconds += 0.3 }
        return min(4.6, max(1.8, seconds * settings.style.rhythm))
    }

    /// Too long for the chosen length: everything but the opening and closing shortens evenly,
    /// never below a comfortable minimum. Too short is fine — nothing is padded.
    static func fitted(_ scenes: [MovieScene], to length: MovieLength) -> [MovieScene] {
        var scenes = scenes
        for _ in 0..<4 {
            let total = MovieTimeline(plan: MoviePlan.measuring(scenes)).duration
            guard total > length.seconds.upperBound else { break }
            let flexible = scenes.indices.filter { scenes[$0].role != .opening && scenes[$0].role != .closing }
            let flexibleTime = flexible.map { scenes[$0].duration }.reduce(0, +)
            guard flexibleTime > 0 else { break }
            let factor = max(0.5, 1 - (total - length.seconds.upperBound) / flexibleTime)
            for index in flexible {
                scenes[index].duration = max(1.8, scenes[index].duration * factor)
            }
        }
        // A transition never takes more than a little under half of either scene.
        for index in scenes.indices.dropFirst() {
            let limit = min(scenes[index].duration, scenes[index - 1].duration) * 0.45
            scenes[index].transitionDuration = min(scenes[index].transitionDuration, limit)
        }
        return scenes
    }

    static func transition(into role: MovieScene.Role, change: MemorySequence.Transition, style: MovieStyle, indexInSection: Int) -> (MovieTransition, Double) {
        switch role {
        case .opening:
            return (.fadeThroughBlack, MovieTimeline.fadeIn)
        case .closing:
            return (.crossfade, 1.0)
        case .sectionOpener:
            switch change {
            case .newYear, .newMonth, .newPlace: return (.fadeThroughBlack, style == .editorial ? 1.2 : 1.0)
            default: return (.crossfade, 0.9)
            }
        case .body:
            // Film cuts now and then inside a moment; the others dissolve softly.
            if style == .film, indexInSection % 2 == 1 { return (.cut, 0) }
            return (.crossfade, style == .editorial ? 0.8 : 0.6)
        }
    }

    // MARK: - Motion

    /// Restrained, alternating movement. Pans travel only across a photo's own spare edge;
    /// photos with people prefer a gentle zoom out (nobody is panned out of the frame).
    static func motion(
        role: MovieScene.Role,
        framing: MovieFraming,
        imageAspect: Double,
        frameAspect: Double,
        hasPeople: Bool,
        style: MovieStyle,
        index: Int,
        previous: MovieMotion?
    ) -> MovieMotion {
        switch role {
        case .opening: return style == .editorial ? .still : .zoomOut
        case .closing: return style == .editorial || style == .film || previous == .zoomIn ? .still : .zoomIn
        default: break
        }
        var options: [MovieMotion]
        if framing == .fit {
            options = [.zoomIn, .still, .zoomOut]
        } else if hasPeople {
            options = [.zoomOut, .still, .zoomIn]
        } else if imageAspect > frameAspect * 1.02 {
            options = [.panRight, .zoomIn, .panLeft, .zoomOut]
        } else if imageAspect < frameAspect * 0.98 {
            options = [.panDown, .zoomIn, .panUp, .zoomOut]
        } else {
            options = [.zoomIn, .zoomOut, .still]
        }
        switch style {
        case .editorial: options.insert(.still, at: 0)
        case .film: options = options.filter { !$0.isZoom || $0 == .zoomIn } + [.still]
        case .warm:
            options = options.filter { !$0.isPan }
            if !options.contains(where: \.isZoom) { options += [.zoomIn, .zoomOut] }
        case .classic: break
        }
        if options.isEmpty { options = [.still] }
        let start = ((index % options.count) + options.count) % options.count
        for step in 0..<options.count {
            let choice = options[(start + step) % options.count]
            if choice == .still || choice != previous { return choice }
        }
        return .still
    }
}

extension MoviePlan {
    /// A throwaway plan holding only scenes, to measure their running time.
    static func measuring(_ scenes: [MovieScene]) -> MoviePlan {
        MoviePlan(source: .photos([]), status: .ready, settings: MovieSettings(), title: FactualTitle(primary: "", secondary: nil, basis: .neutral), periodLabel: nil, scenes: scenes, isUserCut: false, limitations: [], sourceCount: 0, duplicatesRemoved: 0, similarCollapsed: 0)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
