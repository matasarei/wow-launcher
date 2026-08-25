// wow-client-fonts — extract the client's own locale fonts from its MPQ
// archive and add the CP1251 input remap. Native replacement for the former
// python tool (mpyq + fontTools): no Python, no pip, no Xcode CLT needed at
// run time — just the macOS zlib/bzip2 dylibs.
//
// Usage:
//   wow-client-fonts <game-dir | locale-xxXX.MPQ> <out-dir>
//       Reads Data/<locale>/locale-<locale>.MPQ (or the given archive), extracts FRIZQT__.TTF,
//       ARIALN.TTF, MORPHEUS.TTF, SKURRI.TTF, adds the remap, writes the four
//       files into <out-dir> (created). All-or-nothing: exit 1 and write
//       nothing unless all four fonts come out (e.g. enUS fonts have no
//       Cyrillic glyphs). Reasons go to stderr.
//   wow-client-fonts check <font.ttf>...
//       Prints "<file>: remapped" / "<file>: not remapped" per font; exit 0
//       only when every font carries the remap. Used by verify and the tests.
//
// The remap: the ANSI client inserts typed CP1251 bytes into its UTF-8 edit
// boxes as Latin-1 codepoints once the keyboard layout has been toggled
// (winemac.drv never delivers WM_INPUTLANGCHANGE), so the fonts render those
// positions with the Cyrillic glyphs the bytes stand for: U+00C0–U+00FF →
// А–я, Ё/ё at U+00A8/U+00B8, and CP1251's 0xA0–0xBF letters (Ukrainian,
// Belarusian, Serbian, №). Proper Unicode Cyrillic keeps rendering normally.

import Foundation

// MARK: - CP1251 → Unicode remap (Latin-1 codepoint → Cyrillic codepoint)

let REMAP: [UInt32: UInt32] = {
    var m: [UInt32: UInt32] = [:]
    for i in 0..<0x40 { m[0xC0 + UInt32(i)] = 0x410 + UInt32(i) }   // А..я
    let upper: [UInt32: UInt32] = [
        0xA1: 0x40E, 0xA2: 0x45E,   // Ў ў
        0xA3: 0x408,                // Ј
        0xA5: 0x490,                // Ґ
        0xA8: 0x401,                // Ё
        0xAA: 0x404,                // Є
        0xAF: 0x407,                // Ї
        0xB2: 0x406, 0xB3: 0x456,   // І і
        0xB4: 0x491,                // ґ
        0xB8: 0x451,                // ё
        0xB9: 0x2116,               // №
        0xBA: 0x454,                // є
        0xBC: 0x458,                // ј
        0xBD: 0x405, 0xBE: 0x455,   // Ѕ ѕ
        0xBF: 0x457,                // ї
    ]
    m.merge(upper) { a, _ in a }
    return m
}()

let WANTED: [(mpq: String, out: String)] = [
    ("Fonts\\FRIZQT__.TTF", "FRIZQT__.TTF"),
    ("Fonts\\ARIALN.TTF",   "ARIALN.TTF"),
    ("Fonts\\MORPHEUS.TTF", "MORPHEUS.TTF"),
    ("Fonts\\SKURRI.TTF",   "skurri.ttf"),
]

// MARK: - helpers

struct ToolError: Error, CustomStringConvertible {
    let description: String
    init(_ s: String) { description = s }
}

func fail(_ msg: String) -> Never {
    FileHandle.standardError.write("wow-client-fonts: \(msg)\n".data(using: .utf8)!)
    exit(1)
}

@inline(__always) func be16(_ b: [UInt8], _ o: Int) -> Int { Int(b[o]) << 8 | Int(b[o + 1]) }
@inline(__always) func be32(_ b: [UInt8], _ o: Int) -> UInt32 {
    UInt32(b[o]) << 24 | UInt32(b[o + 1]) << 16 | UInt32(b[o + 2]) << 8 | UInt32(b[o + 3])
}
@inline(__always) func le16(_ b: [UInt8], _ o: Int) -> Int { Int(b[o]) | Int(b[o + 1]) << 8 }
@inline(__always) func le32(_ b: [UInt8], _ o: Int) -> UInt32 {
    UInt32(b[o]) | UInt32(b[o + 1]) << 8 | UInt32(b[o + 2]) << 16 | UInt32(b[o + 3]) << 24
}
extension Array where Element == UInt8 {
    mutating func put16(_ v: Int) { append(UInt8((v >> 8) & 0xFF)); append(UInt8(v & 0xFF)) }
    mutating func put32(_ v: UInt32) {
        append(UInt8(v >> 24)); append(UInt8((v >> 16) & 0xFF)); append(UInt8((v >> 8) & 0xFF)); append(UInt8(v & 0xFF))
    }
    mutating func pad4() { while count % 4 != 0 { append(0) } }
}

