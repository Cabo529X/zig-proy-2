//! Madera. Opaca y mate: solo difuso.

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

pub fn textura(gpa: std.mem.Allocator) !Texture {
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
