import Foundation
import Testing
@testable import ReliveCore

/// Memory Movie fixtures (A–J) on the intelligence fixtures.
enum MovieFixture {
    typealias F = IntelligenceFixture

    /// C. A four-day trip, 8 distinct photos a day, a new place each day, mixed shapes, faces on
    /// some photos.
    static func fourDayTrip() -> IntelligenceFixture {
        let days: [(key: String, place: String, day: Int)] = [("t1", "Kaş", 6), ("t2", "Kaş Harbour", 7), ("t3", "Kekova", 8), ("t4", "Kalkan", 9)]
        var moments: [F.MomentSpec] = []
        for (offset, entry) in days.enumerated() {
            var shots: [F.Shot] = []
            for index in 0..<8 {
                let when: Date = date(2025, 8, entry.day, 9).addingTimeInterval(Double(index) * 2_400)
                let faces: Int = index % 4 == 1 ? 2 : 0
                let quality: Double = 0.45 + Double((index * 3) % 5) / 10
                shots.append(F.Shot(id: "\(entry.key)-\(index)", date: when, portrait: index % 3 != 0, look: F.look(offset * 8 + index), faces: faces, quality: quality))
            }
            moments.append(F.MomentSpec(key: entry.key, title: entry.place, shots: shots, place: entry.place, trip: "Lycian Coast"))
        }
        return IntelligenceFixture(moments: moments)
    }

    /// E. A year: 12 months, 12–13 memories each, several moments a month.
    static func bigYear() -> IntelligenceFixture {
        var moments: [F.MomentSpec] = []
        var lookIndex = 0
        for month in 1...12 {
            for part in 0..<3 {
                let count = part == 0 ? 5 : 4
                let start = date(2026, month, 3 + part * 8, 11)
                var shots: [F.Shot] = []
                for index in 0..<count {
                    let when: Date = start.addingTimeInterval(Double(index) * 3_000)
                    let quality: Double = 0.4 + Double((index + month) % 5) / 10
                    shots.append(F.Shot(id: "y\(month)-\(part)-\(index)", date: when, portrait: (index + part) % 2 == 0, look: F.look(lookIndex), quality: quality))
                    lookIndex += 1
                }
                moments.append(F.MomentSpec(key: "y\(month)-\(part)", title: "Day \(month)-\(part)", shots: shots))
            }
        }
        return IntelligenceFixture(moments: moments)
    }

    /// F. Ten photos over two days, three of them favorites.
    static func withFavorites() -> IntelligenceFixture {
        var shots: [F.Shot] = []
        for index in 0..<10 {
            let when: Date = date(2026, 5, 2 + index / 5, 10).addingTimeInterval(Double(index % 5) * 3_600)
            shots.append(F.Shot(id: "fav-\(index)", date: when, favorite: [2, 6, 9].contains(index), look: F.look(30 + index), quality: 0.5))
        }
        return IntelligenceFixture(moments: [
            F.MomentSpec(key: "fa", title: "May Morning", shots: Array(shots.prefix(5))),
            F.MomentSpec(key: "fb", title: "May Afternoon", shots: Array(shots.suffix(5))),
        ])
    }

    static func planner(_ fixture: IntelligenceFixture) -> MovieStoryPlanner {
        MovieStoryPlanner(library: fixture.library)
    }
}

@Suite("Memory Movie: plans")
struct MovieStoryPlannerTests {
    typealias F = IntelligenceFixture
    typealias M = MovieFixture

    @Test func aSmallMomentMakesAShortFilm() {
        let fixture = F.smallMoment()
        let plan = M.planner(fixture).plan(source: .moment(F.momentID("small")), settings: MovieSettings(length: .short))
        #expect(plan.isReady)
        #expect(plan.scenes.count == 5, "five photos, nothing padded")
        #expect(plan.scenes.first?.role == .opening && plan.scenes.last?.role == .closing)
        #expect(plan.scenes.first?.text?.title == "Kaş")
        #expect(plan.scenes.last?.text?.detail == nil, "no Relive branding on a personal movie")
        #expect(!plan.scenes.compactMap(\.text).flatMap(\.all).contains { $0.localizedCaseInsensitiveContains("relive") })
        #expect(plan.duration < MovieLength.short.seconds.upperBound)
        #expect(plan.duration > 10)
    }

    @Test func burstsCollapseInsteadOfRepeating() {
        let fixture = F.burstHeavy()
        let plan = M.planner(fixture).plan(source: .moment(F.momentID("burst")))
        let selfies = plan.photoIDs.filter { $0.hasPrefix("selfie") }
        #expect(selfies.count <= 1, "fifteen near-identical selfies are one scene at most")
        #expect(plan.similarCollapsed >= 14)
        // Only four distinct photos: honestly not enough for a film.
        #expect(plan.status == .insufficient(available: plan.scenes.count, required: MovieEligibility.minimumPhotos))
    }

