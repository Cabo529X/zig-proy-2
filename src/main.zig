const std = @import("std");
const builtin = @import("builtin");

const rl = @import("raylib");
const Framebuffer = @import("framebuffer.zig").Framebuffer;
const Forma = @import("formas.zig").Forma;
const Camera = @import("camera.zig").Camera;
const Light = @import("raytracer.zig").Light;
const Intersect = @import("raytracer.zig").Intersect;
const Material = @import("raytracer.zig").Material;

const htmlColor = @import("cute_colors.zig").htmlColor;
const V3FromColor = @import("raytracer.zig").V3FromColor;
const V3ToColor = @import("raytracer.zig").V3ToColor;

const Clock = std.Io.Clock.real;

const width = 1300;
const height = 900;

const block_sz = 100;

pub fn main() !void {
    var alloc = switch (builtin.mode) {
        .Debug, .ReleaseSafe => std.heap.DebugAllocator(.{}).init,
        .ReleaseFast, .ReleaseSmall => std.heap.smp_allocator,
    };
    const gpa: std.mem.Allocator = switch (builtin.mode) {
        .Debug, .ReleaseSafe => alloc.allocator(),
        .ReleaseFast, .ReleaseSmall => std.heap.smp_allocator,
    };
    defer switch (builtin.mode) {
        .Debug, .ReleaseSafe => _ = alloc.deinit(),
        .ReleaseFast, .ReleaseSmall => {},
    };

    var threaded: std.Io.Threaded = .init(gpa, .{});
    const io = threaded.io();
    var framebuffer = Framebuffer.init(width, height, .black, .white);

    rl.initWindow(width, height, "Raytracer!!!");
    rl.setTraceLogLevel(.warning);
    defer rl.closeWindow();
    rl.setTargetFPS(60);

    var last_frame_time = Clock.now(io);
    var delta: i64 = 1;

    const espejo = Material{
        .Color = V3FromColor(htmlColor("#fff")),
        .Propiedades = .{
            .Albedo = 0,
            .Especular = 1,
            .Reflectividad = 0.9,
            .Transparencia = 0,
        },
        .Especular = 100,
        .Refractive_index = 0,
    };

    const vidrio = Material{
        .Color = V3FromColor(htmlColor("#aaa")),
        .Propiedades = .{
            .Albedo = 0,
            .Especular = 0.5,
            .Reflectividad = 0.1,
            .Transparencia = 0.8,
        },
        .Especular = 125,
        .Refractive_index = 1.5,
    };

    const diamante = Material{
        .Color = V3FromColor(htmlColor("#aaa")),
        .Propiedades = .{
            .Albedo = 0,
            .Especular = 0.5,
            .Reflectividad = 0.1,
            .Transparencia = 0.8,
        },
        .Especular = 125,
        .Refractive_index = 2.417,
    };

    const marmol = Material{
        .Color = V3FromColor(htmlColor("#66664c")),
        .Propiedades = .{
            .Albedo = 0.4,
            .Especular = 0.3,
            .Reflectividad = 0,
            .Transparencia = 0,
        },
        .Especular = 10,
        .Refractive_index = 0,
    };

    const spheres = [_]Forma{
        .{ .Sphere = .{
            .center = .{ .x = 10, .y = 0, .z = -40 },
            .radius = 5,
            .material = espejo,
        } },
        .{ .Sphere = .{
            .center = .{ .x = 12.5, .y = 0, .z = -60 },
            .radius = 5,
            .material = .{
                .Color = V3FromColor(htmlColor("#4c1919")),
                .Propiedades = .{
                    .Albedo = 0.9,
                    .Especular = 0.1,
                    .Reflectividad = 0,
                    .Transparencia = 0,
                },
                .Especular = 10,
                .Refractive_index = 0,
            },
        } },
        .{ .Sphere = .{
            .center = .{ .x = 0, .y = 0, .z = 0 },
            .radius = 5,
            .material = marmol,
        } },
        .{ .Sphere = .{
            .center = .{ .x = 22, .y = 0, .z = -45 },
            .radius = 5,
            .material = espejo,
        } },
        .{ .Sphere = .{
            .center = .{ .x = -25, .y = 0, .z = -40 },
            .radius = 5,
            .material = vidrio,
        } },
        .{ .Sphere = .{
            .center = .{ .x = -37, .y = 0, .z = -40 },
            .radius = 5,
            .material = diamante,
        } },
    };

    const lights = [_]Light{
        .{
            .Color = V3FromColor(htmlColor("#f00")),
            .Intensity = 1,
            .Position = .{ .x = 5, .y = 100, .z = 15 },
        },
        .{
            .Color = V3FromColor(htmlColor("#fff")),
            .Intensity = 1,
            .Position = .{ .x = 0, .y = 0, .z = -250 },
        },
    };

    const cameraDistance = 100;
    var camera: Camera = .init(.{
        .x = 0,
        .y = 0,
        .z = cameraDistance,
    }, .zero());

    const cameraTurnSpeed: f32 = std.math.pi / 2.0;
    var camera_x_angle: f32 = std.math.pi;
    var camera_y_angle: f32 = 0;

    const camera_y_angle_max = std.math.pi / 4.0;
    const camera_y_angle_min = -camera_y_angle_max;

    while (!rl.windowShouldClose()) {
        defer {
            const now = Clock.now(io);
            delta = last_frame_time.durationTo(now).toMicroseconds();
            last_frame_time = now;
        }
        framebuffer.clear();

        const dt: f32 = @as(f32, @floatFromInt(delta)) / 1_000_000;

        if (rl.isKeyDown(.a)) {
            camera_x_angle += cameraTurnSpeed * dt;
        }
        if (rl.isKeyDown(.d)) {
            camera_x_angle -= cameraTurnSpeed * dt;
        }
        if (rl.isKeyDown(.w)) {
            camera_y_angle += cameraTurnSpeed * dt;
            camera_y_angle = @max(camera_y_angle_min, @min(camera_y_angle_max, camera_y_angle));
        }
        if (rl.isKeyDown(.s)) {
            camera_y_angle -= cameraTurnSpeed * dt;
            camera_y_angle = @max(camera_y_angle_min, @min(camera_y_angle_max, camera_y_angle));
        }

        camera.Postition.x = @cos(camera_x_angle) * cameraDistance;
        camera.Postition.y = @sin(camera_y_angle) * cameraDistance;
        camera.Postition.z = @sin(camera_x_angle) * cameraDistance;

        camera.lookAt(.zero());

        try render(&framebuffer, &spheres, &lights, camera);

        try framebuffer.swap_buffers();
    }
}

