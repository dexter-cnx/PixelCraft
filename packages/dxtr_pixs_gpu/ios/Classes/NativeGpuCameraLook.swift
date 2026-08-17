import Foundation

/// PF2 native camera-look control-plane contract.
///
/// Camera frames never cross Flutter's MethodChannel and this state never
/// becomes final-render authority; Rust remains authoritative for saved pixels.
struct NativeGpuCameraLook {
  static let supportedCreativeFilters: Set<String> = [
    "grayscale",
    "invert",
    "vintage",
    "oceanic",
    "lofi",
    "dramatic",
    "golden",
    "pastel_pink",
  ]

  let filmProfileId: String
  let filmStrength: Float
  let creativeFilterId: String
  let creativeFilterStrength: Float
  let exposure: Float
  let temperature: Float
  let tint: Float
  let brightness: Float
  let contrast: Float
  let saturation: Float
  let vignette: Float

  init(arguments: [String: Any]) throws {
    let creative = arguments["creativeFilterId"] as? String ?? ""
    guard creative.isEmpty || Self.supportedCreativeFilters.contains(creative) else {
      throw Self.error("Unsupported camera creative filter: \(creative)")
    }

    filmProfileId = arguments["filmProfileId"] as? String ?? ""
    filmStrength = Self.clamp(Self.number(arguments, "filmStrength", fallback: 0), 0, 1)
    creativeFilterId = creative
    creativeFilterStrength = Self.clamp(
      Self.number(arguments, "creativeFilterStrength", fallback: 0),
      0,
      1
    )
    exposure = Self.clamp(Self.number(arguments, "exposure", fallback: 0), -2, 2)
    temperature = Self.clamp(Self.number(arguments, "temperature", fallback: 0), -1, 1)
    tint = Self.clamp(Self.number(arguments, "tint", fallback: 0), -1, 1)
    brightness = Self.clamp(Self.number(arguments, "brightness", fallback: 1), 0, 2)
    contrast = Self.clamp(Self.number(arguments, "contrast", fallback: 1), 0, 2)
    saturation = Self.clamp(Self.number(arguments, "saturation", fallback: 1), 0, 2)
    vignette = Self.clamp(Self.number(arguments, "vignette", fallback: 0), -1, 1)
  }

  var hasFilm: Bool {
    !filmProfileId.isEmpty && filmStrength > 0
  }

  var hasCreative: Bool {
    !creativeFilterId.isEmpty && creativeFilterStrength > 0
  }

  var hasAdjustments: Bool {
    exposure != 0 || temperature != 0 || tint != 0 ||
      brightness != 1 || contrast != 1 || saturation != 1 || vignette != 0
  }

  var isNeutral: Bool {
    !hasFilm && !hasCreative && !hasAdjustments
  }

  var creativeLutAssetId: String? {
    switch creativeFilterId {
    case "vintage": return "creative_vintage"
    case "oceanic": return "creative_oceanic"
    case "lofi": return "creative_lofi"
    case "dramatic": return "creative_dramatic"
    case "golden": return "creative_golden"
    case "pastel_pink": return "creative_pastel_pink"
    default: return nil
    }
  }

  private static func number(
    _ arguments: [String: Any],
    _ key: String,
    fallback: Float
  ) -> Float {
    (arguments[key] as? NSNumber)?.floatValue ?? fallback
  }

  private static func clamp(_ value: Float, _ lower: Float, _ upper: Float) -> Float {
    max(lower, min(upper, value))
  }

  private static func error(_ message: String) -> NSError {
    NSError(
      domain: "PixelCraftGpu",
      code: 3201,
      userInfo: [NSLocalizedDescriptionKey: message]
    )
  }
}
