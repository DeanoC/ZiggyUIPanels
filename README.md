# ZiggyUIPanels

Contract and boundary package for Ziggy panel-level UI extraction.

## What This Package Contains

- `AttachmentOpen`: shared attachment-open payload used by panel pipelines.
- `DrawResult`: shared per-panel render result surface.

This package is intentionally small in the first extraction phase. Runtime panel
implementation remains in `ziggy-ui` while contracts move here first.

## Build

- `zig build`
- `zig build test`

## License

MIT
