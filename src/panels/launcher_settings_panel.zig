const zui = @import("ziggy-ui");

const widgets = zui.widgets;
const Rect = zui.core.Rect;
const form_layout = zui.ui.layout.form_layout;
const interfaces = zui.ui.panel_interfaces;

// Reusable launcher/workspace settings form built on shared settings contracts.
pub const FocusField = enum {
    none,
    server_url,
    default_session,
    default_agent,
    ui_theme,
    ui_profile,
    ui_theme_pack,
};

pub const Variant = enum {
    launcher,
    workspace,
};

pub const TextFields = struct {
    server_url: []const u8 = "",
    default_session: []const u8 = "",
    default_agent: []const u8 = "",
    ui_theme: []const u8 = "",
    ui_profile: []const u8 = "",
    ui_theme_pack: []const u8 = "",
};

pub const PointerState = struct {
    mouse_x: f32,
    mouse_y: f32,
    mouse_released: bool,
};

pub const State = struct {
    focused_field: FocusField = .none,
    scroll_y: f32 = 0.0,
};

pub const ThemeColors = struct {
    text_primary: [4]f32,
    text_secondary: [4]f32,
};

pub const Host = struct {
    ctx: *anyopaque,
    draw_form_section_title: *const fn (ctx: *anyopaque, x: f32, y: *f32, max_w: f32, layout: form_layout.Metrics, text: []const u8) void,
    draw_form_field_label: *const fn (ctx: *anyopaque, x: f32, y: *f32, max_w: f32, layout: form_layout.Metrics, text: []const u8) void,
    draw_text_input: *const fn (ctx: *anyopaque, rect: Rect, text: []const u8, focused: bool, opts: widgets.text_input.Options) bool,
    draw_button: *const fn (ctx: *anyopaque, rect: Rect, label: []const u8, opts: widgets.button.Options) bool,
    draw_label: *const fn (ctx: *anyopaque, x: f32, y: f32, text: []const u8, color: [4]f32) void,
    draw_text_trimmed: *const fn (ctx: *anyopaque, x: f32, y: f32, max_w: f32, text: []const u8, color: [4]f32) void,
    draw_vertical_scrollbar: *const fn (ctx: *anyopaque, viewport_rect: Rect, content_height: f32, scroll_y: *f32) void,
};

