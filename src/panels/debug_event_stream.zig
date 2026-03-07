const zui = @import("ziggy-ui");

const widgets = zui.widgets;
const Rect = zui.core.Rect;
const form_layout = zui.ui.layout.form_layout;
const interfaces = zui.ui.panel_interfaces;
const zcolors = zui.theme.colors;

// Reusable debug event stream viewport. The host supplies rendering and
// selection callbacks while this module owns layout, scrolling, and hit tests.
pub const PointerState = struct {
    mouse_x: f32,
    mouse_y: f32,
    mouse_clicked: bool,
    mouse_down: bool,
};

pub const ThemeColors = struct {
    primary: [4]f32,
    border: [4]f32,
};

pub const Host = struct {
    ctx: *anyopaque,
    set_output_rect: *const fn (ctx: *anyopaque, rect: Rect) void,
    focus_panel: *const fn (ctx: *anyopaque) void,
    draw_surface_panel: *const fn (ctx: *anyopaque, rect: Rect) void,
    push_clip: *const fn (ctx: *anyopaque, rect: Rect) void,
    pop_clip: *const fn (ctx: *anyopaque) void,
    draw_filled_rect: *const fn (ctx: *anyopaque, rect: Rect, color: [4]f32) void,
    draw_button: *const fn (ctx: *anyopaque, rect: Rect, label: []const u8, opts: widgets.button.Options) bool,
    get_scroll_y: *const fn (ctx: *anyopaque) f32,
    set_scroll_y: *const fn (ctx: *anyopaque, value: f32) void,
    get_scrollbar_dragging: *const fn (ctx: *anyopaque) bool,
    set_scrollbar_dragging: *const fn (ctx: *anyopaque, value: bool) void,
    get_drag_start_y: *const fn (ctx: *anyopaque) f32,
    set_drag_start_y: *const fn (ctx: *anyopaque, value: f32) void,
    get_drag_start_scroll_y: *const fn (ctx: *anyopaque) f32,
    set_drag_start_scroll_y: *const fn (ctx: *anyopaque, value: f32) void,
    set_drag_capture: *const fn (ctx: *anyopaque, capture: bool) void,
    release_drag_capture: *const fn (ctx: *anyopaque) void,
    entry_height: *const fn (ctx: *anyopaque, filtered_index: usize, content_min_x: f32, content_max_x: f32, selected: bool) f32,
    draw_entry: *const fn (ctx: *anyopaque, filtered_index: usize, content_min_x: f32, y: f32, content_max_x: f32, output_rect: Rect, selected: bool, pointer: PointerState) bool,
    select_entry: *const fn (ctx: *anyopaque, filtered_index: usize) void,
    copy_selected_event: *const fn (ctx: *anyopaque) void,
    selected_event_count: *const fn (ctx: *anyopaque) usize,
};