// MARK: - decompression via the system dylibs (no headers/modules needed)

typealias ZUncompress = @convention(c) (UnsafeMutablePointer<UInt8>?, UnsafeMutablePointer<UInt>?, UnsafePointer<UInt8>?, UInt) -> Int32
typealias BZDecompress = @convention(c) (UnsafeMutablePointer<CChar>?, UnsafeMutablePointer<UInt32>?, UnsafeMutablePointer<CChar>?, UInt32, Int32, Int32) -> Int32

func loadSymbol(_ lib: String, _ name: String) -> UnsafeMutableRawPointer? {
    guard let h = dlopen(lib, RTLD_NOW) else { return nil }
    return dlsym(h, name)
}

func zlibInflate(_ src: [UInt8], expected: Int) throws -> [UInt8] {
    guard let sym = loadSymbol("/usr/lib/libz.1.dylib", "uncompress") else { throw ToolError("libz not available") }
    let fn = unsafeBitCast(sym, to: ZUncompress.self)
    var out = [UInt8](repeating: 0, count: expected)
    var outLen = UInt(expected)
    let rc = out.withUnsafeMutableBufferPointer { o in
        src.withUnsafeBufferPointer { s in fn(o.baseAddress, &outLen, s.baseAddress, UInt(src.count)) }
    }
    guard rc == 0, Int(outLen) == expected else { throw ToolError("zlib sector decode failed (rc \(rc))") }
    return out
}

func bzip2Inflate(_ src: [UInt8], expected: Int) throws -> [UInt8] {
    guard let sym = loadSymbol("/usr/lib/libbz2.1.0.dylib", "BZ2_bzBuffToBuffDecompress") else { throw ToolError("libbz2 not available") }
    let fn = unsafeBitCast(sym, to: BZDecompress.self)
    var out = [UInt8](repeating: 0, count: expected)
    var outLen = UInt32(expected)
    var input = src
    let rc = out.withUnsafeMutableBufferPointer { o in
        input.withUnsafeMutableBufferPointer { s in
            fn(UnsafeMutableRawPointer(o.baseAddress!).assumingMemoryBound(to: CChar.self), &outLen,
               UnsafeMutableRawPointer(s.baseAddress!).assumingMemoryBound(to: CChar.self), UInt32(src.count), 0, 0)
        }
    }
    guard rc == 0, Int(outLen) == expected else { throw ToolError("bzip2 sector decode failed (rc \(rc))") }
    return out
}

// MARK: - MPQ reader (the subset WoW locale archives use: v1/v2 header,
// encrypted hash/block tables, zlib/bzip2 multi-sector files; no file
// encryption, no PKWARE implode — the same subset mpyq supports)

let MPQ_FILE_IMPLODE:     UInt32 = 0x00000100
let MPQ_FILE_COMPRESS:    UInt32 = 0x00000200
let MPQ_FILE_ENCRYPTED:   UInt32 = 0x00010000
let MPQ_FILE_SINGLE_UNIT: UInt32 = 0x01000000
let MPQ_FILE_SECTOR_CRC:  UInt32 = 0x04000000
let MPQ_FILE_EXISTS:      UInt32 = 0x80000000

let cryptTable: [UInt32] = {
    var t = [UInt32](repeating: 0, count: 0x500)
    var seed: UInt32 = 0x00100001
    for i in 0..<0x100 {
        var j = i
        for _ in 0..<5 {
            seed = (seed &* 125 &+ 3) % 0x2AAAAB
            let a = (seed & 0xFFFF) << 16
            seed = (seed &* 125 &+ 3) % 0x2AAAAB
            let b = seed & 0xFFFF
            t[j] = a | b
            j += 0x100
        }
    }
    return t
}()

