const std = @import("std");
const rl = @import("raylib");

const Forma = @import("formas.zig").Forma;
const Cube = @import("cube.zig").Cube;
const Light = @import("raytracer.zig").Light;
const Material = @import("raytracer.zig").Material;
const Scene = @import("tracer.zig").Scene;
const tex = @import("texture.zig");
const Texture = tex.Texture;

const Vec3 = rl.Vector3;

fn v3(x: f32, y: f32, z: f32) Vec3 {
    return .{ .x = x, .y = y, .z = z };
}

const Textures = struct {
    grass: Texture,
    stone: Texture,
    wood: Texture,
    brick: Texture,
    mirror: Texture,
    glass: Texture,
    glowstone: Texture,
    sky: Texture,
};

/// Dirección hacia el sol. Se usa para la luz y para dibujar el sol en el skybox.
const sun_direction = blk: {
    // Normalizado a mano porque Vector3.normalize de raylib no se puede evaluar en comptime.
    const x = 0.5;
    const y = 0.75;
    const z = 0.4;
    const len = @sqrt(x * x + y * y + z * z);
    break :blk Vec3{ .x = x / len, .y = y / len, .z = z / len };
};

/// Diorama: una isla de bloques con una casa de ladrillo, un árbol, un espejo,
/// un bloque de vidrio y tres lámparas.
/// Las unidades son "bloques": las texturas se repiten cada 1 unidad.
pub const World = struct {
    textures: *Textures,
    objects: []Forma,
    lights: []Light,

    pub fn init(gpa: std.mem.Allocator) !World {
        const t = try gpa.create(Textures);
        errdefer gpa.destroy(t);

        // Si algo falla a medias, liberamos lo que ya se generó
        var loaded: usize = 0;
        errdefer inline for (std.meta.fields(Textures), 0..) |field, i| {
            if (i < loaded) @field(t, field.name).deinit(gpa);
        };
        t.grass = try tex.grass(gpa);
        loaded += 1;
        t.stone = try tex.stone(gpa);
        loaded += 1;
        t.wood = try tex.wood(gpa);
        loaded += 1;
        t.brick = try tex.brick(gpa);
        loaded += 1;
        t.mirror = try tex.mirror(gpa);
        loaded += 1;
        t.glass = try tex.glass(gpa);
        loaded += 1;
        t.glowstone = try tex.glowstone(gpa);
        loaded += 1;
        t.sky = try tex.skybox(gpa, 1024, 512, sun_direction);
        loaded += 1;

        // --- Materiales ---
        // Cada uno con su textura y sus propios Albedo / Especular / Reflectividad / Transparencia.
        const white = v3(1, 1, 1);

        const grass: Material = .{
            .Color = white,
            .Textura = &t.grass,
            .Especular = 8,
            .Refractive_index = 0,
            .Propiedades = .{ .Albedo = 0.9, .Especular = 0.05, .Reflectividad = 0, .Transparencia = 0 },
        };
        const stone: Material = .{
            .Color = white,
            .Textura = &t.stone,
            .Especular = 16,
            .Refractive_index = 0,
            .Propiedades = .{ .Albedo = 0.9, .Especular = 0.1, .Reflectividad = 0, .Transparencia = 0 },
        };
        const wood: Material = .{
            .Color = white,
            .Textura = &t.wood,
            .Especular = 20,
            .Refractive_index = 0,
            .Propiedades = .{ .Albedo = 0.9, .Especular = 0.15, .Reflectividad = 0, .Transparencia = 0 },
        };
        const brick: Material = .{
            .Color = white,
            .Textura = &t.brick,
            .Especular = 8,
            .Refractive_index = 0,
            .Propiedades = .{ .Albedo = 0.95, .Especular = 0.05, .Reflectividad = 0, .Transparencia = 0 },
        };
        const mirror: Material = .{
            .Color = white,
            .Textura = &t.mirror,
            .Especular = 120,
            .Refractive_index = 0,
            .Propiedades = .{ .Albedo = 0.1, .Especular = 0.8, .Reflectividad = 0.85, .Transparencia = 0 },
        };
        const glass: Material = .{
            .Color = white,
            .Textura = &t.glass,
            .Especular = 150,
            .Refractive_index = 1.5,
            .Propiedades = .{ .Albedo = 0.05, .Especular = 0.9, .Reflectividad = 0.05, .Transparencia = 0.9 },
        };
        const glowstone: Material = .{
            .Color = white,
            .Textura = &t.glowstone,
            .Especular = 10,
            .Refractive_index = 0,
            .Emision = 1.0,
            .Propiedades = .{ .Albedo = 0.3, .Especular = 0.1, .Reflectividad = 0, .Transparencia = 0 },
        };

        // --- Objetos ---
        const objects = try gpa.alloc(Forma, 15);
        errdefer gpa.free(objects);
        var n: usize = 0;
        const add = struct {
            fn box(list: []Forma, count: *usize, min: Vec3, max: Vec3, material: Material) void {
                list[count.*] = .{ .Cube = .init(min, max, material) };
                count.* += 1;
            }
        }.box;

        // Isla: base de piedra y capa de pasto
        add(objects, &n, v3(-4, -2, -4), v3(4, -1, 4), stone);
        add(objects, &n, v3(-4, -1, -4), v3(4, 0, 4), grass);

        // Casa de ladrillo (atrás a la izquierda) con puerta, techo y torrecita de madera
        add(objects, &n, v3(-4, 0, -4), v3(-1, 2, -1), brick);
        add(objects, &n, v3(-3, 0, -1), v3(-2, 2, -0.9), wood);
        add(objects, &n, v3(-4, 2, -4), v3(-1, 3, -1), wood);
        add(objects, &n, v3(-3, 3, -3), v3(-2, 4, -2), wood);

        // Árbol (atrás a la derecha)
        add(objects, &n, v3(2, 0, -3), v3(3, 3, -2), wood);
        add(objects, &n, v3(1, 3, -4), v3(4, 4, -1), grass);
        add(objects, &n, v3(2, 4, -3), v3(3, 5, -2), grass);

        // Baldosa de espejo en el piso (a la derecha del centro): refleja la casa, el árbol y las lámparas
        add(objects, &n, v3(0, 0, -1), v3(3, 0.12, 2), mirror);

        // Bloque grande de vidrio (frente a la casa)
        add(objects, &n, v3(-3, 0, 0), v3(-1, 2, 2), glass);

        // Pilar de piedra con una lámpara arriba
        add(objects, &n, v3(-1, 0, -3), v3(0, 3, -2), stone);
        add(objects, &n, v3(-1, 3, -3), v3(0, 4, -2), glowstone);

        // Lámparas de piedra luminosa en el suelo, al frente
        add(objects, &n, v3(3, 0, 2), v3(4, 1, 3), glowstone);
        add(objects, &n, v3(-4, 0, 2), v3(-3, 1, 3), glowstone);

        std.debug.assert(n == objects.len);

        // --- Luces ---
        // El sol, y una luz cálida en el centro de cada lámpara (los materiales que brillan
        // se ven brillar solos, y estas luces hacen que también iluminen lo que tienen cerca).
        const lamp_color = v3(1.0, 0.7, 0.35);
        const lights = try gpa.alloc(Light, 4);
        errdefer gpa.free(lights);
        lights[0] = .{
            .Color = v3(1.0, 0.95, 0.85),
            .Intensity = 0.95,
            .Position = sun_direction.scale(100),
        };
        lights[1] = .{ .Color = lamp_color, .Intensity = 1.4, .Attenuation = 0.25, .Position = v3(-0.5, 3.5, -2.5) };
        lights[2] = .{ .Color = lamp_color, .Intensity = 1.4, .Attenuation = 0.25, .Position = v3(3.5, 0.5, 2.5) };
        lights[3] = .{ .Color = lamp_color, .Intensity = 1.4, .Attenuation = 0.25, .Position = v3(-3.5, 0.5, 2.5) };

        return .{ .textures = t, .objects = objects, .lights = lights };
    }

    pub fn deinit(self: World, gpa: std.mem.Allocator) void {
        gpa.free(self.lights);
        gpa.free(self.objects);
        inline for (std.meta.fields(Textures)) |field| {
            @field(self.textures, field.name).deinit(gpa);
        }
        gpa.destroy(self.textures);
    }

    pub fn scene(self: *const World) Scene {
        return .{
            .objects = self.objects,
            .lights = self.lights,
            .sky = &self.textures.sky,
            .ambient = v3(0.30, 0.34, 0.42),
        };
    }
};
