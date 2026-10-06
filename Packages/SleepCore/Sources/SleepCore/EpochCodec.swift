import Foundation

/// Packs a night's epochs into a compact binary blob (~23 bytes per epoch, ~23 KB per night)
/// so SwiftData stores one value per night instead of a row per epoch.
public enum EpochCodec {
    static let magic: [UInt8] = [0x53, 0x4C, 0x45, 0x31] // "SLE1"
    static let recordSize = 23

    public static func encode(_ epochs: [EpochFeatures]) -> Data {
        let sorted = epochs.sorted { $0.start < $1.start }
        var out = Data(magic)
        let base = sorted.first?.start.timeIntervalSince1970 ?? 0
        append(&out, base.bitPattern)
        append(&out, UInt32(sorted.count))
        for e in sorted {
            append(&out, UInt32(clamping: Int64((e.start.timeIntervalSince1970 - base).rounded())))
            append(&out, packDb(e.meanDb))
            append(&out, packDb(e.maxDb))
            append(&out, packDb(e.noiseFloorDb))
            append(&out, UInt16(clamping: e.transientCount))
            append(&out, UInt16(clamping: e.activeFrames))
            append(&out, UInt16(clamping: e.totalFrames))
            append(&out, UInt16(clamping: Int(e.spectralCentroid.rounded())))
            append(&out, UInt16(clamping: Int((e.spectralFlux * 1000).rounded())))
            append(&out, UInt16(clamping: Int((e.zeroCrossingRate * 10_000).rounded())))
            out.append(e.soundPlaying ? 1 : 0)
        }
        return out
    }

    public static func decode(_ data: Data) -> [EpochFeatures] {
        let bytes = [UInt8](data)
        guard bytes.count >= 16, Array(bytes[0..<4]) == magic else { return [] }
        var cursor = 4
        let base = Double(bitPattern: read(bytes, &cursor, as: UInt64.self))
        let count = Int(read(bytes, &cursor, as: UInt32.self))
        guard bytes.count >= cursor + count * recordSize else { return [] }
        var result: [EpochFeatures] = []
        result.reserveCapacity(count)
        for _ in 0..<count {
            let offset = Double(read(bytes, &cursor, as: UInt32.self))
            let mean = unpackDb(read(bytes, &cursor, as: Int16.self))
            let maxDb = unpackDb(read(bytes, &cursor, as: Int16.self))
            let floor = unpackDb(read(bytes, &cursor, as: Int16.self))
            let transients = Int(read(bytes, &cursor, as: UInt16.self))
            let active = Int(read(bytes, &cursor, as: UInt16.self))
            let total = Int(read(bytes, &cursor, as: UInt16.self))
            let centroid = Float(read(bytes, &cursor, as: UInt16.self))
            let flux = Float(read(bytes, &cursor, as: UInt16.self)) / 1000
            let zcr = Float(read(bytes, &cursor, as: UInt16.self)) / 10_000
            let playing = bytes[cursor] != 0
            cursor += 1
            result.append(EpochFeatures(
                start: Date(timeIntervalSince1970: base + offset), meanDb: mean, maxDb: maxDb,
                noiseFloorDb: floor, transientCount: transients, activeFrames: active, totalFrames: total,
                spectralCentroid: centroid, spectralFlux: flux, zeroCrossingRate: zcr, soundPlaying: playing
            ))
        }
        return result
    }

    static func packDb(_ db: Float) -> Int16 {
        Int16(clamping: Int((db * 100).rounded()))
    }

    static func unpackDb(_ v: Int16) -> Float {
        Float(v) / 100
    }

    static func append<T: FixedWidthInteger>(_ data: inout Data, _ value: T) {
        var le = value.littleEndian
        withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
    }

    static func read<T: FixedWidthInteger>(_ bytes: [UInt8], _ cursor: inout Int, as: T.Type) -> T {
        var value: T = 0
        for i in 0..<MemoryLayout<T>.size {
            value |= T(truncatingIfNeeded: bytes[cursor + i]) << (8 * i)
        }
        cursor += MemoryLayout<T>.size
        return value
    }
}
