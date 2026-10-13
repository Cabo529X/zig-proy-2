//! Piedra. Opaca y mate: solo difuso.

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

pub fn material(textura_ptr: *const Texture) Material {
    return .{
        .Color = .{ .x = 1, .y = 1, .z = 1 },
        .Textura = textura_ptr,
        .Especular = 16,
        .Refractive_index = 0,
        .Propiedades = .{ .Albedo = 0.9, .Especular = 0.1, .Reflectividad = 0, .Transparencia = 0 },
    };
}
