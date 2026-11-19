#!/bin/sh
set -eu

: "${SRCROOT:?}" "${TARGET_BUILD_DIR:?}" "${UNLOCALIZED_RESOURCES_FOLDER_PATH:?}"
source_file="${FINSIGHT_FIREBASE_PLIST:-$SRCROOT/Runner/GoogleService-Info.plist}"
destination="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/GoogleService-Info.plist"

if [ "${PLATFORM_NAME:-}" = iphoneos ]; then
    enabled_define=$(printf '%s' 'FINSIGHT_FCM_CLIENT_ENABLED=true' | /usr/bin/base64)
    disabled_define=$(printf '%s' 'FINSIGHT_FCM_CLIENT_ENABLED=false' | /usr/bin/base64)
    push_enabled=false
    defines="${DART_DEFINES:-},"
    while [ -n "$defines" ]; do
        case "${defines%%,*}" in
            "$enabled_define") push_enabled=true ;;
            "$disabled_define") push_enabled=false ;;
        esac
        defines="${defines#*,}"
    done
    if [ "$push_enabled" = true ]; then
        if [ ! -f "$source_file" ]; then
            echo "error: FINSIGHT_FCM_CLIENT_ENABLED requires GoogleService-Info.plist." >&2
            exit 1
        fi
        if [ "$(/usr/bin/plutil -extract BUNDLE_ID raw -o - "$source_file" 2>/dev/null || true)" != "${PRODUCT_BUNDLE_IDENTIFIER:?}" ]; then
            echo "error: GoogleService-Info.plist BUNDLE_ID must match PRODUCT_BUNDLE_IDENTIFIER." >&2
            exit 1
        fi
        entitlements="${CODE_SIGN_ENTITLEMENTS:-}"
        case "$entitlements" in
            /*) ;;
            *) entitlements="$SRCROOT/$entitlements" ;;
        esac
        if ! /usr/bin/plutil -extract aps-environment raw -o /dev/null "$entitlements" 2>/dev/null; then
            echo "error: FINSIGHT_FCM_CLIENT_ENABLED requires an aps-environment entitlement." >&2
            exit 1
        fi
    fi
fi

if [ -f "$source_file" ]; then
    /usr/bin/plutil -lint "$source_file" >/dev/null
    /bin/cp "$source_file" "$destination"
elif [ -n "${FINSIGHT_FIREBASE_PLIST:-}" ]; then
    echo "error: FINSIGHT_FIREBASE_PLIST does not point to a file." >&2
    exit 1
elif [ -f "$destination" ]; then
    /bin/rm "$destination"
fi
