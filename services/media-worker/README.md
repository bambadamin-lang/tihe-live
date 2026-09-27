# services/media-worker

Turns a source video into protected, playable content: transcode, encrypt, package, publish.

This is the other half of the protection design from `packages/secure-core` — the server side that
produces what the device decrypts. **Read [`docs/03-content-protection.md`](../../docs/03-content-protection.md)
before changing anything here**, particularly layers 2 and 3.

## Packaging a file

```bash
# transcode in this process, reading the file from disk — no worker or queue needed
pnpm --filter @tihe/media-worker package ./lecture.mp4 \
  --course crs_01J8ZQK5T9XVWR3M2N4P6H8B7C \
  --title "جلسه ۶ — انتگرال" \
  --inline

# or upload the source and let a worker pick it up
pnpm --filter @tihe/media-worker package ./lecture.mp4 --course crs_… --title "…"
pnpm --filter @tihe/media-worker start
```

Both need `ffmpeg` on `PATH` and object storage reachable. `--inline` is the one to use while
developing; the queue route uploads the source to the raw bucket first, because a worker on another
machine cannot read your local path.

## What it produces

```
s3://tihe-vod/{videoId}/
    master.m3u8                     multi-variant playlist, no EXT-X-KEY
    1080p/index.m3u8  seg-00000.ts  AES-128-CTR encrypted segments
    720p/  480p/  audio/
    poster.jpg
    sprite.jpg  sprite.vtt          thumbnail grid for scrubbing
```

plus one `video_assets` row per rendition, one `content_keys` row holding the CEK wrapped with the
KEK, and `videos.status = ready`.

## Three things that are easy to get wrong

**The content key row is created before any transcoding.** Its id is an input to the segment IV
derivation (`segmentIv(keyId, seq)` in `@tihe/crypto`). Create it afterwards and every segment gets
an IV no client can reproduce — video that decrypts to noise, with nothing in any log to say why.

**`videos.status` becomes `ready` only after the last upload lands.** A `ready` video whose segments
are still uploading is a student hitting a 404 mid-lecture.

**The work directory is removed in a `finally`.** It holds plaintext segments. Leaving them behind
after a failed job is precisely the leak that encrypting the output exists to prevent.

## The ladder

| label | height | quality | notes |
|---|---|---|---|
| `1080p` | 1080 | CRF 23, 4.5 Mbps cap | |
| `720p` | 720 | CRF 24, 1.8 Mbps cap | |
| `480p` | 480 | CRF 26, 0.9 Mbps cap | |
| `audio` | — | 64 kbps mono | for a connection that cannot carry video |

**Never upscales.** A 720p source yields 720p and 480p only; a source smaller than every rung is
encoded at its own height rather than stretched. Class recordings are often 720p or less, so this is
the common case.

Capped CRF rather than fixed bitrate, because lecture content is mostly static slides — CRF spends a
fraction of the bits for the same perceived quality, and the cap stops a busy screen-share exceeding
what a student's connection can carry.

Keyframes are forced every 6 seconds so segments are independently decodable. HLS requires it, and
the loopback server depends on it because it serves one segment at a time.

## Idempotency

Keyed on `videoId`. A job that finds complete assets *and* the objects present skips; one that finds
rows but missing objects redoes the work. BullMQ retries a crashed job, and a retry must not duplicate
output or mint a second content key — a new key id would orphan every segment already published.

## Testing

```bash
pnpm --filter @tihe/media-worker test
```

Needs `ffmpeg` and a database; the tests skip rather than fail without them. The suite runs real
transcodes against short synthetic clips, and the pipeline is verified against an in-memory storage
double so it does not need MinIO.

The S3 leg has its own test (`test/storage.integration.test.ts`) which skips when storage is
unreachable and runs in CI.

The sharpest test is cross-language and lives in Rust:
`packages/secure-core/tests/wire_compat.rs` decrypts a segment this packager encrypted and asserts the
MPEG-TS sync byte at every 188-byte boundary. If the Node and Rust ciphers or IV derivations ever
diverge, nothing throws on either side — the student just gets a black screen. Regenerate that
fixture only on a deliberate format change:

```bash
pnpm --filter @tihe/media-worker emit-fixtures
```
