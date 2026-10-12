const std = @import("std");
const rl = @import("raylib");

const Forma = @import("formas.zig").Forma;
const Camera = @import("camera.zig").Camera;
const Framebuffer = @import("framebuffer.zig").Framebuffer;
const Texture = @import("texture.zig").Texture;
const Light = @import("raytracer.zig").Light;
const Intersect = @import("raytracer.zig").Intersect;
const V3ToColor = @import("raytracer.zig").V3ToColor;

const Vec3 = rl.Vector3;

/// Distancia que movemos los orígenes de los rayos secundarios para no volver a
/// chocar con la superficie de la que salen.
const bias: f32 = 1e-3;

pub const max_depth = 5;

pub const Scene = struct {
    objects: []const Forma,
    lights: []const Light,
    sky: *const Texture,
    // Luz mínima que llega a todos lados (luz del cielo), para que las sombras no sean negro puro.
    ambient: Vec3,
};

fn reflect(incident: Vec3, normal: Vec3) Vec3 {
    return incident.subtract(normal.scale(2 * incident.dotProduct(normal)));
}

/// Ley de Snell. `normal` debe apuntar en contra de `incident` y eta = n1 / n2.
/// Devuelve null si hay reflexión interna total.
fn refract(incident: Vec3, normal: Vec3, eta: f32) ?Vec3 {
    const cosi = -incident.dotProduct(normal);
    const k = 1 - eta * eta * (1 - cosi * cosi);
    if (k < 0) return null;
    return incident.scale(eta).add(normal.scale(eta * cosi - @sqrt(k))).normalize();
}

/// Aproximación de Schlick a las ecuaciones de Fresnel:
/// qué fracción de la luz se refleja (el resto se transmite) según el ángulo.
fn schlick(cosine: f32, refractive_index: f32) f32 {
    var r0 = (1 - refractive_index) / (1 + refractive_index);
    r0 = r0 * r0;
    return r0 + (1 - r0) * std.math.pow(f32, 1 - cosine, 5);
}

fn closestHit(origin: Vec3, direction: Vec3, objects: []const Forma) ?Intersect {
    var closest: ?Intersect = null;
    var z_buffer: f32 = std.math.floatMax(f32);
    for (objects) |*object| {
        const hit = object.intersect(origin, direction) orelse continue;
        if (hit.Distancia < z_buffer) {
            z_buffer = hit.Distancia;
            closest = hit;
        }
    }
    return closest;
}

/// Cuánta luz pasa entre `origin` y la luz (1 = toda, 0 = nada).
/// Los objetos opacos la bloquean; los transparentes dejan pasar una parte.
/// Los materiales que brillan no hacen sombra (la luz sale de ellos).
fn lightVisibility(origin: Vec3, direction: Vec3, max_distance: f32, objects: []const Forma) f32 {
    var visibility: f32 = 1;
    for (objects) |*object| {
        const mat = object.material();
        if (mat.Emision > 0) continue;
        const hit = object.intersect(origin, direction) orelse continue;
        if (hit.Distancia >= max_distance) continue;
        visibility *= mat.Propiedades.Transparencia * 0.8;
        if (visibility < 0.001) return 0;
    }
    return visibility;
}

/// Lo que se ve en una dirección cuando el rayo no choca con nada.
fn background(scene: *const Scene, direction: Vec3) Vec3 {
    return scene.sky.sampleSky(direction);
}

/// Rayo secundario (reflejo o refracción). Cuando se acaba la recursión usamos el
/// skybox directamente en vez de devolver negro.
fn secondary(origin: Vec3, direction: Vec3, scene: *const Scene, depth: usize) Vec3 {
    if (depth == 0) return background(scene, direction);
    return castRay(origin, direction, scene, depth - 1);
}

