# Leaf Reader

Leaf Reader is a lightweight macOS PDF reader with page navigation, zoom controls, reading progress restore, and an integrated AI reading assistant.

## What's Included

- `Leaf Reader.app` - the built macOS app bundle.
- `mac-app/main.swift` - the native macOS source code.
- `mac-app/AppIcon.icns` and `mac-app/AppIconSource.png` - app icon assets.

The app bundle already contains the HTML, CSS, JavaScript, and PDF.js resources it needs at runtime.

## Run

Open the app bundle:

```sh
open "Leaf Reader.app"
```

## Build From Source

Compile the Swift app into the existing app bundle:

```sh
swiftc mac-app/main.swift \
  -o "Leaf Reader.app/Contents/MacOS/Leaf Reader" \
  -framework Cocoa \
  -framework PDFKit \
  -framework CryptoKit
```

Then sign it locally:

```sh
codesign --force --deep --sign - "Leaf Reader.app"
```

## Notes

- Minimum macOS version: 12.0.
- Bundle identifier: `com.linlu.leafreader`.
- The local signature is ad-hoc and intended for local distribution/testing.
