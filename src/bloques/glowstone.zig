//! Piedra luminosa. Emisión: brilla sola y tiene luces puntuales en la escena.

const std = @import("std");
const tex = @import("../texture.zig");
const Material = @import("../raytracer.zig").Material;

const Texture = tex.Texture;
const rgb = tex.rgb;
const noise = tex.noise;
const valueNoise = tex.valueNoise;
const blockTexture = tex.blockTexture;
const px = tex.px;
const ix = tex.ix;
const block_size = tex.block_size;

/// "Piedra luminosa": celdas naranjas con puntos claros y oscuros.
pub fn textura(gpa: std.mem.Allocator) !Texture {
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

pub fn material(textura_ptr: *const Texture) Material {
    return .{
        .Color = .{ .x = 1, .y = 1, .z = 1 },
        .Textura = textura_ptr,
        .Especular = 10,
        .Refractive_index = 0,
        .Emision = 1.0,
        .Propiedades = .{ .Albedo = 0.3, .Especular = 0.1, .Reflectividad = 0, .Transparencia = 0 },
    };
}
