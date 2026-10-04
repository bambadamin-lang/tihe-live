/**
 * Registers the app's typefaces from ./fonts (see public/fonts/README.md), so a recording is set
 * in the same type the class was seen in: Peyda in the one TIHE app, Modam in the standalone
 * classroom. Each file registers its own family; styles.css puts Peyda first. A missing file is
 * fine: the stack falls back to a system Persian font.
 */
const FACES = [
  ['Peyda', 'Peyda-Regular.ttf', '400'],
  ['Peyda', 'Peyda-Medium.ttf', '500'],
  ['Peyda', 'Peyda-SemiBold.ttf', '600'],
  ['Peyda', 'Peyda-Bold.ttf', '700'],
  ['Peyda', 'Peyda-ExtraBold.ttf', '800'],
  ['Modam', 'Modam-Regular.ttf', '400'],
  ['Modam', 'Modam-Medium.ttf', '500'],
  ['Modam', 'Modam-Bold.ttf', '700'],
] as const;

export async function loadFonts(): Promise<void> {
  await Promise.all(
    FACES.map(async ([family, file, weight]) => {
      try {
        const face = new FontFace(family, `url(${new URL(`fonts/${file}`, document.baseURI)})`, {
          weight,
        });
        document.fonts.add(await face.load());
      } catch {
        // missing: the fallback fonts take over
      }
    }),
  );
}
