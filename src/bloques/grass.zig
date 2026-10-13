//! Pasto. Opaco y mate: solo difuso.

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

pub fn textura(gpa: std.mem.Allocator) !Texture {
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

pub fn material(textura_ptr: *const Texture) Material {
    return .{
        .Color = .{ .x = 1, .y = 1, .z = 1 },
        .Textura = textura_ptr,
        .Especular = 8,
        .Refractive_index = 0,
        .Propiedades = .{ .Albedo = 0.9, .Especular = 0.05, .Reflectividad = 0, .Transparencia = 0 },
    };
}
