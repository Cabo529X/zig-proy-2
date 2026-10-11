const std = @import("std");
const rl = @import("raylib");

/// Buffer de píxeles en RAM (el raytracer corre en el CPU) y una textura de raylib
/// donde se sube para mostrarlo.
/// La textura se crea una sola vez y se actualiza en cada render, en vez de crearla y
/// destruirla en cada frame.
pub const Framebuffer = struct {
    width: i32,
    height: i32,
    pixels: []rl.Color,
    // null en modo sin ventana (render a archivo)
    texture: ?rl.Texture,

    /// Solo buffer en RAM, sin textura: no necesita ventana de raylib.
    pub fn initCpu(gpa: std.mem.Allocator, width: i32, height: i32) !Framebuffer {
        const pixels = try gpa.alloc(rl.Color, @intCast(width * height));
        @memset(pixels, rl.Color.black);
        return .{ .width = width, .height = height, .pixels = pixels, .texture = null };
    }

    /// Buffer en RAM y textura en la GPU para mostrarlo. Requiere que la ventana ya exista.
    pub fn init(gpa: std.mem.Allocator, width: i32, height: i32) !Framebuffer {
        var self = try initCpu(gpa, width, height);
        errdefer self.deinit(gpa);
        self.texture = try rl.loadTextureFromImage(self.image());
        return self;
    }

    pub fn deinit(self: Framebuffer, gpa: std.mem.Allocator) void {
        if (self.texture) |texture| rl.unloadTexture(texture);
        gpa.free(self.pixels);
    }

    fn image(self: Framebuffer) rl.Image {
        return .{
            .data = self.pixels.ptr,
            .width = self.width,
            .height = self.height,
            .mipmaps = 1,
            .format = .uncompressed_r8g8b8a8,
        };
    }

    pub fn set_pixel(self: *Framebuffer, x: usize, y: usize, color: rl.Color) void {
        self.pixels[y * @as(usize, @intCast(self.width)) + x] = color;
    }

    /// Sube el contenido del buffer a la GPU.
    pub fn upload(self: *Framebuffer) void {
        if (self.texture) |texture| rl.updateTexture(texture, self.pixels.ptr);
    }

    /// Dibuja el buffer estirado para que llene la ventana.
    /// Debe llamarse entre beginDrawing y endDrawing.
    pub fn draw(self: Framebuffer, window_width: i32, window_height: i32) void {
        const texture = self.texture orelse return;
        rl.drawTexturePro(
            texture,
            .{ .x = 0, .y = 0, .width = @floatFromInt(self.width), .height = @floatFromInt(self.height) },
            .{ .x = 0, .y = 0, .width = @floatFromInt(window_width), .height = @floatFromInt(window_height) },
            .{ .x = 0, .y = 0 },
            0,
            .white,
        );
    }

    pub fn render_to_file(self: Framebuffer, filename: [:0]const u8) !void {
        if (!self.image().exportToFile(filename)) return error.CouldntWriteFile;
    }
};
