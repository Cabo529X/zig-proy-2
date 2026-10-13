//! Espejo. Reflexión (Reflectividad alta); el marco oscuro tiñe el reflejo.

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

/// Mosaico metálico pulido: lo que más importa es el marco oscuro, la parte
/// central casi no tiene textura para que el reflejo se vea limpio.
pub fn textura(gpa: std.mem.Allocator) !Texture {
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

pub fn material(textura_ptr: *const Texture) Material {
    return .{
        .Color = .{ .x = 1, .y = 1, .z = 1 },
        .Textura = textura_ptr,
        .Especular = 120,
        .Refractive_index = 0,
        .Propiedades = .{ .Albedo = 0.1, .Especular = 0.8, .Reflectividad = 0.85, .Transparencia = 0 },
    };
}
