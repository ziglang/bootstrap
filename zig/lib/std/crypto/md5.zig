const mem = @import("../mem.zig");
const math = @import("../math.zig");
const endian = @import("../endian.zig");
const builtin = @import("builtin");
const debug = @import("../debug.zig");
const fmt = @import("../fmt.zig");

const RoundParam = struct {
    a: usize,
    b: usize,
    c: usize,
    d: usize,
    k: usize,
    s: u32,
    t: u32,
};

fn Rp(a: usize, b: usize, c: usize, d: usize, k: usize, s: u32, t: u32) RoundParam {
    return RoundParam{
        .a = a,
        .b = b,
        .c = c,
        .d = d,
        .k = k,
        .s = s,
        .t = t,
    };
}

pub const Md5 = struct {
    const Self = @This();
    pub const block_length = 64;
    pub const digest_length = 16;

    s: [4]u32,
    // Streaming Cache
    buf: [64]u8,
    buf_len: u8,
    total_len: u64,

    pub fn init() Self {
        var d: Self = undefined;
        d.reset();
        return d;
    }

    pub fn reset(d: *Self) void {
        d.s[0] = 0x67452301;
        d.s[1] = 0xEFCDAB89;
        d.s[2] = 0x98BADCFE;
        d.s[3] = 0x10325476;
        d.buf_len = 0;
        d.total_len = 0;
    }

    pub fn hash(b: []const u8, out: []u8) void {
        var d = Md5.init();
        d.update(b);
        d.final(out);
    }

    pub fn update(d: *Self, b: []const u8) void {
        var off: usize = 0;

        // Partial buffer exists from previous update. Copy into buffer then hash.
        if (d.buf_len != 0 and d.buf_len + b.len >= 64) {
            off += 64 - d.buf_len;
            mem.copy(u8, d.buf[d.buf_len..], b[0..off]);

            d.round(d.buf[0..]);
            d.buf_len = 0;
        }

        // Full middle blocks.
        while (off + 64 <= b.len) : (off += 64) {
            d.round(b[off .. off + 64]);
        }

        // Copy any remainder for next pass.
        mem.copy(u8, d.buf[d.buf_len..], b[off..]);
        d.buf_len += @intCast(u8, b[off..].len);

        // Md5 uses the bottom 64-bits for length padding
        d.total_len +%= b.len;
    }

    pub fn final(d: *Self, out: []u8) void {
        debug.assert(out.len >= 16);

        // The buffer here will never be completely full.
        mem.set(u8, d.buf[d.buf_len..], 0);

        // Append padding bits.
        d.buf[d.buf_len] = 0x80;
        d.buf_len += 1;

        // > 448 mod 512 so need to add an extra round to wrap around.
        if (64 - d.buf_len < 8) {
            d.round(d.buf[0..]);
            mem.set(u8, d.buf[0..], 0);
        }

        // Append message length.
        var i: usize = 1;
        var len = d.total_len >> 5;
        d.buf[56] = @intCast(u8, d.total_len & 0x1f) << 3;
        while (i < 8) : (i += 1) {
            d.buf[56 + i] = @intCast(u8, len & 0xff);
            len >>= 8;
        }

        d.round(d.buf[0..]);

        for (d.s) |s, j| {
            mem.writeIntLittle(u32, out[4 * j ..][0..4], s);
        }
    }

    fn round(d: *Self, b: []const u8) void {
        debug.assert(b.len == 64);

        var s: [16]u32 = undefined;

        var i: usize = 0;
        while (i < 16) : (i += 1) {
            // NOTE: Performing or's separately improves perf by ~10%
            s[i] = 0;
            s[i] |= @as(u32, b[i * 4 + 0]);
            s[i] |= @as(u32, b[i * 4 + 1]) << 8;
            s[i] |= @as(u32, b[i * 4 + 2]) << 16;
            s[i] |= @as(u32, b[i * 4 + 3]) << 24;
        }

        var v: [4]u32 = [_]u32{
            d.s[0],
            d.s[1],
            d.s[2],
            d.s[3],
        };

        const round0 = comptime [_]RoundParam{
            Rp(0, 1, 2, 3, 0, 7, 0xD76AA478),
            Rp(3, 0, 1, 2, 1, 12, 0xE8C7B756),
            Rp(2, 3, 0, 1, 2, 17, 0x242070DB),
            Rp(1, 2, 3, 0, 3, 22, 0xC1BDCEEE),
            Rp(0, 1, 2, 3, 4, 7, 0xF57C0FAF),
            Rp(3, 0, 1, 2, 5, 12, 0x4787C62A),
            Rp(2, 3, 0, 1, 6, 17, 0xA8304613),
            Rp(1, 2, 3, 0, 7, 22, 0xFD469501),
            Rp(0, 1, 2, 3, 8, 7, 0x698098D8),
            Rp(3, 0, 1, 2, 9, 12, 0x8B44F7AF),
            Rp(2, 3, 0, 1, 10, 17, 0xFFFF5BB1),
            Rp(1, 2, 3, 0, 11, 22, 0x895CD7BE),
            Rp(0, 1, 2, 3, 12, 7, 0x6B901122),
            Rp(3, 0, 1, 2, 13, 12, 0xFD987193),
            Rp(2, 3, 0, 1, 14, 17, 0xA679438E),
            Rp(1, 2, 3, 0, 15, 22, 0x49B40821),
        };
        inline for (round0) |r| {
            v[r.a] = v[r.a] +% (v[r.d] ^ (v[r.b] & (v[r.c] ^ v[r.d]))) +% r.t +% s[r.k];
            v[r.a] = v[r.b] +% math.rotl(u32, v[r.a], r.s);
        }

        const round1 = comptime [_]RoundParam{
            Rp(0, 1, 2, 3, 1, 5, 0xF61E2562),
            Rp(3, 0, 1, 2, 6, 9, 0xC040B340),
            Rp(2, 3, 0, 1, 11, 14, 0x265E5A51),
            Rp(1, 2, 3, 0, 0, 20, 0xE9B6C7AA),
            Rp(0, 1, 2, 3, 5, 5, 0xD62F105D),
            Rp(3, 0, 1, 2, 10, 9, 0x02441453),
            Rp(2, 3, 0, 1, 15, 14, 0xD8A1E681),
            Rp(1, 2, 3, 0, 4, 20, 0xE7D3FBC8),
            Rp(0, 1, 2, 3, 9, 5, 0x21E1CDE6),
            Rp(3, 0, 1, 2, 14, 9, 0xC33707D6),
            Rp(2, 3, 0, 1, 3, 14, 0xF4D50D87),
            Rp(1, 2, 3, 0, 8, 20, 0x455A14ED),
            Rp(0, 1, 2, 3, 13, 5, 0xA9E3E905),
            Rp(3, 0, 1, 2, 2, 9, 0xFCEFA3F8),
            Rp(2, 3, 0, 1, 7, 14, 0x676F02D9),
            Rp(1, 2, 3, 0, 12, 20, 0x8D2A4C8A),
        };
        inline for (round1) |r| {
            v[r.a] = v[r.a] +% (v[r.c] ^ (v[r.d] & (v[r.b] ^ v[r.c]))) +% r.t +% s[r.k];
            v[r.a] = v[r.b] +% math.rotl(u32, v[r.a], r.s);
        }

        const round2 = comptime [_]RoundParam{
            Rp(0, 1, 2, 3, 5, 4, 0xFFFA3942),
            Rp(3, 0, 1, 2, 8, 11, 0x8771F681),
            Rp(2, 3, 0, 1, 11, 16, 0x6D9D6122),
            Rp(1, 2, 3, 0, 14, 23, 0xFDE5380C),
            Rp(0, 1, 2, 3, 1, 4, 0xA4BEEA44),
            Rp(3, 0, 1, 2, 4, 11, 0x4BDECFA9),
            Rp(2, 3, 0, 1, 7, 16, 0xF6BB4B60),
            Rp(1, 2, 3, 0, 10, 23, 0xBEBFBC70),
            Rp(0, 1, 2, 3, 13, 4, 0x289B7EC6),
            Rp(3, 0, 1, 2, 0, 11, 0xEAA127FA),
            Rp(2, 3, 0, 1, 3, 16, 0xD4EF3085),
            Rp(1, 2, 3, 0, 6, 23, 0x04881D05),
            Rp(0, 1, 2, 3, 9, 4, 0xD9D4D039),
            Rp(3, 0, 1, 2, 12, 11, 0xE6DB99E5),
            Rp(2, 3, 0, 1, 15, 16, 0x1FA27CF8),
            Rp(1, 2, 3, 0, 2, 23, 0xC4AC5665),
        };
        inline for (round2) |r| {
            v[r.a] = v[r.a] +% (v[r.b] ^ v[r.c] ^ v[r.d]) +% r.t +% s[r.k];
            v[r.a] = v[r.b] +% math.rotl(u32, v[r.a], r.s);
        }

        const round3 = comptime [_]RoundParam{
            Rp(0, 1, 2, 3, 0, 6, 0xF4292244),
            Rp(3, 0, 1, 2, 7, 10, 0x432AFF97),
            Rp(2, 3, 0, 1, 14, 15, 0xAB9423A7),
            Rp(1, 2, 3, 0, 5, 21, 0xFC93A039),
            Rp(0, 1, 2, 3, 12, 6, 0x655B59C3),
            Rp(3, 0, 1, 2, 3, 10, 0x8F0CCC92),
            Rp(2, 3, 0, 1, 10, 15, 0xFFEFF47D),
            Rp(1, 2, 3, 0, 1, 21, 0x85845DD1),
            Rp(0, 1, 2, 3, 8, 6, 0x6FA87E4F),
            Rp(3, 0, 1, 2, 15, 10, 0xFE2CE6E0),
            Rp(2, 3, 0, 1, 6, 15, 0xA3014314),
            Rp(1, 2, 3, 0, 13, 21, 0x4E0811A1),
            Rp(0, 1, 2, 3, 4, 6, 0xF7537E82),
            Rp(3, 0, 1, 2, 11, 10, 0xBD3AF235),
            Rp(2, 3, 0, 1, 2, 15, 0x2AD7D2BB),
            Rp(1, 2, 3, 0, 9, 21, 0xEB86D391),
        };
        inline for (round3) |r| {
            v[r.a] = v[r.a] +% (v[r.c] ^ (v[r.b] | ~v[r.d])) +% r.t +% s[r.k];
            v[r.a] = v[r.b] +% math.rotl(u32, v[r.a], r.s);
        }

        d.s[0] +%= v[0];
        d.s[1] +%= v[1];
        d.s[2] +%= v[2];
        d.s[3] +%= v[3];
    }
};