func mpqHash(_ name: String, _ type: UInt32) -> UInt32 {
    var s1: UInt32 = 0x7FED7FED, s2: UInt32 = 0xEEEEEEEE
    for var ch in Array(name.uppercased().utf8) {
        if ch == UInt8(ascii: "/") { ch = UInt8(ascii: "\\") }
        s1 = cryptTable[Int(type << 8) + Int(ch)] ^ (s1 &+ s2)
        s2 = UInt32(ch) &+ s1 &+ s2 &+ (s2 << 5) &+ 3
    }
    return s1
}

func mpqDecrypt(_ words: [UInt32], key: UInt32) -> [UInt32] {
    var s1 = key, s2: UInt32 = 0xEEEEEEEE
    var out = words
    for i in 0..<out.count {
        s2 = s2 &+ cryptTable[0x400 + Int(s1 & 0xFF)]
        let v = out[i] ^ (s1 &+ s2)
        out[i] = v
        s1 = ((~s1 << 0x15) &+ 0x11111111) | (s1 >> 0x0B)
        s2 = v &+ s2 &+ (s2 << 5) &+ 3
    }
    return out
}

final class MPQArchive {
    private let data: Data
    private let base: Int
    private let sectorSize: Int
    private var hashTable: [(a: UInt32, b: UInt32, block: UInt32)] = []
    private var blockTable: [(offset: Int, archived: Int, size: Int, flags: UInt32)] = []

    private static func slice(_ d: Data, _ off: Int, _ len: Int) throws -> [UInt8] {
        guard off >= 0, len >= 0, off + len <= d.count else { throw ToolError("archive truncated") }
        return Array(d[off..<off + len])
    }
    private func bytes(_ off: Int, _ len: Int) throws -> [UInt8] { try MPQArchive.slice(data, off, len) }

    init(path: String) throws {
        let d = try Data(contentsOf: URL(fileURLWithPath: path), options: .alwaysMapped)
        // header on a 512-byte boundary; 'MPQ\x1b' is a user-data block to skip over
        var off = 0, found = -1
        while off + 32 <= d.count, off < 1 << 20 {
            if try MPQArchive.slice(d, off, 4) == [0x4D, 0x50, 0x51, 0x1A] { found = off; break }
            off += 512
        }
        guard found >= 0 else { throw ToolError("not an MPQ archive") }
        data = d
        base = found
        let h = try MPQArchive.slice(d, found, 32)
        let headerSize = Int(le32(h, 4))
        sectorSize = 512 << le16(h, 14)
        var hashOff = Int(le32(h, 16)), blockOff = Int(le32(h, 20))
        let hashN = Int(le32(h, 24)), blockN = Int(le32(h, 28))
        if headerSize >= 44 {
            let ext = try MPQArchive.slice(d, found, 44)
            hashOff += le16(ext, 40) << 32
            blockOff += le16(ext, 42) << 32
        }
        guard hashN > 0, hashN & (hashN - 1) == 0 else { throw ToolError("bad hash table size") }
        let hw = mpqDecrypt(try words(base + hashOff, hashN * 4), key: mpqHash("(hash table)", 3))
        for i in 0..<hashN { hashTable.append((hw[i * 4], hw[i * 4 + 1], hw[i * 4 + 3])) }
        let bw = mpqDecrypt(try words(base + blockOff, blockN * 4), key: mpqHash("(block table)", 3))
        for i in 0..<blockN {
            blockTable.append((Int(bw[i * 4]), Int(bw[i * 4 + 1]), Int(bw[i * 4 + 2]), bw[i * 4 + 3]))
        }
    }

    private func words(_ off: Int, _ n: Int) throws -> [UInt32] {
        let b = try bytes(off, n * 4)
        return (0..<n).map { le32(b, $0 * 4) }
    }

    func contains(_ name: String) -> Bool { (try? locate(name)) != nil }

    private func locate(_ name: String) throws -> (offset: Int, archived: Int, size: Int, flags: UInt32) {
        let a = mpqHash(name, 1), b = mpqHash(name, 2)
        let mask = UInt32(hashTable.count - 1)
        let start = Int(mpqHash(name, 0) & mask)
        var i = start
        repeat {
            let e = hashTable[i]
            if e.block == 0xFFFFFFFF { break }                       // empty: end of chain
            if e.block != 0xFFFFFFFE, e.a == a, e.b == b {           // 0xFFFFFFFE = deleted
                guard Int(e.block) < blockTable.count else { throw ToolError("bad block index") }
                let blk = blockTable[Int(e.block)]
                guard blk.flags & MPQ_FILE_EXISTS != 0 else { break }
                return blk
            }
            i = (i + 1) & Int(mask)
        } while i != start
        throw ToolError("\(name) not in archive")
    }

