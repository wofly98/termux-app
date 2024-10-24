#!/bin/bash
GITHUB_SHA=A12345678a
GITHUB_ENV=""
PACKAGE_VARIANT=apt-android-7
          exit_on_error() { echo "$1"; exit 1; }

          echo "Setting vars"

          if [ "$GITHUB_EVENT_NAME" == "pull_request" ]; then
              GITHUB_SHA="${{ github.event.pull_request.head.sha }}" # Do not use last merge commit set in GITHUB_SHA
          fi

          # Set RELEASE_VERSION_NAME to "<CURRENT_VERSION_NAME>+<last_commit_hash>"
          CURRENT_VERSION_NAME_REGEX='\s+versionName "([^"]+)"$'
          CURRENT_VERSION_NAME="$(grep -m 1 -E "$CURRENT_VERSION_NAME_REGEX" ./app/build.gradle | sed -r "s/$CURRENT_VERSION_NAME_REGEX/\1/")"
          RELEASE_VERSION_NAME="v$CURRENT_VERSION_NAME+${GITHUB_SHA:0:7}" # The "+" is necessary so that versioning precedence is not affected
          if ! printf "%s" "${RELEASE_VERSION_NAME/v/}" | grep -qP '^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-((?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*)(?:\.(?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*))*))?(?:\+([0-9a-zA-Z-]+(?:\.[0-9a-zA-Z-]+)*))?$'; then
           exit_on_error "The versionName '${RELEASE_VERSION_NAME/v/}' is not a valid version as per semantic version '2.0.0' spec in the format 'major.minor.patch(-prerelease)(+buildmetadata)'. https://semver.org/spec/v2.0.0.html."
          fi

          APK_DIR_PATH="./app/build/outputs/apk/debug"
          APK_VERSION_TAG="$RELEASE_VERSION_NAME-$PACKAGE_VARIANT-github-debug" # Note the "-", GITHUB_SHA will already have "+" before it
          APK_BASENAME_PREFIX="termux-app_$APK_VERSION_TAG"

          # Used by attachment steps later
          echo "APK_DIR_PATH=$APK_DIR_PATH" >> $GITHUB_ENV
          echo "APK_VERSION_TAG=$APK_VERSION_TAG" >> $GITHUB_ENV
          echo "APK_BASENAME_PREFIX=$APK_BASENAME_PREFIX" >> $GITHUB_ENV

          echo "Building APKs for 'APK_VERSION_TAG' build"
          export TERMUX_APP_VERSION_NAME="${RELEASE_VERSION_NAME/v/}" # Used by app/build.gradle
          export TERMUX_APK_VERSION_TAG="$APK_VERSION_TAG" # Used by app/build.gradle
          export TERMUX_PACKAGE_VARIANT="$PACKAGE_VARIANT" # Used by app/build.gradle
          if ! ./gradlew --info assembleDebug; then
            exit_on_error "Build failed for '$APK_VERSION_TAG' build."
          fi

          echo "Validating APKs"
          for abi in universal arm64-v8a armeabi-v7a x86_64 x86; do
            if ! test -f "$APK_DIR_PATH/${APK_BASENAME_PREFIX}_$abi.apk"; then
              files_found="$(ls "$APK_DIR_PATH")"
              exit_on_error "Failed to find built APK at '$APK_DIR_PATH/${APK_BASENAME_PREFIX}_$abi.apk'. Files found: "$'\n'"$files_found"
            fi
          done

          echo "Generating sha25sums file"
          if ! (cd "$APK_DIR_PATH"; sha256sum \
            "${APK_BASENAME_PREFIX}_universal.apk" \
            "${APK_BASENAME_PREFIX}_arm64-v8a.apk" \
            "${APK_BASENAME_PREFIX}_armeabi-v7a.apk" \
            "${APK_BASENAME_PREFIX}_x86_64.apk" \
            "${APK_BASENAME_PREFIX}_x86.apk" \
            > "${APK_BASENAME_PREFIX}_sha256sums"); then
            exit_on_error "Generate sha25sums failed for '$APK_VERSION_TAG' release."
          fi
