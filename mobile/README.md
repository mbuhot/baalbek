# mobile

**Language:** Capacitor

**Purpose:** Android (Gradle) + iOS (xcodebuild) as tier-0 system tasks.

Capacitor wrapper over the `web` PWA. Moon decides *whether* to invoke each
build (affected-detection, ordering); Gradle's/Xcode's own caches handle
intra-build speed. iOS builds are macOS-only and excluded from container CI
(the one accepted exception to proto owning every toolchain). Skeleton only
(Stage 0) — no build manifests yet; those land in Stage 1 and Stage 7.
