import Foundation
import Testing
@testable import ReliveCore

@Suite("Creation geometry")
struct CreationGeometryTests {
    @Test("Export sizes match each shape at 2160 px wide")
    func exportSizes() {
        #expect(CreationAspectRatio.square.exportPixelSize == (2160, 2160))
        #expect(CreationAspectRatio.portrait.exportPixelSize == (2160, 2700))
        #expect(CreationAspectRatio.story.exportPixelSize == (2160, 3840))
        for ratio in CreationAspectRatio.allCases {
            let size = ratio.designSize
            #expect(size.width == CreationAspectRatio.designWidth)
            #expect(abs(size.aspectRatio - ratio.widthOverHeight) < 0.001)
        }
    }

    @Test("A photo always covers its frame, and the crop stays inside the photo")
    func fillCoversFrame() {
        let frames = [CanvasSize(width: 300, height: 400), CanvasSize(width: 500, height: 200), CanvasSize(width: 250, height: 250)]
        for aspect in [0.5, 0.75, 1, 1.5, 3, -1, .nan] {
            for frame in frames {
                let rect = CropMath.fillRect(imageAspect: aspect, frameSize: frame)
                #expect(rect.minX <= 0.0001 && rect.minY <= 0.0001)
                #expect(rect.maxX >= frame.width - 0.0001 && rect.maxY >= frame.height - 0.0001)
                #expect(abs(rect.aspectRatio - CropMath.sanitizedAspect(aspect)) < 0.0001)
            }
        }
    }

    @Test("Tall photos in wide frames are cropped slightly above center")
    func focusBias() {
        let rect = CropMath.fillRect(imageAspect: 0.75, frameSize: CanvasSize(width: 400, height: 200))
        let hiddenAbove = -rect.minY
        let hiddenBelow = rect.maxY - 200
        #expect(hiddenAbove < hiddenBelow)
    }

    @Test("Crop loss is zero for matching shapes and grows with the mismatch")
    func cropLoss() {
        #expect(CropMath.cropLoss(imageAspect: 1.5, frameAspect: 1.5) == 0)
        #expect(CropMath.cropLoss(imageAspect: 0.75, frameAspect: 1.5) > CropMath.cropLoss(imageAspect: 1, frameAspect: 1.5))
    }

    @Test("Export requests are sized to the frame and capped for very large frames")
    func exportRequestSizing() {
        let normal = CreationImageSizing.exportPixelSize(forFrame: CanvasSize(width: 500, height: 400))
        #expect(normal == CanvasSize(width: 1000, height: 800))
        let huge = CreationImageSizing.exportPixelSize(forFrame: CanvasSize(width: 5000, height: 2500))
        #expect(huge.width <= CreationImageSizing.maximumExportSide && huge.height <= CreationImageSizing.maximumExportSide)
    }
}

@Suite("Collage layouts")
struct CollageLayoutTests {
    let engine = CollageLayoutEngine()

    static let shapeSets: [[Double]] = [
        [0.75, 0.75],
        [1.5, 1.5],
        [0.75, 1.5],
        [1, 0.75, 1.5],
        [0.75, 0.75, 0.75, 0.75],
        [1.5, 0.75, 1.33, 0.56, 1, 1.78],
        [3.5, 0.75, 1.5],
        Array(repeating: 0.75, count: 7),
        Array(repeating: 1.5, count: 9),
        (0..<12).map { $0.isMultiple(of: 2) ? 0.75 : 1.5 },
    ]