fn render(target: *Framebuffer, objects: []const Forma, lights: []const Light, camera: Camera) !void {
    const width_f32: f32 = @floatFromInt(target.width);
    const height_f32: f32 = @floatFromInt(target.height);

    const aspect_ratio = width_f32 / height_f32;
    const FOV = std.math.pi / 3.0;
    const perspective_scale = @tan(FOV * 0.5);

    for (0..height) |screen_y| {
        for (0..width) |screen_x| {
            const x_f32: f32 = @floatFromInt(screen_x);
            const y_f32: f32 = @floatFromInt(screen_y);

            const x_minus1_to_1 = (x_f32 * 2) / width_f32 - 1;
            const y_minus1_to_1 = 1 - (y_f32 * 2) / height_f32;

            const x_direction = x_minus1_to_1 * aspect_ratio * perspective_scale;
            const y_direction = y_minus1_to_1 * perspective_scale;

            const direction_from_camera = (rl.Vector3{
                .x = x_direction,
                .y = y_direction,
                .z = 1,
            }).normalize();

            const direction = rl.Vector3{
                .x = direction_from_camera.x * camera.Right.x + direction_from_camera.y * camera.Up.x + direction_from_camera.z * camera.Forward.x,
                .y = direction_from_camera.x * camera.Right.y + direction_from_camera.y * camera.Up.y + direction_from_camera.z * camera.Forward.y,
                .z = direction_from_camera.x * camera.Right.z + direction_from_camera.y * camera.Up.z + direction_from_camera.z * camera.Forward.z,
            };

            const col = cast_ray(camera.Postition, direction, objects, lights, 5);
            target.set_current_color(V3ToColor(col));
            try target.set_pixel(@intCast(screen_x), @intCast(screen_y));
        }
    }
}

fn reflect(incident: rl.Vector3, normal: rl.Vector3) rl.Vector3 {
    return incident.subtract(normal.scale(2 * incident.dotProduct(normal)));
}

