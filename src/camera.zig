const rl = @import("raylib");
const std = @import("std");

pub const Camera = struct {
    Postition: rl.Vector3,
    Forward: rl.Vector3,
    Right: rl.Vector3,
    Up: rl.Vector3,

    pub fn init(position: rl.Vector3, target: rl.Vector3) Camera {
        var out = Camera{
            .Forward = .zero(), //Se va a reemplazar
            .Postition = position,
            .Right = .{ .x = 1, .y = 0, .z = 0 },
            .Up = .{ .x = 0, .y = 1, .z = 0 },
        };
        out.lookAt(target);
        return out;
    }

    //https://www.scratchapixel.com/lessons/mathematics-physics-for-computer-graphics/lookat-function//framing-lookat-function.html
    pub fn lookAt(self: *Camera, target: rl.Vector3) void {
        self.Forward = target.subtract(self.Postition).normalize();

        // Usamos siempre el "arriba" del mundo como vector auxiliar (en vez del Up
        // anterior de la cámara) para que no se acumule error entre frames.
        // Con producto cruz sacamos un vector perpendicular a Forward y al arriba del
        // mundo: ese es Right. El orden importa: Forward x Up da Right (Up x Forward da Left),
        // así la imagen no sale en espejo.
        const world_up = rl.Vector3{ .x = 0, .y = 1, .z = 0 };
        self.Right = rl.Vector3.crossProduct(self.Forward, world_up).normalize();

        // Up sí queda 100% perpendicular a Right y Forward.
        self.Up = rl.Vector3.crossProduct(self.Right, self.Forward).normalize();
    }
};