    @Test("Every style places every photo exactly once, inside the canvas, for 2–12 photos")
    func everyPhotoPlaced() {
        for style in CollageStyle.allCases {
            for ratio in CreationAspectRatio.allCases {
                for count in CollageLayoutEngine.photoRange {
                    let aspects = (0..<count).map { [0.75, 1.5, 1, 0.56][$0 % 4] }
                    for caption in [CollageCaptionSpec.none, CollageCaptionSpec(showsTitle: true, showsDetail: true)] {
                        let layout = engine.layout(photoAspects: aspects, style: style, canvas: ratio.designSize, caption: caption)
                        let canvas = LayoutRect(x: 0, y: 0, width: layout.canvas.width, height: layout.canvas.height)
                        #expect(layout.slots.count == count, "\(style) \(ratio) \(count)")
                        #expect(Set(layout.slots.map(\.photoIndex)) == Set(0..<count))
                        for slot in layout.slots {
                            #expect(slot.photoFrame.width > 20 && slot.photoFrame.height > 20, "\(style) \(ratio) \(count) too small")
                            #expect(canvas.contains(slot.frame.rotatedBounds(degrees: slot.rotation)), "\(style) \(ratio) \(count) outside")
                            #expect(slot.frame.contains(slot.photoFrame))
                        }
                    }
                }
            }
        }
    }

    @Test("Flat styles never overlap photos or the caption")
    func noOverlaps() {
        for style in [CollageStyle.minimal, .editorial, .grid, .film, .polaroid] {
            for ratio in CreationAspectRatio.allCases {
                for aspects in Self.shapeSets {
                    let layout = engine.layout(
                        photoAspects: aspects, style: style, canvas: ratio.designSize,
                        caption: CollageCaptionSpec(showsTitle: true, showsDetail: true)
                    )
                    let frames = layout.slots.map(\.frame)
                    for (i, a) in frames.enumerated() {
                        for b in frames[(i + 1)...] {
                            #expect(!a.overlaps(b), "\(style) \(ratio) \(aspects)")
                        }
                        if let caption = layout.caption {
                            #expect(!a.rotatedBounds(degrees: 0).overlaps(caption), "\(style) caption overlap")
                        }
                        #expect(!a.overlaps(layout.watermark), "\(style) watermark overlap")
                    }
                }
            }
        }
    }

    @Test("Minimal keeps every photo's own shape")
    func minimalNoCrop() {
        for aspects in Self.shapeSets {
            let layout = engine.layout(photoAspects: aspects, style: .minimal, canvas: CreationAspectRatio.portrait.designSize, caption: .none)
            for slot in layout.slots {
                let expected = min(2.4, max(0.5, aspects[slot.photoIndex]))
                #expect(abs(slot.photoFrame.aspectRatio - expected) < 0.01)
            }
        }
    }

    @Test("Grid chooses rows that fit portrait and landscape photos")
    func gridFitsOrientation() {
        let canvas = CreationAspectRatio.square.designSize
        // Two portraits sit side by side; two landscapes stack.
        let portraits = engine.layout(photoAspects: [0.75, 0.75], style: .grid, canvas: canvas, caption: .none)
        let landscapes = engine.layout(photoAspects: [1.5, 1.5], style: .grid, canvas: canvas, caption: .none)
        #expect(portraits.slots.allSatisfy { $0.photoFrame.aspectRatio < 1 })
        #expect(landscapes.slots.allSatisfy { $0.photoFrame.aspectRatio > 1 })
        // With more photos the slots still lean the photos' way.
        let average: (CollageLayout) -> Double = { layout in
            layout.slots.reduce(0) { $0 + $1.photoFrame.aspectRatio } / Double(layout.slots.count)
        }
        for count in 3...12 {
            let tall = engine.layout(photoAspects: Array(repeating: 0.75, count: count), style: .grid, canvas: canvas, caption: .none)
            let wide = engine.layout(photoAspects: Array(repeating: 1.5, count: count), style: .grid, canvas: canvas, caption: .none)
            #expect(average(tall) <= average(wide) + 1e-9, "\(count) photos")
        }
    }

