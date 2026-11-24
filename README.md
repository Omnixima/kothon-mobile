# কথন (Kothon) for iPhone and Android

> **Beta.** Early prototype. Expect rough edges.

## Download

**iPhone and iPad:** on the App Store.

<a href="https://apps.apple.com/app/id6837325285"><img src="docs/images/app-store-badge.svg" alt="Download on the App Store" height="50"></a>

**Android:** coming soon to Google Play.

Speak Bengali in any app and Kothon types it, fully on your phone. No audio
or text ever leaves the device. This is the mobile sibling of the
[Kothon desktop app](https://github.com/Omnixima/kothon).

## How it fits together

```
core/      kothon-core: the Rust engine shared by iPhone and Android
           (transcribe-cpp + punctuation + numbers + English words,
            the same pipeline as the desktop app), behind a small C API
ios/       SwiftUI app + custom keyboard extension (XcodeGen project)
android/   Kotlin keyboard (IME), coming after the iPhone prototype
scripts/   build scripts
```

Models download once from Hugging Face, the same ones the desktop app uses:

| Model | Size | Use |
|---|---|---|
| [দ্রুত, FastConformer CTC 116M](https://huggingface.co/omnixima/bangla-fastconformer-ctc-116m-gguf) | 132 MB | Default |
| [নিখুঁত, Whisper Medium](https://huggingface.co/omnixima/bengaliai-whisper-medium-gguf) | 793 MB | Newer phones |
| [Punctuation, MuRIL 6-layer](https://huggingface.co/omnixima/bangla-punctuation-muril6) | 128 MB | Optional |

### iPhone: why the keyboard opens the app

iOS doesn't let keyboards use the microphone. So the mic key asks the Kothon
app to record:

1. With no session running, the keyboard opens Kothon, which turns the mic on
   and starts recording. Swipe back to your app (the "◀" link, top left).
2. Kothon keeps listening in the background (the orange dot) for 5 minutes
   after the last dictation, so after that first time the mic key works
   right inside the keyboard.
3. Tap stop: Kothon transcribes on the phone and the keyboard types the text.

The app and keyboard share an App Group (`group.com.kothon.dictation`) and
signal each other with Darwin notifications. The keyboard loads no model,
which keeps it well under iOS's keyboard memory limit. "Allow Full Access"
is needed for the App Group; the keyboard makes no network requests.

## Build for iPhone

Needs a Mac with Xcode 16+, [Rust](https://rustup.rs), and Homebrew.

```bash
brew install cmake xcodegen
./scripts/build-ios.sh
open ios/Kothon.xcodeproj
```

Pick your iPhone and press Run. Then in the app: download the দ্রুত model,
and add the keyboard in Settings → General → Keyboard → Keyboards → Add New
Keyboard → কথন, with Allow Full Access on.

## Core tests

```bash
cd core && cargo test --release
```

## License

MIT. See [LICENSE](LICENSE). Kothon is built on
[Handy](https://github.com/cjpais/Handy) by CJ Pais.
