const zui = @import("ziggy-ui");

const widgets = zui.widgets;
const Rect = zui.core.Rect;
const form_layout = zui.ui.layout.form_layout;
const interfaces = zui.ui.panel_interfaces;
const zcolors = zui.theme.colors;

// Reusable filesystem-adjacent tools panel. The host owns runtime and contract
// side effects; this module owns the panel layout and action emission.
pub const FocusField = enum {
    none,
    contract_payload,
};

pub const State = struct {
    focused_field: FocusField = .none,
};

pub const ThemeColors = struct {
    text_primary: [4]f32,
    text_secondary: [4]f32,
    primary: [4]f32,
    border: [4]f32,
    surface: [4]f32,
};

pub const Host = struct {
    ctx: *anyopaque,
    draw_text_trimmed: *const fn (ctx: *anyopaque, x: f32, y: f32, max_w: f32, text: []const u8, color: [4]f32) void,
    draw_text_input: *const fn (ctx: *anyopaque, rect: Rect, text: []const u8, focused: bool, opts: widgets.text_input.Options) bool,
    draw_button: *const fn (ctx: *anyopaque, rect: Rect, label: []const u8, opts: widgets.button.Options) bool,
    draw_surface_panel: *const fn (ctx: *anyopaque, rect: Rect) void,
    draw_text_wrapped: *const fn (ctx: *anyopaque, x: f32, y: f32, max_w: f32, text: []const u8, color: [4]f32) f32,
    draw_rect: *const fn (ctx: *anyopaque, rect: Rect, color: [4]f32) void,
};

pub fn draw(
    host: Host,
    rect: Rect,
    layout: form_layout.Metrics,
    model: interfaces.FilesystemToolsPanelModel,
    view: interfaces.FilesystemToolsPanelView,
    colors: ThemeColors,
    state: *State,
) ?interfaces.FilesystemToolsPanelAction {
    const pad = layout.inset;
    const gap = pad * 0.8;
    const title_h = layout.line_height + layout.row_gap * 0.4;
    const content_y = rect.min[1] + title_h + gap;
    const content_h = @max(0.0, rect.max[1] - content_y - pad);
    var action: ?interfaces.FilesystemToolsPanelAction = null;

    host.draw_text_trimmed(host.ctx, rect.min[0] + pad, rect.min[1] + pad * 0.55, rect.width() - pad * 2.0, "Runtime & Contracts", colors.text_primary);
    host.draw_text_trimmed(host.ctx, rect.min[0] + pad, rect.min[1] + pad * 0.55 + layout.line_height, rect.width() - pad * 2.0, "Service controls and contract helpers", colors.text_secondary);

    if (content_h <= 0.0) return action;

    if (rect.width() >= 760.0) {
        const runtime_w = @max(220.0, rect.width() * 0.34 - gap * 0.5 - pad);
        const runtime_rect = Rect.fromXYWH(rect.min[0] + pad, content_y, runtime_w, content_h);
        const contract_rect = Rect.fromXYWH(runtime_rect.max[0] + gap, content_y, rect.max[0] - runtime_rect.max[0] - gap - pad, content_h);
        drawRuntimeTools(host, runtime_rect, layout, model, colors, &action);
        drawContractTools(host, contract_rect, layout, model, view, colors, state, &action);
    } else {
        const runtime_h = @min(120.0, content_h * 0.36);
        const runtime_rect = Rect.fromXYWH(rect.min[0] + pad, content_y, rect.width() - pad * 2.0, runtime_h);
        const contract_rect = Rect.fromXYWH(rect.min[0] + pad, runtime_rect.max[1] + gap, rect.width() - pad * 2.0, @max(0.0, rect.max[1] - runtime_rect.max[1] - gap - pad));
        drawRuntimeTools(host, runtime_rect, layout, model, colors, &action);
        drawContractTools(host, contract_rect, layout, model, view, colors, state, &action);
    }

    return action;
}

