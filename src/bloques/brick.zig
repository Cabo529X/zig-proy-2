//! Ladrillo. Opaco y mate: solo difuso.

const std = @import("std");
const tex = @import("../texture.zig");
const Material = @import("../raytracer.zig").Material;

const rl = @import("raylib");
const Vec3 = rl.Vector3;
const Texture = tex.Texture;
const rgb = tex.rgb;
const noise = tex.noise;
const valueNoise = tex.valueNoise;
const blockTexture = tex.blockTexture;
const px = tex.px;
const ix = tex.ix;
const block_size = tex.block_size;

pub fn textura(gpa: std.mem.Allocator) !Texture {
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

pub fn material(textura_ptr: *const Texture) Material {
    return .{
        .Color = .{ .x = 1, .y = 1, .z = 1 },
        .Textura = textura_ptr,
        .Especular = 8,
        .Refractive_index = 0,
        .Propiedades = .{ .Albedo = 0.95, .Especular = 0.05, .Reflectividad = 0, .Transparencia = 0 },
    };
}
