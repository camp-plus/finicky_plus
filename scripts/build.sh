#!/bin/bash

# Exit on error
set -e


# Build config-api
(
    cd packages/config-api
    npm run build
    npm run generate-types

    # Copy config API to finicky
    cd ../../
    cp packages/config-api/dist/finickyConfigAPI.js apps/finicky/src/assets/finickyConfigAPI.js
)

# Build finicky-ui
(
    cd packages/finicky-ui
    npm run build

    # Copy finicky-ui dist to finicky
    cd ../../

    # Ensure destination directory exists
    mkdir -p apps/finicky/src/assets/templates

    # Copy templates from dist to finicky app
    cp -r packages/finicky-ui/dist/* apps/finicky/src/assets/templates
)

# Determine app name based on target architecture (for CI builds)
if [ -n "$BUILD_TARGET_ARCH" ]; then
    APP_NAME="Finicky-${BUILD_TARGET_ARCH}.app"
else
    APP_NAME="Finicky.app"
fi


# Build the application
(
    # Get build information
    COMMIT_HASH=$(git rev-parse --short HEAD)
    BUILD_DATE=$(date -u '+%Y-%m-%d %H:%M:%S UTC')
    API_HOST=""
    if [ -f .env ]; then
        API_HOST=$(grep '^API_HOST=' .env | cut -d '=' -f 2-)
    else
        echo "WARN: .env not found; API_HOST will be empty."
    fi


    ARCH_FLAG=""
    if [ -n "$BUILD_TARGET_ARCH" ]; then
        export GOOS="darwin"
        export CGO_ENABLED=1
        SDKROOT=$(xcrun --sdk macosx --show-sdk-path)
        export SDKROOT

        case "$BUILD_TARGET_ARCH" in
            amd64)
                export GOARCH="amd64"
                ARCH_FLAG="-arch x86_64"
                export CC="xcrun --sdk macosx clang -arch x86_64"
                export CXX="xcrun --sdk macosx clang++ -arch x86_64"
                ;;
            arm64)
                export GOARCH="arm64"
                ARCH_FLAG="-arch arm64"
                export CC="xcrun --sdk macosx clang -arch arm64"
                export CXX="xcrun --sdk macosx clang++ -arch arm64"
                ;;
        esac
    fi

    export CGO_CFLAGS="-mmacosx-version-min=12.0 ${ARCH_FLAG}"
    export CGO_LDFLAGS="-mmacosx-version-min=12.0 ${ARCH_FLAG}"

    cd apps/finicky
    mkdir -p build/${APP_NAME}/Contents/MacOS
    mkdir -p build/${APP_NAME}/Contents/Resources
    go build -C src \
        -ldflags \
        "-X 'finicky/version.commitHash=${COMMIT_HASH}' \
        -X 'finicky/version.buildDate=${BUILD_DATE}' \
        -X 'finicky/version.apiHost=${API_HOST}'" \
        -o ../build/${APP_NAME}/Contents/MacOS/Finicky
)

# Copy static assets
cp packages/config-api/dist/finicky.d.ts apps/finicky/build/${APP_NAME}/Contents/Resources/finicky.d.ts
cp -r apps/finicky/assets/* apps/finicky/build/${APP_NAME}/Contents/

# Only replace existing app if not in CI (BUILD_TARGET_ARCH not set)
if [ -z "$BUILD_TARGET_ARCH" ]; then
    # Replace existing app
    rm -rf /Applications/Finicky.app
    cp -r apps/finicky/build/Finicky.app /Applications/
fi

echo "Build complete ✨"