    private func decode(_ sector: [UInt8], expected: Int, flags: UInt32) throws -> [UInt8] {
        if flags & MPQ_FILE_COMPRESS == 0 || sector.count >= expected { return sector }
        guard let type = sector.first else { throw ToolError("empty sector") }
        let payload = Array(sector.dropFirst())
        switch type {
        case 0x02: return try zlibInflate(payload, expected: expected)
        case 0x10: return try bzip2Inflate(payload, expected: expected)
        default: throw ToolError(String(format: "unsupported sector compression 0x%02x", type))
        }
    }

    func read(_ name: String) throws -> [UInt8] {
        let blk = try locate(name)
        if blk.flags & MPQ_FILE_ENCRYPTED != 0 { throw ToolError("\(name) is encrypted (unsupported)") }
        if blk.flags & MPQ_FILE_IMPLODE != 0 { throw ToolError("\(name) uses PKWARE implode (unsupported)") }
        let fileBase = base + blk.offset
        if blk.flags & MPQ_FILE_SINGLE_UNIT != 0 {
            return try decode(try bytes(fileBase, blk.archived), expected: blk.size, flags: blk.flags)
        }
        let sectors = (blk.size + sectorSize - 1) / sectorSize
        let table = try words(fileBase, sectors + 1 + (blk.flags & MPQ_FILE_SECTOR_CRC != 0 ? 1 : 0))
        var out = [UInt8](); out.reserveCapacity(blk.size)
        for s in 0..<sectors {
            let from = Int(table[s]), to = Int(table[s + 1])
            guard to >= from, to <= blk.archived else { throw ToolError("bad sector table in \(name)") }
            let expected = min(sectorSize, blk.size - s * sectorSize)
            out += try decode(try bytes(fileBase + from, to - from), expected: expected, flags: blk.flags)
        }
        guard out.count == blk.size else { throw ToolError("size mismatch reading \(name)") }
        return out
    }
}

// MARK: - TrueType cmap rewrite

struct CmapSubtable {
    let platform: Int, encoding: Int, offset: Int   // offset within the cmap table
}

func isUnicodeTable(_ p: Int, _ e: Int) -> Bool { p == 0 || (p == 3 && (e == 1 || e == 10)) }

/// Byte length of a cmap subtable of any format.
func subtableLength(_ c: [UInt8], _ o: Int) throws -> Int {
    guard o + 4 <= c.count else { throw ToolError("cmap subtable out of range") }
    let format = be16(c, o)
    switch format {
    case 0, 2, 4, 6: return be16(c, o + 2)
    case 8, 10, 12, 13: guard o + 8 <= c.count else { throw ToolError("cmap subtable out of range") }; return Int(be32(c, o + 4))
    case 14: guard o + 6 <= c.count else { throw ToolError("cmap subtable out of range") }; return Int(be32(c, o + 2))
    default: throw ToolError("unknown cmap subtable format \(format)")
    }
}

/// Decode a format 4 or 12 subtable into codepoint → glyph. Returns nil for other formats.
func decodeSubtable(_ c: [UInt8], _ o: Int) throws -> [UInt32: Int]? {
    let format = be16(c, o)
    var map: [UInt32: Int] = [:]
    if format == 4 {
        let segCount = be16(c, o + 6) / 2
        let endOff = o + 14, startOff = endOff + segCount * 2 + 2
        let deltaOff = startOff + segCount * 2, rangeOff = deltaOff + segCount * 2
        guard rangeOff + segCount * 2 <= c.count else { throw ToolError("format 4 subtable truncated") }
        for s in 0..<segCount {
            let end = be16(c, endOff + s * 2), start = be16(c, startOff + s * 2)
            let delta = be16(c, deltaOff + s * 2), range = be16(c, rangeOff + s * 2)
            if start > end { continue }
            for cp in start...end {
                if cp == 0xFFFF { continue }
                var g: Int
                if range == 0 {
                    g = (cp + delta) & 0xFFFF
                } else {
                    let idx = rangeOff + s * 2 + range + (cp - start) * 2
                    guard idx + 2 <= c.count else { continue }
                    let gid = be16(c, idx)
                    if gid == 0 { continue }
                    g = (gid + delta) & 0xFFFF
                }
                if g != 0 { map[UInt32(cp)] = g }
            }
        }
        return map
    }
    if format == 12 {
        let n = Int(be32(c, o + 12))
        guard o + 16 + n * 12 <= c.count else { throw ToolError("format 12 subtable truncated") }
        for i in 0..<n {
            let p = o + 16 + i * 12
            let start = be32(c, p), end = be32(c, p + 4), g0 = be32(c, p + 8)
            if start > end || end - start > 0x10FFFF { continue }
            for cp in start...end { map[cp] = Int(g0 + (cp - start)) }
        }
        return map
    }
    return nil
}

