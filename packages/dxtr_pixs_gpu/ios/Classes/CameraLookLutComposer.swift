import Foundation
import Metal

/// PF2 control-rate LUT composer for the iOS live camera path.
///
/// Composition happens only when CameraLook changes. The 60 fps Metal renderer
/// continues sampling a single 33^3 LUT texture per frame. Saved pixels remain
/// Rust-authoritative.
///
/// Canonical order: Adjust -> Film -> Creative.
final class CameraLookLutComposer {
  private static let lutSize = 33
  private static let tiles = 6
  private static let atlasSize = lutSize * tiles
  private static let midpoint: Float = 128.0 / 255.0

  private let device: MTLDevice

  init(device: MTLDevice) {
    self.device = device
  }

  func compose(_ look: NativeGpuCameraLook) throws -> MTLTexture {
    let film = look.hasFilm ? try loadAtlas(look.filmProfileId) : nil
    let creativeAsset = look.creativeLutAssetId
    let creative = look.hasCreative && creativeAsset != nil
      ? try loadAtlas(creativeAsset!)
      : nil

    var volume = Data(count: Self.lutSize * Self.lutSize * Self.lutSize * 4)
    volume.withUnsafeMutableBytes { raw in
      guard let bytes = raw.bindMemory(to: UInt8.self).baseAddress else { return }
      for blue in 0..<Self.lutSize {
        for green in 0..<Self.lutSize {
          for red in 0..<Self.lutSize {
            var color = SIMD3<Float>(
              Float(red) / Float(Self.lutSize - 1),
              Float(green) / Float(Self.lutSize - 1),
              Float(blue) / Float(Self.lutSize - 1)
            )

            color = Self.applyAdjustments(color, look: look)

            if let film {
              let effected = Self.sampleAtlas(film, color: color)
              color = Self.mix(color, effected, amount: look.filmStrength)
            }

            if look.hasCreative {
              if look.creativeFilterId == "grayscale" || look.creativeFilterId == "invert" {
                color = Self.applyExactCreative(
                  color,
                  filterId: look.creativeFilterId,
                  strength: look.creativeFilterStrength
                )
              } else if let creative {
                let effected = Self.sampleAtlas(creative, color: color)
                color = Self.mix(color, effected, amount: look.creativeFilterStrength)
              }
            }

            let offset = (red + Self.lutSize * (green + Self.lutSize * blue)) * 4
            bytes[offset] = Self.channelByte(color.x)
            bytes[offset + 1] = Self.channelByte(color.y)
            bytes[offset + 2] = Self.channelByte(color.z)
            bytes[offset + 3] = 255
          }
        }
      }
    }

    return try makeTexture(bytes: volume)
  }

  private func loadAtlas(_ assetId: String) throws -> Data {
    guard let url = Bundle.main.url(
      forResource: assetId,
      withExtension: "rgba8",
      subdirectory: "gpu_luts"
    ) else {
      throw Self.error("Missing camera look LUT asset: \(assetId)")
    }
    let data = try Data(contentsOf: url)
    let expected = Self.atlasSize * Self.atlasSize * 4
    guard data.count == expected else {
      throw Self.error("Unexpected camera look LUT byte count for \(assetId): \(data.count)")
    }
    return data
  }

  private func makeTexture(bytes: Data) throws -> MTLTexture {
    let descriptor = MTLTextureDescriptor()
    descriptor.textureType = .type3D
    descriptor.pixelFormat = .rgba8Unorm
    descriptor.width = Self.lutSize
    descriptor.height = Self.lutSize
    descriptor.depth = Self.lutSize
    descriptor.mipmapLevelCount = 1
    descriptor.usage = [.shaderRead]
    descriptor.storageMode = .shared

    guard let texture = device.makeTexture(descriptor: descriptor) else {
      throw Self.error("Unable to allocate composed 33^3 camera look LUT")
    }

    bytes.withUnsafeBytes { raw in
      guard let base = raw.baseAddress else { return }
      texture.replace(
        region: MTLRegionMake3D(0, 0, 0, Self.lutSize, Self.lutSize, Self.lutSize),
        mipmapLevel: 0,
        slice: 0,
        withBytes: base,
        bytesPerRow: Self.lutSize * 4,
        bytesPerImage: Self.lutSize * Self.lutSize * 4
      )
    }
    return texture
  }

