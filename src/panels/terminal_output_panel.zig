const zui = @import("ziggy-ui");

const Rect = zui.core.Rect;
const interfaces = zui.ui.panel_interfaces;

// Reusable terminal output viewport. The host supplies per-line styled drawing.
pub const ThemeColors = struct {
    text_secondary: [4]f32,
};

pub const Host = struct {
    ctx: *anyopaque,
    draw_text_trimmed: *const fn (ctx: *anyopaque, x: f32, y: f32, max_w: f32, text: []const u8, color: [4]f32) void,
    draw_line: *const fn (ctx: *anyopaque, line_index: usize, x: f32, y: f32, max_w: f32) void,
};

pub fn draw(
    host: Host,
    output_rect: Rect,
    inner: f32,
    colors: ThemeColors,
    view: interfaces.TerminalOutputView,
) void {
    if (view.total_lines == 0) {
        host.draw_text_trimmed(
            host.ctx,
            output_rect.min[0] + inner,
            output_rect.min[1] + inner,
            output_rect.width() - inner * 2.0,
            view.empty_text,
            colors.text_secondary,
        );
        return;
    }

    const line_height = @max(1.0, view.line_height);
    const usable_height = @max(1.0, output_rect.height() - inner * 2.0);
    const max_lines_float = @floor(usable_height / line_height);
    if (max_lines_float < 1.0) return;
    const max_lines: usize = @intFromFloat(max_lines_float);

    const start_line = if (view.total_lines > max_lines) view.total_lines - max_lines else 0;
    const draw_x = output_rect.min[0] + inner;
    const draw_w = @max(1.0, output_rect.width() - inner * 2.0);
    const max_y = output_rect.max[1] - inner;

    var y = output_rect.min[1] + inner;
    var line_idx = start_line;
    while (line_idx < view.total_lines and y + line_height <= max_y + 0.5) : (line_idx += 1) {
        host.draw_line(host.ctx, line_idx, draw_x, y, draw_w);
        y += line_height;
    }
}