pub fn castRay(origin: Vec3, direction: Vec3, scene: *const Scene, depth: usize) Vec3 {
    const hit = closestHit(origin, direction, scene.objects) orelse return background(scene, direction);
    const mat = hit.Material;

    // Color de la textura en este punto, con el tinte del material
    const tex = mat.Textura.sampleNearest(hit.U, hit.V).multiply(mat.Color);

    // Si el rayo viene desde adentro de un objeto (ya refractado), la normal debe voltearse
    // para que siempre apunte hacia donde está el rayo.
    const entering = direction.dotProduct(hit.Normal) < 0;
    const normal = if (entering) hit.Normal else hit.Normal.negate();

    // Desde el punto a la cámara
    const view_direction = direction.negate();

    // --- Luz directa (Phong + sombras) ---
    var diffuse_light = scene.ambient;
    var specular_light: Vec3 = .zero();
    const shadow_origin = hit.Punto.add(normal.scale(bias));

    for (scene.lights) |light| {
        const to_light = light.Position.subtract(hit.Punto);
        const light_distance_sqr = to_light.lengthSqr();
        const light_distance = @sqrt(light_distance_sqr);
        // La dirección del punto a la luz
        const light_dir = to_light.scale(1 / light_distance);

        // ¿Cómo sabemos qué tan "bien" nos pega la luz?
        const n_dot_l = normal.dotProduct(light_dir);
        if (n_dot_l <= 0) continue;

        const visibility = lightVisibility(shadow_origin, light_dir, light_distance, scene.objects);
        if (visibility <= 0) continue;

        const attenuation = 1 / (1 + light.Attenuation * light_distance_sqr);
        const strength = light.Intensity * attenuation * visibility;

        diffuse_light = diffuse_light.add(light.Color.scale(n_dot_l * strength));

        // Dirección a la que reflejamos la luz
        const reflection_dir = reflect(light_dir.negate(), normal);

        // ¿Qué tan liso es nuestro objeto?
        // ¿Qué tan intensa y precisa es su relfexión especular?
        const specular_intensity = std.math.pow(f32, @max(0, reflection_dir.dotProduct(view_direction)), mat.Especular);
        specular_light = specular_light.add(light.Color.scale(specular_intensity * strength));
    }

    // El cómo mezclar los objetos es más al gusto.
    var color = tex.multiply(diffuse_light).scale(mat.Propiedades.Albedo);
    color = color.add(specular_light.scale(mat.Propiedades.Especular));

    // --- Material que brilla ---
    if (mat.Emision > 0) {
        color = color.add(tex.scale(mat.Emision));
    }

    // --- Reflexión y refracción ---
    var reflect_weight = mat.Propiedades.Reflectividad;
    var refract_weight = mat.Propiedades.Transparencia;
    var refract_direction: ?Vec3 = null;

    if (refract_weight > 0) {
        // Entrando al material pasamos de aire (1) al índice del material; saliendo, al revés.
        const eta = if (entering) 1 / mat.Refractive_index else mat.Refractive_index;
        refract_direction = refract(direction, normal, eta);

        if (refract_direction) |refracted| {
            // Fresnel: en ángulos rasantes el vidrio se comporta más como espejo.
            const cosine = if (entering) -direction.dotProduct(normal) else -refracted.dotProduct(normal);
            const fresnel = schlick(cosine, mat.Refractive_index);
            reflect_weight += refract_weight * fresnel;
            refract_weight *= 1 - fresnel;
        } else {
            // Reflexión interna total: nada se transmite, todo se refleja.
            reflect_weight += refract_weight;
            refract_weight = 0;
        }
    }

    if (reflect_weight > 0) {
        const reflect_direction = reflect(direction, normal);
        const reflect_color = secondary(hit.Punto.add(normal.scale(bias)), reflect_direction, scene, depth);
        // Multiplicar por la textura hace que los materiales con color
        // (o con marco, como el espejo) tiñan lo que reflejan.
        color = color.add(reflect_color.multiply(tex).scale(reflect_weight));
    }

    if (refract_weight > 0) {
        if (refract_direction) |refracted| {
            const refract_color = secondary(hit.Punto.subtract(normal.scale(bias)), refracted, scene, depth);
            color = color.add(refract_color.multiply(tex).scale(refract_weight));
        }
    }

    return color;
}

// ---------------------------------------------------------------------------
// Render concurrente
// ---------------------------------------------------------------------------

const max_threads = 64;

const RenderJob = struct {
    target: *Framebuffer,
    scene: *const Scene,
    camera: Camera,
    // Siguiente fila por renderizar. Cada hilo toma una fila con fetchAdd,
    // así los hilos que terminan rápido (filas de cielo) toman más trabajo.
    next_row: std.atomic.Value(usize) = .init(0),
};

fn renderRows(job: *RenderJob) void {
    const target = job.target;
    const width: usize = @intCast(target.width);
    const height: usize = @intCast(target.height);

    const width_f32: f32 = @floatFromInt(width);
    const height_f32: f32 = @floatFromInt(height);

    const aspect_ratio = width_f32 / height_f32;
    const FOV = std.math.pi / 3.0;
    const perspective_scale = @tan(FOV * 0.5);
    const camera = job.camera;

    while (true) {
        const screen_y = job.next_row.fetchAdd(1, .monotonic);
        if (screen_y >= height) break;

        for (0..width) |screen_x| {
            // +0.5: el rayo pasa por el centro del píxel
            const x_f32: f32 = @as(f32, @floatFromInt(screen_x)) + 0.5;
            const y_f32: f32 = @as(f32, @floatFromInt(screen_y)) + 0.5;

            const x_minus1_to_1 = (x_f32 * 2) / width_f32 - 1;
            const y_minus1_to_1 = 1 - (y_f32 * 2) / height_f32;

            const x_direction = x_minus1_to_1 * aspect_ratio * perspective_scale;
            const y_direction = y_minus1_to_1 * perspective_scale;

            const direction_from_camera = (Vec3{
                .x = x_direction,
                .y = y_direction,
                .z = 1,
            }).normalize();

            const direction = Vec3{
                .x = direction_from_camera.x * camera.Right.x + direction_from_camera.y * camera.Up.x + direction_from_camera.z * camera.Forward.x,
                .y = direction_from_camera.x * camera.Right.y + direction_from_camera.y * camera.Up.y + direction_from_camera.z * camera.Forward.y,
                .z = direction_from_camera.x * camera.Right.z + direction_from_camera.y * camera.Up.z + direction_from_camera.z * camera.Forward.z,
            };

            const col = castRay(camera.Postition, direction, job.scene, max_depth);
            target.set_pixel(screen_x, screen_y, V3ToColor(col));
        }
    }
}

/// Renderiza la escena completa repartiendo las filas entre `thread_count` hilos
/// (el hilo que llama también trabaja). Cada píxel es independiente de los demás,
/// así que no hace falta sincronizar nada más que el contador de filas.
pub fn render(target: *Framebuffer, scene: *const Scene, camera: Camera, thread_count: usize) void {
    var job = RenderJob{
        .target = target,
        .scene = scene,
        .camera = camera,
    };

    var threads: [max_threads]std.Thread = undefined;
    var spawned: usize = 0;
    const wanted = @min(thread_count, max_threads) -| 1;
    while (spawned < wanted) : (spawned += 1) {
        threads[spawned] = std.Thread.spawn(.{}, renderRows, .{&job}) catch break;
    }

    renderRows(&job);

    for (threads[0..spawned]) |thread| thread.join();

    target.upload();
}
