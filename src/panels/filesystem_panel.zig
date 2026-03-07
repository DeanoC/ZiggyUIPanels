const zui = @import("ziggy-ui");

const widgets = zui.widgets;
const Rect = zui.core.Rect;
const form_layout = zui.ui.layout.form_layout;
const interfaces = zui.ui.panel_interfaces;

// Reusable filesystem panel shell. The host owns filesystem operations and
// preview data; this module owns control layout and action emission.
pub const FocusField = enum {
    none,
    contract_payload,
};

pub const State = struct {
    focused_field: FocusField = .none,
    entry_page: usize = 0,
};

pub const PointerState = struct {
    mouse_x: f32,
    mouse_y: f32,
    mouse_released: bool,
};

pub const ThemeColors = struct {
    text_primary: [4]f32,
    text_secondary: [4]f32,
    primary: [4]f32,
    error_text: [4]f32,
};

pub const Host = struct {
    ctx: *anyopaque,
    draw_label: *const fn (ctx: *anyopaque, x: f32, y: f32, text: []const u8, color: [4]f32) void,
    draw_text_trimmed: *const fn (ctx: *anyopaque, x: f32, y: f32, max_w: f32, text: []const u8, color: [4]f32) void,
    draw_text_input: *const fn (ctx: *anyopaque, rect: Rect, text: []const u8, focused: bool, opts: widgets.text_input.Options) bool,
    draw_button: *const fn (ctx: *anyopaque, rect: Rect, label: []const u8, opts: widgets.button.Options) bool,
    draw_surface_panel: *const fn (ctx: *anyopaque, rect: Rect) void,
    draw_text_wrapped: *const fn (ctx: *anyopaque, x: f32, y: f32, max_w: f32, text: []const u8, color: [4]f32) f32,
};