fn refract(incident: rl.Vector3, normal: rl.Vector3, refractive_index: f32) ?rl.Vector3 {
    var cosi = incident.dotProduct(normal);

    var etai: f32 = 1;
    var etat = refractive_index;
    var n = normal;

    if (cosi > 0) {
        std.mem.swap(f32, &etai, &etat);
        n = n.scale(-1);
    } else {
        cosi = -cosi;
    }

    const eta = etai / etat;
    const k = 1 - eta * eta * (1 - cosi * cosi);

    if (k < 0) {
        return null;
    } else {
        return (incident.scale(eta).add(n.scale(eta * cosi - @sqrt(k)))).normalize();
    }
}

fn cast_ray(origin: rl.Vector3, direction: rl.Vector3, objects: []const Forma, lights: []const Light, max_recursion: usize) rl.Vector3 {
    var closest_hit: ?Intersect = null;
    var z_buffer: f32 = std.math.floatMax(f32);
    for (objects) |object| {
        const hit = object.intersect(
            origin,
            direction,
        ) orelse continue;

        if (hit.Distancia < z_buffer) {
            z_buffer = hit.Distancia;

            closest_hit = hit;
        }
    }

    if (closest_hit) |hit| {
        const mat = hit.Material;
        var color: rl.Vector3 = .zero();

        // Desde el punto a la cámara
        const view_direction = direction.scale(-1);

        if (mat.Propiedades.Reflectividad > 0) {
            if (max_recursion > 0) {
                const reflect_direction = rl.Vector3{ .x = 0, .y = 1, .z = 0 };
                const new_og = hit.Punto; // Esto puede hacer que topemos con la misma figura
                // Eso es malo
                const reflect_color = cast_ray(new_og, reflect_direction, objects, lights, max_recursion - 1);
                color = color.add(reflect_color.scale(mat.Propiedades.Reflectividad));
            } else {
                // Refleja el fondo
                color = color.add(.zero());
            }
        }

        if (mat.Propiedades.Transparencia > 0) {
            if (max_recursion > 0) {
                if (refract(direction, hit.Normal, mat.Refractive_index)) |refract_direction| {
                    const new_og = hit.Punto; // Esto puede hacer que topemos con la misma figura
                    // Eso es malo
                    const refract_color = cast_ray(new_og, refract_direction, objects, lights, max_recursion - 1);
                    color = color.add(refract_color.scale(mat.Propiedades.Transparencia));
                } else {
                    const reflect_direction = rl.Vector3{ .x = 0, .y = 1, .z = 0 };
                    const new_og = hit.Punto; // Esto puede hacer que topemos con la misma figura
                    // Eso es malo
                    const reflect_color = cast_ray(new_og, reflect_direction, objects, lights, max_recursion - 1);
                    color = color.add(reflect_color.scale(mat.Propiedades.Reflectividad));
                }
            } else {
                // Refleja el fondo
                color = color.add(.zero());
            }
        }

        for (lights) |light| {
            if (obscured(hit.Punto, light, objects))
                continue;

            // La dirección del punto a la luz
            const light_dir = light.Position.subtract(hit.Punto).normalize();

            // ¿Cómo sabemos qué tan "bien" nos pega la luz?
            const diffuse_intensity = @max(0, hit.Normal.dotProduct(light_dir)) * light.Intensity;

            const diffuse = mat.Color.scale(diffuse_intensity);

            // Dirección a la que reflejamos la luz
            const reflection_dir = reflect(light_dir.scale(-1), hit.Normal);

            // ¿Qué tan liso es nuestro objeto?
            // ¿Qué tan intensa y precisa es su relfexión especular?
            const specular_intensity = std.math.pow(f32, @max(0, reflection_dir.dotProduct(view_direction)), mat.Especular) * light.Intensity;

            const specular = light.Color.scale(specular_intensity);

            // El cómo mezclar los objetos es más al gusto.
            color = color.add(diffuse.scale(mat.Propiedades.Albedo));
            color = color.add(specular.scale(mat.Propiedades.Especular));
        }

        return color;
    } else return .zero();
}

fn obscured(origin: rl.Vector3, light: Light, objects: []const Forma) bool {
    const to_light = light.Position.subtract(origin);
    const light_distance = to_light.length();
    const light_dir = to_light.normalize();

    // Empujamos el origen un poco hacia la luz para no toparnos
    // con la misma figura de la que salimos (shadow acne).
    const shadow_origin = origin.add(light_dir.scale(1e-3));

    for (objects) |object| {
        const hit = object.intersect(shadow_origin, light_dir) orelse continue;
        if (hit.Distancia < light_distance) {
            return true;
        }
    }

    return false;
}
