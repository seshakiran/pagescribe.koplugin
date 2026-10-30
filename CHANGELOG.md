## 0.12.0 — standalone PageScribe repository

- Publish handwriting as an independent repository and release package.
- Make the launcher circular and slightly larger, with page-preserving masked painting and initialized corner pixels.
- Keep native pen writing, native finger text selection, inline modes/colors, draggable controls and notebook exports.
- Remove dictionary/audio plugin sources and generation tools from the current distribution; audio remains an optional separate install.
- Show the tray Audio shortcut only when the optional Dictionary audio plugin is loaded.
- Preserve upstream Git history, AGPL-3.0 attribution, the existing install folder, settings and saved notes.
- Point the built-in updater to the standalone repository.

## 0.11.0 — native finger highlights and close control

- Add a small × in the tray's top-right corner to close all inline options while keeping the launcher.
- Default to Pen writes · Finger selects; retain native finger holds and drags for KOReader text highlights, notes and dictionary.
- Keep Pen only for palm rejection and make Finger draws an explicit separate option, with saved input preference.
- Block contacts that began during a pen stroke until they lift.
- Rename the freehand Highlight tool to Marker without changing saved annotations.

## 0.10.0 — pen and highlighter colors

- Add eight inline color chips with names and selected checkmarks for both tools.
- Persist independent Pen and Highlight colors and store color per stroke.
- Preserve RGB through live drawing, stroke replay, HTML notebooks and PDF annotations.
- Group PDF annotations by width, tool and color; preserve older ink unchanged.
- Keep ink legible on monochrome screens and use partial refresh on color screens.

## 0.9.2 — reachable launcher position

- Start the handwriting launcher halfway down the right edge, clear of KOReader's progress bar.
- Move the previous bottom-edge default to the middle on upgrade while preserving other saved placements and the preferred toolbar side.

## 0.9.1 — icon launcher and moved-tray input fix

- Replace launch text with a font-independent pen-and-handwriting icon.
- Finish quick drags on KOReader swipe/multiswipe releases, using end_pos rather than the swipe start point.
- Recover from interrupted drags on a new contact or tap, so controls cannot stay latched in dragging mode.
- Share integral screen rectangles between rendering and button hit testing.

## 0.9.0 — small launcher, larger inline tray

- Keep the launch tab small while expanding the inline tray at the screen's normal scale, with larger labels and tap targets.
- Add 2, 4, 7, 9, 10 and 12 px pen widths in the inline row and reader menu.
- Preserve dragging, independent highlighter widths, audio controls and existing notes.

## 0.8.0 — compact draggable tray

- Shrink the closed tray to 48×30 logical pixels and the open strip to 380×40, with a 38-pixel inline row only while writing. Cap UI scale to keep it compact on high-DPI readers.
- Drag either the tab or expanded tray directly, without holding first; follow each movement, restore the page and persist the final position.
- Put pen width, independent highlighter widths and pen/finger choices inline instead of in a settings dialog.
- Add a direct Audio tray action while preserving Dictionary audio as its own main-menu item.
- Preserve existing settings, notes, color palette and native pen handling.

## 0.7.1

- Refresh Undo availability after handwriting changes or page navigation without adding refreshes for ordinary pen samples.

## 0.7.0 — direct toolbar

- Replace the wheel and SELECT step with Read, Pen, Highlight, and Erase buttons that apply on one tap.
- Show the active tool with a filled button, checkmark, explicit status, actual width and input mode.
- Keep writing available with the toolbar open. Collapse into a labeled status tab that always reopens.
- Separate Undo, Notes, and Settings; disable Undo when the page has no handwriting.
- Add direct settings for pen width and pen-only input, with a link to Dictionary audio.
- Add a dictionary audio dialog with independent English/Spanish switches and visible Spanish speed selection.

## 0.6.0 — PageScribe

- Rename the visible product to PageScribe while preserving install folder, settings, notes, gesture IDs and update URLs.
- Add an iPod-style NOW USING display with applied tool, ink on/off, width and input mode.
- Separate pending choices, ACTIVE NOW / NOT ACTIVE badges, descriptions, exact SELECT actions and named previous/next options.
- Add an automatic color-screen palette with RGB-preserving text and shapes; retain explicit high-contrast monochrome states.
- Verify native pen writing, highlighting, palm blocking and pen control gestures alongside touch.
- Keep unavailable undo actions explicit and preserve the persistent launcher.

## 0.5.0 — classic click wheel and clear Spanish speech

- Replace orbiting tool bubbles with a classic click-wheel panel: rotate/arrow to browse, center SELECT to commit.
- Separate the active tool header from the browsed choice; use explicit ON/OFF status in the persistent launcher.
- Render into a bounded cached buffer using integer coordinates, antialiased ring edges and measured text boxes.
- Restore old/new panel bounds and perform a clean refresh on close.
- Replace legacy Spanish clips with full-quality Piper neural voice data in a separate local pack.
- Add independent English/Spanish pronunciation toggles and Normal/Slower/Very slow Spanish playback speeds with pitch preservation.
- Validate bounds at multiple DPI scales and test persistence, visibility and native speed parameters.

## 0.4.0 — faster writing and permanent radial controls

- Replace the removable toolbar with a permanent state hub and tap-to-open radial wheel.
- Show the active tool, select pen/marker/eraser directly, and offer Read, Undo, Note and width controls.
- Merge brush runs and batch display posts at 30 Hz, with a final pen-up flush and cancellation on redraw.
- Add optional offline English and Spanish dictionary audio plugin and a local recording packer.
- Cover wheel input, hidden-control recovery, refresh coalescing, and audio lifecycle with tests.
- Device latency and physical speaker output need live verification.

## 0.3.0 — Viwoods notebook fork

- Capture native KOReader stylus callbacks, restore prior handlers, and use touch rotation.
- Optional stylus-only drawing blocks finger/palm drawing and page turns outside the toolbar.
- Cycle pen, readable dotted freehand marker, and eraser; export marker ink with PDF opacity.
- Browse annotated pages, navigate to them, and attach or edit typed page notes.
- Export an offline HTML notebook with embedded SVG handwriting and escaped typed notes.
- Fix erasing long segments with sparse samples; discard strokes crossing a page change.
- Track edits in document settings and point the updater to this fork.
- Device input behavior still requires live validation on Viwoods; existing plugin data stays separate.

# Changelog

## 0.2.1 - 2026-08-31

- Add reliable AppStore and Storefront update detection through matching
  plugin metadata and stable GitHub releases.
- Add CI-verified release packaging with an installable
  `fingerink.koplugin.zip` asset.
- Document that no KOReader gesture configuration is required.
- Keep documentation and development files outside the installable plugin
  directory and release archive.

## 0.2 - 2026-08-30

- Add a compact icon toolbar with a remembered movable position.
- Prevent the toolbar from swallowing input intended for KOReader.
- Export supported strokes as native PDF ink annotations.
