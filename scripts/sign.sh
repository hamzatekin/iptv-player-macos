#!/bin/sh
# Re-signs the built app with your Apple Development certificate, when the Keychain has one.
#
# macOS lets a build read the login an earlier build saved in the Keychain only when both are signed
# by the same Apple-issued certificate (the item belongs to its team). An ad-hoc build counts as a new
# app after every rebuild, so it forgot the login. Without a certificate the build stays ad-hoc.
# A free one: Xcode > Settings > Accounts > + > Apple ID, then Manage Certificates > + > Apple Development.
# IPTV_SIGN_IDENTITY picks one (its name or SHA-1); it is required when there are several, because
# signing with another team's certificate locks the app out of the saved login again.
set -e
APP="$1"
if [ -n "$IPTV_SIGN_IDENTITY" ]; then
  IDENTITY="$IPTV_SIGN_IDENTITY"
else
  MATCHES="$(security find-identity -v -p codesigning | grep '"Apple Development: ' || true)"
  if [ "$(printf '%s\n' "$MATCHES" | grep -c .)" -gt 1 ]; then
    echo "error: several Apple Development certificates; set IPTV_SIGN_IDENTITY to the SHA-1 of the one to sign with:" >&2
    printf '%s\n' "$MATCHES" >&2
    exit 1
  fi
  IDENTITY="$(printf '%s\n' "$MATCHES" | awk 'NF { print $2 }')"
fi
if [ -z "$IDENTITY" ]; then
  echo "note: no Apple Development certificate: the build is ad-hoc and won't read the login saved by earlier builds (see scripts/sign.sh)"
  exit 0
fi
# Keep the entitlements Xcode signed with (the sandbox, and get-task-allow in debug builds).
ENTITLEMENTS="$(mktemp -t iptvplayer-entitlements)"
trap 'rm -f "$ENTITLEMENTS"' EXIT
codesign -d --entitlements - --xml "$APP" > "$ENTITLEMENTS" 2>/dev/null
codesign --force --sign "$IDENTITY" --entitlements "$ENTITLEMENTS" --timestamp=none "$APP"
codesign -dv "$APP" 2>&1 | grep -E '^(Authority|TeamIdentifier)=' | head -2 | sed 's/^/signed: /'
