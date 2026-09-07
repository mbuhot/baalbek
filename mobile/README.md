# mobile

**Language:** Capacitor

**Purpose:** Android (Gradle) + iOS (xcodebuild) as tier-0 system tasks.

A [Capacitor](https://capacitorjs.com) 8 project wrapping `web`'s built
PWA as native Android and iOS apps. `capacitor.config.ts` sets `webDir`
to `../web/dist`, so `cap sync` copies whatever `web` last built —
there is no second copy of the web assets in this project.

- **App ID:** `com.alembic.baalbek.dispatch`. **App name:** "Baalbek
  Dispatch", matching `web`'s PWA manifest.
- **Which API the packaged app calls.** A WebView's origin is the device, so
  `web`'s same-origin default cannot apply here — the app would fetch its own
  bundle. `scripts/stamp-api-config.sh` rewrites `api-config.js` in the synced
  native project after each `cap sync`, from `MOBILE_API_BASE_URL` (default:
  the host machine as an emulator sees it, `http://10.0.2.2:4004` on Android
  and `http://localhost:4004` on iOS). That value is not in the task hash, so
  changing it needs `moon run mobile:build-android --force`. `web` raises
  rather than guessing if the file is ever missed — see `web/README.md`,
  "Which API this app talks to".
- **`CapacitorHttp` is enabled** (`capacitor.config.ts`), which patches
  `fetch`/`XMLHttpRequest` to make native requests. Those never pass through
  the WebView's CORS enforcement, which is why no tier of this system carries
  CORS configuration. It is bundled in `@capacitor/core` 8.5.1 and off by
  default.
- `android/` and `ios/` are the Capacitor-generated native scaffolds
  (`pnpm exec cap add android` / `add ios`), committed per Capacitor
  convention so native-side customisation survives. Their build output
  (`android/app/build`, `ios/build`, …) is gitignored.

## Android

`moon run mobile:build-android` runs a real `./gradlew assembleDebug`,
producing an installable unsigned debug APK at
`android/app/build/outputs/apk/debug/app-debug.apk` from the actual `web`
PWA content. `moon run mobile:build` (PLAN.md's Stage 7 gate) reaches it
through an unconditional `deps` edge — Android has no accepted exception
and runs in every environment.

Versions below came from `pnpm exec cap add android` — they are Capacitor
8.5.1's own current defaults, not independently chosen here.

| Component | Version |
|---|---|
| Android Gradle Plugin | 8.13.0 |
| Gradle | 8.14.3 |
| compileSdk / targetSdk | 36 |
| minSdk | 24 |

**JDK: Eclipse Temurin 21**, proto-managed (`java` in root `.prototools`).
Capacitor 8's Android library compiles with `JavaVersion.VERSION_21`, so a
JDK ≥ 21 is required. `scripts/build-android.sh` exports `JAVA_HOME` from
proto's install directly, so an inherited `JAVA_HOME` cannot override the
pin (gradlew prefers `$JAVA_HOME/bin/java` over `PATH`).

### The Android SDK is not proto-managed

No first-party or asdf proto plugin covers the Android SDK. It is pinned
and installed directly instead — the same category as the apt packages
the Stage 0 `Dockerfile` installs for OTP/Rustler builds.
`scripts/setup-android-sdk.sh` is the setup script `mobile:build-android`
runs first; it is idempotent, and installs to `~/.android-sdk`, outside
the repo:

- Android cmdline-tools, pinned build `9862592`.
- `platforms;android-36` and `build-tools;36.0.0`, licenses accepted
  non-interactively.

On a Mac or an x86_64 Linux host that is all it does. On **aarch64 Linux**
(this sandbox) it additionally, gated on `uname -m`:

- Registers a `qemu-x86_64` binfmt handler and installs `qemu-user-binfmt`,
  because Google ships no `linux_aarch64` build of `aapt2` (AGP's resource
  compiler, bundled in build-tools) — only `linux` (x86_64), `osx`, and
  `windows`. The real x86_64 `aapt2` then runs under CPU emulation.
- Installs the `amd64` multiarch libraries that emulated `aapt2` links
  against (`libc6`, `libstdc++6`, `zlib1g`), adding an `amd64`-scoped apt
  source since this host's default `ports.ubuntu.com` carries `arm64` only.
- Imports the sandbox's TLS-intercepting proxy CA into proto's JDK
  truststore, without which Gradle's wrapper cannot fetch its own
  distribution. Skipped when that CA file is absent.

Those steps need `sudo`, which the sandbox grants.

`scripts/build-android.sh` also passes
`scripts/external-build-dir.init.gradle` as a Gradle `--init-script`,
relocating every subproject's `build/` directory to
`$HOME/.cache/baalbek-gradle-build`, so Gradle's intermediates stay out of
the working tree. The APK is copied back to its in-repo path so Moon caches
it as a declared output.

## iOS

`mobile:build-ios` runs `pnpm exec cap sync ios` and a real
`xcodebuild -project ios/App/App.xcodeproj -scheme App -configuration
Debug -sdk iphonesimulator … build` — the command a Mac developer would
run, not a stub. It carries `tags: ["requires-macos"]` and
`options.runInCI: false`: PLAN.md's one accepted exception to this
project's toolchain-purity rule ("iOS builds need macOS"). `xcodebuild`
exists only on macOS, so the task cannot run in this Linux sandbox or in
container CI.

Capacitor 8 uses Swift Package Manager (`ios/App/CapApp-SPM/`), not
CocoaPods, so `pnpm exec cap add ios` needed no Mac-only step and its
scaffold is committed here. Only `xcodebuild` itself is Mac-only.

Three independent mechanisms keep it out of this environment, none of
which weakens the real Mac build:

1. `scripts/build.sh` (`mobile:build`'s command) asks moon which tasks
   carry the tag — `moon query tasks --project mobile
   'taskTag=requires-macos'` — and runs each only on Darwin. Moon 2.5.4's
   negated forms (`taskTag!=`, `taskTag!~`) both return an empty set, so
   the positive query is inverted here instead.
2. `scripts/build-ios.sh` guards itself: off macOS, or with no
   `xcodebuild` on `PATH`, it logs a skip and exits 0 before doing any
   work. This is what keeps `moon check --all` green, since that command
   has no tag filtering and sweeps every build-shaped task id.
3. `runInCI: false`, for the Stage 12 `moon ci` gate.

The skip is always logged, never silent:

```
$ moon run mobile:build-ios
mobile:build-ios | skipped: requires-macos, not available in this environment (xcodebuild not found)
```

A Mac developer runs `moon run mobile:build-ios` and gets a genuine build.

## Local setup

```bash
# from repo root
moon run web:build            # produces web/dist, which cap sync consumes
cd mobile
pnpm install
pnpm exec cap sync android     # or: pnpm exec cap sync ios
```

Or via Moon from the repo root: `moon run mobile:build-android`,
`moon run mobile:build-ios`, or `moon run mobile:build` (the Stage 7
gate). Each depends on `web:build`.
