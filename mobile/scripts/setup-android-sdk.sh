#!/usr/bin/env bash
# Idempotent Android SDK bootstrap for `mobile:build-android`. Installs the
# OS-level SDK components Gradle needs, which no proto plugin covers, so they
# sit in the same category as the apt packages the root Dockerfile installs.
# Safe to re-run: every step checks for its own prior effect first.
set -euo pipefail

ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-$HOME/.android-sdk}"
CMDLINE_TOOLS_BUILD="9862592" # pinned: Android cmdline-tools, checked 2026-09-06
PLATFORM="android-36"
BUILD_TOOLS="36.0.0"

# Runs a command with its output held back, and prints all of it when the
# command fails. Nothing here may discard output outright: a step that exits
# non-zero and says nothing is worse than one that is merely noisy.
run_logged() {
  local log
  log="$(mktemp)"
  if ! "$@" > "$log" 2>&1; then
    echo "error: failed: $*" >&2
    cat "$log" >&2
    rm -f "$log"
    return 1
  fi
  rm -f "$log"
}

echo "==> Android SDK root: $ANDROID_SDK_ROOT"

if [ ! -x "$ANDROID_SDK_ROOT/cmdline-tools/latest/bin/sdkmanager" ]; then
  echo "==> Downloading Android cmdline-tools (build $CMDLINE_TOOLS_BUILD)"
  tmp_zip="$(mktemp -d)/cmdline-tools.zip"
  # `-f` so an HTTP error is an error: without it curl writes the error page
  # into the file and exits 0, and the failure surfaces later as a corrupt zip.
  curl -fsSL --retry 3 --retry-delay 2 -o "$tmp_zip" \
    "https://dl.google.com/android/repository/commandlinetools-linux-${CMDLINE_TOOLS_BUILD}_latest.zip"
  tmp_extract="$(mktemp -d)"
  unzip -q "$tmp_zip" -d "$tmp_extract"
  mkdir -p "$ANDROID_SDK_ROOT/cmdline-tools/latest"
  mv "$tmp_extract/cmdline-tools/"* "$ANDROID_SDK_ROOT/cmdline-tools/latest/"
  rm -rf "$tmp_zip" "$tmp_extract"
fi

SDKMANAGER="$ANDROID_SDK_ROOT/cmdline-tools/latest/bin/sdkmanager"

if [ ! -d "$ANDROID_SDK_ROOT/licenses" ]; then
  echo "==> Accepting Android SDK licenses"
  # A here-string, not `yes |`: sdkmanager closes stdin once it has every
  # answer, so `yes` dies of SIGPIPE (141) and `pipefail` reports that as a
  # failed step even though sdkmanager succeeded. 100 answers covers the 7
  # licenses asked about today; `timeout` turns a longer list into an error
  # rather than a wait on a prompt nothing will answer.
  run_logged timeout 600 "$SDKMANAGER" --sdk_root="$ANDROID_SDK_ROOT" --licenses \
    <<< "$(printf 'y\n%.0s' $(seq 100))"
fi

echo "==> Installing platforms;$PLATFORM, build-tools;$BUILD_TOOLS"
run_logged "$SDKMANAGER" --sdk_root="$ANDROID_SDK_ROOT" \
  "platforms;$PLATFORM" "build-tools;$BUILD_TOOLS"

