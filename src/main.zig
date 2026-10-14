const std = @import("std");

const rl = @import("raylib");
const Framebuffer = @import("framebuffer.zig").Framebuffer;
const Camera = @import("camera.zig").Camera;
const World = @import("scene.zig").World;
const tracer = @import("tracer.zig");

const width = 1300;
const height = 900;

// Mientras la cámara se mueve renderizamos a menor resolución para que sea interactivo;
// cuando se queda quieta renderizamos una vez a resolución completa.
// La tecla M cambia entre estos factores (1 = resolución completa también al moverse).
const motion_scales = [_]i32{ 4, 2, 1 };

const target = rl.Vector3{ .x = 0, .y = 1, .z = 0 };
const default_x_angle: f32 = 1.0;
const default_y_angle: f32 = 0.5;
const default_distance: f32 = 11;
const distance_min: f32 = 4;
const distance_max: f32 = 40;

/// Pone la cámara en una esfera alrededor del objetivo.
/// x es el giro horizontal, y la inclinación.
fn placeCamera(camera: *Camera, x_angle: f32, y_angle: f32, distance: f32) void {
    camera.Postition = .{
        .x = target.x + @cos(x_angle) * @cos(y_angle) * distance,
        .y = target.y + @sin(y_angle) * distance,
        .z = target.z + @sin(x_angle) * @cos(y_angle) * distance,
    };
    camera.lookAt(target);
}

