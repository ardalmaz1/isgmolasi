import Foundation

/// The catalog that ships inside the app, so Trending Now works offline and on first launch.
///
/// It is the same JSON format a remote catalog uses and goes through the same parser and
/// validation. All trends are original Relive interpretations with generic names — no other
/// company's templates, artwork or trademarks.
public enum StarterTrendCatalog {
    public static let json = #"""
    {
      "schemaVersion": 1,
      "revision": 1,
      "trends": [
        {
          "id": "bw-editorial",
          "name": "B&W Editorial",
          "summary": "A cinematic black-and-white portrait of the two of you.",
          "detail": "Deep blacks, soft grain and a clean white border, like a print from a magazine shoot.",
          "execution": "local",
          "recipe": { "id": "bw-editorial", "version": 1 },
          "photos": { "minimum": 1, "maximum": 2 },
          "aspectRatios": ["portrait"],
          "guidance": ["Faces clearly visible.", "Good light makes the blacks richer."],
          "badge": "trending",
          "priority": 100,
          "privacy": "onDevice",
          "tier": "free"
        },
        {
          "id": "film-couple",
          "name": "Film Couple",
          "summary": "Warm film colour, soft grain and the real date in the corner.",
          "detail": "Your photo as if it came back from the lab: warm tones, gentle fade, and the day it was taken stamped in orange.",
          "execution": "local",
          "recipe": { "id": "film-couple", "version": 1 },
          "photos": { "minimum": 1, "maximum": 1 },
          "aspectRatios": ["portrait"],
          "guidance": ["Daylight photos work best."],
          "badge": "new",
          "priority": 90,
          "privacy": "onDevice",
          "tier": "free"
        },
        {
          "id": "photo-booth-strip",
          "name": "Photo Booth Strip",
          "summary": "Your photos as one strip from the booth at the end of the night.",
          "detail": "Three or four frames stacked on a paper strip, in black and white or colour.",
          "execution": "template",
          "recipe": { "id": "photo-booth", "version": 1 },
          "photos": { "minimum": 3, "maximum": 4 },
          "aspectRatios": ["story"],
          "guidance": ["Photos taken close together tell the best strip.", "Faces clearly visible."],
          "priority": 80,
          "privacy": "onDevice",
          "tier": "free"
        },
        {
          "id": "magazine-cover",
          "name": "Magazine Cover",
          "summary": "One photo as the cover of a magazine about the two of you.",
          "detail": "A bold masthead, your photo full bleed, and cover lines taken from the photo's real place and date.",
          "execution": "template",
          "recipe": { "id": "magazine-cover", "version": 1 },
          "photos": { "minimum": 1, "maximum": 1 },
          "aspectRatios": ["portrait"],
          "guidance": ["Portrait photos with space above your heads work best."],
          "badge": "new",
          "priority": 70,
          "privacy": "onDevice",
          "tier": "pro"
        },
        {
          "id": "cinematic-poster",
          "name": "Cinematic Poster",
          "summary": "A widescreen still from your own photo, with credits.",
          "detail": "Your photo framed like a film still, with the place as the title and your names in the credits.",
          "execution": "template",
          "recipe": { "id": "cinematic-poster", "version": 1 },
          "photos": { "minimum": 1, "maximum": 1 },
          "aspectRatios": ["story"],
          "guidance": ["Landscape photos fill the frame best."],
          "priority": 60,
          "privacy": "onDevice",
          "tier": "pro"
        },
        {
          "id": "golden-hour-portrait",
          "name": "Golden Hour Portrait",
          "summary": "A new portrait of you two in warm evening light.",
          "detail": "An AI-made portrait from two of your photos. It needs the photos you choose to be processed by an AI provider.",
          "execution": "ai",
          "recipe": { "id": "golden-hour", "version": 1 },
          "photos": { "minimum": 2, "maximum": 2 },
          "aspectRatios": ["portrait"],
          "guidance": ["One clear photo of each of you."],
          "priority": 10,
          "privacy": "aiProvider",
          "tier": "pro"
        }
      ]
    }
    """#

    /// The parsed starter catalog. Validated by tests; an empty catalog if it ever failed to parse.
    public static var catalog: TrendCatalog {
        switch TrendCatalogParser.parse(Data(json.utf8)) {
        case .success(let parsed): parsed.catalog
        case .failure: TrendCatalog(revision: 0, trends: [])
        }
    }
}
