const zui = @import("ziggy-ui");

const widgets = zui.widgets;
const Rect = zui.core.Rect;
const form_layout = zui.ui.layout.form_layout;
const interfaces = zui.ui.panel_interfaces;

// Reusable project workspace panel. The host owns project/workspace operations
// while this module owns layout, scrolling, and typed action emission.
pub const FocusField = enum {
    none,
    project_token,
    create_name,
    create_vision,
    operator_token,
    mount_path,
    mount_node_id,
    mount_export_name,
};

pub const TextFields = struct {
    project_token: []const u8 = "",
    create_name: []const u8 = "",
    create_vision: []const u8 = "",
    operator_token: []const u8 = "",
    mount_path: []const u8 = "/",
    mount_node_id: []const u8 = "",
    mount_export_name: []const u8 = "",
};

pub const State = struct {
    focused_field: FocusField = .none,
    scroll_y: f32 = 0.0,
};

pub const PointerState = struct {
    mouse_x: f32,
    mouse_y: f32,
    mouse_released: bool,
};

pub const ThemeColors = struct {
    text_primary: [4]f32,
    text_secondary: [4]f32,
    warning_text: [4]f32,
    error_text: [4]f32,
};

pub const Host = struct {
    ctx: *anyopaque,
    draw_form_section_title: *const fn (ctx: *anyopaque, x: f32, y: *f32, max_w: f32, layout: form_layout.Metrics, text: []const u8) void,
    draw_form_field_label: *const fn (ctx: *anyopaque, x: f32, y: *f32, max_w: f32, layout: form_layout.Metrics, text: []const u8) void,
    draw_text_input: *const fn (ctx: *anyopaque, rect: Rect, text: []const u8, focused: bool, opts: widgets.text_input.Options) bool,
    draw_button: *const fn (ctx: *anyopaque, rect: Rect, label: []const u8, opts: widgets.button.Options) bool,
    draw_label: *const fn (ctx: *anyopaque, x: f32, y: f32, text: []const u8, color: [4]f32) void,
    draw_text_trimmed: *const fn (ctx: *anyopaque, x: f32, y: f32, max_w: f32, text: []const u8, color: [4]f32) void,
    draw_status_row: *const fn (ctx: *anyopaque, rect: Rect) void,
    draw_vertical_scrollbar: *const fn (ctx: *anyopaque, viewport_rect: Rect, content_height: f32, scroll_y: *f32) void,
};