    @Test func aTripProgressesThroughItsDays() {
        let fixture = M.fourDayTrip()
        let plan = M.planner(fixture).plan(source: .trip(F.tripID("Lycian Coast")))
        #expect(plan.isReady)
        #expect(plan.title.primary == "Lycian Coast")
        #expect(plan.periodLabel == "August 6–9, 2025")
        // The body is in the order it was taken; every day appears.
        let library = fixture.library
        let bodyDates = plan.scenes.dropFirst().compactMap { library.assets[$0.assetID]?.creationDate }
        #expect(bodyDates == bodyDates.sorted())
        let days = Set(plan.photoIDs.map { String($0.prefix(2)) })
        #expect(days == ["t1", "t2", "t3", "t4"])
        // A new place gets the stronger transition and, sometimes, its name.
        let openers = plan.scenes.filter { $0.role == .sectionOpener }
        #expect(openers.count >= 3)
        #expect(openers.dropFirst().allSatisfy { $0.transition == .fadeThroughBlack })
        let labels = plan.scenes.compactMap { $0.role == .sectionOpener ? $0.text?.title : nil }
        #expect(!labels.isEmpty)
        #expect(labels.allSatisfy { ["Kaş Harbour", "Kekova", "Kalkan"].contains($0) })
        #expect(plan.scenes.count <= MovieLength.standard.sceneCap)
    }

    @Test func framingFollowsTheShapeOfEachPhoto() {
        let fixture = M.fourDayTrip()
        let tall = M.planner(fixture).plan(source: .trip(F.tripID("Lycian Coast")), settings: MovieSettings(aspect: .portrait))
        for scene in tall.scenes {
            // 3:4 portraits fill a 9:16 frame (a quarter cropped); 4:3 landscapes are shown whole.
            #expect(scene.framing == (scene.imageAspect < 1 ? .fill : .fit))
        }
        let wide = M.planner(fixture).plan(source: .trip(F.tripID("Lycian Coast")), settings: MovieSettings(aspect: .landscape))
        for scene in wide.scenes {
            #expect(scene.framing == (scene.imageAspect > 1 ? .fill : .fit))
        }
        // A photo with people is never panned across.
        let library = fixture.library
        for scene in tall.scenes where (library.assets[scene.assetID]?.analysis?.faceCount ?? 0) > 0 {
            #expect(!scene.motion.isPan)
        }
    }

    @Test func aBigYearIsCappedNotFlooded() {
        let fixture = M.bigYear()
        let planner = M.planner(fixture)
        for length in MovieLength.allCases {
            let plan = planner.plan(source: .year(2026), settings: MovieSettings(length: length))
            #expect(plan.isReady)
            #expect(plan.scenes.count <= length.sceneCap)
            #expect(plan.scenes.count >= length.sceneCap - 2, "\(length): \(plan.scenes.count)")
            #expect(plan.duration <= length.seconds.upperBound + 0.01, "\(length): \(plan.duration)")
        }
        let long = planner.plan(source: .year(2026), settings: MovieSettings(length: .long))
        let months = Set(long.photoIDs.map { $0.split(separator: "-")[0] })
        #expect(months.count >= 8, "spread across the year: \(months.count) months")
        #expect(long.title.primary == "Our 2026")
    }

    @Test func favoritesCountWithoutRepeating() {
        let fixture = M.withFavorites()
        let plan = M.planner(fixture).plan(source: .favorites, settings: MovieSettings(length: .short))
        #expect(Set(plan.photoIDs).count == plan.photoIDs.count)
        let all = M.planner(fixture).plan(source: .photos(fixture.moments.flatMap(\.shots).map(\.id)), settings: MovieSettings())
        #expect(Set(all.photoIDs).count == all.photoIDs.count)
        let month = M.planner(fixture).plan(source: .month(MonthKey(year: 2026, month: 5)), settings: MovieSettings(length: .short))
        #expect(["fav-2", "fav-6", "fav-9"].contains(month.cover ?? ""), "a favorite opens")
        #expect(month.scenes.filter { ["fav-2", "fav-6", "fav-9"].contains($0.assetID) }.count >= 2)
        // Strong photos stay on screen a little longer than their neighbours.
        let favorite = month.scenes.first { $0.role == .body && $0.assetID.hasPrefix("fav-") && ["fav-6", "fav-9", "fav-2"].contains($0.assetID) }
        let ordinary = month.scenes.first { $0.role == .body && !["fav-2", "fav-6", "fav-9"].contains($0.assetID) }
        if let favorite, let ordinary {
            #expect(favorite.duration >= ordinary.duration)
        }
    }

