const std = @import("std");
const rl = @import("raylib");

const Vec3 = rl.Vector3;

/// Imagen en memoria con colores en f32 (rgb en [0, 1]).
/// Todas las texturas del proyecto se generan por código, no dependen de archivos.
pub const Texture = struct {
    width: usize,
    height: usize,
    pixels: []Vec3,

    pub fn init(gpa: std.mem.Allocator, width: usize, height: usize) !Texture {
        return .{
            .width = width,
            .height = height,
            .pixels = try gpa.alloc(Vec3, width * height),
        };
    }

    pub fn deinit(self: Texture, gpa: std.mem.Allocator) void {
        gpa.free(self.pixels);
    }

    /// Muestreo sin interpolar (se ve "pixel art", como los bloques de Minecraft).
    /// u y v se repiten; v crece hacia abajo en la imagen.
    pub fn sampleNearest(self: *const Texture, u: f32, v: f32) Vec3 {
        const fu = u - @floor(u);
        const fv = v - @floor(v);
        const x: usize = @min(self.width - 1, @as(usize, @intFromFloat(fu * @as(f32, @floatFromInt(self.width)))));
        const y: usize = @min(self.height - 1, @as(usize, @intFromFloat(fv * @as(f32, @floatFromInt(self.height)))));
        return self.pixels[y * self.width + x];
    }

    /// Muestreo bilineal para el skybox.
    /// u se repite (es el ángulo alrededor), v se limita (polos).
    fn sampleBilinear(self: *const Texture, u: f32, v: f32) Vec3 {
        const w: f32 = @floatFromInt(self.width);
        const h: f32 = @floatFromInt(self.height);
        const fx = (u - @floor(u)) * w - 0.5;
        const fy = std.math.clamp(v * h - 0.5, 0, h - 1);

        const x0f = @floor(fx);
        const y0f = @floor(fy);
        const tx = fx - x0f;
        const ty = fy - y0f;

        const xi: i64 = @intFromFloat(x0f);
        const x0: usize = @intCast(@mod(xi, @as(i64, @intCast(self.width))));
        const x1: usize = @intCast(@mod(xi + 1, @as(i64, @intCast(self.width))));
        const y0: usize = @intFromFloat(y0f);
        const y1: usize = @min(self.height - 1, y0 + 1);

        const top = lerp3(self.pixels[y0 * self.width + x0], self.pixels[y0 * self.width + x1], tx);
        const bottom = lerp3(self.pixels[y1 * self.width + x0], self.pixels[y1 * self.width + x1], tx);
        return lerp3(top, bottom, ty);
    }

    /// Skybox equirectangular: dirección (normalizada) -> color del cielo.
    pub fn sampleSky(self: *const Texture, dir: Vec3) Vec3 {
        const u = std.math.atan2(dir.z, dir.x) / (2 * std.math.pi) + 0.5;
        const v = std.math.acos(std.math.clamp(dir.y, -1, 1)) / std.math.pi;
        return self.sampleBilinear(u, v);
    }
};

pub fn lerp3(a: Vec3, b: Vec3, t: f32) Vec3 {
    return a.add(b.subtract(a).scale(t));
}

pub fn rgb(r: f32, g: f32, b: f32) Vec3 {
    return .{ .x = r, .y = g, .z = b };
}

// ---------------------------------------------------------------------------
// Ruido determinista
// ---------------------------------------------------------------------------

fn hash(x: i32, y: i32, seed: u32) u32 {
    var h: u32 = seed *% 0x9E3779B1;
    h ^= @as(u32, @bitCast(x)) *% 0x85EBCA6B;
    h = (h << 13) | (h >> 19);
    h ^= @as(u32, @bitCast(y)) *% 0xC2B2AE35;
    h *%= 0x27D4EB2F;
    h ^= h >> 15;
    h *%= 0x85EBCA77;
    h ^= h >> 13;
    return h;
}

/// Ruido en [0, 1) por celda entera.
pub fn noise(x: i32, y: i32, seed: u32) f32 {
    return @as(f32, @floatFromInt(hash(x, y, seed) & 0xFFFF)) / 65536.0;
}

pub fn smooth(t: f32) f32 {
    return t * t * (3 - 2 * t);
}

pub fn valueNoise(x: f32, y: f32, seed: u32) f32 {
    const x0: i32 = @intFromFloat(@floor(x));
    const y0: i32 = @intFromFloat(@floor(y));
    const tx = smooth(x - @floor(x));
    const ty = smooth(y - @floor(y));
    const a = noise(x0, y0, seed);
    const b = noise(x0 + 1, y0, seed);
    const c = noise(x0, y0 + 1, seed);
    const d = noise(x0 + 1, y0 + 1, seed);
    const top = a + (b - a) * tx;
    const bottom = c + (d - c) * tx;
    return top + (bottom - top) * ty;
}

pub fn fbm(x: f32, y: f32, seed: u32) f32 {
    var sum: f32 = 0;
    var amp: f32 = 0.5;
    var freq: f32 = 1;
    for (0..4) |i| {
        sum += amp * valueNoise(x * freq, y * freq, seed +% @as(u32, @intCast(i)));
        amp *= 0.5;
        freq *= 2;
    }
    return sum;
}

// ---------------------------------------------------------------------------
// Ayudas para texturas de bloques (16x16); cada bloque vive en bloques/
// ---------------------------------------------------------------------------

pub const block_size = 16;

pub fn blockTexture(gpa: std.mem.Allocator) !Texture {
    return Texture.init(gpa, block_size, block_size);
}

pub fn px(t: *Texture, x: usize, y: usize) *Vec3 {
    return &t.pixels[y * t.width + x];
}

pub fn ix(v: usize) i32 {
    return @intCast(v);
}
