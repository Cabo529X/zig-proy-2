//! Skybox: imagen equirectangular generada por código (degradado, nubes y sol).

const std = @import("std");
const rl = @import("raylib");
const tex = @import("texture.zig");

const Texture = tex.Texture;
const Vec3 = rl.Vector3;
const rgb = tex.rgb;
const fbm = tex.fbm;
const lerp3 = tex.lerp3;

/// Cielo equirectangular con degradado, sol y nubes.
/// `sun_dir` debe estar normalizado y coincidir con la luz del sol de la escena.
pub fn generar(gpa: std.mem.Allocator, width: usize, height: usize, sun_dir: Vec3) !Texture {
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
