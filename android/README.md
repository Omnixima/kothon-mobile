# Kothon for Android (planned)

A keyboard (InputMethodService) in Kotlin. Unlike iOS, Android keyboards
can record directly, so no hand-off to the app is needed. It will load
`libkothon_core.so` (built from `core/` with cargo-ndk for arm64-v8a)
through a small JNI bridge.
