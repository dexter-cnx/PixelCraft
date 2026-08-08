import Foundation
import Metal

final class MetalFilmLutLoader {
  static let lutSize = 33
  private static let tilesPerRow = 6
  private static let atlasSize = lutSize * tilesPerRow

  private let device: MTLDevice

  init(device: MTLDevice) {
    self.device = device
  }

  func load(profileId: String) throws -> MTLTexture {
    guard let url = Bundle.main.url(
      forResource: profileId,
      withExtension: "rgba8",
      subdirectory: "gpu_luts"
    ) else {
      throw NSError(
        domain: "PixelCraftGpu",
        code: 1001,
        userInfo: [NSLocalizedDescriptionKey: "Missing Film LUT asset: \(profileId)"]
      )
    }

    let atlas = try Data(contentsOf: url)
    let expected = Self.atlasSize * Self.atlasSize * 4
    guard atlas.count == expected else {
      throw NSError(
        domain: "PixelCraftGpu",
        code: 1002,
        userInfo: [NSLocalizedDescriptionKey: "Unexpected Film LUT byte count for \(profileId): \(atlas.count)"]
      )
    }

    var volume = Data(count: Self.lutSize * Self.lutSize * Self.lutSize * 4)
    atlas.withUnsafeBytes { atlasRaw in
      volume.withUnsafeMutableBytes { volumeRaw in
        guard
          let atlasBytes = atlasRaw.bindMemory(to: UInt8.self).baseAddress,
          let volumeBytes = volumeRaw.bindMemory(to: UInt8.self).baseAddress
        else { return }

        for blue in 0..<Self.lutSize {
          let tileX = blue % Self.tilesPerRow
          let tileY = blue / Self.tilesPerRow
          for green in 0..<Self.lutSize {
            for red in 0..<Self.lutSize {
              let atlasX = tileX * Self.lutSize + red
              let atlasY = tileY * Self.lutSize + green
              let atlasOffset = (atlasY * Self.atlasSize + atlasX) * 4
              let volumeOffset = (red + Self.lutSize * (green + Self.lutSize * blue)) * 4
              volumeBytes[volumeOffset] = atlasBytes[atlasOffset]
              volumeBytes[volumeOffset + 1] = atlasBytes[atlasOffset + 1]
              volumeBytes[volumeOffset + 2] = atlasBytes[atlasOffset + 2]
              volumeBytes[volumeOffset + 3] = 255
            }
          }
        }
      }
    }

    return try makeTexture(bytes: volume)
  }

  func makeIdentity() throws -> MTLTexture {
    var volume = Data(count: Self.lutSize * Self.lutSize * Self.lutSize * 4)
    volume.withUnsafeMutableBytes { raw in
      guard let bytes = raw.bindMemory(to: UInt8.self).baseAddress else { return }
      for blue in 0..<Self.lutSize {
        for green in 0..<Self.lutSize {
          for red in 0..<Self.lutSize {
            let offset = (red + Self.lutSize * (green + Self.lutSize * blue)) * 4
            bytes[offset] = UInt8(round(Double(red) / Double(Self.lutSize - 1) * 255.0))
            bytes[offset + 1] = UInt8(round(Double(green) / Double(Self.lutSize - 1) * 255.0))
            bytes[offset + 2] = UInt8(round(Double(blue) / Double(Self.lutSize - 1) * 255.0))
            bytes[offset + 3] = 255
          }
        }
      }
    }
    return try makeTexture(bytes: volume)
  }

  static func canonicalAssetsAvailable() -> Bool {
    let profileIds = [
      "provia_inspired",
      "velvia_inspired",
      "astia_inspired",
      "e100_inspired",
      "ektar_inspired",
      "chrome64_inspired",
    ]
    return profileIds.allSatisfy {
      Bundle.main.url(forResource: $0, withExtension: "rgba8", subdirectory: "gpu_luts") != nil
    }
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
      throw NSError(
        domain: "PixelCraftGpu",
        code: 1003,
        userInfo: [NSLocalizedDescriptionKey: "Unable to allocate 33^3 Metal LUT texture"]
      )
    }

    bytes.withUnsafeBytes { raw in
      guard let base = raw.baseAddress else { return }
      texture.replace(
        region: MTLRegionMake3D(0, 0, 0, Self.lutSize, Self.lutSize, Self.lutSize),
        mipmapLevel: 0,
        withBytes: base,
        bytesPerRow: Self.lutSize * 4,
        bytesPerImage: Self.lutSize * Self.lutSize * 4
      )
    }
    return texture
  }
}