pub fn draw(
    host: Host,
    rect: Rect,
    layout: form_layout.Metrics,
    ui_scale: f32,
    colors: ThemeColors,
    model: interfaces.ProjectPanelModel,
    view: interfaces.ProjectPanelView,
    fields: TextFields,
    pointer: PointerState,
    state: *State,
) ?interfaces.ProjectPanelAction {
    const pad = layout.inset;
    const rect_width = rect.max[0] - rect.min[0];
    const input_height = layout.input_height;
    const button_height = layout.button_height;
    const input_width = @max(220.0, rect_width - pad * 2.0);
    var y = rect.min[1] + pad - state.scroll_y;
    var action: ?interfaces.ProjectPanelAction = null;

    host.draw_form_section_title(host.ctx, rect.min[0] + pad, &y, input_width, layout, view.title);

    host.draw_form_field_label(host.ctx, rect.min[0] + pad, &y, input_width, layout, "Selected Project");
    const project_rect = Rect.fromXYWH(rect.min[0] + pad, y, input_width, input_height);
    _ = host.draw_button(
        host.ctx,
        project_rect,
        view.selected_project_button_label,
        .{ .variant = .secondary, .disabled = !model.has_projects },
    );

    y += input_height;
    host.draw_text_trimmed(host.ctx, rect.min[0] + pad, y, input_width, view.lock_state_text, colors.text_secondary);
    y += layout.line_height + layout.row_gap * 0.45;

    host.draw_form_field_label(host.ctx, rect.min[0] + pad, &y, input_width, layout, "Project Token (optional; required only for locked projects)");
    const project_token_rect = Rect.fromXYWH(rect.min[0] + pad, y, input_width, input_height);
    const project_token_focused = host.draw_text_input(
        host.ctx,
        project_token_rect,
        fields.project_token,
        state.focused_field == .project_token,
        .{ .placeholder = "proj-..." },
    );
    if (project_token_focused) state.focused_field = .project_token;

    y += input_height + layout.row_gap;
    host.draw_form_field_label(host.ctx, rect.min[0] + pad, &y, input_width, layout, "Create Project Name");
    const create_name_rect = Rect.fromXYWH(rect.min[0] + pad, y, input_width, input_height);
    const create_name_focused = host.draw_text_input(
        host.ctx,
        create_name_rect,
        fields.create_name,
        state.focused_field == .create_name,
        .{ .placeholder = "Distributed Workspace" },
    );
    if (create_name_focused) state.focused_field = .create_name;

    y += input_height + layout.row_gap * 0.8;
    host.draw_form_field_label(host.ctx, rect.min[0] + pad, &y, input_width, layout, "Create Vision (optional)");
    const create_vision_rect = Rect.fromXYWH(rect.min[0] + pad, y, input_width, input_height);
    const create_vision_focused = host.draw_text_input(
        host.ctx,
        create_vision_rect,
        fields.create_vision,
        state.focused_field == .create_vision,
        .{ .placeholder = "unified node mounts" },
    );
    if (create_vision_focused) state.focused_field = .create_vision;

    y += input_height + layout.row_gap * 0.8;
    host.draw_form_field_label(host.ctx, rect.min[0] + pad, &y, input_width, layout, "Operator Token (optional)");
    const operator_token_rect = Rect.fromXYWH(rect.min[0] + pad, y, input_width, input_height);
    const operator_token_focused = host.draw_text_input(
        host.ctx,
        operator_token_rect,
        fields.operator_token,
        state.focused_field == .operator_token,
        .{ .placeholder = "(fallback: saved admin token)" },
    );
    if (operator_token_focused) state.focused_field = .operator_token;

    y += input_height + layout.section_gap;
    const button_width: f32 = @max(152.0 * ui_scale, rect_width * 0.28);
    const create_rect = Rect.fromXYWH(rect.min[0] + pad, y, button_width, button_height);
    const refresh_rect = Rect.fromXYWH(create_rect.max[0] + pad, y, button_width, button_height);
    const activate_rect = Rect.fromXYWH(refresh_rect.max[0] + pad, y, button_width, button_height);

    if (host.draw_button(host.ctx, create_rect, "Create Project", .{ .variant = .primary, .disabled = !model.can_create_project })) {
        emitAction(&action, .create_project);
    }
    if (host.draw_button(host.ctx, refresh_rect, "Refresh Workspace", .{ .variant = .secondary, .disabled = model.controlsDisabled() })) {
        emitAction(&action, .refresh_workspace);
    }
    if (host.draw_button(host.ctx, activate_rect, "Activate Project", .{ .variant = .secondary, .disabled = !model.can_activate_project })) {
        emitAction(&action, .activate_project);
    }

    y += button_height + layout.row_gap;
    const lock_rect = Rect.fromXYWH(rect.min[0] + pad, y, button_width, button_height);
    const unlock_rect = Rect.fromXYWH(lock_rect.max[0] + pad, y, button_width, button_height);
    if (host.draw_button(host.ctx, lock_rect, "Lock Project", .{ .variant = .secondary, .disabled = !model.can_lock_project })) {
        emitAction(&action, .lock_project);
    }
    if (host.draw_button(host.ctx, unlock_rect, "Unlock Project", .{ .variant = .secondary, .disabled = !model.can_unlock_project })) {
        emitAction(&action, .unlock_project);
    }

    y += button_height + layout.section_gap * 0.7;
    host.draw_form_section_title(host.ctx, rect.min[0] + pad, &y, input_width, layout, "Project Mount");

    host.draw_form_field_label(host.ctx, rect.min[0] + pad, &y, input_width, layout, "Mount Path");
    const mount_path_rect = Rect.fromXYWH(rect.min[0] + pad, y, input_width, input_height);
    const mount_path_focused = host.draw_text_input(
        host.ctx,
        mount_path_rect,
        fields.mount_path,
        state.focused_field == .mount_path,
        .{ .placeholder = "/work" },
    );
    if (mount_path_focused) state.focused_field = .mount_path;

    y += input_height + layout.row_gap * 0.8;
    host.draw_form_field_label(host.ctx, rect.min[0] + pad, &y, input_width, layout, "Mount Node ID");
    const mount_node_rect = Rect.fromXYWH(rect.min[0] + pad, y, input_width, input_height);
    const mount_node_focused = host.draw_text_input(
        host.ctx,
        mount_node_rect,
        fields.mount_node_id,
        state.focused_field == .mount_node_id,
        .{ .placeholder = "node-2" },
    );
    if (mount_node_focused) state.focused_field = .mount_node_id;

    y += input_height + layout.row_gap * 0.8;
    host.draw_form_field_label(host.ctx, rect.min[0] + pad, &y, input_width, layout, "Mount Export Name");
    const mount_export_rect = Rect.fromXYWH(rect.min[0] + pad, y, input_width, input_height);
    const mount_export_focused = host.draw_text_input(
        host.ctx,
        mount_export_rect,
        fields.mount_export_name,
        state.focused_field == .mount_export_name,
        .{ .placeholder = "work" },
    );
    if (mount_export_focused) state.focused_field = .mount_export_name;

    y += input_height + layout.section_gap;
    const add_mount_rect = Rect.fromXYWH(rect.min[0] + pad, y, button_width, button_height);
    const remove_mount_rect = Rect.fromXYWH(add_mount_rect.max[0] + pad, y, button_width, button_height);
    if (host.draw_button(host.ctx, add_mount_rect, "Add Mount", .{ .variant = .primary, .disabled = model.controlsDisabled() })) {
        emitAction(&action, .add_mount);
    }
    if (host.draw_button(host.ctx, remove_mount_rect, "Remove Mount", .{ .variant = .secondary, .disabled = model.controlsDisabled() })) {
        emitAction(&action, .remove_mount);
    }

    if (view.mount_hint) |hint| {
        host.draw_text_trimmed(
            host.ctx,
            rect.min[0] + pad,
            y + button_height + layout.row_gap * 0.5,
            input_width,
            hint,
            colors.text_secondary,
        );
    }

    y += button_height + layout.row_gap;
    if (view.mount_hint != null) y += layout.line_height;
    host.draw_text_trimmed(
        host.ctx,
        rect.min[0] + pad,
        y + @max(0.0, (button_height - layout.line_height) * 0.5),
        input_width,
        view.help_line,
        colors.text_secondary,
    );

    y += button_height + layout.section_gap;
    const auth_status_rect = Rect.fromXYWH(rect.min[0] + pad, y, button_width, button_height);
    const auth_rotate_user_rect = Rect.fromXYWH(auth_status_rect.max[0] + pad, y, button_width, button_height);
    const auth_rotate_admin_rect = Rect.fromXYWH(auth_rotate_user_rect.max[0] + pad, y, button_width, button_height);
    if (host.draw_button(host.ctx, auth_status_rect, "Auth Status", .{ .variant = .secondary, .disabled = model.controlsDisabled() })) {
        emitAction(&action, .auth_status);
    }
    if (host.draw_button(host.ctx, auth_rotate_user_rect, "Rotate User", .{ .variant = .secondary, .disabled = model.controlsDisabled() })) {
        emitAction(&action, .rotate_auth_user);
    }
    if (host.draw_button(host.ctx, auth_rotate_admin_rect, "Rotate Admin", .{ .variant = .primary, .disabled = model.controlsDisabled() })) {
        emitAction(&action, .rotate_auth_admin);
    }

    y += button_height + layout.row_gap;
    const auth_reveal_admin_rect = Rect.fromXYWH(rect.min[0] + pad, y, button_width, button_height);
    const auth_copy_admin_rect = Rect.fromXYWH(auth_reveal_admin_rect.max[0] + pad, y, button_width, button_height);
    const auth_reveal_user_rect = Rect.fromXYWH(auth_copy_admin_rect.max[0] + pad, y, button_width, button_height);
    if (host.draw_button(host.ctx, auth_reveal_admin_rect, "Reveal Admin", .{ .variant = .secondary, .disabled = model.controlsDisabled() })) {
        emitAction(&action, .reveal_auth_admin);
    }
    if (host.draw_button(host.ctx, auth_copy_admin_rect, "Copy Admin", .{ .variant = .secondary, .disabled = model.controlsDisabled() })) {
        emitAction(&action, .copy_auth_admin);
    }
    if (host.draw_button(host.ctx, auth_reveal_user_rect, "Reveal User", .{ .variant = .secondary, .disabled = model.controlsDisabled() })) {
        emitAction(&action, .reveal_auth_user);
    }

    y += button_height + layout.row_gap;
    const auth_copy_user_rect = Rect.fromXYWH(rect.min[0] + pad, y, button_width, button_height);
    if (host.draw_button(host.ctx, auth_copy_user_rect, "Copy User", .{ .variant = .secondary, .disabled = model.controlsDisabled() })) {
        emitAction(&action, .copy_auth_user);
    }

    y += button_height + layout.section_gap;
    const status_height: f32 = @max(layout.line_height + layout.inner_inset * 2.2, 32.0 * ui_scale);
    const status_rect = Rect.fromXYWH(rect.min[0] + pad, y, input_width, status_height);
    host.draw_status_row(host.ctx, status_rect);
    y += status_height + layout.row_gap;

    if (view.workspace_error_text) |err_text| {
        host.draw_label(host.ctx, rect.min[0] + pad, y, err_text, colors.error_text);
        y += layout.line_height;
    }
    if (view.selected_project_line) |line| {
        host.draw_label(host.ctx, rect.min[0] + pad, y, line, colors.text_secondary);
        y += layout.line_height;
    }
    if (view.setup_status_line) |line| {
        host.draw_label(
            host.ctx,
            rect.min[0] + pad,
            y,
            line,
            if (view.setup_status_warning) colors.warning_text else colors.text_secondary,
        );
        y += layout.line_height;
    }
    if (view.setup_vision_line) |line| {
        host.draw_text_trimmed(host.ctx, rect.min[0] + pad, y, input_width, line, colors.text_secondary);
        y += layout.line_height;
    }
    if (view.workspace_summary_line) |line| {
        host.draw_label(host.ctx, rect.min[0] + pad, y, line, colors.text_secondary);
        y += layout.line_height;
    }
    if (view.workspace_health_line) |line| {
        const health_color = if (view.workspace_health_error)
            colors.error_text
        else if (view.workspace_health_warning)
            colors.warning_text
        else
            colors.text_secondary;
        host.draw_label(host.ctx, rect.min[0] + pad, y, line, health_color);
        y += layout.line_height;
    }
    if (view.counts_line) |line| {
        host.draw_label(host.ctx, rect.min[0] + pad, y, line, colors.text_secondary);
        y += layout.line_height;
    }
    y += layout.row_gap * 0.6;

    if (view.projects.len > 0) {
        host.draw_label(host.ctx, rect.min[0] + pad, y, "Project List:", colors.text_primary);
        y += layout.label_to_input_gap;
        const row_h = @max(layout.button_height * 0.86, layout.line_height + layout.inner_inset);
        const row_gap = @max(1.0, layout.inner_inset * 0.3);
        const row_step = row_h + row_gap;
        const list_top = y;
        const list_bottom = rect.max[1] + state.scroll_y;
        const visible_start_idx: usize = @intFromFloat(@max(0.0, @floor((rect.min[1] - list_top) / row_step)));
        const visible_end_idx_unclamped: usize = @intFromFloat(@max(0.0, @ceil((list_bottom - list_top) / row_step)));
        const max_projects: usize = view.projects.len;
        const visible_end_idx = @min(max_projects, visible_end_idx_unclamped + 1);

        if (visible_start_idx > 0) {
            y += row_step * @as(f32, @floatFromInt(visible_start_idx));
        }

        var idx: usize = visible_start_idx;
        while (idx < max_projects) : (idx += 1) {
            if (idx >= visible_end_idx) {
                const remaining = max_projects - idx;
                y += row_step * @as(f32, @floatFromInt(remaining));
                break;
            }
            const project = view.projects[idx];
            const row_button_w = @max(90.0 * ui_scale, rect_width * 0.17);
            const text_max_w = @max(120.0, rect_width - (pad * 2.0) - row_button_w - pad);
            const text_y = y + @max(0.0, (row_h - layout.line_height) * 0.5);
            host.draw_text_trimmed(host.ctx, rect.min[0] + pad, text_y, text_max_w, project.line, colors.text_secondary);
            const use_rect = Rect.fromXYWH(rect.min[0] + pad + text_max_w + pad, y, row_button_w, row_h);
            if (host.draw_button(
                host.ctx,
                use_rect,
                if (project.selected) "Selected" else "Use",
                .{ .variant = .secondary, .disabled = project.selected },
            )) {
                emitAction(&action, .{ .select_project_index = project.index });
            }
            y += row_step;
        }
    }

    if (view.nodes.len > 0) {
        y += layout.section_gap * 0.45;
        host.draw_label(host.ctx, rect.min[0] + pad, y, "Nodes:", colors.text_primary);
        y += layout.label_to_input_gap;
        const max_nodes: usize = @min(view.nodes.len, 8);
        var idx: usize = 0;
        while (idx < max_nodes) : (idx += 1) {
            const node = view.nodes[idx];
            host.draw_label(
                host.ctx,
                rect.min[0] + pad,
                y,
                node.line,
                if (node.degraded) colors.warning_text else colors.text_secondary,
            );
            y += layout.line_height;
        }
    }

    if (pointer.mouse_released and
        state.focused_field != .none and
        !project_token_rect.contains(.{ pointer.mouse_x, pointer.mouse_y }) and
        !create_name_rect.contains(.{ pointer.mouse_x, pointer.mouse_y }) and
        !create_vision_rect.contains(.{ pointer.mouse_x, pointer.mouse_y }) and
        !operator_token_rect.contains(.{ pointer.mouse_x, pointer.mouse_y }) and
        !mount_path_rect.contains(.{ pointer.mouse_x, pointer.mouse_y }) and
        !mount_node_rect.contains(.{ pointer.mouse_x, pointer.mouse_y }) and
        !mount_export_rect.contains(.{ pointer.mouse_x, pointer.mouse_y }))
    {
        state.focused_field = .none;
    }

    const content_bottom_scrolled = y;
    const content_bottom = content_bottom_scrolled + state.scroll_y;
    const total_height = content_bottom - (rect.min[1] + pad);
    const viewport_h = @max(0.0, rect.max[1] - rect.min[1] - pad * 2.0);
    const scroll_view_rect = Rect.fromXYWH(rect.min[0], rect.min[1] + pad, rect_width, viewport_h);
    host.draw_vertical_scrollbar(host.ctx, scroll_view_rect, total_height, &state.scroll_y);
    return action;
}

fn emitAction(slot: *?interfaces.ProjectPanelAction, next: interfaces.ProjectPanelAction) void {
    if (slot.* == null) slot.* = next;
}
