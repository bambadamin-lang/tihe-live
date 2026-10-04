# Modam

The classroom's typeface: **Modam** (مُدام) by Naser Khadem, from FontIran — the eight weights of
its standard cut, `Modam-ExtraLight.ttf` to `Modam-Black.ttf`. `ClassroomFonts` registers every
`Modam-*.ttf` here as the family `Modam` at runtime; the engine reads each file's weight
(200–900) from the file itself.

- **Standard cut, not FaNum or NoEn.** The standard cut keeps Latin digits and letters, which
  server addresses, session ids and board formulas need. The UI turns its own numbers into
  Persian digits.
- **Missing characters.** Modam has no "…", "·" (the watermark's separator), "²" or emoji; the
  theme's fallback fonts and the platform supply them.
- **TTF only.** Flutter cannot load WOFF/WOFF2.
- **Recordings.** `services/live/egress-template/public/fonts/` holds the regular, medium and bold
  files too, so recordings are set in the same type.
- **Licence.** Modam is commercial software ("To use this font, it is necessary to obtain the
  license from www.fontiran.com"). The institute's licence must cover embedding it in the app
  and its installer. Keep these files out of any public copy of the repository.
