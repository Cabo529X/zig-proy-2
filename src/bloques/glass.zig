//! Vidrio. Refracción (índice 1.5), Fresnel, reflexión y tinte de color.

const std = @import("std");
const tex = @import("../texture.zig");

const Texture = tex.Texture;
const rgb = tex.rgb;
const noise = tex.noise;
const valueNoise = tex.valueNoise;
const blockTexture = tex.blockTexture;
const px = tex.px;
const ix = tex.ix;
const block_size = tex.block_size;

/// Vidrio azulado con marco y un destello diagonal.
pub fn textura(gpa: std.mem.Allocator) !Texture {
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