# aapt2 (bundled in build-tools) has no linux-aarch64 native build — Google
# publishes "linux" (x86_64), "osx", and "windows" classifiers only, verified
# against the aapt2 Maven artifact for every AGP release up to 9.4.0 as of
# this writing. On an aarch64 host, run it under qemu user-mode emulation:
# real x86_64 aapt2, genuinely executed, just CPU-emulated — not a fake or a
# skip. x86_64 Linux and macOS hosts need none of this block.
if [ "$(uname -m)" = "aarch64" ]; then
  if [ ! -e /proc/sys/fs/binfmt_misc/qemu-x86_64 ]; then
    echo "==> Registering qemu-user x86_64 binfmt handler (aarch64 host)"
    command -v qemu-x86_64 >/dev/null || {
      echo "error: qemu-x86_64 not installed. Run: sudo apt-get install -y qemu-user-binfmt" >&2
      exit 1
    }
    [ -e /proc/sys/fs/binfmt_misc/register ] || sudo mount -t binfmt_misc binfmt_misc /proc/sys/fs/binfmt_misc
    sudo bash -c 'echo ":qemu-x86_64:M::\x7f\x45\x4c\x46\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\x3e\x00:\xff\xff\xff\xff\xff\xfe\xfe\xfc\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff\xff:/usr/bin/qemu-x86_64:OCF" > /proc/sys/fs/binfmt_misc/register'
  fi

  if ! dpkg-query -W -f='${Status}' libc6:amd64 2>/dev/null | grep -q "install ok installed"; then
    echo "==> Installing amd64 multiarch libraries (aapt2's runtime deps under emulation)"
    sudo dpkg --add-architecture amd64
    if [ ! -f /etc/apt/sources.list.d/ubuntu-amd64.sources ]; then
      # ports.ubuntu.com (this host's default) carries arm64 only; amd64
      # packages live on the regular archive mirror. Scoped to amd64 so it
      # never shadows the arm64 base system's own package set.
      sudo tee /etc/apt/sources.list.d/ubuntu-amd64.sources >/dev/null <<'EOF'
Types: deb
URIs: http://archive.ubuntu.com/ubuntu/
Suites: resolute resolute-updates resolute-security
Components: main universe restricted multiverse
Architectures: amd64
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg
EOF
    fi
    sudo apt-get update -qq
    sudo apt-get install -y -qq libc6:amd64 libstdc++6:amd64 zlib1g:amd64
  fi
fi

# proto's JDK ships Adoptium's own cacerts, which does not know about this
# sandbox's TLS-intercepting proxy CA. Without it Gradle's wrapper cannot
# fetch its own distribution (PKIX validation failure). The OS trust store
# already has the CA — that's how curl/git succeed — so mirror it in once.
# No-op on any host without that CA file.
#
# Resolve the JDK via ~/.proto/bin/java, a real symlink into the install
# dir. `command -v java` must not be used: under a moon task's PATH it
# finds proto's *shim*, a standalone binary whose readlink resolves to
# ~/.proto and silently yields no cacerts.
PROXY_CA="/usr/local/share/ca-certificates/proxy-ca.crt"
if [ -f "$PROXY_CA" ]; then
  PROTO_JAVA="${PROTO_HOME:-$HOME/.proto}/bin/java"
  [ -e "$PROTO_JAVA" ] || { echo "error: no proto-managed java at $PROTO_JAVA. Run: proto install java" >&2; exit 1; }
  JAVA_HOME_RESOLVED="$(dirname "$(dirname "$(readlink -f "$PROTO_JAVA")")")"
  CACERTS="$JAVA_HOME_RESOLVED/lib/security/cacerts"
  [ -f "$CACERTS" ] || { echo "error: no cacerts at $CACERTS (resolved JDK home: $JAVA_HOME_RESOLVED)" >&2; exit 1; }
  # The resolved JDK's keytool, never PATH's: proto ships no keytool shim, so
  # a bare `keytool` is a system JDK where one happens to exist.
  if ! "$JAVA_HOME_RESOLVED/bin/keytool" -list -keystore "$CACERTS" \
       -storepass changeit -alias docker-sandboxes-proxy-ca >/dev/null 2>&1; then
    echo "==> Importing sandbox proxy CA into $CACERTS"
    run_logged sudo "$JAVA_HOME_RESOLVED/bin/keytool" -importcert -noprompt \
      -trustcacerts -alias docker-sandboxes-proxy-ca -file "$PROXY_CA" \
      -keystore "$CACERTS" -storepass changeit
  fi
fi

echo "==> Android SDK ready at $ANDROID_SDK_ROOT"