pub fn draw(
    host: Host,
    rect: Rect,
    layout: form_layout.Metrics,
    ui_scale: f32,
    colors: ThemeColors,
    model: interfaces.LauncherSettingsModel,
    fields: TextFields,
    pointer: PointerState,
    state: *State,
    variant: Variant,
) ?interfaces.LauncherSettingsAction {
    const pad = layout.inset;
    const rect_width = rect.max[0] - rect.min[0];
    const input_height = layout.input_height;
    const button_height = layout.button_height;
    const input_width = @max(220.0, rect_width - pad * 2.0);
    var y = rect.min[1] + pad - state.scroll_y;
    var action: ?interfaces.LauncherSettingsAction = null;

    const title = switch (variant) {
        .launcher => "SpiderApp - Settings",
        .workspace => "Workspace Settings",
    };
    host.draw_form_section_title(host.ctx, rect.min[0] + pad, &y, input_width, layout, title);

    if (variant == .workspace) {
        host.draw_text_trimmed(
            host.ctx,
            rect.min[0] + pad,
            y,
            input_width,
            "Connection/session/agent configuration moved to Launcher.",
            colors.text_secondary,
        );
        y += layout.line_height + layout.section_gap * 0.5;
    } else {
        host.draw_form_field_label(host.ctx, rect.min[0] + pad, &y, input_width, layout, "Server URL");
        const input_rect = Rect.fromXYWH(rect.min[0] + pad, y, input_width, input_height);
        const url_focused = host.draw_text_input(
            host.ctx,
            input_rect,
            fields.server_url,
            state.focused_field == .server_url,
            .{ .placeholder = "ws://127.0.0.1:18790" },
        );
        if (url_focused) state.focused_field = .server_url;

        y += input_height + pad * 0.5;
        host.draw_label(host.ctx, rect.min[0] + pad, y, "Connect role", colors.text_primary);
        y += 20.0 * ui_scale;
        const role_button_width: f32 = @max(120.0, (rect_width - pad * 3.0) * 0.5);
        const connect_role_admin_rect = Rect.fromXYWH(rect.min[0] + pad, y, role_button_width, input_height);
        const connect_role_user_rect = Rect.fromXYWH(connect_role_admin_rect.max[0] + pad, y, role_button_width, input_height);
        if (host.draw_button(
            host.ctx,
            connect_role_admin_rect,
            "Admin",
            .{ .variant = if (model.active_role == .admin) .primary else .secondary },
        )) {
            emitAction(&action, .{ .set_connect_role = .admin });
        }
        if (host.draw_button(
            host.ctx,
            connect_role_user_rect,
            "User",
            .{ .variant = if (model.active_role == .user) .primary else .secondary },
        )) {
            emitAction(&action, .{ .set_connect_role = .user });
        }
        y += input_height + 4.0 * ui_scale;
        host.draw_label(
            host.ctx,
            rect.min[0] + pad,
            y,
            if (model.connection_state == .connected) "Role applies on next reconnect" else "Role applies on next connect",
            colors.text_secondary,
        );

        y += 18.0 * ui_scale + pad * 0.5;
        host.draw_form_field_label(host.ctx, rect.min[0] + pad, &y, input_width, layout, "Default session");
        const default_session_rect = Rect.fromXYWH(rect.min[0] + pad, y, input_width, input_height);
        const default_session_focused = host.draw_text_input(
            host.ctx,
            default_session_rect,
            fields.default_session,
            state.focused_field == .default_session,
            .{ .placeholder = "main" },
        );
        if (default_session_focused) state.focused_field = .default_session;

        y += input_height + layout.row_gap;
        host.draw_form_field_label(host.ctx, rect.min[0] + pad, &y, input_width, layout, "Default agent");
        const default_agent_rect = Rect.fromXYWH(rect.min[0] + pad, y, input_width, input_height);
        const default_agent_focused = host.draw_text_input(
            host.ctx,
            default_agent_rect,
            fields.default_agent,
            state.focused_field == .default_agent,
            .{ .placeholder = "leave empty for role default" },
        );
        if (default_agent_focused) state.focused_field = .default_agent;
        y += input_height + layout.row_gap;

        if (pointer.mouse_released and
            isFocusField(state.focused_field) and
            !input_rect.contains(.{ pointer.mouse_x, pointer.mouse_y }) and
            !default_session_rect.contains(.{ pointer.mouse_x, pointer.mouse_y }) and
            !default_agent_rect.contains(.{ pointer.mouse_x, pointer.mouse_y }))
        {
            state.focused_field = .none;
        }
    }

    host.draw_form_field_label(host.ctx, rect.min[0] + pad, &y, input_width, layout, "UI Theme");
    const ui_theme_rect = Rect.fromXYWH(rect.min[0] + pad, y, input_width, input_height);
    const ui_theme_focused = host.draw_text_input(
        host.ctx,
        ui_theme_rect,
        fields.ui_theme,
        state.focused_field == .ui_theme,
        .{ .placeholder = "default" },
    );
    if (ui_theme_focused) state.focused_field = .ui_theme;

    y += input_height + layout.row_gap;
    host.draw_form_field_label(host.ctx, rect.min[0] + pad, &y, input_width, layout, "UI Profile");
    const ui_profile_rect = Rect.fromXYWH(rect.min[0] + pad, y, input_width, input_height);
    const ui_profile_focused = host.draw_text_input(
        host.ctx,
        ui_profile_rect,
        fields.ui_profile,
        state.focused_field == .ui_profile,
        .{ .placeholder = "default" },
    );
    if (ui_profile_focused) state.focused_field = .ui_profile;

    y += input_height + layout.row_gap;
    host.draw_form_field_label(host.ctx, rect.min[0] + pad, &y, input_width, layout, "UI Theme Pack");
    const ui_theme_pack_rect = Rect.fromXYWH(rect.min[0] + pad, y, input_width, input_height);
    const ui_theme_pack_focused = host.draw_text_input(
        host.ctx,
        ui_theme_pack_rect,
        fields.ui_theme_pack,
        state.focused_field == .ui_theme_pack,
        .{ .placeholder = "" },
    );
    if (ui_theme_pack_focused) state.focused_field = .ui_theme_pack;

    y += input_height + layout.section_gap * 0.55;
    const watch_button_label = if (model.watch_theme_pack) "Watch Theme Pack: On" else "Watch Theme Pack: Off";
    const watch_button_rect = Rect.fromXYWH(rect.min[0] + pad, y, @max(220.0, rect_width * 0.62), button_height);
    if (host.draw_button(host.ctx, watch_button_rect, watch_button_label, .{ .variant = .secondary })) {
        emitAction(&action, .toggle_watch_theme_pack);
    }

    if (variant == .launcher) {
        y += button_height + layout.row_gap;
        const auto_connect_label = if (model.auto_connect_on_launch) "Auto Connect: On" else "Auto Connect: Off";
        const auto_connect_rect = Rect.fromXYWH(rect.min[0] + pad, y, @max(220.0, rect_width * 0.52), button_height);
        if (host.draw_button(host.ctx, auto_connect_rect, auto_connect_label, .{ .variant = .secondary })) {
            emitAction(&action, .toggle_auto_connect_on_launch);
        }

        y += button_height + layout.row_gap;
        const ws_verbose_label = if (model.ws_verbose_logs) "Verbose WS Logs: On" else "Verbose WS Logs: Off";
        const ws_verbose_rect = Rect.fromXYWH(rect.min[0] + pad, y, @max(220.0, rect_width * 0.56), button_height);
        if (host.draw_button(host.ctx, ws_verbose_rect, ws_verbose_label, .{ .variant = .secondary })) {
            emitAction(&action, .toggle_ws_verbose_logs);
        }
    }

    y += button_height + layout.row_gap;
    host.draw_label(host.ctx, rect.min[0] + pad, y, "Terminal renderer", colors.text_primary);
    y += 20.0 * ui_scale;
    const backend_button_width: f32 = @max(120.0, (rect_width - pad * 3.0) * 0.5);
    const backend_plain_rect = Rect.fromXYWH(rect.min[0] + pad, y, backend_button_width, button_height);
    const backend_ghostty_rect = Rect.fromXYWH(backend_plain_rect.max[0] + pad, y, backend_button_width, button_height);
    if (host.draw_button(
        host.ctx,
        backend_plain_rect,
        "Plain",
        .{ .variant = if (model.terminal_backend == .plain_text) .primary else .secondary },
    )) {
        emitAction(&action, .{ .set_terminal_backend = .plain_text });
    }
    if (host.draw_button(
        host.ctx,
        backend_ghostty_rect,
        "Ghostty-VT",
        .{ .variant = if (model.terminal_backend == .ghostty_vt) .primary else .secondary },
    )) {
        emitAction(&action, .{ .set_terminal_backend = .ghostty_vt });
    }
    y += button_height + layout.row_gap * 0.6;
    host.draw_text_trimmed(
        host.ctx,
        rect.min[0] + pad,
        y,
        input_width,
        "Runtime selection; saved when you press Save Config.",
        colors.text_secondary,
    );

    if (pointer.mouse_released and
        isFocusField(state.focused_field) and
        !ui_theme_rect.contains(.{ pointer.mouse_x, pointer.mouse_y }) and
        !ui_profile_rect.contains(.{ pointer.mouse_x, pointer.mouse_y }) and
        !ui_theme_pack_rect.contains(.{ pointer.mouse_x, pointer.mouse_y }))
    {
        state.focused_field = .none;
    }

    if (variant == .launcher) {
        const button_width: f32 = @max(148.0 * ui_scale, rect_width * 0.25);
        const action_row_y = y + layout.line_height + layout.section_gap * 0.45;
        const connect_rect = Rect.fromXYWH(rect.min[0] + pad, action_row_y, button_width, button_height);
        if (host.draw_button(
            host.ctx,
            connect_rect,
            "Connect",
            .{ .variant = .primary, .disabled = model.isConnecting() },
        )) {
            emitAction(&action, .connect);
        }

        const save_rect = Rect.fromXYWH(connect_rect.max[0] + pad, action_row_y, button_width, button_height);
        if (host.draw_button(host.ctx, save_rect, "Save Config", .{ .variant = .secondary })) {
            emitAction(&action, .save_config);
        }

        const history_row_y = action_row_y + button_height + layout.row_gap;
        const load_history_rect = Rect.fromXYWH(rect.min[0] + pad, history_row_y, button_width, button_height);
        if (host.draw_button(
            host.ctx,
            load_history_rect,
            "Load History",
            .{ .variant = .secondary, .disabled = !model.canRunConnectedActions() },
        )) {
            emitAction(&action, .load_history);
        }

        const restore_rect = Rect.fromXYWH(load_history_rect.max[0] + pad, history_row_y, button_width, button_height);
        if (host.draw_button(
            host.ctx,
            restore_rect,
            "Restore Last",
            .{ .variant = .secondary, .disabled = !model.canRunConnectedActions() },
        )) {
            emitAction(&action, .restore_last);
        }

        host.draw_text_trimmed(
            host.ctx,
            rect.min[0] + pad,
            history_row_y + button_height + layout.row_gap * 0.5,
            input_width,
            "Open panels from Windows menu (top bar).",
            colors.text_secondary,
        );

        const content_bottom_scrolled = history_row_y + button_height + layout.row_gap * 1.5 + layout.line_height;
        applyScroll(host, rect, pad, rect_width, content_bottom_scrolled, state);
    } else {
        y += button_height + layout.section_gap;
        const save_rect = Rect.fromXYWH(rect.min[0] + pad, y, @max(148.0 * ui_scale, rect_width * 0.25), button_height);
        if (host.draw_button(host.ctx, save_rect, "Save Workspace Settings", .{ .variant = .secondary })) {
            emitAction(&action, .save_config);
        }
        const content_bottom_scrolled = y + button_height + layout.row_gap + layout.line_height;
        applyScroll(host, rect, pad, rect_width, content_bottom_scrolled, state);
    }

    return action;
}

fn emitAction(slot: *?interfaces.LauncherSettingsAction, next: interfaces.LauncherSettingsAction) void {
    if (slot.* == null) slot.* = next;
}

fn applyScroll(host: Host, rect: Rect, pad: f32, rect_width: f32, content_bottom_scrolled: f32, state: *State) void {
    const content_bottom = content_bottom_scrolled + state.scroll_y;
    const total_height = content_bottom - (rect.min[1] + pad);
    const viewport_h = @max(0.0, rect.max[1] - rect.min[1] - pad * 2.0);
    const max_scroll = if (total_height > viewport_h) total_height - viewport_h else 0.0;
    if (state.scroll_y < 0.0) state.scroll_y = 0.0;
    if (state.scroll_y > max_scroll) state.scroll_y = max_scroll;
    const scroll_view_rect = Rect.fromXYWH(rect.min[0], rect.min[1] + pad, rect_width, viewport_h);
    host.draw_vertical_scrollbar(host.ctx, scroll_view_rect, total_height, &state.scroll_y);
}

fn isFocusField(field: FocusField) bool {
    return switch (field) {
        .server_url,
        .default_session,
        .default_agent,
        .ui_theme,
        .ui_profile,
        .ui_theme_pack,
        => true,
        else => false,
    };
}