    @Test func handPickedPhotosAreKeptExactly() {
        let fixture = M.fourDayTrip()
        let picks = ["t3-4", "t1-0", "t4-7", "t2-2", "t1-5", "t3-1"]
        let planner = M.planner(fixture)
        let plan = planner.plan(source: .photos(picks), settings: MovieSettings())
        #expect(plan.photoIDs == picks, "order and photos as chosen")
        #expect(plan.isUserCut)
        // Choosing another opening moves it to the front and keeps the rest in order.
        let covered = planner.plan(source: .photos(picks), photos: picks, cover: "t4-7", settings: MovieSettings())
        #expect(covered.photoIDs == ["t4-7", "t3-4", "t1-0", "t2-2", "t1-5", "t3-1"])
    }

    @Test func hiddenMissingAndDuplicatesAreLeftOut() {
        var fixture = M.fourDayTrip()
        fixture.moments[1].hidden = true
        fixture.moments[2].duplicates = ["t3-6"]
        fixture.unavailable = ["t4-2", "t4-3"]
        let plan = M.planner(fixture).plan(source: .trip(F.tripID("Lycian Coast")), settings: MovieSettings(length: .long))
        #expect(!plan.photoIDs.contains { $0.hasPrefix("t2-") }, "hidden")
        #expect(!plan.photoIDs.contains("t3-6"), "duplicate")
        #expect(!plan.photoIDs.contains("t4-2") && !plan.photoIDs.contains("t4-3"), "missing")
        // A hand-picked cut that loses a photo says so instead of filling the gap.
        let picks = ["t1-0", "t1-1", "t4-2", "t1-2", "t1-3", "t1-4"]
        let cut = M.planner(fixture).plan(source: .photos(picks), settings: MovieSettings())
        #expect(cut.photoIDs == ["t1-0", "t1-1", "t1-2", "t1-3", "t1-4"])
        #expect(cut.limitations.contains(.missing(1)))
    }

    @Test func mixedYearsKeepTheirOwnPeriod() {
        let fixture = F.mixedYears()
        let library = fixture.library
        let all = fixture.moments.flatMap(\.shots).map(\.id)
        let plan = M.planner(fixture).plan(source: .year(2025))
        #expect(plan.photoIDs.allSatisfy { testCalendar.component(.year, from: library.assets[$0]!.creationDate!) == 2025 })
        let everything = M.planner(fixture).plan(source: .photos(all), settings: MovieSettings())
        #expect(everything.periodLabel == "2025 – 2026")
        #expect(everything.scenes.last?.text?.title == "2025 – 2026")
        #expect(everything.scenes.contains { $0.role == .sectionOpener && $0.transition == .fadeThroughBlack })
    }

    @Test func tooLittleIsSaidPlainly() {
        let fixture = F.smallMoment()
        let three = M.planner(fixture).plan(source: .photos(["small-0", "small-1", "small-2"]), settings: MovieSettings())
        #expect(three.status == .insufficient(available: 3, required: 5))
        let none = M.planner(fixture).plan(source: .photos([]), settings: MovieSettings())
        #expect(none.status == .insufficient(available: 0, required: 5))
        #expect(none.scenes.isEmpty)
    }
}

@Suite("Memory Movie: edit rules")
struct MovieEditRuleTests {
    typealias F = IntelligenceFixture
    typealias M = MovieFixture

    private var plans: [MoviePlan] {
        let trip = M.fourDayTrip()
        let year = M.bigYear()
        var result: [MoviePlan] = []
        for style in MovieStyle.allCases {
            for aspect in MovieAspect.allCases {
                result.append(M.planner(trip).plan(source: .trip(F.tripID("Lycian Coast")), settings: MovieSettings(aspect: aspect, style: style)))
                result.append(M.planner(year).plan(source: .year(2026), settings: MovieSettings(aspect: aspect, length: .long, style: style)))
            }
        }
        return result
    }

    @Test func plansAreDeterministic() {
        let fixture = M.fourDayTrip()
        let a = M.planner(fixture).plan(source: .trip(F.tripID("Lycian Coast")))
        let b = M.planner(fixture).plan(source: .trip(F.tripID("Lycian Coast")))
        #expect(a == b)
    }

    @Test func noPhotoAppearsTwice() {
        for plan in plans {
            #expect(Set(plan.photoIDs).count == plan.photoIDs.count)
        }
    }