func encodeFormat4(_ map: [UInt32: Int]) throws -> [UInt8] {
    let codes = map.keys.filter { $0 < 0xFFFF }.sorted()
    var starts: [Int] = [], ends: [Int] = [], deltas: [Int] = [], ranges: [Int] = [], glyphs: [Int] = []
    var i = 0
    while i < codes.count {
        var j = i
        while j + 1 < codes.count, codes[j + 1] == codes[j] + 1 { j += 1 }
        let start = Int(codes[i]), end = Int(codes[j])
        let run = (i...j).map { map[codes[$0]]! }
        let consecutive = zip(run, run.dropFirst()).allSatisfy { $1 == $0 + 1 }
        starts.append(start); ends.append(end)
        if consecutive {
            deltas.append((run[0] - start) & 0xFFFF); ranges.append(0)
        } else {
            deltas.append(0); ranges.append(-glyphs.count - 1)   // placeholder: index into glyphs (negative marker)
            glyphs += run
        }
        i = j + 1
    }
    starts.append(0xFFFF); ends.append(0xFFFF); deltas.append(1); ranges.append(0)
    let segCount = starts.count
    var out: [UInt8] = []
    let length = 16 + segCount * 8 + glyphs.count * 2
    guard length <= 0xFFFF else { throw ToolError("format 4 subtable too large") }
    var entrySelector = 0
    while (1 << (entrySelector + 1)) <= segCount { entrySelector += 1 }
    let searchRange = 2 * (1 << entrySelector)
    out.put16(4); out.put16(length); out.put16(0)
    out.put16(segCount * 2); out.put16(searchRange); out.put16(entrySelector); out.put16(segCount * 2 - searchRange)
    for e in ends { out.put16(e) }
    out.put16(0)
    for s in starts { out.put16(s) }
    for d in deltas { out.put16(d) }
    for (s, r) in ranges.enumerated() {
        if r == 0 { out.put16(0) } else { out.put16(2 * (segCount - s + (-r - 1))) }
    }
    for g in glyphs { out.put16(g) }
    return out
}

func encodeFormat12(_ map: [UInt32: Int]) -> [UInt8] {
    let codes = map.keys.sorted()
    var groups: [(UInt32, UInt32, UInt32)] = []
    var i = 0
    while i < codes.count {
        var j = i
        while j + 1 < codes.count, codes[j + 1] == codes[j] + 1, map[codes[j + 1]]! == map[codes[j]]! + 1 { j += 1 }
        groups.append((codes[i], codes[j], UInt32(map[codes[i]]!)))
        i = j + 1
    }
    var out: [UInt8] = []
    out.put16(12); out.put16(0); out.put32(UInt32(16 + groups.count * 12)); out.put32(0); out.put32(UInt32(groups.count))
    for g in groups { out.put32(g.0); out.put32(g.1); out.put32(g.2) }
    return out
}

func tableChecksum(_ b: [UInt8]) -> UInt32 {
    var sum: UInt32 = 0
    var i = 0
    while i < b.count {
        var w: UInt32 = 0
        for k in 0..<4 { w = w << 8 | (i + k < b.count ? UInt32(b[i + k]) : 0) }
        sum = sum &+ w
        i += 4
    }
    return sum
}

struct TrueTypeFont {
    var tables: [(tag: String, data: [UInt8])]   // in directory order
    let header: [UInt8]                          // first 4 bytes (sfnt version)

