#!/bin/bash
set -euo pipefail

bottom_VERSION=$1
BUILD_VERSION=$2

if [ -z "$bottom_VERSION" ] || [ -z "$BUILD_VERSION" ]; then
    echo "Usage: $0 <bottom_version> <build_version>"
    echo "Example: $0 0.14.8 1"
    exit 1
fi

PACKAGE_NAME="btm"
ORIG_TARBALL="${PACKAGE_NAME}_${bottom_VERSION}.orig.tar.gz"
BUILD_DIR="${PACKAGE_NAME}-${bottom_VERSION}"
# GitHub archives of ClementTsang/bottom extract as bottom-<version>/ while the
# Debian source package is named btm, so the tree is renamed after extraction.
UPSTREAM_DIR="bottom-${bottom_VERSION}"

echo "Creating the source package for btm ${bottom_VERSION}-${BUILD_VERSION}..."

# A rebuild of an upstream version already released here (a +N build bump)
# must ship the very same orig tarball: the pool holds one per upstream
# version and reprepro refuses a different one, and nothing guarantees the
# archive download is byte-identical next time. Reuse the earlier release's copy.
if [ ! -f "$ORIG_TARBALL" ]; then
    for ((b = BUILD_VERSION - 1; b >= 1; b--)); do
        if wget -q "https://github.com/dariogriffo/bottom-debian/releases/download/${bottom_VERSION}%2B${b}/${ORIG_TARBALL}" -O "$ORIG_TARBALL"; then
            echo "  Reusing $ORIG_TARBALL from release ${bottom_VERSION}+${b}"
            break
        fi
        rm -f "$ORIG_TARBALL"
    done
fi

# Download upstream source tarball (shared .orig.tar.gz across all distributions).
# Upstream tags carry no "v" prefix. The tarball is used byte-for-byte as
# published by GitHub, so repeated runs produce an identical .orig.tar.gz.
if [ ! -f "$ORIG_TARBALL" ]; then
    echo "Downloading upstream source from GitHub..."
    wget -q "https://github.com/ClementTsang/bottom/archive/refs/tags/${bottom_VERSION}.tar.gz" -O "$ORIG_TARBALL"
    echo "  Downloaded $ORIG_TARBALL"
else
    echo "  Using existing $ORIG_TARBALL"
fi

build_source_package() {
    local FULL_VERSION="${bottom_VERSION}-${BUILD_VERSION}~griffo"

    echo "  Building source package ${FULL_VERSION}..."

    # Clean and recreate build directory from orig tarball
    rm -rf "$BUILD_DIR" "$UPSTREAM_DIR"
    tar -xf "$ORIG_TARBALL"
    mv "$UPSTREAM_DIR" "$BUILD_DIR"

    # Copy Debian packaging directory
    cp -r debian "$BUILD_DIR/"

    # Generate the changelog (overwrites placeholder)
    cat > "$BUILD_DIR/debian/changelog" << EOFC
btm (${FULL_VERSION}) stable; urgency=medium

  * New upstream release ${bottom_VERSION}.

 -- Dario Griffo <dariogriffo@gmail.com>  $(date -R)
EOFC

    # Build source package (.dsc + .debian.tar.xz); reuses existing .orig.tar.gz
    dpkg-source -b "$BUILD_DIR"

    rm -rf "$BUILD_DIR"
    echo "    ${FULL_VERSION}"
}

echo ""
# One source package for every suite, as with the binaries (see build_debian.sh).
build_source_package

echo ""
echo "Source packages created successfully!"
echo ""
echo "Generated files:"
ls -la "${PACKAGE_NAME}_"*.dsc "${PACKAGE_NAME}_"*.orig.tar.gz "${PACKAGE_NAME}_"*.debian.tar.xz 2>/dev/null || true