pub fn draw(
    host: Host,
    rect: Rect,
    layout: form_layout.Metrics,
    model: interfaces.FilesystemPanelModel,
    view: interfaces.FilesystemPanelView,
    colors: ThemeColors,
    pointer: PointerState,
    state: *State,
) ?interfaces.FilesystemPanelAction {
    const pad = layout.inset;
    const inner = layout.inner_inset;
    const row_h = layout.button_height;
    const width = rect.max[0] - rect.min[0];
    const content_width = @max(220.0, width - pad * 2.0);
    var y = rect.min[1] + pad;
    var action: ?interfaces.FilesystemPanelAction = null;

    host.draw_label(host.ctx, rect.min[0] + pad, y, "Filesystem Browser", colors.text_primary);
    y += layout.title_gap;

    var path_buf: [512]u8 = undefined;
    const path_line = std.fmt.bufPrint(&path_buf, "Path: {s}", .{view.path_label}) catch view.path_label;
    host.draw_text_trimmed(host.ctx, rect.min[0] + pad, y, content_width, path_line, colors.text_secondary);
    y += layout.line_height + layout.row_gap * 0.55;

    const action_w: f32 = @max(124.0, width * 0.21);
    const refresh_rect = Rect.fromXYWH(rect.min[0] + pad, y, action_w, row_h);
    const up_rect = Rect.fromXYWH(refresh_rect.max[0] + pad, y, action_w, row_h);
    const root_rect = Rect.fromXYWH(up_rect.max[0] + pad, y, action_w * 1.35, row_h);
    if (host.draw_button(host.ctx, refresh_rect, "Refresh", .{ .variant = .secondary, .disabled = model.controlsDisabled() })) {
        emitAction(&action, .refresh);
    }
    if (host.draw_button(host.ctx, up_rect, "Up", .{ .variant = .secondary, .disabled = model.controlsDisabled() })) {
        emitAction(&action, .navigate_up);
    }
    if (host.draw_button(host.ctx, root_rect, "Use Workspace Root", .{ .variant = .secondary, .disabled = model.controlsDisabled() })) {
        emitAction(&action, .use_workspace_root);
    }

    y += row_h + layout.row_gap;
    if (model.busy) {
        host.draw_text_trimmed(host.ctx, rect.min[0] + pad, y, content_width, "Loading filesystem...", colors.text_secondary);
        y += layout.line_height;
    }
    if (view.error_text) |err_text| {
        host.draw_text_trimmed(host.ctx, rect.min[0] + pad, y, content_width, err_text, colors.error_text);
        y += layout.line_height;
    }

    if (model.has_service_runtime_root) {
        host.draw_text_trimmed(host.ctx, rect.min[0] + pad, y, content_width, "Service Runtime Controls", colors.text_secondary);
        y += layout.line_height + layout.row_gap * 0.4;

        const runtime_disabled = model.controlsDisabled();
        const runtime_button_w: f32 = @max(96.0, (content_width - pad * 3.0) / 4.0);
        const status_rect = Rect.fromXYWH(rect.min[0] + pad, y, runtime_button_w, row_h);
        const health_rect = Rect.fromXYWH(status_rect.max[0] + pad, y, runtime_button_w, row_h);
        const metrics_rect = Rect.fromXYWH(health_rect.max[0] + pad, y, runtime_button_w, row_h);
        const config_rect = Rect.fromXYWH(metrics_rect.max[0] + pad, y, runtime_button_w, row_h);
        if (host.draw_button(host.ctx, status_rect, "Status", .{ .variant = .secondary, .disabled = runtime_disabled })) emitAction(&action, .{ .runtime_read = .status });
        if (host.draw_button(host.ctx, health_rect, "Health", .{ .variant = .secondary, .disabled = runtime_disabled })) emitAction(&action, .{ .runtime_read = .health });
        if (host.draw_button(host.ctx, metrics_rect, "Metrics", .{ .variant = .secondary, .disabled = runtime_disabled })) emitAction(&action, .{ .runtime_read = .metrics });
        if (host.draw_button(host.ctx, config_rect, "Config", .{ .variant = .secondary, .disabled = runtime_disabled })) emitAction(&action, .{ .runtime_read = .config });

        y += row_h + layout.row_gap * 0.5;
        const enable_rect = Rect.fromXYWH(rect.min[0] + pad, y, runtime_button_w, row_h);
        const disable_rect = Rect.fromXYWH(enable_rect.max[0] + pad, y, runtime_button_w, row_h);
        const restart_rect = Rect.fromXYWH(disable_rect.max[0] + pad, y, runtime_button_w, row_h);
        const reset_rect = Rect.fromXYWH(restart_rect.max[0] + pad, y, runtime_button_w, row_h);
        if (host.draw_button(host.ctx, enable_rect, "Enable", .{ .variant = .secondary, .disabled = runtime_disabled })) emitAction(&action, .{ .runtime_control = .enable });
        if (host.draw_button(host.ctx, disable_rect, "Disable", .{ .variant = .secondary, .disabled = runtime_disabled })) emitAction(&action, .{ .runtime_control = .disable });
        if (host.draw_button(host.ctx, restart_rect, "Restart", .{ .variant = .secondary, .disabled = runtime_disabled })) emitAction(&action, .{ .runtime_control = .restart });
        if (host.draw_button(host.ctx, reset_rect, "Reset", .{ .variant = .secondary, .disabled = runtime_disabled })) emitAction(&action, .{ .runtime_control = .reset });

        y += row_h + layout.row_gap * 0.5;
        const invoke_rect = Rect.fromXYWH(rect.min[0] + pad, y, @max(140.0, runtime_button_w * 1.4), row_h);
        if (host.draw_button(host.ctx, invoke_rect, "Invoke {}", .{ .variant = .primary, .disabled = runtime_disabled })) {
            emitAction(&action, .{ .runtime_control = .invoke });
        }
        y += row_h + layout.row_gap;
    }

    host.draw_text_trimmed(host.ctx, rect.min[0] + pad, y, content_width, "Agent Contract Services", colors.text_secondary);
    y += layout.line_height + layout.row_gap * 0.4;

    const contract_disabled = model.controlsDisabled();
    const contract_button_w: f32 = @max(100.0, (content_width - pad * 3.0) / 4.0);
    const contract_refresh_rect = Rect.fromXYWH(rect.min[0] + pad, y, contract_button_w, row_h);
    const contract_prev_rect = Rect.fromXYWH(contract_refresh_rect.max[0] + pad, y, contract_button_w, row_h);
    const contract_next_rect = Rect.fromXYWH(contract_prev_rect.max[0] + pad, y, contract_button_w, row_h);
    const contract_open_rect = Rect.fromXYWH(contract_next_rect.max[0] + pad, y, contract_button_w, row_h);
    if (host.draw_button(host.ctx, contract_refresh_rect, "Refresh Contracts", .{ .variant = .secondary, .disabled = contract_disabled })) emitAction(&action, .contract_refresh);
    if (host.draw_button(host.ctx, contract_prev_rect, "Prev", .{ .variant = .secondary, .disabled = contract_disabled or !model.hasContractPager() })) emitAction(&action, .contract_select_prev);
    if (host.draw_button(host.ctx, contract_next_rect, "Next", .{ .variant = .secondary, .disabled = contract_disabled or !model.hasContractPager() })) emitAction(&action, .contract_select_next);
    if (host.draw_button(host.ctx, contract_open_rect, "Open Service Dir", .{ .variant = .secondary, .disabled = contract_disabled or !model.has_selected_contract_service })) emitAction(&action, .contract_open_service_dir);
    y += row_h + layout.row_gap * 0.45;

    host.draw_text_trimmed(host.ctx, rect.min[0] + pad, y, content_width, view.selected_contract_label, colors.text_secondary);
    y += layout.line_height + layout.row_gap * 0.35;

    const payload_rect = Rect.fromXYWH(rect.min[0] + pad, y, content_width, row_h);
    const payload_focused = host.draw_text_input(
        host.ctx,
        payload_rect,
        view.contract_payload,
        state.focused_field == .contract_payload,
        .{ .placeholder = "{\"tool_name\":\"memory_search\",\"arguments\":{\"query\":\"...\"}}" },
    );
    if (payload_focused) state.focused_field = .contract_payload;
    y += row_h + layout.row_gap * 0.45;

    const invoke_rect = Rect.fromXYWH(rect.min[0] + pad, y, contract_button_w, row_h);
    const status_rect = Rect.fromXYWH(invoke_rect.max[0] + pad, y, contract_button_w, row_h);
    const result_rect = Rect.fromXYWH(status_rect.max[0] + pad, y, contract_button_w, row_h);
    const help_rect = Rect.fromXYWH(result_rect.max[0] + pad, y, contract_button_w, row_h);
    if (host.draw_button(host.ctx, invoke_rect, "Invoke", .{ .variant = .primary, .disabled = contract_disabled or !model.has_selected_contract_service })) emitAction(&action, .contract_invoke);
    if (host.draw_button(host.ctx, status_rect, "Read Status", .{ .variant = .secondary, .disabled = contract_disabled or !model.has_selected_contract_service })) emitAction(&action, .contract_read_status);
    if (host.draw_button(host.ctx, result_rect, "Read Result", .{ .variant = .secondary, .disabled = contract_disabled or !model.has_selected_contract_service })) emitAction(&action, .contract_read_result);
    if (host.draw_button(host.ctx, help_rect, "Read Help", .{ .variant = .secondary, .disabled = contract_disabled or !model.has_selected_contract_service })) emitAction(&action, .contract_read_help);

    y += row_h + layout.row_gap * 0.45;
    const schema_rect = Rect.fromXYWH(rect.min[0] + pad, y, contract_button_w, row_h);
    const template_rect = Rect.fromXYWH(schema_rect.max[0] + pad, y, contract_button_w, row_h);
    if (host.draw_button(host.ctx, schema_rect, "Read Schema", .{ .variant = .secondary, .disabled = contract_disabled or !model.has_selected_contract_service })) emitAction(&action, .contract_read_schema);
    if (host.draw_button(host.ctx, template_rect, "Use Template", .{ .variant = .secondary, .disabled = contract_disabled or !model.has_selected_contract_service })) emitAction(&action, .contract_use_template);

    if (pointer.mouse_released and state.focused_field == .contract_payload and !payload_rect.contains(.{ pointer.mouse_x, pointer.mouse_y })) {
        state.focused_field = .none;
    }

    y += row_h + layout.row_gap;
    const listing_height = @max(140.0, (rect.max[1] - y - pad * 2.0) * 0.52);
    const listing_rect = Rect.fromXYWH(rect.min[0] + pad, y, content_width, listing_height);
    host.draw_surface_panel(host.ctx, listing_rect);

    const list_row_h = @max(layout.button_height * 0.8, layout.line_height + inner * 0.9);
    const list_row_gap = @max(1.0, inner * 0.35);
    const list_step = list_row_h + list_row_gap;
    const listing_inner_height = @max(0.0, listing_rect.height() - inner * 2.0);
    const rows_without_pager = @max(1, @as(usize, @intFromFloat(@floor((listing_inner_height + list_row_gap) / list_step))));
    const pager_h = row_h;
    const pager_gap = layout.row_gap * 0.45;
    const needs_pager = view.entries.len > rows_without_pager;
    const rows_per_page = if (needs_pager)
        @max(1, @as(usize, @intFromFloat(@floor((@max(0.0, listing_inner_height - pager_h - pager_gap) + list_row_gap) / list_step))))
    else
        rows_without_pager;
    const page_count = @max(1, std.math.divCeil(usize, view.entries.len, rows_per_page) catch 1);
    if (state.entry_page >= page_count) state.entry_page = page_count - 1;

    var list_y = listing_rect.min[1] + inner;
    if (needs_pager) {
        const pager_button_w: f32 = @max(72.0, @min(96.0, listing_rect.width() * 0.18));
        const prev_rect = Rect.fromXYWH(listing_rect.min[0] + inner, list_y, pager_button_w, pager_h);
        const next_rect = Rect.fromXYWH(listing_rect.max[0] - inner - pager_button_w, list_y, pager_button_w, pager_h);
        if (host.draw_button(host.ctx, prev_rect, "Prev", .{ .variant = .secondary, .disabled = state.entry_page == 0 })) {
            state.entry_page -= 1;
        }
        if (host.draw_button(host.ctx, next_rect, "Next", .{ .variant = .secondary, .disabled = state.entry_page + 1 >= page_count })) {
            state.entry_page += 1;
        }

        var page_buf: [80]u8 = undefined;
        const start_ordinal = state.entry_page * rows_per_page + 1;
        const end_ordinal = @min(view.entries.len, (state.entry_page + 1) * rows_per_page);
        const page_text = std.fmt.bufPrint(&page_buf, "Entries {d}-{d} of {d}", .{ start_ordinal, end_ordinal, view.entries.len }) catch "Entries";
        host.draw_text_trimmed(
            host.ctx,
            prev_rect.max[0] + inner,
            list_y + @max(0.0, (pager_h - layout.line_height) * 0.5),
            @max(0.0, next_rect.min[0] - prev_rect.max[0] - inner * 2.0),
            page_text,
            colors.text_secondary,
        );
        list_y += pager_h + pager_gap;
    }

    if (view.entries.len == 0) {
        host.draw_text_trimmed(
            host.ctx,
            listing_rect.min[0] + inner,
            list_y,
            listing_rect.width() - inner * 2.0,
            "No filesystem entries",
            colors.text_secondary,
        );
    }

    const start_idx = @min(view.entries.len, state.entry_page * rows_per_page);
    const end_idx = @min(view.entries.len, start_idx + rows_per_page);
    var idx: usize = start_idx;
    while (idx < end_idx) : (idx += 1) {
        const entry = view.entries[idx];
        const row_rect = Rect.fromXYWH(
            listing_rect.min[0] + inner,
            list_y,
            listing_rect.width() - inner * 2.0,
            list_row_h,
        );
        if (host.draw_button(host.ctx, row_rect, entry.label, .{ .variant = .secondary, .disabled = model.busy })) {
            emitAction(&action, .{ .open_entry_index = entry.index });
        }
        if (entry.badge) |badge| {
            host.draw_text_trimmed(
                host.ctx,
                row_rect.min[0] + @max(80.0, row_rect.width() * 0.5),
                row_rect.min[1] + @max(0.0, (row_rect.height() - layout.line_height) * 0.5),
                row_rect.width() * 0.46,
                badge,
                colors.primary,
            );
        }
        list_y += list_row_h + list_row_gap;
    }

    y = listing_rect.max[1] + pad;
    const preview_rect = Rect.fromXYWH(rect.min[0] + pad, y, content_width, @max(100.0, rect.max[1] - y - pad));
    host.draw_surface_panel(host.ctx, preview_rect);
    host.draw_text_trimmed(
        host.ctx,
        preview_rect.min[0] + inner,
        preview_rect.min[1] + inner,
        preview_rect.width() - inner * 2.0,
        view.preview_title,
        colors.text_secondary,
    );
    if (view.preview_text) |text| {
        _ = host.draw_text_wrapped(
            host.ctx,
            preview_rect.min[0] + inner,
            preview_rect.min[1] + inner + layout.line_height + layout.row_gap * 0.5,
            preview_rect.width() - inner * 2.0,
            text,
            colors.text_primary,
        );
    }

    return action;
}

fn emitAction(slot: *?interfaces.FilesystemPanelAction, next: interfaces.FilesystemPanelAction) void {
    if (slot.* == null) slot.* = next;
}

const std = @import("std");
