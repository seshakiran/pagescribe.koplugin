# Feature showcase (Remotion)

This project creates seven 1920×1080 rendered feature previews and a 48.4-second, 30-fps H.264/AAC walkthrough using those pictures. It covers PageScribe 0.12 and Dictionary Audio 0.4.

These are **rendered UI previews, not tablet screenshots or recordings**. PageScribe toolbar geometry and labels are drawn from the actual `ink_bar.lua` through a lightweight SVG buffer adapter. Font rasterization approximates KOReader. Dictionary Audio dialog labels, toggle states and speed choices are read from its actual Lua module. Book text, handwriting and dictionary presentation are illustrative original material. Color examples do not imply a monochrome device can display color.

## Reproduce the video

From this folder:

```sh
npm ci
npm run typecheck
npm run render
```

Output: `out/pagescribe-dictionary-audio-walkthrough.mp4`. Screenshots are regenerated into `public/screenshots/`. The render first creates distinct stills, then bundles those pictures into the video with frame-driven fades and camera movement.

The script uses a local Google Chrome installation on macOS when available. Set `REMOTION_BROWSER_EXECUTABLE` to choose a browser, or let Remotion obtain its supported headless browser on other systems. `STILLS_ONLY=1 npm run render` renders just the screenshots. `npm run studio` opens the composition editor.

## Update the UI snapshots

The committed UI snapshots make the project renderable without the second repository or any audio pack. To regenerate the PageScribe toolbars from the checked-out plugin source:

```sh
node scripts/generate-assets.mjs
```

To also refresh the Dictionary Audio dialog labels from a sibling checkout:

```sh
AUDIO_REPO=/path/to/dictionary-audio.koplugin node scripts/generate-assets.mjs
```

This uses Lua and runs PageScribe’s regression harness before drawing the toolbar. Font files come from the pinned Fontsource packages; their SIL Open Font Licenses are included in `public/fonts/`.

## Audio

A single **synthetic** Spanish word demonstrates the existing slower-playback setting. The sound bed is original synthesized audio. See `public/audio/SOURCE.md`. Regenerating that sample requires an existing neural pack:

```sh
python3 scripts/prepare-audio.py /path/to/spanish-neural-audio
ffmpeg -i public/audio/libro.flac -af atempo=0.85 public/audio/libro-slower.wav
```

The checked-in WAVs are sufficient to render; no models or large packs are needed. The source script generates the original sound bed deterministically. The video makes no claim about real-device latency, palm-rejection performance, or exact e-ink refresh appearance.

## Publication

Still images and the lightweight animated preview are displayed in both projects’ READMEs. The full MP4 and WebVTT captions are attached to their existing plugin releases, keeping large video binaries out of the source tree. The plugin installation ZIPs do not include this media project or its dependencies.