    init(_ b: [UInt8]) throws {
        guard b.count >= 12 else { throw ToolError("not a TrueType font") }
        let version = be32(b, 0)
        guard version == 0x00010000 || version == 0x74727565 else { throw ToolError("not a TrueType font") }
        header = Array(b[0..<4])
        let n = be16(b, 4)
        guard 12 + n * 16 <= b.count else { throw ToolError("font directory truncated") }
        var t: [(String, [UInt8])] = []
        for i in 0..<n {
            let r = 12 + i * 16
            let tag = String(bytes: b[r..<r + 4], encoding: .isoLatin1) ?? "????"
            let off = Int(be32(b, r + 8)), len = Int(be32(b, r + 12))
            guard off + len <= b.count else { throw ToolError("table \(tag) out of range") }
            t.append((tag, Array(b[off..<off + len])))
        }
        tables = t
    }

    func table(_ tag: String) -> [UInt8]? { tables.first { $0.tag == tag }?.data }

    /// Parse the cmap: encoding records and decoded unicode subtables (by subtable offset).
    func cmapSubtables() throws -> [CmapSubtable] {
        guard let c = table("cmap"), c.count >= 4 else { throw ToolError("no cmap table") }
        let n = be16(c, 2)
        guard 4 + n * 8 <= c.count else { throw ToolError("cmap truncated") }
        return (0..<n).map { CmapSubtable(platform: be16(c, 4 + $0 * 8), encoding: be16(c, 6 + $0 * 8), offset: Int(be32(c, 8 + $0 * 8))) }
    }

    /// The "best" unicode mapping (same preference order as fontTools' getBestCmap).
    func bestCmap() throws -> [UInt32: Int] {
        guard let c = table("cmap") else { throw ToolError("no cmap table") }
        let subs = try cmapSubtables()
        let pref = [(3, 10), (0, 6), (0, 4), (3, 1), (0, 3), (0, 2), (0, 1), (0, 0)]
        for (p, e) in pref {
            if let s = subs.first(where: { $0.platform == p && $0.encoding == e }), let m = try decodeSubtable(c, s.offset) { return m }
        }
        throw ToolError("no unicode cmap subtable")
    }

    /// Apply the remap to every unicode subtable; returns false when the font has no Cyrillic.
    mutating func remap() throws -> Bool {
        guard let c = table("cmap") else { throw ToolError("no cmap table") }
        let best = try bestCmap()
        guard best[0x410] != nil else { return false }
        let subs = try cmapSubtables()
        var rebuilt: [Int: [UInt8]] = [:]          // original subtable offset → new bytes
        for s in subs where rebuilt[s.offset] == nil {
            let len = try subtableLength(c, s.offset)
            guard s.offset + len <= c.count else { throw ToolError("cmap subtable out of range") }
            let raw = Array(c[s.offset..<s.offset + len])
            let format = be16(c, s.offset)
            if isUnicodeTable(s.platform, s.encoding), var m = try decodeSubtable(c, s.offset) {
                for (dst, src) in REMAP { if let g = best[src] { m[dst] = g } }
                rebuilt[s.offset] = format == 4 ? try encodeFormat4(m) : encodeFormat12(m)
            } else {
                rebuilt[s.offset] = raw
            }
        }
        // reassemble: header + records (original order) + subtables (first-use order, shared offsets kept shared)
        var body: [UInt8] = []
        var newOffset: [Int: Int] = [:]
        var order: [Int] = []
        for s in subs where newOffset[s.offset] == nil {
            order.append(s.offset)
            newOffset[s.offset] = 4 + subs.count * 8 + body.count
            body += rebuilt[s.offset]!
            body.pad4()
        }
        var out: [UInt8] = []
        out.put16(0); out.put16(subs.count)
        for s in subs { out.put16(s.platform); out.put16(s.encoding); out.put32(UInt32(newOffset[s.offset]!)) }
        out += body
        let idx = tables.firstIndex { $0.tag == "cmap" }!
        tables[idx].data = out
        return true
    }