    @Test("Editorial gives the lead photo the largest slot, shaped for it")
    func editorialLead() {
        for ratio in CreationAspectRatio.allCases {
            for aspects in Self.shapeSets {
                let layout = engine.layout(photoAspects: aspects, style: .editorial, canvas: ratio.designSize, caption: .none)
                let lead = layout.slot(forPhoto: 0)!.photoFrame.area
                #expect(layout.slots.allSatisfy { $0.photoFrame.area <= lead + 0.01 }, "\(ratio) \(aspects)")
            }
        }
        // A portrait lead on a square canvas goes in a tall column; a landscape lead goes across.
        let portraitLead = engine.layout(photoAspects: [0.75, 1, 1], style: .editorial, canvas: CreationAspectRatio.square.designSize, caption: .none)
        #expect(portraitLead.slot(forPhoto: 0)!.frame.aspectRatio < 1)
        let landscapeLead = engine.layout(photoAspects: [1.78, 1, 1], style: .editorial, canvas: CreationAspectRatio.portrait.designSize, caption: .none)
        #expect(landscapeLead.slot(forPhoto: 0)!.frame.aspectRatio > 1)
    }

    @Test("Film runs strips the way most photos were taken")
    func filmDirection() {
        let canvas = CreationAspectRatio.portrait.designSize
        let portraits = engine.layout(photoAspects: [0.75, 0.75, 0.75, 1.5], style: .film, canvas: canvas, caption: .none)
        #expect(portraits.filmStrips.allSatisfy { $0.isVertical })
        #expect(portraits.slots.allSatisfy { $0.photoFrame.aspectRatio < 1 })
        let landscapes = engine.layout(photoAspects: [1.5, 1.5, 0.75], style: .film, canvas: canvas, caption: .none)
        #expect(landscapes.filmStrips.allSatisfy { !$0.isVertical })
        #expect(landscapes.slots.allSatisfy { $0.photoFrame.aspectRatio > 1 })
        // Every frame sits on a strip.
        for slot in landscapes.slots {
            #expect(landscapes.filmStrips.contains { $0.frame.contains(slot.frame) })
        }
    }

    @Test("Polaroid prints match each photo's orientation")
    func polaroidWindows() {
        let layout = engine.layout(photoAspects: [0.75, 1.5, 1], style: .polaroid, canvas: CreationAspectRatio.square.designSize, caption: .none)
        let windows = (0..<3).map { layout.slot(forPhoto: $0)!.photoFrame.aspectRatio }
        #expect(windows[0] < 0.9)
        #expect(windows[1] > 1.2)
        #expect(abs(windows[2] - 1) < 0.01)
    }

    @Test("Scrapbook draws the lead photo last, on top")
    func scrapbookOrder() {
        let layout = engine.layout(photoAspects: [1, 1, 1, 1], style: .scrapbook, canvas: CreationAspectRatio.square.designSize, caption: .none)
        #expect(layout.slots.last?.photoIndex == 0)
        #expect(layout.slots.contains { $0.hasTape })
    }

    @Test("Layouts are deterministic")
    func deterministic() {
        for style in CollageStyle.allCases {
            let a = engine.layout(photoAspects: Self.shapeSets[5], style: style, canvas: CreationAspectRatio.story.designSize, caption: .none)
            let b = engine.layout(photoAspects: Self.shapeSets[5], style: style, canvas: CreationAspectRatio.story.designSize, caption: .none)
            #expect(a == b)
        }
    }

    @Test("Turning the caption off gives the photos more room")
    func captionReservesSpace() {
        let canvas = CreationAspectRatio.portrait.designSize
        for style in CollageStyle.allCases {
            let with = engine.layout(photoAspects: [0.75, 0.75, 1.5], style: style, canvas: canvas, caption: CollageCaptionSpec(showsTitle: true, showsDetail: true))
            let without = engine.layout(photoAspects: [0.75, 0.75, 1.5], style: style, canvas: canvas, caption: .none)
            #expect(with.caption != nil && without.caption == nil)
            let area: (CollageLayout) -> Double = { $0.slots.reduce(0) { $0 + $1.photoFrame.area } }
            #expect(area(without) >= area(with) - 0.01, "\(style)")
        }
    }

