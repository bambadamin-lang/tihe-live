# Peyda

Put the Peyda font files here, as **TTF or OTF** (Flutter cannot load WOFF/WOFF2). Any file
whose name starts with `Peyda` is picked up at startup; the weight is read from the name:

| File name contains | Weight |
|---|---|
| `Thin` | 100 |
| `ExtraLight` | 200 |
| `Light` | 300 |
| `Regular` (or nothing) | 400 |
| `Medium` | 500 |
| `SemiBold` | 600 |
| `Bold` | 700 |
| `ExtraBold` | 800 |
| `Black` | 900 |

e.g. `Peyda-Regular.ttf`, `Peyda-Bold.ttf`. Until they are here the classroom uses the
platform's Persian font. Check that the font licence allows embedding in an app.

The recording template uses the same files: copy them to
`services/live/egress-template/public/fonts/` as well.