/// Modo sin ventana: renderiza un solo cuadro a un PNG.
///   proyecto_02 --render salida.png [ancho alto [giro inclinacion distancia]]
fn renderToFile(gpa: std.mem.Allocator, io: std.Io, args: []const [:0]const u8) !void {
    const parse = std.fmt.parseFloat;
    const out_path = args[0];
    const out_width: i32 = if (args.len > 2) try std.fmt.parseInt(i32, args[1], 10) else width;
    const out_height: i32 = if (args.len > 2) try std.fmt.parseInt(i32, args[2], 10) else height;
    const x_angle: f32 = if (args.len > 5) try parse(f32, args[3]) else default_x_angle;
    const y_angle: f32 = if (args.len > 5) try parse(f32, args[4]) else default_y_angle;
    const distance: f32 = if (args.len > 5) try parse(f32, args[5]) else default_distance;

    const world = try World.init(gpa);
    defer world.deinit(gpa);
    const scene = world.scene();

    var framebuffer = try Framebuffer.initCpu(gpa, out_width, out_height);
    defer framebuffer.deinit(gpa);

    var camera: Camera = .init(.{ .x = 0, .y = 0, .z = 14 }, target);
    placeCamera(&camera, x_angle, y_angle, distance);

    const thread_count = std.Thread.getCpuCount() catch 4;
    const clock = std.Io.Clock.real;
    const start = clock.now(io);
    tracer.render(&framebuffer, &scene, camera, thread_count);
    const ms: f64 = @as(f64, @floatFromInt(start.durationTo(clock.now(io)).toMicroseconds())) / 1000;
    std.debug.print("render {d}x{d} con {d} hilos: {d:.0} ms\n", .{ out_width, out_height, thread_count, ms });
    try framebuffer.render_to_file(out_path);
}

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;

    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len > 2 and std.mem.eql(u8, args[1], "--render")) {
        return renderToFile(gpa, init.io, args[2..]);
    }

    rl.initWindow(width, height, "Diorama - Raytracer");
    rl.setTraceLogLevel(.warning);
    defer rl.closeWindow();
    rl.setTargetFPS(60);

    const thread_count = std.Thread.getCpuCount() catch 4;

    const world = try World.init(gpa);
    defer world.deinit(gpa);
    const scene = world.scene();

    // Un framebuffer por cada resolución con la que renderizamos
    var fb_quarter = try Framebuffer.init(gpa, width / 4, height / 4);
    defer fb_quarter.deinit(gpa);
    var fb_half = try Framebuffer.init(gpa, width / 2, height / 2);
    defer fb_half.deinit(gpa);
    var fb_full = try Framebuffer.init(gpa, width, height);
    defer fb_full.deinit(gpa);
    const motion_buffers = [_]*Framebuffer{ &fb_quarter, &fb_half, &fb_full };

    var camera: Camera = .init(.{ .x = 0, .y = 0, .z = 14 }, target);

    // La cámara orbita alrededor del diorama
    var camera_x_angle: f32 = default_x_angle;
    var camera_y_angle: f32 = default_y_angle;
    var camera_distance: f32 = default_distance;

    const camera_turn_speed: f32 = std.math.pi / 2.0;
    const camera_y_angle_min: f32 = 0.05;
    const camera_y_angle_max: f32 = 1.4;

    var auto_rotate = false;
    var motion_scale_index: usize = 1;
    var show_hud = true;

    var displayed: *Framebuffer = &fb_full;
    var full_resolution_ready = false;
    var render_ms: f64 = 0;

    while (!rl.windowShouldClose()) {
        const dt = rl.getFrameTime();
        var moved = false;

        // --- Rotación ---
        if (rl.isKeyDown(.a)) {
            camera_x_angle += camera_turn_speed * dt;
            moved = true;
        }
        if (rl.isKeyDown(.d)) {
            camera_x_angle -= camera_turn_speed * dt;
            moved = true;
        }
        if (rl.isKeyDown(.w)) {
            camera_y_angle += camera_turn_speed * dt;
            moved = true;
        }
        if (rl.isKeyDown(.s)) {
            camera_y_angle -= camera_turn_speed * dt;
            moved = true;
        }
        if (rl.isMouseButtonDown(.left)) {
            const delta = rl.getMouseDelta();
            if (delta.x != 0 or delta.y != 0) {
                camera_x_angle -= delta.x * 0.006;
                camera_y_angle += delta.y * 0.006;
                moved = true;
            }
        }
        if (rl.isKeyPressed(.r)) auto_rotate = !auto_rotate;
        if (auto_rotate) {
            camera_x_angle += 0.5 * dt;
            moved = true;
        }

        // --- Zoom ---
        const wheel = rl.getMouseWheelMove();
        if (wheel != 0) {
            camera_distance *= @exp(-wheel * 0.1);
            moved = true;
        }
        if (rl.isKeyDown(.e) or rl.isKeyDown(.up)) {
            camera_distance *= @exp(-1.2 * dt);
            moved = true;
        }
        if (rl.isKeyDown(.q) or rl.isKeyDown(.down)) {
            camera_distance *= @exp(1.2 * dt);
            moved = true;
        }

        camera_y_angle = std.math.clamp(camera_y_angle, camera_y_angle_min, camera_y_angle_max);
        camera_distance = std.math.clamp(camera_distance, distance_min, distance_max);

        // --- Otros controles ---
        if (rl.isKeyPressed(.m)) {
            motion_scale_index = (motion_scale_index + 1) % motion_scales.len;
            moved = true;
        }
        if (rl.isKeyPressed(.h)) show_hud = !show_hud;
        if (rl.isKeyPressed(.p)) {
            displayed.render_to_file("captura.png") catch {};
        }

        placeCamera(&camera, camera_x_angle, camera_y_angle, camera_distance);

        // --- Render ---
        if (moved) {
            displayed = motion_buffers[motion_scale_index];
            full_resolution_ready = displayed == &fb_full;
            const start = rl.getTime();
            tracer.render(displayed, &scene, camera, thread_count);
            render_ms = (rl.getTime() - start) * 1000;
        } else if (!full_resolution_ready) {
            displayed = &fb_full;
            const start = rl.getTime();
            tracer.render(displayed, &scene, camera, thread_count);
            render_ms = (rl.getTime() - start) * 1000;
            full_resolution_ready = true;
        }

        // --- Dibujar ---
        rl.beginDrawing();
        defer rl.endDrawing();

        displayed.draw(width, height);

        if (show_hud) {
            var buf: [128]u8 = undefined;
            const stats = std.fmt.bufPrintSentinel(
                &buf,
                "{d}x{d} | render {d:.0} ms | {d} hilos | zoom {d:.1}",
                .{ displayed.width, displayed.height, render_ms, thread_count, camera_distance },
                0,
            ) catch "";
            rl.drawText(stats, 11, 11, 18, .black);
            rl.drawText(stats, 10, 10, 18, .white);
            rl.drawText("A/D o arrastrar: rotar | W/S: inclinar | rueda o Q/E: zoom | R: giro automatico | M: calidad al mover | H: ocultar | P: captura", 11, height - 29, 16, .black);
            rl.drawText("A/D o arrastrar: rotar | W/S: inclinar | rueda o Q/E: zoom | R: giro automatico | M: calidad al mover | H: ocultar | P: captura", 10, height - 30, 16, .white);
        }
    }
}
