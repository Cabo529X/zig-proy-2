const Sphere = @import("sphere.zig").Sphere;
const Cube = @import("cube.zig").Cube;
const Intersect = @import("raytracer.zig").Intersect;
const Material = @import("raytracer.zig").Material;
const rl = @import("raylib");

const tipo = enum {
    Sphere,
    Cube,
};

pub const Forma = union(tipo) {
    Sphere: Sphere,
    Cube: Cube,

    pub fn intersect(self: *const Forma, origin: rl.Vector3, direction: rl.Vector3) ?Intersect {
        return switch (self.*) {
            .Sphere => |*a| a.intersect(origin, direction),
            .Cube => |*a| a.intersect(origin, direction),
        };
    }

    pub fn material(self: *const Forma) *const Material {
        return switch (self.*) {
            .Sphere => |*a| &a.material,
            .Cube => |*a| &a.material,
        };
    }
};
