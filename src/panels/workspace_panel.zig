const zui = @import("ziggy-ui");

const widgets = zui.widgets;
const Rect = zui.core.Rect;
const form_layout = zui.ui.layout.form_layout;
const interfaces = zui.ui.panel_interfaces;

// Reusable workspace management panel, drawn only when the app is in the
// workspace stage (already connected and attached to a workspace). Creation of
// new workspaces is handled by the launcher modal; this panel is for managing
// the active workspace: switching, mounts, binds, nodes, auth tokens.
pub const FocusField = enum {
    none,
    workspace_token,
    // create_* fields are kept so TextFields stays wire-compatible with the
    // launcher modal that shares the same settings_panel backing store.
    create_name,
    create_vision,
    template_id,
    operator_token,
    mount_path,
    mount_node_id,
    mount_export_name,
    bind_path,
    bind_target_path,
};

pub const TextFields = struct {
    workspace_token: []const u8 = "",
    create_name: []const u8 = "",
    create_vision: []const u8 = "",
    template_id: []const u8 = "",
    operator_token: []const u8 = "",
    mount_path: []const u8 = "/",
    mount_node_id: []const u8 = "",
    mount_export_name: []const u8 = "",
    bind_path: []const u8 = "/repo",
    bind_target_path: []const u8 = "/nodes/local/fs",
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
    model: interfaces.WorkspacePanelModel,
    view: interfaces.WorkspacePanelView,
    fields: TextFields,
    pointer: PointerState,
    state: *State,
) ?interfaces.WorkspacePanelAction {
    const pad = layout.inset;
    const rect_width = rect.max[0] - rect.min[0];
    const input_width = @max(220.0, rect_width - pad * 2.0);
    const input_height = layout.input_height;
    const button_height = layout.button_height;
    const half_w = (input_width - pad) * 0.5;
    const btn_w = @max(130.0 * ui_scale, input_width * 0.26);
    const x = rect.min[0] + pad;
    var y = rect.min[1] + pad - state.scroll_y;
    var action: ?interfaces.WorkspacePanelAction = null;

    // ── Current workspace status ─────────────────────────────
    // Compact info header: selected workspace + lock state.
    if (view.selected_workspace_line) |line| {
        host.draw_text_trimmed(host.ctx, x, y, input_width, line, colors.text_primary);
        y += layout.line_height;
    }
    if (view.session_status_line) |line| {
        host.draw_text_trimmed(host.ctx, x, y, input_width, line,
            if (view.session_status_warning) colors.warning_text else colors.text_secondary);
        y += layout.line_height;
    }
    host.draw_text_trimmed(host.ctx, x, y, input_width, view.lock_state_text, colors.text_secondary);
    y += layout.line_height + layout.row_gap * 0.5;

    // Primary actions: Refresh | Activate | Attach Session.
    const refresh_r = Rect.fromXYWH(x, y, btn_w, button_height);
    const activate_r = Rect.fromXYWH(refresh_r.max[0] + pad, y, btn_w, button_height);
    const attach_r = Rect.fromXYWH(activate_r.max[0] + pad, y, btn_w, button_height);
    if (host.draw_button(host.ctx, refresh_r, "Refresh",
        .{ .variant = .secondary, .disabled = model.controlsDisabled() }))
        emitAction(&action, .refresh_workspace);
    if (host.draw_button(host.ctx, activate_r, "Activate",
        .{ .variant = .secondary, .disabled = !model.can_activate_workspace }))
        emitAction(&action, .activate_workspace);
    if (host.draw_button(host.ctx, attach_r, "Attach Session",
        .{ .variant = .primary, .disabled = !model.can_attach_session }))
        emitAction(&action, .attach_session);
    y += button_height + layout.row_gap * 0.4;

    // Status and health text (errors, setup hints, health warnings).
    if (view.workspace_error_text) |err| {
        host.draw_text_trimmed(host.ctx, x, y, input_width, err, colors.error_text);
        y += layout.line_height;
    }
    if (view.setup_status_line) |line| {
        host.draw_text_trimmed(host.ctx, x, y, input_width, line,
            if (view.setup_status_warning) colors.warning_text else colors.text_secondary);
        y += layout.line_height;
    }
    if (view.workspace_health_line) |line| {
        host.draw_text_trimmed(host.ctx, x, y, input_width, line,
            if (view.workspace_health_error) colors.error_text
            else if (view.workspace_health_warning) colors.warning_text
            else colors.text_secondary);
        y += layout.line_height;
    }
    if (view.workspace_summary_line) |line| {
        host.draw_text_trimmed(host.ctx, x, y, input_width, line, colors.text_secondary);
        y += layout.line_height;
    }
    y += layout.section_gap;

    // ── Switch Workspace ─────────────────────────────────────
    // Virtualized list — only drawn when there's more than one workspace or
    // when no workspace is currently selected.
    if (view.workspaces.len > 0) {
        host.draw_form_section_title(host.ctx, x, &y, input_width, layout, "Switch Workspace");

        const ws_row_h = @max(button_height * 0.82, layout.line_height + layout.inner_inset);
        const ws_row_gap = @max(1.0, layout.inner_inset * 0.3);
        const ws_row_step = ws_row_h + ws_row_gap;
        const ws_btn_w = btn_w * 0.50;
        const ws_text_max_w = input_width - ws_btn_w - pad;

        const list_top = y;
        const list_bottom = rect.max[1] + state.scroll_y;
        const vis_start: usize = @intFromFloat(@max(0.0, @floor((rect.min[1] - list_top) / ws_row_step)));
        const vis_end_raw: usize = @intFromFloat(@max(0.0, @ceil((list_bottom - list_top) / ws_row_step)));
        const vis_end = @min(view.workspaces.len, vis_end_raw + 1);

        if (vis_start > 0) y += ws_row_step * @as(f32, @floatFromInt(vis_start));

        var wi: usize = vis_start;
        while (wi < view.workspaces.len) : (wi += 1) {
            if (wi >= vis_end) {
                y += ws_row_step * @as(f32, @floatFromInt(view.workspaces.len - wi));
                break;
            }
            const ws = view.workspaces[wi];
            const text_y = y + @max(0.0, (ws_row_h - layout.line_height) * 0.5);
            host.draw_text_trimmed(host.ctx, x, text_y, ws_text_max_w, ws.line,
                if (ws.selected) colors.text_primary else colors.text_secondary);
            const sel_r = Rect.fromXYWH(x + ws_text_max_w + pad * 0.5, y, ws_btn_w, ws_row_h);
            if (host.draw_button(host.ctx, sel_r,
                if (ws.selected) "Active" else "Switch",
                .{ .variant = if (ws.selected) .primary else .secondary, .disabled = ws.selected }))
                emitAction(&action, .{ .select_workspace_index = ws.index });
            y += ws_row_step;
        }
        y += layout.section_gap;
    }

    // ── Mounts ───────────────────────────────────────────────
    // Mounts attach a remote node's filesystem export into this workspace.
    host.draw_form_section_title(host.ctx, x, &y, input_width, layout, "Mounts");

    if (view.mounts.len > 0) {
        const mt_h = @max(button_height * 0.82, layout.line_height + layout.inner_inset);
        const mt_gap = @max(1.0, layout.inner_inset * 0.3);
        const mt_act_w = btn_w * 0.48;
        const mt_text_max_w = input_width - mt_act_w * 2.0 - pad * 1.5;
        for (view.mounts) |m| {
            const is_sel = m.selected;
            const text_y = y + @max(0.0, (mt_h - layout.line_height) * 0.5);
            host.draw_text_trimmed(host.ctx, x, text_y, mt_text_max_w, m.mount_path,
                if (is_sel) colors.text_primary else colors.text_secondary);
            const sel_r = Rect.fromXYWH(x + mt_text_max_w + pad * 0.5, y, mt_act_w, mt_h);
            const rm_r = Rect.fromXYWH(sel_r.max[0] + pad * 0.5, y, mt_act_w, mt_h);
            if (host.draw_button(host.ctx, sel_r,
                if (is_sel) "Selected" else "Select",
                .{ .variant = .secondary, .disabled = is_sel }))
                emitAction(&action, .{ .select_mount_index = m.index });
            if (host.draw_button(host.ctx, rm_r, "Remove",
                .{ .variant = .secondary, .disabled = !model.can_remove_mount or !is_sel }))
                emitAction(&action, .remove_selected_mount);
            y += mt_h + mt_gap;
        }
        y += layout.row_gap * 0.3;
    } else {
        host.draw_text_trimmed(host.ctx, x, y, input_width, "No mounts configured.", colors.text_secondary);
        y += layout.line_height + layout.row_gap * 0.3;
    }

    // Add-mount form: three fields on one row — Path | Node ID | Export.
    const mp_w = input_width * 0.38;
    const mn_w = input_width * 0.28;
    const me_w = input_width - mp_w - mn_w - pad * 2.0;
    host.draw_label(host.ctx, x, y, "Path", colors.text_secondary);
    host.draw_label(host.ctx, x + mp_w + pad, y, "Node ID", colors.text_secondary);
    host.draw_label(host.ctx, x + mp_w + mn_w + pad * 2.0, y, "Export", colors.text_secondary);
    y += layout.label_to_input_gap;
    const mount_path_rect = Rect.fromXYWH(x, y, mp_w, input_height);
    const mount_node_rect = Rect.fromXYWH(x + mp_w + pad, y, mn_w, input_height);
    const mount_export_rect = Rect.fromXYWH(x + mp_w + mn_w + pad * 2.0, y, me_w, input_height);
    if (host.draw_text_input(host.ctx, mount_path_rect, fields.mount_path,
        state.focused_field == .mount_path, .{ .placeholder = "/" }))
        state.focused_field = .mount_path;
    if (host.draw_text_input(host.ctx, mount_node_rect, fields.mount_node_id,
        state.focused_field == .mount_node_id, .{ .placeholder = "node-id" }))
        state.focused_field = .mount_node_id;
    if (host.draw_text_input(host.ctx, mount_export_rect, fields.mount_export_name,
        state.focused_field == .mount_export_name, .{ .placeholder = "work" }))
        state.focused_field = .mount_export_name;
    y += input_height + layout.row_gap * 0.6;

    const node_picker_open = view.nodes_for_picker.len > 0;
    const add_mount_r = Rect.fromXYWH(x, y, btn_w, button_height);
    const browse_r = Rect.fromXYWH(add_mount_r.max[0] + pad, y, btn_w, button_height);
    if (host.draw_button(host.ctx, add_mount_r, "Add Mount",
        .{ .variant = .primary, .disabled = model.controlsDisabled() }))
        emitAction(&action, .add_mount);
    if (host.draw_button(host.ctx, browse_r,
        if (node_picker_open) "Hide Nodes" else "Browse Nodes",
        .{ .variant = if (node_picker_open) .primary else .secondary, .disabled = model.controlsDisabled() }))
        emitAction(&action, .open_node_browser);
    y += button_height + layout.row_gap * 0.4;

    if (view.mount_hint) |hint| {
        host.draw_text_trimmed(host.ctx, x, y, input_width, hint, colors.text_secondary);
        y += layout.line_height + layout.row_gap * 0.3;
    }

    // Node picker — toggled by Browse Nodes / Hide Nodes.
    // node_browser_open is inferred from nodes_for_picker being populated.
    if (node_picker_open) {
        host.draw_label(host.ctx, x, y, "Select a node to fill the Node ID field:", colors.text_secondary);
        y += layout.label_to_input_gap;
        const pk_h = @max(button_height * 0.78, layout.line_height + layout.inner_inset);
        const pk_gap = @max(1.0, layout.inner_inset * 0.3);
        const pk_use_w = btn_w * 0.44;
        const pk_text_max_w = input_width - pk_use_w - pad;
        const max_nodes: usize = @min(view.nodes_for_picker.len, 8);
        for (view.nodes_for_picker[0..max_nodes]) |np| {
            const text_y = y + @max(0.0, (pk_h - layout.line_height) * 0.5);
            host.draw_text_trimmed(host.ctx, x, text_y, pk_text_max_w, np.node_name,
                if (np.online) colors.text_secondary else colors.warning_text);
            const use_r = Rect.fromXYWH(x + pk_text_max_w + pad * 0.5, y, pk_use_w, pk_h);
            if (host.draw_button(host.ctx, use_r, "Use", .{ .variant = .secondary, .disabled = false }))
                emitAction(&action, .{ .select_node_for_mount = np.index });
            y += pk_h + pk_gap;
        }
    } else if (!model.has_nodes and !model.controlsDisabled()) {
        // No nodes known yet — prompt a refresh so the list can populate.
        host.draw_text_trimmed(host.ctx, x, y, input_width,
            "No nodes found. Try Refresh to discover nodes.", colors.text_secondary);
        y += layout.line_height + layout.row_gap * 0.3;
    }
    y += layout.section_gap;

    // ── Binds ────────────────────────────────────────────────
    // Binds create path aliases within the workspace filesystem.
    // e.g. /repo → /nodes/local/fs/home/user/myproject
    host.draw_form_section_title(host.ctx, x, &y, input_width, layout, "Binds");

    if (view.binds.len > 0) {
        const bd_h = @max(button_height * 0.82, layout.line_height + layout.inner_inset);
        const bd_gap = @max(1.0, layout.inner_inset * 0.3);
        const bd_act_w = btn_w * 0.48;
        const bd_text_max_w = input_width - bd_act_w * 2.0 - pad * 1.5;
        for (view.binds) |b| {
            const is_sel = b.selected;
            const text_y = y + @max(0.0, (bd_h - layout.line_height) * 0.5);
            host.draw_text_trimmed(host.ctx, x, text_y, bd_text_max_w, b.bind_path,
                if (is_sel) colors.text_primary else colors.text_secondary);
            const sel_r = Rect.fromXYWH(x + bd_text_max_w + pad * 0.5, y, bd_act_w, bd_h);
            const rm_r = Rect.fromXYWH(sel_r.max[0] + pad * 0.5, y, bd_act_w, bd_h);
            if (host.draw_button(host.ctx, sel_r,
                if (is_sel) "Selected" else "Select",
                .{ .variant = .secondary, .disabled = is_sel }))
                emitAction(&action, .{ .select_bind_index = b.index });
            if (host.draw_button(host.ctx, rm_r, "Remove",
                .{ .variant = .secondary, .disabled = !model.can_remove_bind or !is_sel }))
                emitAction(&action, .remove_selected_bind);
            y += bd_h + bd_gap;
        }
        y += layout.row_gap * 0.3;
    } else {
        host.draw_text_trimmed(host.ctx, x, y, input_width, "No binds configured.", colors.text_secondary);
        y += layout.line_height + layout.row_gap * 0.3;
    }

    // Add-bind form: Bind Path (half) | Target Path (half).
    host.draw_label(host.ctx, x, y, "Bind Path", colors.text_secondary);
    host.draw_label(host.ctx, x + half_w + pad, y, "Target Path", colors.text_secondary);
    y += layout.label_to_input_gap;
    const bind_path_rect = Rect.fromXYWH(x, y, half_w, input_height);
    const bind_target_rect = Rect.fromXYWH(x + half_w + pad, y, half_w, input_height);
    if (host.draw_text_input(host.ctx, bind_path_rect, fields.bind_path,
        state.focused_field == .bind_path, .{ .placeholder = "/repo" }))
        state.focused_field = .bind_path;
    if (host.draw_text_input(host.ctx, bind_target_rect, fields.bind_target_path,
        state.focused_field == .bind_target_path, .{ .placeholder = "/nodes/local/fs" }))
        state.focused_field = .bind_target_path;
    y += input_height + layout.row_gap * 0.6;

    const add_bind_r = Rect.fromXYWH(x, y, btn_w, button_height);
    if (host.draw_button(host.ctx, add_bind_r, "Add Bind",
        .{ .variant = .primary, .disabled = !model.can_activate_workspace }))
        emitAction(&action, .add_bind);
    y += button_height + layout.section_gap;

    // ── Nodes ────────────────────────────────────────────────
    if (view.nodes.len > 0) {
        host.draw_form_section_title(host.ctx, x, &y, input_width, layout, "Nodes");
        const max_nodes: usize = @min(view.nodes.len, 8);
        for (view.nodes[0..max_nodes]) |node| {
            host.draw_label(host.ctx, x, y, node.line,
                if (node.degraded) colors.warning_text else colors.text_secondary);
            y += layout.line_height;
        }
        y += layout.section_gap;
    }

    // ── Auth & Tokens ────────────────────────────────────────
    host.draw_form_section_title(host.ctx, x, &y, input_width, layout, "Auth & Tokens");

    // Workspace token — only relevant when workspace is locked.
    host.draw_label(host.ctx, x, y, "Workspace Token (required when workspace is locked)", colors.text_secondary);
    y += layout.label_to_input_gap;
    const workspace_token_rect = Rect.fromXYWH(x, y, input_width, input_height);
    if (host.draw_text_input(host.ctx, workspace_token_rect, fields.workspace_token,
        state.focused_field == .workspace_token, .{ .placeholder = "workspace-..." }))
        state.focused_field = .workspace_token;
    y += input_height + layout.row_gap * 0.7;

    // Lock / Unlock (token rotation) + Rotate Token.
    const lock_r = Rect.fromXYWH(x, y, btn_w, button_height);
    const unlock_r = Rect.fromXYWH(lock_r.max[0] + pad, y, btn_w, button_height);
    const rotate_r = Rect.fromXYWH(unlock_r.max[0] + pad, y, btn_w, button_height);
    if (host.draw_button(host.ctx, lock_r, "Lock",
        .{ .variant = .secondary, .disabled = !model.can_lock_workspace }))
        emitAction(&action, .lock_workspace);
    if (host.draw_button(host.ctx, unlock_r, "Unlock",
        .{ .variant = .secondary, .disabled = !model.can_unlock_workspace }))
        emitAction(&action, .unlock_workspace);
    if (host.draw_button(host.ctx, rotate_r, "Rotate Token",
        .{ .variant = .secondary, .disabled = !model.can_rotate_token }))
        emitAction(&action, .rotate_workspace_token);
    y += button_height + layout.row_gap * 0.4;

    // Token display (shown after rotate).
    if (view.token_display) |tok| {
        host.draw_text_trimmed(host.ctx, x, y, input_width, tok, colors.text_secondary);
        y += layout.line_height + layout.row_gap * 0.3;
    }

    // Auth role management buttons.
    const auth_r1a = Rect.fromXYWH(x, y, btn_w, button_height);
    const auth_r1b = Rect.fromXYWH(auth_r1a.max[0] + pad, y, btn_w, button_height);
    const auth_r1c = Rect.fromXYWH(auth_r1b.max[0] + pad, y, btn_w, button_height);
    if (host.draw_button(host.ctx, auth_r1a, "Auth Status",
        .{ .variant = .secondary, .disabled = model.controlsDisabled() }))
        emitAction(&action, .auth_status);
    if (host.draw_button(host.ctx, auth_r1b, "Rotate User",
        .{ .variant = .secondary, .disabled = model.controlsDisabled() }))
        emitAction(&action, .rotate_auth_user);
    if (host.draw_button(host.ctx, auth_r1c, "Rotate Admin",
        .{ .variant = .primary, .disabled = model.controlsDisabled() }))
        emitAction(&action, .rotate_auth_admin);
    y += button_height + layout.row_gap * 0.6;

    const auth_r2a = Rect.fromXYWH(x, y, btn_w, button_height);
    const auth_r2b = Rect.fromXYWH(auth_r2a.max[0] + pad, y, btn_w, button_height);
    const auth_r2c = Rect.fromXYWH(auth_r2b.max[0] + pad, y, btn_w, button_height);
    const auth_r2d = Rect.fromXYWH(auth_r2c.max[0] + pad, y, btn_w, button_height);
    if (host.draw_button(host.ctx, auth_r2a, "Reveal Admin",
        .{ .variant = .secondary, .disabled = model.controlsDisabled() }))
        emitAction(&action, .reveal_auth_admin);
    if (host.draw_button(host.ctx, auth_r2b, "Copy Admin",
        .{ .variant = .secondary, .disabled = model.controlsDisabled() }))
        emitAction(&action, .copy_auth_admin);
    if (host.draw_button(host.ctx, auth_r2c, "Reveal User",
        .{ .variant = .secondary, .disabled = model.controlsDisabled() }))
        emitAction(&action, .reveal_auth_user);
    if (host.draw_button(host.ctx, auth_r2d, "Copy User",
        .{ .variant = .secondary, .disabled = model.controlsDisabled() }))
        emitAction(&action, .copy_auth_user);
    y += button_height + layout.section_gap;

    // ── Local Node ───────────────────────────────────────────
    if (model.has_local_node) {
        host.draw_form_section_title(host.ctx, x, &y, input_width, layout, "Local Node");
        if (view.local_node_id) |nid| {
            host.draw_label(host.ctx, x, y, nid, colors.text_secondary);
            y += layout.line_height;
        }
        if (view.local_node_name) |nname| {
            host.draw_label(host.ctx, x, y, nname, colors.text_secondary);
            y += layout.line_height;
        }
        if (view.local_node_ttl_text) |ttl| {
            host.draw_label(host.ctx, x, y, ttl,
                if (view.local_node_bootstrapped) colors.text_secondary else colors.warning_text);
            y += layout.line_height + layout.row_gap * 0.4;
        }
        const rb_r = Rect.fromXYWH(x, y, btn_w * 1.3, button_height);
        if (host.draw_button(host.ctx, rb_r, "Re-bootstrap Local Node",
            .{ .variant = .secondary, .disabled = model.controlsDisabled() }))
            emitAction(&action, .rebootstrap_local_node);
        y += button_height + layout.section_gap;
    }

    // ── Status bar ───────────────────────────────────────────
    const status_h = @max(layout.line_height + layout.inner_inset * 2.2, 32.0 * ui_scale);
    const status_rect = Rect.fromXYWH(x, y, input_width, status_h);
    host.draw_status_row(host.ctx, status_rect);
    y += status_h + layout.row_gap;

    if (view.counts_line) |line| {
        host.draw_label(host.ctx, x, y, line, colors.text_secondary);
        y += layout.line_height;
    }
    if (view.template_line) |line| {
        host.draw_label(host.ctx, x, y, line, colors.text_secondary);
        y += layout.line_height;
    }
    if (view.binds_line) |line| {
        host.draw_text_trimmed(host.ctx, x, y, input_width, line, colors.text_secondary);
        y += layout.line_height;
    }
    y += layout.row_gap * 0.5;
    host.draw_text_trimmed(host.ctx, x, y, input_width, view.help_line, colors.text_secondary);
    y += layout.line_height + layout.row_gap;

    // Focus-clearing: click outside any text input clears keyboard focus.
    if (pointer.mouse_released and state.focused_field != .none and
        !workspace_token_rect.contains(.{ pointer.mouse_x, pointer.mouse_y }) and
        !mount_path_rect.contains(.{ pointer.mouse_x, pointer.mouse_y }) and
        !mount_node_rect.contains(.{ pointer.mouse_x, pointer.mouse_y }) and
        !mount_export_rect.contains(.{ pointer.mouse_x, pointer.mouse_y }) and
        !bind_path_rect.contains(.{ pointer.mouse_x, pointer.mouse_y }) and
        !bind_target_rect.contains(.{ pointer.mouse_x, pointer.mouse_y }))
    {
        state.focused_field = .none;
    }

    // Scrollbar.
    const content_bottom_scrolled = y;
    const content_bottom = content_bottom_scrolled + state.scroll_y;
    const total_height = content_bottom - (rect.min[1] + pad);
    const viewport_h = @max(0.0, rect.max[1] - rect.min[1] - pad * 2.0);
    const scroll_view_rect = Rect.fromXYWH(rect.min[0], rect.min[1] + pad, rect_width, viewport_h);
    host.draw_vertical_scrollbar(host.ctx, scroll_view_rect, total_height, &state.scroll_y);

    return action;
}

fn emitAction(slot: *?interfaces.WorkspacePanelAction, next: interfaces.WorkspacePanelAction) void {
    if (slot.* == null) slot.* = next;
}
