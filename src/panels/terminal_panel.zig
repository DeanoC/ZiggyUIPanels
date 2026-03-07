const zui = @import("ziggy-ui");

const widgets = zui.widgets;
const Rect = zui.core.Rect;
const form_layout = zui.ui.layout.form_layout;
const interfaces = zui.ui.panel_interfaces;

// Reusable terminal panel shell. The host owns terminal transport and output
// rendering while this module owns controls, focus, and typed actions.
pub const FocusField = enum {
    none,
    command_input,
};

pub const State = struct {
    focused_field: FocusField = .none,
};

pub const PointerState = struct {
    mouse_x: f32,
    mouse_y: f32,
    mouse_released: bool,
};

pub const ThemeColors = struct {
    text_primary: [4]f32,
    text_secondary: [4]f32,
    error_text: [4]f32,
};

pub const Host = struct {
    ctx: *anyopaque,
    draw_label: *const fn (ctx: *anyopaque, x: f32, y: f32, text: []const u8, color: [4]f32) void,
    draw_text_trimmed: *const fn (ctx: *anyopaque, x: f32, y: f32, max_w: f32, text: []const u8, color: [4]f32) void,
    draw_text_input: *const fn (ctx: *anyopaque, rect: Rect, text: []const u8, focused: bool, opts: widgets.text_input.Options) bool,
    draw_button: *const fn (ctx: *anyopaque, rect: Rect, label: []const u8, opts: widgets.button.Options) bool,
    draw_surface_panel: *const fn (ctx: *anyopaque, rect: Rect) void,
    draw_output: *const fn (ctx: *anyopaque, rect: Rect, inner: f32) void,
};

pub fn draw(
    host: Host,
    rect: Rect,
    layout: form_layout.Metrics,
    colors: ThemeColors,
    model: interfaces.TerminalPanelModel,
    view: interfaces.TerminalPanelView,
    pointer: PointerState,
    state: *State,
) ?interfaces.TerminalPanelAction {
    const pad = layout.inset;
    const inner = layout.inner_inset;
    const row_h = layout.button_height;
    const width = rect.max[0] - rect.min[0];
    const content_width = @max(220.0, width - pad * 2.0);
    var y = rect.min[1] + pad;
    var action: ?interfaces.TerminalPanelAction = null;

    host.draw_label(host.ctx, rect.min[0] + pad, y, view.title, colors.text_primary);
    y += layout.title_gap;
    host.draw_text_trimmed(host.ctx, rect.min[0] + pad, y, content_width, view.backend_line, colors.text_secondary);
    y += layout.line_height;
    if (view.backend_detail) |detail| {
        host.draw_text_trimmed(host.ctx, rect.min[0] + pad, y, content_width, detail, colors.text_secondary);
        y += layout.line_height;
    }
    host.draw_text_trimmed(host.ctx, rect.min[0] + pad, y, content_width, view.session_line, colors.text_secondary);
    y += layout.line_height;
    if (view.status_text) |status_text| {
        host.draw_text_trimmed(host.ctx, rect.min[0] + pad, y, content_width, status_text, colors.text_secondary);
        y += layout.line_height;
    }
    if (view.error_text) |error_text| {
        host.draw_text_trimmed(host.ctx, rect.min[0] + pad, y, content_width, error_text, colors.error_text);
        y += layout.line_height;
    }

    const button_w = @max(108.0, (content_width - pad * 4.0) / 5.0);
    const start_rect = Rect.fromXYWH(rect.min[0] + pad, y, button_w, row_h);
    const stop_rect = Rect.fromXYWH(start_rect.max[0] + pad, y, button_w, row_h);
    const poll_rect = Rect.fromXYWH(stop_rect.max[0] + pad, y, button_w, row_h);
    const resize_rect = Rect.fromXYWH(poll_rect.max[0] + pad, y, button_w, row_h);
    const clear_rect = Rect.fromXYWH(resize_rect.max[0] + pad, y, button_w, row_h);
    if (host.draw_button(host.ctx, start_rect, view.start_label, .{ .variant = .primary, .disabled = model.controlsDisabled() })) emitAction(&action, .start_or_restart);
    if (host.draw_button(host.ctx, stop_rect, "Stop", .{ .variant = .secondary, .disabled = model.controlsDisabled() or !model.has_session })) emitAction(&action, .stop);
    if (host.draw_button(host.ctx, poll_rect, "Read", .{ .variant = .secondary, .disabled = model.controlsDisabled() or !model.has_session })) emitAction(&action, .read);
    if (host.draw_button(host.ctx, resize_rect, "Resize 120x36", .{ .variant = .secondary, .disabled = model.controlsDisabled() or !model.has_session })) emitAction(&action, .resize_default);
    if (host.draw_button(host.ctx, clear_rect, "Clear Output", .{ .variant = .secondary })) emitAction(&action, .clear_output);
    y += row_h + layout.row_gap * 0.5;

    const auto_poll_rect = Rect.fromXYWH(rect.min[0] + pad, y, @max(180.0, button_w * 1.2), row_h);
    if (host.draw_button(host.ctx, auto_poll_rect, if (model.auto_poll) "Auto Poll: On" else "Auto Poll: Off", .{ .variant = .secondary })) emitAction(&action, .toggle_auto_poll);
    const ctrl_c_rect = Rect.fromXYWH(auto_poll_rect.max[0] + pad, y, @max(108.0, button_w), row_h);
    if (host.draw_button(host.ctx, ctrl_c_rect, "Send Ctrl+C", .{ .variant = .secondary, .disabled = model.controlsDisabled() or !model.has_session })) emitAction(&action, .send_ctrl_c);
    const copy_rect = Rect.fromXYWH(ctrl_c_rect.max[0] + pad, y, @max(108.0, button_w), row_h);
    if (host.draw_button(host.ctx, copy_rect, "Copy Output", .{ .variant = .secondary, .disabled = !model.has_output })) emitAction(&action, .copy_output);
    y += row_h + layout.row_gap * 0.5;

    const input_rect = Rect.fromXYWH(rect.min[0] + pad, y, @max(220.0, content_width - button_w - pad), row_h);
    const send_rect = Rect.fromXYWH(input_rect.max[0] + pad, y, button_w, row_h);
    const input_focused = host.draw_text_input(
        host.ctx,
        input_rect,
        view.input_text,
        state.focused_field == .command_input,
        .{ .placeholder = "Type command and press Enter (or Send)" },
    );
    if (input_focused) state.focused_field = .command_input;
    if (host.draw_button(host.ctx, send_rect, "Send", .{ .variant = .primary, .disabled = model.controlsDisabled() or !model.has_input })) emitAction(&action, .send_input);
    if (pointer.mouse_released and state.focused_field == .command_input and !input_rect.contains(.{ pointer.mouse_x, pointer.mouse_y })) {
        state.focused_field = .none;
    }

    y += row_h + layout.row_gap;
    const output_rect = Rect.fromXYWH(
        rect.min[0] + pad,
        y,
        content_width,
        @max(120.0, rect.max[1] - y - pad),
    );
    host.draw_surface_panel(host.ctx, output_rect);
    host.draw_output(host.ctx, output_rect, inner);
    return action;
}

fn emitAction(slot: *?interfaces.TerminalPanelAction, next: interfaces.TerminalPanelAction) void {
    if (slot.* == null) slot.* = next;
}