  private static func applyAdjustments(
    _ source: SIMD3<Float>,
    look: NativeGpuCameraLook
  ) -> SIMD3<Float> {
    var color = clamp01(source + SIMD3<Float>(repeating: look.brightness - 1))
    color = clamp01((color - SIMD3<Float>(repeating: midpoint)) * look.contrast + SIMD3<Float>(repeating: midpoint))
    let luminance = color.x * 0.2126 + color.y * 0.7152 + color.z * 0.0722
    color = clamp01(SIMD3<Float>(repeating: luminance) + (color - SIMD3<Float>(repeating: luminance)) * look.saturation)
    return color
  }

  /// Mirrors the existing editor creative kernel's rounded u8 arithmetic.
  private static func applyExactCreative(
    _ source: SIMD3<Float>,
    filterId: String,
    strength: Float
  ) -> SIMD3<Float> {
    let source8 = SIMD3<Int>(
      Int(round(clamp01(source.x) * 255)),
      Int(round(clamp01(source.y) * 255)),
      Int(round(clamp01(source.z) * 255))
    )
    let effected8: SIMD3<Int>
    switch filterId {
    case "grayscale":
      let average = (source8.x + source8.y + source8.z) / 3
      effected8 = SIMD3<Int>(repeating: average)
    case "invert":
      effected8 = SIMD3<Int>(repeating: 255) - source8
    default:
      return source
    }

    let t = max(0, min(1, strength))
    func blended(_ s: Int, _ e: Int) -> Float {
      Float(max(0, min(255, Int(round(Float(s) + Float(e - s) * t))))) / 255
    }
    return SIMD3<Float>(
      blended(source8.x, effected8.x),
      blended(source8.y, effected8.y),
      blended(source8.z, effected8.z)
    )
  }

  private static func sampleAtlas(_ atlas: Data, color: SIMD3<Float>) -> SIMD3<Float> {
    let scaled = clamp01(color) * Float(lutSize - 1)
    let r0 = Int(floor(scaled.x))
    let g0 = Int(floor(scaled.y))
    let b0 = Int(floor(scaled.z))
    let r1 = min(r0 + 1, lutSize - 1)
    let g1 = min(g0 + 1, lutSize - 1)
    let b1 = min(b0 + 1, lutSize - 1)
    let rf = scaled.x - Float(r0)
    let gf = scaled.y - Float(g0)
    let bf = scaled.z - Float(b0)

    func texel(_ red: Int, _ green: Int, _ blue: Int) -> SIMD3<Float> {
      let tileX = blue % tiles
      let tileY = blue / tiles
      let x = tileX * lutSize + red
      let y = tileY * lutSize + green
      let offset = (y * atlasSize + x) * 4
      return atlas.withUnsafeBytes { raw in
        let bytes = raw.bindMemory(to: UInt8.self)
        return SIMD3<Float>(
          Float(bytes[offset]) / 255,
          Float(bytes[offset + 1]) / 255,
          Float(bytes[offset + 2]) / 255
        )
      }
    }

    func slice(_ blue: Int) -> SIMD3<Float> {
      let c00 = texel(r0, g0, blue)
      let c10 = texel(r1, g0, blue)
      let c01 = texel(r0, g1, blue)
      let c11 = texel(r1, g1, blue)
      let top = c00 + (c10 - c00) * rf
      let bottom = c01 + (c11 - c01) * rf
      return top + (bottom - top) * gf
    }

    let low = slice(b0)
    let high = slice(b1)
    return low + (high - low) * bf
  }

  private static func mix(
    _ source: SIMD3<Float>,
    _ effected: SIMD3<Float>,
    amount: Float
  ) -> SIMD3<Float> {
    let t = max(0, min(1, amount))
    return clamp01(source + (effected - source) * t)
  }

  private static func clamp01(_ value: Float) -> Float {
    max(0, min(1, value))
  }

  private static func clamp01(_ value: SIMD3<Float>) -> SIMD3<Float> {
    SIMD3<Float>(clamp01(value.x), clamp01(value.y), clamp01(value.z))
  }

  private static func channelByte(_ value: Float) -> UInt8 {
    UInt8(max(0, min(255, Int(round(clamp01(value) * 255)))))
  }

  private static func error(_ message: String) -> NSError {
    NSError(
      domain: "PixelCraftGpuCameraLook",
      code: 5001,
      userInfo: [NSLocalizedDescriptionKey: message]
    )
  }
}
