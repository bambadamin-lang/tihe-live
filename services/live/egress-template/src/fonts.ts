/**
 * Registers Peyda from ./fonts if the files have been added (see public/fonts/README.md).
 * Missing files are fine: the stack falls back to a system Persian font.
 */
const FACES = [
  ['Peyda-Regular.ttf', '400'],
  ['Peyda-Medium.ttf', '500'],
  ['Peyda-SemiBold.ttf', '600'],
  ['Peyda-Bold.ttf', '700'],
  ['Peyda-ExtraBold.ttf', '800'],
] as const;

export async function loadFonts(): Promise<void> {
  await Promise.all(
    FACES.map(async ([file, weight]) => {
      try {
        const face = new FontFace('Peyda', `url(${new URL(`fonts/${file}`, document.baseURI)})`, {
          weight,
        });
        document.fonts.add(await face.load());
      } catch {
        // not provided yet
      }
    }),
  );
}
