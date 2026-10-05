/**
 * Registers Modam, the classroom's typeface, from ./fonts (see public/fonts/README.md), so the
 * recording is set in the same type as the app. A missing file is fine: the stack falls back
 * to a system Persian font.
 */
const FACES = [
  ['Modam-Regular.ttf', '400'],
  ['Modam-Medium.ttf', '500'],
  ['Modam-Bold.ttf', '700'],
] as const;

export async function loadFonts(): Promise<void> {
  await Promise.all(
    FACES.map(async ([file, weight]) => {
      try {
        const face = new FontFace('Modam', `url(${new URL(`fonts/${file}`, document.baseURI)})`, {
          weight,
        });
        document.fonts.add(await face.load());
      } catch {
        // missing: the fallback fonts take over
      }
    }),
  );
}
