# Le Cyanotype

**La chambre noire dans une pixel shader.** A native iOS app that turns any photograph
into a faithful 19th-century photographic tirage — cyanotype, ferrotype (tintype),
daguerréotype, Van Dyke brown, or albumen/salt print — by *physically modelling* each
process's chemistry rather than slapping on a filter.

## The surprising use of Core Image

The heart of the app is a single stitchable Metal `CIColorKernel` (`AltProcess.ci.metal`)
that acts as a **darkroom simulator**. For each process it reproduces the real behaviour of
the sensitized paper or plate:

- **Actinic / spectral response** — cyanotype and salt prints see mostly UV/blue, so reds go
  dark and skies blow out; collodion (tintype) is blue-sensitive. The kernel weights the
  channels toward each process's real spectral sensitivity before collapsing to a density.
- **Characteristic (H&D) curve** — a toe (base fog), a straight-line gamma slope, and a
  highlight shoulder, tuned per process. The tintype is hard and contrasty with creamy
  highlights; the daguerreotype is delicate and low-contrast.
- **Toning** — a shadow/mid/highlight split-tone painted in the pigment or metal the
  chemistry actually deposits: Prussian blue, cold silver, mirror-silver, Van Dyke brown,
  gold-toned sepia.
- **Metal sheen** — a cool specular glint added only in the near-white highlights of the
  plate processes.
- **Silver / chemical grain** — weighted toward the midtones, where it really shows.

Around the kernel, a Core Image graph layers the imperfections that betray a real print:
procedurally-generated **paper tooth** (deckle) or **plate lacquer**, **coffee-stain
speckle** or **plate scratches**, a **hand-coated brush edge** (you can't hand-coat a
lacquered plate, so it's disabled there), optical softness, and edge falloff.

## Features

- **Pick a photo** (`PHPickerViewController`) or use the **bundled sample scene** — pick →
  process → export works fully in the Simulator, no camera needed.
- **Les bains** — a chemical-tray selector; tap a tray to dip the photo in that process,
  which snaps to that chemistry's honest defaults.
- **Live controls** — exposure, contrast, virage (toning), grain, paper/plate texture,
  vignettage, and the hand-coated brush edge. Debounced live preview.
- **Planche-contact** — the photo run through all five processes side by side to compare.
- **Recettes** — save a look (process + settings) with SwiftData; applies with one tap.
- **Export** full-resolution to Photos.

## Design identity

A wet-darkroom, 19th-century atelier: chemical-tray blacks and Prussian blues, warm
letterpress cream type (serif display + tracked uppercase captions), sepia and cyan
swatches, enamel trays with liquid meniscus highlights. The app icon is an Anna-Atkins-style
fern-frond cyanotype photogram.

## Build

```
cd ~/Claude/apps/le-cyanotype
xcodegen generate
xcodebuild -project LeCyanotype.xcodeproj -scheme LeCyanotype -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO
xcodebuild -project LeCyanotype.xcodeproj -scheme LeCyanotype -destination 'generic/platform=iOS' build CODE_SIGNING_ALLOWED=NO
```

- Module/scheme **LeCyanotype**, bundle `com.jac.LeCyanotype`, team 9WZ66DZ69J, Automatic signing.
- `IPHONEOS_DEPLOYMENT_TARGET` 26.0, device family 1,2 (iPhone + iPad).
- The `.ci.metal` kernel compiles into the app's `default.metallib`; the engine loads it by
  function name and degrades gracefully to a pure Core Image graph if it can't.

© 2026 Jacques Gautreau
