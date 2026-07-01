# Le Cyanotype

**La chambre noire dans une pixel shader.** A native iOS app that turns any photograph
into a faithful 19th-century photographic tirage — cyanotype, ferrotype (tintype),
daguerréotype, Van Dyke brown, or albumen/salt print — by *physically modelling* each
process's chemistry rather than slapping on a filter.

## The surprising use of Core Image

The heart of the app is a single stitchable Metal `CIColorKernel` (`AltProcess.ci.metal`)
that acts as a **darkroom simulator**. For each process it reproduces the real behaviour of
the sensitized paper or plate:

- **Actinic / spectral response** — none of these emulsions were panchromatic. Each carries
  its *own* per-channel sensitivity (R, G, B weights that sum to ≈1, so neutrals are
  preserved and only coloured light is redistributed): the cyanotype is nearly blind to red,
  collodion (tintype) is blue-sensitive, the daguerreotype has the broadest response of the
  five. Warm subjects render dark and blue skies blow out — most extremely on the cyanotype.
- **Characteristic (H&D) curve** — a straight-line gamma slope, a highlight shoulder, and a
  base-fog / veiling floor (nothing on an aged print reaches true paper-black), tuned per
  process. The tintype is hard and contrasty with creamy highlights; the daguerreotype is
  delicate and low-contrast.
- **Toning** — a shadow/mid/highlight split-tone painted in the pigment or metal the
  chemistry actually deposits: Prussian blue, cold silver, mirror-silver, Van Dyke brown,
  gold-toned sepia.
- **Metal sheen** — a cool specular glint added only in the near-white highlights of the
  plate processes.
- **Bronzing** — the signature cyanotype tell: its deepest, over-exposed Prussian-blue
  shadows solarise to a warm metallic bronze with a faint sheen. Unique to the cyanotype.
- **Silver grain** — weighted toward the midtones, and scaled by how much silver the process
  actually deposits: collodion plates grain hard, POP papers less, and the grainless
  Prussian-blue cyanotype barely at all.

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