    @Test("Unknown photo sizes are treated as square instead of breaking the layout")
    func unknownSizes() {
        let layout = engine.layout(photoAspects: [0, .nan, -2], style: .grid, canvas: CreationAspectRatio.square.designSize, caption: .none)
        #expect(layout.slots.count == 3)
        #expect(layout.slots.allSatisfy { $0.photoFrame.area > 0 })
    }

    @Test("Linear partition keeps order and balances sums")
    func partition() {
        let groups = CollageLayoutEngine.partition([1, 1, 1, 1, 2, 2], into: 2)
        #expect(groups.flatMap { $0 } == [1, 1, 1, 1, 2, 2])
        #expect(groups.map { $0.reduce(0, +) } == [4, 4])
        #expect(CollageLayoutEngine.distribute(5, into: 2) == [2, 3])
    }
}

@Suite("Make it for me")
struct CollageAutoDesignerTests {
    let designer = CollageAutoDesigner()

    func photos(_ aspects: [Double]) -> [CollagePhotoInfo] {
        aspects.enumerated().map { index, aspect in
            CollagePhotoInfo(id: "p\(index)", aspectRatio: aspect, quality: index == 2 ? 0.9 : 0.5, date: date(2026, 5, 1, 10 + index))
        }
    }

    @Test("The best photo leads; the rest follow in the order they were taken")
    func order() {
        let ordered = designer.suggestedOrder(photos([1, 1, 1, 1]).reversed())
        #expect(ordered.map(\.id) == ["p2", "p0", "p1", "p3"])
    }

    @Test("Undated photos go last and ties resolve by identifier")
    func undatedLast() {
        let input = [
            CollagePhotoInfo(id: "b", aspectRatio: 1, quality: 0.5, date: nil),
            CollagePhotoInfo(id: "a", aspectRatio: 1, quality: 0.5, date: nil),
            CollagePhotoInfo(id: "c", aspectRatio: 1, quality: 0.5, date: date(2026, 1, 1)),
        ]
        #expect(designer.suggestedOrder(input).map(\.id) == ["c", "a", "b"])
    }

    @Test("Suggestions are deterministic and cover every style and shape")
    func deterministic() {
        let input = photos([0.75, 1.5, 0.75, 1, 1.33])
        let a = designer.suggestions(for: input, caption: CollageCaptionSpec(showsTitle: true, showsDetail: true))
        let b = designer.suggestions(for: input.reversed(), caption: CollageCaptionSpec(showsTitle: true, showsDetail: true))
        #expect(a == b)
        #expect(a.count == CollageStyle.allCases.count * CreationAspectRatio.allCases.count)
    }

    @Test("Pressing again offers a different style")
    func distinctStyles() {
        let suggestions = designer.distinctSuggestions(for: photos([0.75, 0.75, 1.5]), caption: .none)
        #expect(suggestions.count == 3)
        #expect(Set(suggestions.map(\.style)).count == 3)
    }

    @Test("Many photos favour an orderly grid; a few favour a looser layout")
    func countShapesChoice() {
        let many = designer.suggestions(for: photos(Array(repeating: 1.33, count: 12)), caption: .none)[0]
        #expect([CollageStyle.grid, .minimal, .film].contains(many.style))
        let few = designer.suggestions(for: photos([0.75, 0.75]), caption: .none)[0]
        #expect(few.style != .grid)
    }

    @Test("Two portraits are not squeezed into a story-shaped canvas side by side")
    func portraitsShape() {
        let best = designer.suggestions(for: photos([0.75, 0.75]), caption: .none)[0]
        let layout = CollageLayoutEngine().layout(photoAspects: [0.75, 0.75], style: best.style, canvas: best.aspectRatio.designSize, caption: .none)
        let coverage = layout.slots.reduce(0) { $0 + $1.photoFrame.area } / (layout.canvas.width * layout.canvas.height)
        #expect(coverage > 0.35)
    }
}