fn drawRuntimeTools(
    host: Host,
    rect: Rect,
    layout: form_layout.Metrics,
    model: interfaces.FilesystemToolsPanelModel,
    colors: ThemeColors,
    action: *?interfaces.FilesystemToolsPanelAction,
) void {
    if (rect.height() <= 0.0) return;
    const inner = @max(8.0, layout.inner_inset * 0.75);
    const row_h = @max(24.0, layout.button_height * 0.64);
    const gap = layout.inset * 0.45;
    host.draw_surface_panel(host.ctx, rect);
    host.draw_rect(host.ctx, rect, zcolors.withAlpha(colors.border, 0.5));

    var y = rect.min[1] + inner;
    host.draw_text_trimmed(host.ctx, rect.min[0] + inner, y, rect.width() - inner * 2.0, "Runtime", colors.text_primary);
    y += layout.line_height + layout.row_gap * 0.4;

    if (!model.has_service_runtime_root) {
        _ = host.draw_text_wrapped(host.ctx, rect.min[0] + inner, y, rect.width() - inner * 2.0, "No runtime directory is selected in the current explorer location.", colors.text_secondary);
        return;
    }

    const button_w: f32 = @max(66.0, (rect.width() - inner * 2.0 - gap * 3.0) / 4.0);
    const disabled = model.controlsDisabled();
    const status_rect = Rect.fromXYWH(rect.min[0] + inner, y, button_w, row_h);
    const health_rect = Rect.fromXYWH(status_rect.max[0] + gap, y, button_w, row_h);
    const metrics_rect = Rect.fromXYWH(health_rect.max[0] + gap, y, button_w, row_h);
    const config_rect = Rect.fromXYWH(metrics_rect.max[0] + gap, y, button_w, row_h);
    if (host.draw_button(host.ctx, status_rect, "Status", .{ .variant = .secondary, .disabled = disabled })) emitAction(action, .{ .runtime_read = .status });
    if (host.draw_button(host.ctx, health_rect, "Health", .{ .variant = .secondary, .disabled = disabled })) emitAction(action, .{ .runtime_read = .health });
    if (host.draw_button(host.ctx, metrics_rect, "Metrics", .{ .variant = .secondary, .disabled = disabled })) emitAction(action, .{ .runtime_read = .metrics });
    if (host.draw_button(host.ctx, config_rect, "Config", .{ .variant = .secondary, .disabled = disabled })) emitAction(action, .{ .runtime_read = .config });

    y += row_h + layout.row_gap * 0.45;
    const enable_rect = Rect.fromXYWH(rect.min[0] + inner, y, button_w, row_h);
    const disable_rect = Rect.fromXYWH(enable_rect.max[0] + gap, y, button_w, row_h);
    const restart_rect = Rect.fromXYWH(disable_rect.max[0] + gap, y, button_w, row_h);
    const reset_rect = Rect.fromXYWH(restart_rect.max[0] + gap, y, button_w, row_h);
    if (host.draw_button(host.ctx, enable_rect, "Enable", .{ .variant = .secondary, .disabled = disabled })) emitAction(action, .{ .runtime_control = .enable });
    if (host.draw_button(host.ctx, disable_rect, "Disable", .{ .variant = .secondary, .disabled = disabled })) emitAction(action, .{ .runtime_control = .disable });
    if (host.draw_button(host.ctx, restart_rect, "Restart", .{ .variant = .secondary, .disabled = disabled })) emitAction(action, .{ .runtime_control = .restart });
    if (host.draw_button(host.ctx, reset_rect, "Reset", .{ .variant = .secondary, .disabled = disabled })) emitAction(action, .{ .runtime_control = .reset });

    y += row_h + layout.row_gap * 0.45;
    const invoke_rect = Rect.fromXYWH(rect.min[0] + inner, y, @max(98.0, button_w * 1.2), row_h);
    if (host.draw_button(host.ctx, invoke_rect, "Invoke {}", .{ .variant = .primary, .disabled = disabled })) emitAction(action, .{ .runtime_control = .invoke });
}

