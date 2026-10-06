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

fn lerp3(a: Vec3, b: Vec3, t: f32) Vec3 {
    return a.add(b.subtract(a).scale(t));
}

fn rgb(r: f32, g: f32, b: f32) Vec3 {
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
fn noise(x: i32, y: i32, seed: u32) f32 {
    return @as(f32, @floatFromInt(hash(x, y, seed) & 0xFFFF)) / 65536.0;
}

fn smooth(t: f32) f32 {
    return t * t * (3 - 2 * t);
}

fn valueNoise(x: f32, y: f32, seed: u32) f32 {
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

fn fbm(x: f32, y: f32, seed: u32) f32 {
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
// Texturas de los materiales (16x16)
// ---------------------------------------------------------------------------

const block_size = 16;

fn blockTexture(gpa: std.mem.Allocator) !Texture {
    return Texture.init(gpa, block_size, block_size);
}

fn px(t: *Texture, x: usize, y: usize) *Vec3 {
    return &t.pixels[y * t.width + x];
}

fn ix(v: usize) i32 {
    return @intCast(v);
}

pub fn grass(gpa: std.mem.Allocator) !Texture {
    var t = try blockTexture(gpa);
    for (0..t.height) |y| {
        for (0..t.width) |x| {
            const n = noise(ix(x), ix(y), 11);
            var c = rgb(0.24, 0.55, 0.14);
            c = c.scale(0.8 + 0.4 * n);
            // Algunas briznas más claras y matas más oscuras
            if (noise(ix(x), ix(y), 12) > 0.9) c = rgb(0.5, 0.75, 0.25);
            if (noise(ix(x), ix(y), 13) > 0.93) c = rgb(0.12, 0.35, 0.08);
            px(&t, x, y).* = c;
        }
    }
    return t;
}

pub fn stone(gpa: std.mem.Allocator) !Texture {
    var t = try blockTexture(gpa);
    for (0..t.height) |y| {
        for (0..t.width) |x| {
            // Manchas grandes + grano fino
            const blotch = valueNoise(@as(f32, @floatFromInt(x)) * 0.35, @as(f32, @floatFromInt(y)) * 0.35, 21);
            const n = noise(ix(x), ix(y), 22);
            var g: f32 = 0.42 + 0.22 * blotch + 0.08 * n;
            if (noise(ix(x), ix(y), 23) > 0.94) g *= 0.65; // grietas
            px(&t, x, y).* = rgb(g, g, g * 1.03);
        }
    }
    return t;
}

pub fn wood(gpa: std.mem.Allocator) !Texture {
    var t = try blockTexture(gpa);
    const plank_h = 4;
    for (0..t.height) |y| {
        const plank = y / plank_h;
        const row_in_plank = y % plank_h;
        for (0..t.width) |x| {
            // Cada tabla tiene su propio tono y vetas largas en horizontal
            const plank_tone = 0.85 + 0.3 * noise(ix(plank), 0, 31);
            const grain = noise(ix(x / 5), ix(y), 32);
            var c = rgb(0.72, 0.53, 0.30).scale(plank_tone * (0.85 + 0.25 * grain));
            if (row_in_plank == plank_h - 1) c = c.scale(0.6); // separación entre tablas
            px(&t, x, y).* = c;
        }
    }
    return t;
}

pub fn brick(gpa: std.mem.Allocator) !Texture {
    var t = try blockTexture(gpa);
    const brick_h = 4;
    for (0..t.height) |y| {
        const row = y / brick_h;
        const in_row = y % brick_h;
        const offset: usize = if (row % 2 == 0) 0 else 4;
        for (0..t.width) |x| {
            const bx = (x + offset) % 8;
            var c: Vec3 = undefined;
            if (in_row == brick_h - 1 or bx == 7) {
                // Mortero
                c = rgb(0.72, 0.70, 0.66).scale(0.9 + 0.2 * noise(ix(x), ix(y), 41));
            } else {
                const id: i32 = @intCast(row * 4 + (x + offset) / 8);
                const tone = 0.85 + 0.3 * noise(id, 0, 42);
                c = rgb(0.62, 0.24, 0.17).scale(tone * (0.9 + 0.2 * noise(ix(x), ix(y), 43)));
            }
            px(&t, x, y).* = c;
        }
    }
    return t;
}

/// Mosaico metálico pulido: lo que más importa es el marco oscuro, la parte
/// central casi no tiene textura para que el reflejo se vea limpio.
pub fn mirror(gpa: std.mem.Allocator) !Texture {
    var t = try blockTexture(gpa);
    for (0..t.height) |y| {
        for (0..t.width) |x| {
            const edge = x == 0 or y == 0 or x == t.width - 1 or y == t.height - 1;
            var c = rgb(0.92, 0.95, 1.0).scale(0.97 + 0.03 * noise(ix(x), ix(y), 51));
            if (edge) c = rgb(0.38, 0.40, 0.45);
            px(&t, x, y).* = c;
        }
    }
    return t;
}

/// Vidrio azulado con marco y un destello diagonal.
pub fn glass(gpa: std.mem.Allocator) !Texture {
    var t = try blockTexture(gpa);
    for (0..t.height) |y| {
        for (0..t.width) |x| {
            const edge = x == 0 or y == 0 or x == t.width - 1 or y == t.height - 1;
            var c = rgb(0.88, 0.98, 1.0);
            if (edge) c = rgb(0.55, 0.78, 0.85);
            // Destello: dos diagonales
            const d = (x + y) % block_size;
            if (!edge and (d == 5 or d == 6 or d == 9)) c = rgb(1.0, 1.0, 1.0);
            px(&t, x, y).* = c;
        }
    }
    return t;
}

/// "Piedra luminosa": celdas naranjas con puntos claros y oscuros.
pub fn glowstone(gpa: std.mem.Allocator) !Texture {
    var t = try blockTexture(gpa);
    for (0..t.height) |y| {
        for (0..t.width) |x| {
            const n = valueNoise(@as(f32, @floatFromInt(x)) * 0.5, @as(f32, @floatFromInt(y)) * 0.5, 61);
            var c = rgb(0.95, 0.62, 0.22).scale(0.75 + 0.5 * n);
            const s = noise(ix(x), ix(y), 62);
            if (s > 0.85) c = rgb(1.0, 0.92, 0.6);
            if (s < 0.08) c = rgb(0.7, 0.35, 0.1);
            px(&t, x, y).* = c;
        }
    }
    return t;
}

// ---------------------------------------------------------------------------
// Skybox
// ---------------------------------------------------------------------------

/// Cielo equirectangular con degradado, sol y nubes.
/// `sun_dir` debe estar normalizado y coincidir con la luz del sol de la escena.
pub fn skybox(gpa: std.mem.Allocator, width: usize, height: usize, sun_dir: Vec3) !Texture {
    var t = try Texture.init(gpa, width, height);

    const zenith = rgb(0.18, 0.40, 0.85);
    const horizon = rgb(0.72, 0.84, 0.96);
    const ground = rgb(0.50, 0.62, 0.82);

    for (0..height) |j| {
        const phi = (@as(f32, @floatFromInt(j)) + 0.5) / @as(f32, @floatFromInt(height)) * std.math.pi;
        for (0..width) |i| {
            const theta = ((@as(f32, @floatFromInt(i)) + 0.5) / @as(f32, @floatFromInt(width)) - 0.5) * 2 * std.math.pi;
            const dir = Vec3{
                .x = @sin(phi) * @cos(theta),
                .y = @cos(phi),
                .z = @sin(phi) * @sin(theta),
            };

            var c: Vec3 = undefined;
            if (dir.y >= 0) {
                c = lerp3(horizon, zenith, std.math.pow(f32, dir.y, 0.55));

                // Nubes: ruido proyectado sobre un plano sobre el observador
                if (dir.y > 0.02) {
                    const cx = dir.x / (dir.y + 0.25) * 2.2;
                    const cz = dir.z / (dir.y + 0.25) * 2.2;
                    const density = std.math.clamp((fbm(cx + 10, cz + 10, 71) - 0.48) * 3.5, 0, 1);
                    const fade = std.math.clamp(dir.y * 6, 0, 1);
                    c = lerp3(c, rgb(1, 1, 1), density * fade * 0.9);
                }
            } else {
                c = lerp3(horizon, ground, std.math.clamp(-dir.y * 3, 0, 1));
            }

            // Sol: disco brillante y halo
            const s = @max(0, dir.dotProduct(sun_dir));
            c = c.add(rgb(1.0, 0.9, 0.7).scale(std.math.pow(f32, s, 64) * 0.5));
            if (s > 0.9985) c = rgb(1.0, 0.98, 0.9);

            t.pixels[j * width + i] = c;
        }
    }
    return t;
}