const htest = @import("test.zig");

test "md5 single" {
    htest.assertEqualHash(Md5, "d41d8cd98f00b204e9800998ecf8427e", "");
    htest.assertEqualHash(Md5, "0cc175b9c0f1b6a831c399e269772661", "a");
    htest.assertEqualHash(Md5, "900150983cd24fb0d6963f7d28e17f72", "abc");
    htest.assertEqualHash(Md5, "f96b697d7cb7938d525a2f31aaf161d0", "message digest");
    htest.assertEqualHash(Md5, "c3fcd3d76192e4007dfb496cca67e13b", "abcdefghijklmnopqrstuvwxyz");
    htest.assertEqualHash(Md5, "d174ab98d277d9f5a5611c2c9f419d9f", "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789");
    htest.assertEqualHash(Md5, "57edf4a22be3c955ac49da2e2107b67a", "12345678901234567890123456789012345678901234567890123456789012345678901234567890");
}

test "md5 streaming" {
    var h = Md5.init();
    var out: [16]u8 = undefined;

    h.final(out[0..]);
    htest.assertEqual("d41d8cd98f00b204e9800998ecf8427e", out[0..]);

    h.reset();
    h.update("abc");
    h.final(out[0..]);
    htest.assertEqual("900150983cd24fb0d6963f7d28e17f72", out[0..]);

    h.reset();
    h.update("a");
    h.update("b");
    h.update("c");
    h.final(out[0..]);

    htest.assertEqual("900150983cd24fb0d6963f7d28e17f72", out[0..]);
}

test "md5 aligned final" {
    var block = [_]u8{0} ** Md5.block_length;
    var out: [Md5.digest_length]u8 = undefined;

    var h = Md5.init();
    h.update(&block);
    h.final(out[0..]);
}