fn drawContractTools(
    host: Host,
    rect: Rect,
    layout: form_layout.Metrics,
    model: interfaces.FilesystemToolsPanelModel,
    view: interfaces.FilesystemToolsPanelView,
    colors: ThemeColors,
    state: *State,
    action: *?interfaces.FilesystemToolsPanelAction,
) void {
    if (rect.height() <= 0.0) return;
    const inner = @max(8.0, layout.inner_inset * 0.75);
    const row_h = @max(24.0, layout.button_height * 0.64);
    const gap = layout.inset * 0.45;
    host.draw_surface_panel(host.ctx, rect);
    host.draw_rect(host.ctx, rect, zcolors.withAlpha(colors.border, 0.5));

    var y = rect.min[1] + inner;
    host.draw_text_trimmed(host.ctx, rect.min[0] + inner, y, rect.width() - inner * 2.0, "Contracts", colors.text_primary);
    y += layout.line_height + layout.row_gap * 0.4;

    const disabled = model.controlsDisabled();
    const button_w: f32 = @max(68.0, (rect.width() - inner * 2.0 - gap * 3.0) / 4.0);
    const refresh_rect = Rect.fromXYWH(rect.min[0] + inner, y, button_w, row_h);
    const prev_rect = Rect.fromXYWH(refresh_rect.max[0] + gap, y, button_w, row_h);
    const next_rect = Rect.fromXYWH(prev_rect.max[0] + gap, y, button_w, row_h);
    const open_rect = Rect.fromXYWH(next_rect.max[0] + gap, y, button_w, row_h);
    if (host.draw_button(host.ctx, refresh_rect, "Refresh", .{ .variant = .secondary, .disabled = disabled })) emitAction(action, .contract_refresh);
    if (host.draw_button(host.ctx, prev_rect, "Prev", .{ .variant = .secondary, .disabled = disabled or !model.hasContractPager() })) emitAction(action, .contract_select_prev);
    if (host.draw_button(host.ctx, next_rect, "Next", .{ .variant = .secondary, .disabled = disabled or !model.hasContractPager() })) emitAction(action, .contract_select_next);
    if (host.draw_button(host.ctx, open_rect, "Open Dir", .{ .variant = .secondary, .disabled = disabled or !model.has_selected_contract_service })) emitAction(action, .contract_open_service_dir);

    y += row_h + layout.row_gap * 0.45;
    host.draw_text_trimmed(host.ctx, rect.min[0] + inner, y, rect.width() - inner * 2.0, view.selected_contract_label, colors.text_secondary);
    y += layout.line_height + layout.row_gap * 0.35;

    const payload_rect = Rect.fromXYWH(rect.min[0] + inner, y, rect.width() - inner * 2.0, row_h);
    const payload_focused = host.draw_text_input(host.ctx, payload_rect, view.contract_payload, state.focused_field == .contract_payload, .{ .placeholder = "{\"tool_name\":\"memory_search\",\"arguments\":{\"query\":\"...\"}}" });
    if (payload_focused) state.focused_field = .contract_payload;
    y += row_h + layout.row_gap * 0.45;

    const invoke_rect = Rect.fromXYWH(rect.min[0] + inner, y, button_w, row_h);
    const status_rect = Rect.fromXYWH(invoke_rect.max[0] + gap, y, button_w, row_h);
    const result_rect = Rect.fromXYWH(status_rect.max[0] + gap, y, button_w, row_h);
    const help_rect = Rect.fromXYWH(result_rect.max[0] + gap, y, button_w, row_h);
    if (host.draw_button(host.ctx, invoke_rect, "Invoke", .{ .variant = .primary, .disabled = disabled or !model.has_selected_contract_service })) emitAction(action, .contract_invoke);
    if (host.draw_button(host.ctx, status_rect, "Status", .{ .variant = .secondary, .disabled = disabled or !model.has_selected_contract_service })) emitAction(action, .contract_read_status);
    if (host.draw_button(host.ctx, result_rect, "Result", .{ .variant = .secondary, .disabled = disabled or !model.has_selected_contract_service })) emitAction(action, .contract_read_result);
    if (host.draw_button(host.ctx, help_rect, "Help", .{ .variant = .secondary, .disabled = disabled or !model.has_selected_contract_service })) emitAction(action, .contract_read_help);

    y += row_h + layout.row_gap * 0.45;
    const schema_rect = Rect.fromXYWH(rect.min[0] + inner, y, button_w, row_h);
    const template_rect = Rect.fromXYWH(schema_rect.max[0] + gap, y, button_w, row_h);
    if (host.draw_button(host.ctx, schema_rect, "Schema", .{ .variant = .secondary, .disabled = disabled or !model.has_selected_contract_service })) emitAction(action, .contract_read_schema);
    if (host.draw_button(host.ctx, template_rect, "Template", .{ .variant = .secondary, .disabled = disabled or !model.has_selected_contract_service })) emitAction(action, .contract_use_template);
}

fn emitAction(slot: *?interfaces.FilesystemToolsPanelAction, next: interfaces.FilesystemToolsPanelAction) void {
    if (slot.* == null) slot.* = next;
}