    @Test func transitionsAndMotionStayRestrained() {
        for plan in plans {
            #expect(plan.scenes.first?.transition == .fadeThroughBlack)
            for (index, scene) in plan.scenes.enumerated() {
                #expect((1.8...4.6).contains(scene.duration), "\(scene.duration)")
                if index > 0 {
                    #expect(scene.transitionDuration <= min(scene.duration, plan.scenes[index - 1].duration) * 0.45 + 1e-9)
                    let previous = plan.scenes[index - 1].motion
                    #expect(scene.motion == .still || scene.motion != previous, "no motion twice in a row")
                }
                if scene.framing == .fit { #expect(!scene.motion.isPan) }
            }
        }
    }

    @Test func styleAndShapeNeverChangeTheFacts() {
        let fixture = M.fourDayTrip()
        let planner = M.planner(fixture)
        let base = planner.plan(source: .trip(F.tripID("Lycian Coast")))
        for style in MovieStyle.allCases {
            for aspect in MovieAspect.allCases {
                let other = planner.plan(source: .trip(F.tripID("Lycian Coast")), settings: MovieSettings(aspect: aspect, style: style))
                #expect(other.photoIDs == base.photoIDs)
                #expect(other.title == base.title)
                #expect(other.periodLabel == base.periodLabel)
                #expect(other.scenes.map(\.text) == base.scenes.map(\.text))
            }
        }
    }

    @Test func everyWordIsFactual() {
        for plan in plans {
            for text in plan.scenes.compactMap(\.text) {
                for part in text.all {
                    #expect(FactualTextPolicy.isFactual(part), "\(part)")
                }
            }
        }
        let quiet = M.planner(M.fourDayTrip()).plan(source: .trip(F.tripID("Lycian Coast")), settings: MovieSettings(showsText: false))
        #expect(quiet.scenes.allSatisfy { $0.text == nil })
    }

    @Test func aVariationIsDifferentButStillTheSameMemories() {
        let fixture = M.fourDayTrip()
        let planner = M.planner(fixture)
        let first = planner.plan(source: .trip(F.tripID("Lycian Coast")))
        let second = planner.plan(source: .trip(F.tripID("Lycian Coast")), settings: MovieSettings(variation: 1))
        #expect(first.cover != second.cover)
        #expect(Set(first.photoIDs) == Set(second.photoIDs))
        #expect(planner.plan(source: .trip(F.tripID("Lycian Coast")), settings: MovieSettings(variation: 1)) == second)
    }

    @Test func diagnosticsHoldNoIdentifiers() {
        let fixture = M.fourDayTrip()
        let plan = M.planner(fixture).plan(source: .trip(F.tripID("Lycian Coast")))
        let line = plan.diagnosticsLine
        #expect(line.hasPrefix("movie_plan source=trip"))
        #expect(!line.contains("t1-") && !line.contains("Kaş") && !line.contains("Lycian") && !line.contains("2025"))
    }
}

@Suite("Memory Movie: timeline and geometry")
struct MovieTimelineTests {
    typealias F = IntelligenceFixture
    typealias M = MovieFixture

    private var plan: MoviePlan {
        M.planner(M.fourDayTrip()).plan(source: .trip(F.tripID("Lycian Coast")))
    }

    @Test func itFadesInAndOutOfBlack() {
        let timeline = MovieTimeline(plan: plan)
        #expect(timeline.frame(at: 0).blackOpacity > 0.99)
        #expect(timeline.frame(at: timeline.duration).blackOpacity > 0.95)
        #expect(timeline.frame(at: 2).blackOpacity == 0)
        #expect(timeline.frame(at: 2).layers.map(\.sceneIndex) == [0])
    }

    @Test func crossfadesOverlapAndCutsDoNot() {
        let plan = self.plan
        let timeline = MovieTimeline(plan: plan)
        let total = plan.scenes.map(\.duration).reduce(0, +)
        let overlaps = plan.scenes.dropFirst().filter { $0.transition == .crossfade }.map(\.transitionDuration).reduce(0, +)
        #expect(abs(timeline.duration - (total - overlaps)) < 1e-6)
        // In the middle of a crossfade both photos are on screen, the new one on top.
        if let index = plan.scenes.indices.dropFirst().first(where: { plan.scenes[$0].transition == .crossfade }) {
            let middle = timeline.starts[index] + plan.scenes[index].transitionDuration / 2
            let frame = timeline.frame(at: middle)
            #expect(frame.layers.map(\.sceneIndex) == [index - 1, index])
            #expect(frame.layers.last!.opacity > 0.2 && frame.layers.last!.opacity < 0.8)
        }
        // Every moment of the film shows a photo.
        var t = 0.0
        while t < timeline.duration {
            #expect(!timeline.frame(at: t).layers.isEmpty)
            t += 0.25
        }
    }

