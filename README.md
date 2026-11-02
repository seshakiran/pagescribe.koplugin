# PageScribe for KOReader

Write on your books with a pen while keeping KOReader’s native finger text selection. PageScribe is a standalone KOReader plugin: handwriting requires no dictionary, audio pack, account or companion plugin.

## Feature video

https://github.com/user-attachments/assets/561f65a5-9c4f-4087-a0ba-2a357c53295f

## Install

**Yes: the release ZIP contains `fingerink.koplugin`, and that is the folder to copy.** There is no separate `pagescribe.koplugin` folder. **PageScribe** is the name you will see inside KOReader; `fingerink.koplugin` is the retained installation folder name.

Download the release asset named **pagescribe.koplugin.zip**, rather than GitHub’s automatically generated “Source code” ZIP. After extracting, the layout on your device should be:

```text
koreader/
└── plugins/
    └── fingerink.koplugin/
        ├── main.lua
        └── _meta.lua
```

Copy the whole `fingerink.koplugin` folder, not just its files. Do not copy the ZIP itself into `plugins`, nest the folder twice, or rename it to `pagescribe.koplugin`. The spelling is **fingerink**, without an extra “l”.


1. Download **pagescribe.koplugin.zip** from the [latest release](https://github.com/seshakiran/pagescribe.koplugin/releases/latest).
2. Extract it and copy the included **fingerink.koplugin** folder into KOReader’s **plugins** directory.
3. Fully close and reopen KOReader, enable **PageScribe** in the plugin manager if needed, and open a book.
4. Tap the round handwriting icon midway down the right edge.

The final path is `koreader/plugins/fingerink.koplugin/main.lua`. The legacy folder name is intentional: it preserves settings, notes, gesture assignments and upgrades. **Replace the existing folder; do not install a second copy or rename it.** The built-in updater now follows this repository.

KOReader 2026.03 or newer supports finger drawing. Native pen input requires a KOReader build and device with the stylus callback API. PDF ink export requires KOReader 2026.07 or newer. Development has used a Viwoods AiPaper Mini with KOReader v2026.07.2-206; behavior on other hardware still needs device testing. Disable competing handwriting capture plugins while using PageScribe.

## First use

1. Fully restart KOReader after copying the folder. If PageScribe is disabled, enable it in KOReader’s plugin manager and restart again.
2. **Open a book.** The handwriting launcher appears inside the reader, midway down the right edge; it does not appear on the library/home screen.
3. Tap the round handwriting icon, then choose **Pen**. On a compatible build, write with your pen while your finger long-presses text for normal KOReader selection.
4. Choose **Read** to return to reading. The **×** closes the toolbar; tap the launcher to reopen it. Drag the launcher or toolbar to move it away from text.

If the icon is absent inside a book, check that the file really is at `koreader/plugins/fingerink.koplugin/main.lua`, confirm PageScribe is enabled, and restart KOReader. If the icon appears but the pen does not draw, check the stylus compatibility requirements below and disable competing handwriting plugins. Finger drawing is available through **Finger draws** on supported builds.

## Tools and input

Tap **Read**, **Pen**, **Marker**, or **Erase** to activate the tool immediately. The filled button and checkmark show the active state. Width, input and color options stay inline with the page.

- **Pen writes · Finger selects** is the default: the pen draws, while finger long-press and drag use KOReader’s native text highlights, notes and dictionary.
- **Pen only** blocks finger contacts for palm rejection.
- **Finger draws** explicitly enables finger ink instead of native finger selection.
- **Marker** makes freehand page overlays; native text highlights remain KOReader text annotations.
- **Read** stops ink capture and restores normal reading gestures.

Pen widths: **2, 4, 7, 9, 10, 12 px**. Marker widths: **12, 24, 36 px**. Both tools have **Black, Blue, Red, Green, Purple, Orange, Pink and Yellow**, remembered independently. Each stroke keeps its own color. Monochrome screens show readable black ink; color screens and HTML/PDF exports retain the chosen colors.

The circular launcher is slightly larger for easier pen and finger taps. Drag the launcher or open tray anywhere on screen. A long press is optional; the final position is saved. The **×** at the top-right closes the tray and all its options, keeping the icon available to reopen it. **Undo** removes the last ink stroke on the current page.

## Notes and exports

**Notes** opens the page-note editor, navigation to pages containing notes, and HTML notebook export. The notebook combines handwriting and typed notes without copying book text. Ink is saved per page in KOReader’s sidecar settings.

**More tools → PageScribe** includes PDF ink export, refresh settings, notebook management and plugin updates. PDF export writes native annotations and removes successfully exported strokes from PageScribe’s editable overlay. Exported PDF strokes can then be edited using a PDF annotation editor.

Page overlays on reflowable books are tied to page layout. Keep font size, margins and orientation stable when working with existing ink.

## Optional dictionary audio

Dictionary pronunciation has its own standalone repository: [Dictionary Audio](https://github.com/seshakiran/dictionary-audio.koplugin), with its own [release ZIP](https://github.com/seshakiran/dictionary-audio.koplugin/releases/latest), updater and pack-building tools. PageScribe and Dictionary Audio can each be used independently. Existing installations keep the same **dictionary-audio.koplugin** folder, language preferences and downloaded packs.

To use everything together, install the PageScribe ZIP and Dictionary Audio ZIP into KOReader’s plugins directory, keep or install the audio packs described in the Dictionary Audio README, and restart KOReader. PageScribe’s **Audio** button opens Dictionary Audio settings; native dictionary lookups provide **Hear English** and **Hear Spanish**.

If that plugin is loaded, PageScribe shows an **Audio** shortcut. Otherwise, the tray omits Audio. No large dictionary, voice model or pronunciation pack is downloaded by this plugin.

## Development

Run `lua5.1 test.lua` for capture, native selection, tool state, moved-tray interaction, stroke rendering and export regression checks. Run `./scripts/package.sh` to produce `dist/pagescribe.koplugin.zip`. CI tests Lua 5.1 compatibility and validates the archive inventory before automatic releases.

`CHANGELOG.md` records feature changes. The inherited `spec.md`, `requirements.md` and `decisions.md` contain historical design notes from the original Finger Ink project.

## Troubleshooting

For an intermittent stray mark or overlay, note its appearance, active tool, input mode and book format, and whether a page turn or full refresh clears it. That distinguishes a saved stroke from a display-refresh artifact. Restart KOReader after plugin updates.

## License and attribution

AGPL-3.0, inherited from the original Finger Ink project. See [LICENSE](LICENSE) and the preserved commit history.