pub fn draw(
    host: Host,
    output_rect: Rect,
    layout: form_layout.Metrics,
    ui_scale: f32,
    colors: ThemeColors,
    view: interfaces.DebugEventStreamView,
    pointer: PointerState,
) void {
    const inner = layout.inner_inset;
    const line_height = layout.line_height;
    const event_gap = @max(2.0 * ui_scale, inner * 0.35);
    const scrollbar_reserved = @max(14.0, 8.0 * ui_scale + inner);
    const filtered_indices = view.filtered_indices;

    host.set_output_rect(host.ctx, output_rect);
    if (pointer.mouse_clicked and output_rect.contains(.{ pointer.mouse_x, pointer.mouse_y })) {
        host.focus_panel(host.ctx);
    }
    host.draw_surface_panel(host.ctx, output_rect);

    const usable_height = @max(0.0, output_rect.height() - inner * 2.0);
    if (usable_height <= 0) return;

    var have_copy_rect = false;
    var copy_btn_rect: Rect = Rect.fromXYWH(0, 0, 0, 0);
    const selected_visible = blk: {
        const selected_idx = view.selected_index orelse break :blk false;
        var lo: usize = 0;
        var hi: usize = filtered_indices.len;
        while (lo < hi) {
            const mid = lo + (hi - lo) / 2;
            const value = @as(usize, @intCast(filtered_indices[mid]));
            if (value == selected_idx) break :blk true;
            if (value < selected_idx) lo = mid + 1 else hi = mid;
        }
        break :blk false;
    };
    if (selected_visible) {
        const copy_btn_w: f32 = @max(84.0 * ui_scale, layout.line_height * 4.1);
        const copy_btn_h: f32 = @max(layout.button_height * 0.74, 24.0 * ui_scale);
        copy_btn_rect = Rect.fromXYWH(
            output_rect.max[0] - copy_btn_w - inner * 0.5,
            output_rect.min[1] + inner * 0.5,
            copy_btn_w,
            copy_btn_h,
        );
        have_copy_rect = true;
    }

    const content_min_x = output_rect.min[0] + inner + 2.0;
    const content_max_x = output_rect.max[0] - scrollbar_reserved;

    var total_content_height: f32 = inner * 2.0;
    for (filtered_indices) |raw_idx| {
        const idx = @as(usize, @intCast(raw_idx));
        const is_selected = view.selected_index != null and view.selected_index.? == idx;
        total_content_height += host.entry_height(host.ctx, idx, content_min_x, content_max_x, is_selected) + event_gap;
    }
    const max_scroll = @max(0.0, total_content_height - output_rect.height());
    var scroll_y = host.get_scroll_y(host.ctx);
    if (scroll_y < 0.0) scroll_y = 0.0;
    if (scroll_y > max_scroll) scroll_y = max_scroll;
    host.set_scroll_y(host.ctx, scroll_y);

    const sb_width: f32 = 8.0 * ui_scale;
    const sb_track_rect = if (max_scroll > 0)
        Rect.fromXYWH(
            output_rect.max[0] - sb_width - inner * 0.35,
            output_rect.min[1] + inner * 0.35,
            sb_width,
            output_rect.height() - inner * 0.7,
        )
    else
        Rect.fromXYWH(0, 0, 0, 0);
    const clicked_scrollbar_track = pointer.mouse_clicked and max_scroll > 0 and sb_track_rect.contains(.{ pointer.mouse_x, pointer.mouse_y });

    host.push_clip(host.ctx, output_rect);
    defer host.pop_clip(host.ctx);

    var cur_y = output_rect.min[1] + inner - scroll_y;
    for (filtered_indices) |raw_idx| {
        const idx = @as(usize, @intCast(raw_idx));
        const is_selected = view.selected_index != null and view.selected_index.? == idx;
        const entry_h = host.entry_height(host.ctx, idx, content_min_x, content_max_x, is_selected) + event_gap;

        if (cur_y + entry_h < output_rect.min[1]) {
            cur_y += entry_h;
            continue;
        }
        if (cur_y > output_rect.max[1]) break;

        const entry_rect = Rect.fromXYWH(output_rect.min[0], cur_y, output_rect.width(), entry_h - event_gap);
        if (is_selected) {
            host.draw_filled_rect(host.ctx, entry_rect, zcolors.withAlpha(colors.primary, 0.25));
        }

        const clicked_fold_marker = host.draw_entry(
            host.ctx,
            idx,
            content_min_x,
            cur_y,
            content_max_x,
            output_rect,
            is_selected,
            pointer,
        );

        const clicked_entry = pointer.mouse_clicked and !clicked_scrollbar_track and entry_rect.contains(.{ pointer.mouse_x, pointer.mouse_y });
        const clicked_copy = have_copy_rect and copy_btn_rect.contains(.{ pointer.mouse_x, pointer.mouse_y });
        if (clicked_entry and !clicked_copy and !clicked_fold_marker) {
            if (view.selected_index == null or view.selected_index.? != idx) {
                host.select_entry(host.ctx, idx);
            }
        }

        cur_y += entry_h;
    }

    if (max_scroll > 0) {
        const thumb_height = @max(20.0, sb_track_rect.height() * (output_rect.height() / total_content_height));
        const thumb_y_ratio = scroll_y / max_scroll;
        const thumb_y = sb_track_rect.min[1] + thumb_y_ratio * (sb_track_rect.height() - thumb_height);
        const thumb_rect = Rect.fromXYWH(sb_track_rect.min[0], thumb_y, sb_width, thumb_height);

        host.draw_filled_rect(host.ctx, sb_track_rect, zcolors.withAlpha(colors.border, 0.3));

        const is_hovered = thumb_rect.contains(.{ pointer.mouse_x, pointer.mouse_y });
        const dragging = host.get_scrollbar_dragging(host.ctx);
        const thumb_color = if (dragging)
            colors.primary
        else if (is_hovered)
            zcolors.blend(colors.border, colors.primary, 0.5)
        else
            colors.border;
        host.draw_filled_rect(host.ctx, thumb_rect, thumb_color);

        if (pointer.mouse_clicked and is_hovered) {
            host.set_scrollbar_dragging(host.ctx, true);
            host.set_drag_start_y(host.ctx, pointer.mouse_y);
            host.set_drag_start_scroll_y(host.ctx, scroll_y);
            host.set_drag_capture(host.ctx, true);
        } else if (pointer.mouse_clicked and sb_track_rect.contains(.{ pointer.mouse_x, pointer.mouse_y })) {
            const page_scroll = @max(line_height * 3.0, output_rect.height() * 0.9);
            if (pointer.mouse_y < thumb_rect.min[1]) {
                scroll_y -= page_scroll;
            } else if (pointer.mouse_y > thumb_rect.max[1]) {
                scroll_y += page_scroll;
            }
            if (scroll_y < 0.0) scroll_y = 0.0;
            if (scroll_y > max_scroll) scroll_y = max_scroll;
            host.set_scroll_y(host.ctx, scroll_y);
        }

        if (host.get_scrollbar_dragging(host.ctx)) {
            if (pointer.mouse_down) {
                const delta_y = pointer.mouse_y - host.get_drag_start_y(host.ctx);
                const scroll_per_pixel = max_scroll / (sb_track_rect.height() - thumb_height);
                scroll_y = host.get_drag_start_scroll_y(host.ctx) + delta_y * scroll_per_pixel;
                host.set_scroll_y(host.ctx, scroll_y);
            } else {
                host.set_scrollbar_dragging(host.ctx, false);
                host.release_drag_capture(host.ctx);
            }
        }
    } else {
        host.set_scrollbar_dragging(host.ctx, false);
        host.release_drag_capture(host.ctx);
    }

    if (have_copy_rect and view.selected_index != null and host.selected_event_count(host.ctx) > 0) {
        if (host.draw_button(host.ctx, copy_btn_rect, "Copy", .{ .variant = .secondary })) {
            host.copy_selected_event(host.ctx);
        }
    }
}