    func serialize() -> [UInt8] {
        let n = tables.count
        var entrySelector = 0
        while (1 << (entrySelector + 1)) <= n { entrySelector += 1 }
        let searchRange = 16 * (1 << entrySelector)
        var dir: [UInt8] = header
        dir.put16(n); dir.put16(searchRange); dir.put16(entrySelector); dir.put16(n * 16 - searchRange)
        var body: [UInt8] = []
        var records: [(String, UInt32, Int, Int)] = []
        let headerLen = 12 + n * 16
        for t in tables {
            var d = t.data
            if t.tag == "head", d.count >= 12 { d[8] = 0; d[9] = 0; d[10] = 0; d[11] = 0 }   // checkSumAdjustment
            records.append((t.tag, tableChecksum(d), headerLen + body.count, d.count))
            body += d
            body.pad4()
        }
        for r in records {
            dir += Array(r.0.utf8.prefix(4)) + [UInt8](repeating: 0x20, count: max(0, 4 - r.0.utf8.count))
            dir.put32(r.1); dir.put32(UInt32(r.2)); dir.put32(UInt32(r.3))
        }
        var font = dir + body
        if let head = records.first(where: { $0.0 == "head" }) {
            let adj = 0xB1B0AFBA &- tableChecksum(font)
            let o = head.2 + 8
            font[o] = UInt8(adj >> 24); font[o + 1] = UInt8((adj >> 16) & 0xFF); font[o + 2] = UInt8((adj >> 8) & 0xFF); font[o + 3] = UInt8(adj & 0xFF)
        }
        return font
    }
}

/// Does this font carry the remap? (в at U+00E2 and і at U+00B3 resolve to the Cyrillic glyphs.)
func isRemapped(_ font: TrueTypeFont) -> Bool {
    guard let m = try? font.bestCmap(), let cyr = m[0x432], let lat = m[0xE2], cyr == lat else { return false }
    if let i = m[0x456] { return m[0xB3] == i }
    return true
}

// MARK: - commands

func extract(game: String, out: String) {
    let fm = FileManager.default
    var mpqs: [String]
    if game.lowercased().hasSuffix(".mpq") {          // a locale archive given directly (e.g. a stashed language pack)
        mpqs = [game]
    } else {
        let dataDir = (game as NSString).appendingPathComponent("Data")
        let locales = ((try? fm.contentsOfDirectory(atPath: dataDir)) ?? []).filter { $0.count == 4 }.sorted()
        mpqs = locales.map { "\(dataDir)/\($0)/locale-\($0).MPQ" }
    }
    mpqs = mpqs.filter { fm.fileExists(atPath: $0) }
    guard !mpqs.isEmpty else { fail("no Data/<locale>/locale-<locale>.MPQ under \(game)") }
    var lastError = "no locale archive contains the four fonts"
    for mpq in mpqs {
        do {
            let archive = try MPQArchive(path: mpq)
            var results: [(String, [UInt8])] = []
            for w in WANTED {
                var font = try TrueTypeFont(try archive.read(w.mpq))
                guard try font.remap() else { throw ToolError("\(w.mpq) has no Cyrillic glyphs (not a ruRU client)") }
                results.append((w.out, font.serialize()))
            }
            try fm.createDirectory(atPath: out, withIntermediateDirectories: true)
            for (name, bytes) in results {
                try Data(bytes).write(to: URL(fileURLWithPath: (out as NSString).appendingPathComponent(name)))
            }
            print("extracted \(results.count) fonts from \(mpq)")
            exit(0)
        } catch {
            lastError = "\((mpq as NSString).lastPathComponent): \(error)"
        }
    }
    fail(lastError)
}

func check(_ paths: [String]) {
    var allGood = !paths.isEmpty
    for p in paths {
        let name = (p as NSString).lastPathComponent
        if let d = try? Data(contentsOf: URL(fileURLWithPath: p)), let f = try? TrueTypeFont([UInt8](d)) {
            let ok = isRemapped(f)
            print("\(name): \(ok ? "remapped" : "not remapped")")
            if !ok { allGood = false }
        } else {
            print("\(name): unreadable"); allGood = false
        }
    }
    exit(allGood ? 0 : 1)
}

let args = Array(CommandLine.arguments.dropFirst())
if args.count >= 2, args[0] == "check" {
    check(Array(args.dropFirst()))
} else if args.count == 2 {
    extract(game: args[0], out: args[1])
} else {
    fail("usage: wow-client-fonts <game-dir> <out-dir> | check <font.ttf>...")
}
