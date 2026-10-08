const std = @import("std");
const rl = @import("raylib");
const Intersect = @import("raytracer.zig").Intersect;
const Material = @import("raytracer.zig").Material;

const eps: f32 = 1e-4;

/// Caja alineada a los ejes (AABB). Con lados de 1 es un cubo; con lados mayores
/// la textura se repite cada unidad del mundo, así que se ve como una pila de cubos.
pub const Cube = struct {
    min: rl.Vector3,
    max: rl.Vector3,
    material: Material,

    pub fn init(min: rl.Vector3, max: rl.Vector3, material: Material) Cube {
        return .{ .min = min, .max = max, .material = material };
    }

    fn axis(v: rl.Vector3, i: usize) f32 {
        return switch (i) {
            0 => v.x,
            1 => v.y,
            else => v.z,
        };
    }

    // Método de los "slabs": intersectamos el rayo con los 3 pares de planos
    // y nos quedamos con el intervalo [t_near, t_far] donde está dentro de los 3.
    pub fn intersect(self: *const Cube, origin: rl.Vector3, direction: rl.Vector3) ?Intersect {
        var t_near: f32 = -std.math.floatMax(f32);
        var t_far: f32 = std.math.floatMax(f32);
        var near_axis: usize = 0;
        var far_axis: usize = 0;

        for (0..3) |i| {
            const o = axis(origin, i);
            const d = axis(direction, i);
            const lo = axis(self.min, i);
            const hi = axis(self.max, i);

            if (@abs(d) < 1e-8) {
                // Paralelo a este par de planos: o está entre ellos o nunca choca.
                if (o < lo or o > hi) return null;
                continue;
            }

            const inv = 1 / d;
            var t1 = (lo - o) * inv;
            var t2 = (hi - o) * inv;
            if (t1 > t2) std.mem.swap(f32, &t1, &t2);

            if (t1 > t_near) {
                t_near = t1;
                near_axis = i;
            }
            if (t2 < t_far) {
                t_far = t2;
                far_axis = i;
            }
            if (t_near > t_far) return null;
        }

        if (t_far < eps) return null;

        // Si el origen está dentro de la caja (rayos refractados), el choque es la cara de salida.
        const t: f32 = if (t_near > eps) t_near else t_far;
        const hit_axis: usize = if (t_near > eps) near_axis else far_axis;
        const d_axis = axis(direction, hit_axis);

        // Normal siempre hacia afuera de la caja
        const sign: f32 = if (t_near > eps)
            (if (d_axis > 0) -1 else 1)
        else
            (if (d_axis > 0) 1 else -1);

        var normal = rl.Vector3.zero();
        const point = origin.add(direction.scale(t));

        // UV en unidades del mundo, el origen de v queda arriba en las caras laterales.
        var u: f32 = undefined;
        var v: f32 = undefined;
        switch (hit_axis) {
            0 => {
                normal.x = sign;
                u = point.z * sign * -1;
                v = -point.y;
            },
            1 => {
                normal.y = sign;
                u = point.x;
                v = point.z * sign * -1;
            },
            else => {
                normal.z = sign;
                u = point.x * sign;
                v = -point.y;
            },
        }

        return .{
            .Material = &self.material,
            .Distancia = t,
            .Normal = normal,
            .Punto = point,
            .U = u,
            .V = v,
        };
    }
};
