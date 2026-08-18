bottom_VERSION=$1
BUILD_VERSION=$2
ARCH=${3:-amd64}  # Default to amd64 if no architecture specified

if [ -z "$bottom_VERSION" ] || [ -z "$BUILD_VERSION" ]; then
    echo "Usage: $0 <bottom_version> <build_version> [architecture]"
    echo "Example: $0 0.14.8 1 arm64"
    echo "Example: $0 0.14.8 1 all    # Build for all architectures"
    echo "Supported architectures: amd64, arm64, armhf, riscv64, i386, all"
    exit 1
fi

# Upstream tags are NOT prefixed with "v" (e.g. 0.14.8).
BASE_URL="https://github.com/ClementTsang/bottom/releases/download/${bottom_VERSION}"
RAW_URL="https://raw.githubusercontent.com/ClementTsang/bottom/${bottom_VERSION}"

# Function to map Debian architecture to the upstream release asset name.
# Upstream asset names do NOT carry the version, only the target triple.
get_bottom_asset() {
    local arch=$1
    case "$arch" in
        "amd64")
            echo "bottom_x86_64-unknown-linux-musl"
            ;;
        "arm64")
            echo "bottom_aarch64-unknown-linux-musl"
            ;;
        "armhf")
            echo "bottom_armv7-unknown-linux-musleabihf"
            ;;
        "i386")
            echo "bottom_i686-unknown-linux-musl"
            ;;
        "riscv64")
            # No musl build is published for riscv64; upstream only ships a
            # glibc build (needs GLIBC_2.39, i.e. trixie/noble and later).
            echo "bottom_riscv64gc-unknown-linux-gnu"
            ;;
        *)
            echo ""
            ;;
    esac
}

# riscv64 is the only dynamically linked binary we ship.
get_depends() {
    local arch=$1
    case "$arch" in
        "riscv64") echo "libc6 (>= 2.39)" ;;
        *)         echo "" ;;
    esac
}

# Function to build for a specific architecture
build_architecture() {
    local build_arch=$1
    local bottom_asset bottom_release depends

    bottom_asset=$(get_bottom_asset "$build_arch")
    if [ -z "$bottom_asset" ]; then
        echo "❌ Unsupported architecture: $build_arch"
        echo "Supported architectures: amd64, arm64, armhf, riscv64, i386"
        return 1
    fi
    depends=$(get_depends "$build_arch")

    # The upstream asset name has no version in it, so use our own directory.
    bottom_release="btm-${bottom_VERSION}-${build_arch}"

    echo "Building for architecture: $build_arch using ${bottom_asset}.tar.gz"

    # Clean up any previous builds for this architecture
    rm -rf "$bottom_release" || true
    rm -f "${bottom_asset}.tar.gz" manpage.tar.gz || true

    # Download and extract the btm binary (+ completions) for this architecture
    if ! wget "${BASE_URL}/${bottom_asset}.tar.gz"; then
        echo "❌ Failed to download bottom binary for $build_arch"
        return 1
    fi

    # bottom tarballs are flat (btm + completion/), extract into a per-arch dir
    mkdir -p "$bottom_release"
    if ! tar -xf "${bottom_asset}.tar.gz" -C "$bottom_release"; then
        echo "❌ Failed to extract bottom binary for $build_arch"
        return 1
    fi
    rm -f "${bottom_asset}.tar.gz"

    # The man page is a separate, architecture independent release asset.
    mkdir -p "$bottom_release/manpage"
    if ! wget -O manpage.tar.gz "${BASE_URL}/manpage.tar.gz"; then
        echo "❌ Failed to download the bottom man page"
        return 1
    fi
    if ! tar -xf manpage.tar.gz -C "$bottom_release/manpage"; then
        echo "❌ Failed to extract the bottom man page"
        return 1
    fi
    rm -f manpage.tar.gz
    # Upstream ships btm.1.gz; unpack it so the Dockerfile can re-gzip -9n.
    gunzip -f "$bottom_release/manpage/btm.1.gz"

    # Desktop entry and icon (Debian's own btm package ships both).
    mkdir -p "$bottom_release/desktop" "$bottom_release/icons"
    if ! wget -O "$bottom_release/desktop/bottom.desktop" "${BASE_URL}/bottom.desktop"; then
        echo "❌ Failed to download bottom.desktop"
        return 1
    fi
    if ! wget -O "$bottom_release/icons/bottom-system-monitor.svg" \
        "${RAW_URL}/assets/icons/bottom-system-monitor.svg"; then
        echo "❌ Failed to download the bottom icon"
        return 1
    fi

    # Build packages for appropriate Debian distributions
    # riscv64 is only supported in trixie (v13) and later, not in bookworm (v12)
    if [ "$build_arch" = "riscv64" ]; then
        declare -a arr=("trixie" "forky" "sid")
    else
        declare -a arr=("bookworm" "trixie" "forky" "sid")
    fi

    for dist in "${arr[@]}"; do
        FULL_VERSION="$bottom_VERSION-${BUILD_VERSION}~${dist}_${build_arch}"
        echo "  Building $FULL_VERSION"

        if ! docker build . -t "btm-$dist-$build_arch" \
            --build-arg DEBIAN_DIST="$dist" \
            --build-arg bottom_VERSION="$bottom_VERSION" \
            --build-arg BUILD_VERSION="$BUILD_VERSION" \
            --build-arg FULL_VERSION="$FULL_VERSION" \
            --build-arg ARCH="$build_arch" \
            --build-arg DEPENDS="$depends" \
            --build-arg BOTTOM_RELEASE="$bottom_release"; then
            echo "❌ Failed to build Docker image for $dist on $build_arch"
            return 1
        fi

        id="$(docker create "btm-$dist-$build_arch")"
        if ! docker cp "$id:/btm_$FULL_VERSION.deb" - > "./btm_$FULL_VERSION.deb"; then
            echo "❌ Failed to extract .deb package for $dist on $build_arch"
            return 1
        fi

        if ! tar -xf "./btm_$FULL_VERSION.deb"; then
            echo "❌ Failed to extract .deb contents for $dist on $build_arch"
            return 1
        fi
    done

    # Clean up extracted directory
    rm -rf "$bottom_release" || true

    echo "✅ Successfully built for $build_arch"
    return 0
}

# Main build logic
if [ "$ARCH" = "all" ]; then
    echo "🚀 Building bottom $bottom_VERSION-$BUILD_VERSION for all supported architectures..."
    echo ""

    # All supported architectures
    ARCHITECTURES=("amd64" "arm64" "armhf" "riscv64" "i386")

    for build_arch in "${ARCHITECTURES[@]}"; do
        echo "==========================================="
        echo "Building for architecture: $build_arch"
        echo "==========================================="

        if ! build_architecture "$build_arch"; then
            echo "❌ Failed to build for $build_arch"
            exit 1
        fi

        echo ""
    done

    echo "🎉 All architectures built successfully!"
    echo "Generated packages:"
    ls -la btm_*.deb
else
    # Build for single architecture
    if ! build_architecture "$ARCH"; then
        exit 1
    fi
fi