    @Test func wordsAppearAfterTheirPhoto() {
        let timeline = MovieTimeline(plan: plan)
        #expect(timeline.frame(at: 0.1).captions.isEmpty)
        #expect(timeline.frame(at: 2).captions.first?.text.title == "Lycian Coast")
        #expect(timeline.frame(at: timeline.duration - 0.5).captions.first?.text.title == plan.scenes.last?.text?.title)
        #expect(timeline.frame(at: timeline.duration - 0.5).captions.first?.text.detail == nil)
    }

    @Test func aFilledPhotoAlwaysCoversTheFrame() {
        for aspect in MovieAspect.allCases {
            let plan = M.planner(M.fourDayTrip()).plan(source: .trip(F.tripID("Lycian Coast")), settings: MovieSettings(aspect: aspect))
            let canvas = aspect.renderSize
            for scene in plan.scenes {
                for progress in stride(from: 0.0, through: 1.0, by: 0.1) {
                    let rect = MovieGeometry.imageRect(for: scene, canvas: canvas, progress: progress)
                    switch scene.framing {
                    case .fill:
                        #expect(rect.minX <= 0.001 && rect.minY <= 0.001 && rect.maxX >= canvas.width - 0.001 && rect.maxY >= canvas.height - 0.001, "\(scene.motion) \(progress)")
                        #expect(rect.width <= CropMath.fillRect(imageAspect: scene.imageAspect, frameSize: canvas).width * (1 + MovieGeometry.zoomAmount) + 0.01)
                    case .fit:
                        // The whole photo shows (allowing the gentle zoom's few percent).
                        #expect(rect.width <= canvas.width * 1.05 && rect.height <= canvas.height * 1.05)
                        #expect(abs(rect.width / rect.height - scene.imageAspect) < 0.01)
                    }
                }
            }
        }
    }

    @Test func loadSizesAreBoundedByTheFrame() {
        let plan = self.plan
        for scene in plan.scenes {
            let size = MovieGeometry.loadSize(for: scene, canvas: MovieAspect.portrait.renderSize)
            #expect(size.width <= 1920 * 2.2 && size.height <= 1920 * 1.2, "\(size)")
        }
    }
}

@Suite("Memory Movie: Premium and drafts")
struct MovieCommercialTests {
    @Test func movieExportIsPremiumAndNeverTheFreeCreation() {
        #expect(!PremiumCapability.memoryMovie.isCoveredByFreeCreation)
        let fresh = FreeCreationAllowance()
        #expect(PremiumPolicy.exportDecision(for: .memoryMovie, isPremium: false, allowance: fresh) == .requiresPremium)
        #expect(PremiumPolicy.exportDecision(for: .memoryMovie, isPremium: true, allowance: fresh) == .allowed)
        // The free creation's own rule is unchanged.
        #expect(PremiumPolicy.exportDecision(for: .collageExport, isPremium: false, allowance: fresh) == .allowedAsFreeCreation)
        var allowance = fresh
        let used = allowance.recordSuccessfulExport(of: .memoryMovie, decision: .allowed, at: Date())
        #expect(!used)
        #expect(allowance.isAvailable)
        #expect(PaywallEntryPoint.memoryMovie.capability == .memoryMovie)
        #expect(PaywallCopy(entry: .memoryMovie).context == "Keep this movie")
    }

    @Test func aMovieDraftKeepsItsStateNotItsPixels() throws {
        let state = MovieState(photoIDs: ["a", "b", "c", "d", "e"], cover: "c", settings: MovieSettings(aspect: .landscape, length: .short, style: .film, showsText: false, variation: 2), isUserCut: true)
        let creation = SavedCreation(kind: .movie, createdAt: Date(timeIntervalSince1970: 0), source: .month(MonthKey(year: 2026, month: 8)), movie: state)
        let data = try JSONEncoder().encode(creation)
        let decoded = try JSONDecoder().decode(SavedCreation.self, from: data)
        #expect(decoded.movie == state)
        #expect(decoded.photoIDs == ["a", "b", "c", "d", "e"])
        // Creations saved before movies existed still decode.
        let story = SavedCreation(kind: .story, createdAt: Date(timeIntervalSince1970: 0), source: .favorites)
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(story)) as! [String: Any]
        json.removeValue(forKey: "movie")
        let old = try JSONDecoder().decode(SavedCreation.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(old.movie == nil && old.kind == .story)
    }
}
