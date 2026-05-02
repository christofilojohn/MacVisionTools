# Mac Vision Tools App Icons

The active app icon is the `primary` version exported into:

`src/Assets.xcassets/AppIcon.appiconset`

The alternate candidate icons in this folder are deterministic vector renders from:

`tools/generate_app_icons.swift`

The restored source artwork is kept as `source-old-icon.png` so the AppIcon asset catalog only contains assigned icon slots.

## Variants

- `original`: the restored source artwork, square-cropped for macOS.
- `primary`: the active app icon, using the restored artwork with light polish.
- `soft`: lower contrast and saturation.
- `vibrant`: higher contrast and saturation.
- `muted`: quieter color treatment.

Run this from the repository root to regenerate the complete macOS icon set and all preview variants:

```sh
swift tools/generate_app_icons.swift
```
