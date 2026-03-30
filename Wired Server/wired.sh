#!/bin/sh
set -x
exec 2>&1

PATH="/opt/local/bin:/usr/local/bin:$PATH"

if echo $CONFIGURATION | grep -q Debug; then
	BASE_CFLAGS="-O0"
else
	BASE_CFLAGS="-O2"
fi

WIRED_USER=$(id -un)
WIRED_GROUP=$(id -gn)
BUILD=$("$SRCROOT/wired/config.guess")

# Use Xcode's SDKROOT if it points to a valid SDK; fall back to the generic symlink
[ -d "$SDKROOT" ] || SDKROOT="$DEVELOPER_SDK_DIR/MacOSX.sdk"
MACOSX_DEPLOYMENT_TARGET=10.13

OPENSSL_LIB="$SRCROOT/Pods/OpenSSL-Universal/lib-macos"
OPENSSL_INC="$SRCROOT/Pods/OpenSSL-Universal/include-macos"

# Xcode's Copy Bundle Resources phase copies $BUILT_PRODUCTS_DIR/Wired/ into the app bundle
WIRED_BINARY="$BUILT_PRODUCTS_DIR/Wired/wired"

echo "=== wired.sh start ==="
echo "SRCROOT=$SRCROOT"
echo "WIRED_BINARY=$WIRED_BINARY"
echo "OPENSSL_LIB=$OPENSSL_LIB (exists: $([ -f "$OPENSSL_LIB/libcrypto.a" ] && echo YES || echo NO))"

mkdir -p "$BUILT_PRODUCTS_DIR"

# ── Use /tmp for all build intermediates to avoid spaces in path ──────────────
# In Archive builds, TARGET_TEMP_DIR / OBJECT_FILE_DIR / BUILT_PRODUCTS_DIR all
# contain "Wired Server" (space), which breaks autoconf's eval-based compiler
# tests and make's unquoted variable expansion.
BLDBASE="/tmp/wsbuild_$$"

# ── Single configure pass (arm64 native) ─────────────────────────────────────
TMPDIR_ARM64="$BLDBASE/arm64"
OBJDIR_ARM64="$BLDBASE/obj_arm64"
INSTALL_PREFIX="$BLDBASE/install"
CC_ARM64="/usr/bin/clang -arch arm64"
# Preprocessor flags only — linker flags must NOT go here or they appear before
# -lwired in the link command, breaking static-library symbol resolution.
CPPFLAGS_COMMON="-isysroot ${SDKROOT} -mmacosx-version-min=${MACOSX_DEPLOYMENT_TARGET} -I${OPENSSL_INC}"
# Library search paths for configure/make (separate from CPPFLAGS)
LDFLAGS_COMMON="-L${OPENSSL_LIB} -L${SDKROOT}/usr/lib"
# Extra libs appended after -lwired so static-library resolution works
LIBS_EXTRA="-lcrypto -lssl"

rm -rf "$TMPDIR_ARM64"
mkdir -p "$TMPDIR_ARM64/make/libwired" "$TMPDIR_ARM64/run"

echo "=== configure wired (arm64) ==="
cd "$SRCROOT/wired" || { echo "ERROR: cd wired failed"; exit 1; }

CC="$CC_ARM64" CFLAGS="$BASE_CFLAGS -arch arm64" \
    CPPFLAGS="$CPPFLAGS_COMMON -arch arm64 -I$TMPDIR_ARM64/make" \
    LDFLAGS="$LDFLAGS_COMMON" LIBS="$LIBS_EXTRA" \
    ./configure \
    --host="arm64-apple-darwin$(uname -r)" --build="$BUILD" \
    --enable-warnings \
    --srcdir="$SRCROOT/wired" \
    --with-objdir="$OBJDIR_ARM64" \
    --with-rundir="$TMPDIR_ARM64/run/wired" \
    --prefix="$INSTALL_PREFIX" \
    --with-fake-prefix="/Library" \
    --with-wireddir="Wired" \
    --with-user="$WIRED_USER" \
    --with-group="$WIRED_GROUP" \
    --without-libwired || { echo "ERROR: wired configure (arm64) failed"; exit 1; }

mv config.h Makefile "$TMPDIR_ARM64/make/"

echo "=== configure libwired (arm64) ==="
cd "$SRCROOT/wired/libwired" || { echo "ERROR: cd libwired failed"; exit 1; }

CC="$CC_ARM64" CFLAGS="$BASE_CFLAGS -arch arm64" \
    CPPFLAGS="$CPPFLAGS_COMMON -arch arm64 -I$TMPDIR_ARM64/make/libwired" \
    LDFLAGS="$LDFLAGS_COMMON" LIBS="$LIBS_EXTRA" \
    ./configure \
    --host="arm64-apple-darwin$(uname -r)" --build="$BUILD" \
    --enable-warnings --enable-pthreads --enable-libxml2 --enable-p7 --enable-sqlite3 \
    --srcdir="$SRCROOT/wired/libwired" \
    --with-rundir="$TMPDIR_ARM64/run/wired/libwired" || { echo "ERROR: libwired configure (arm64) failed"; exit 1; }

mv config.h Makefile "$TMPDIR_ARM64/make/libwired"

# prepare support files + build arm64
mkdir -p "$TMPDIR_ARM64/run/wired/files/Drop Box/.wired" \
         "$TMPDIR_ARM64/run/wired/files/Uploads/.wired"
for i in "banner.png" "files/Drop Box/.wired/permissions" \
         "files/Drop Box/.wired/type" "files/Uploads/.wired/type" "wired.xml"; do
    cp "$SRCROOT/wired/run/$i" "$TMPDIR_ARM64/run/wired/$i"
done

echo "=== make arm64 ==="
cd "$TMPDIR_ARM64/make"
make -f "$TMPDIR_ARM64/make/Makefile" || { echo "ERROR: make arm64 failed"; exit 1; }
make -f "$TMPDIR_ARM64/make/Makefile" install-wired || { echo "ERROR: install-wired arm64 failed"; exit 1; }

echo "arm64 binary: $(file "$INSTALL_PREFIX/Wired/wired")"
cp "$INSTALL_PREFIX/Wired/wired" "/tmp/wired_arm64_$$" || { echo "ERROR: copy arm64 failed"; exit 1; }

# ── x86_64 pass: same Makefile, override CC + re-use compatible config.h ──────
# macOS arm64 and x86_64 share identical config.h (both 64-bit LE, same sizes)
# We reuse the arm64 Makefile but override the compiler via make CC=...
TMPDIR_X86="$BLDBASE/x86_64"
OBJDIR_X86="$BLDBASE/obj_x86"
CC_X86="/usr/bin/clang -arch x86_64"

rm -rf "$TMPDIR_X86"
mkdir -p "$TMPDIR_X86/make/libwired" "$TMPDIR_X86/run"

# Copy arm64 make files and patch objdir/rundir/arch for x86_64
sed "s|${OBJDIR_ARM64}|${OBJDIR_X86}|g; s|${TMPDIR_ARM64}|${TMPDIR_X86}|g; s|-arch arm64|-arch x86_64|g" \
    "$TMPDIR_ARM64/make/Makefile" > "$TMPDIR_X86/make/Makefile"
sed "s|${OBJDIR_ARM64}|${OBJDIR_X86}|g; s|${TMPDIR_ARM64}|${TMPDIR_X86}|g; s|-arch arm64|-arch x86_64|g" \
    "$TMPDIR_ARM64/make/libwired/Makefile" > "$TMPDIR_X86/make/libwired/Makefile"
cp "$TMPDIR_ARM64/make/config.h"          "$TMPDIR_X86/make/config.h"
cp "$TMPDIR_ARM64/make/libwired/config.h" "$TMPDIR_X86/make/libwired/config.h"

mkdir -p "$TMPDIR_X86/run/wired/files/Drop Box/.wired" \
         "$TMPDIR_X86/run/wired/files/Uploads/.wired"
for i in "banner.png" "files/Drop Box/.wired/permissions" \
         "files/Drop Box/.wired/type" "files/Uploads/.wired/type" "wired.xml"; do
    cp "$SRCROOT/wired/run/$i" "$TMPDIR_X86/run/wired/$i"
done

echo "=== make x86_64 ==="
cd "$TMPDIR_X86/make"
make -f "$TMPDIR_X86/make/Makefile" \
    CC="$CC_X86" \
    CFLAGS="$BASE_CFLAGS -arch x86_64" \
    || { echo "ERROR: make x86_64 failed"; exit 1; }

make -f "$TMPDIR_X86/make/Makefile" install-wired \
    CC="$CC_X86" \
    || { echo "ERROR: install-wired x86_64 failed"; exit 1; }

echo "x86_64 binary: $(file "$INSTALL_PREFIX/Wired/wired")"
cp "$INSTALL_PREFIX/Wired/wired" "/tmp/wired_x86_64_$$" || { echo "ERROR: copy x86_64 failed"; exit 1; }

# ── Create Universal Binary ────────────────────────────────────────────────────
echo "=== lipo ==="
mkdir -p "$BUILT_PRODUCTS_DIR/Wired"
lipo -create "/tmp/wired_arm64_$$" "/tmp/wired_x86_64_$$" \
     -output "$WIRED_BINARY" || { echo "ERROR: lipo failed"; exit 1; }
chmod 755 "$WIRED_BINARY"
echo "=== Result: $(lipo -info "$WIRED_BINARY") ==="

rm -f "/tmp/wired_arm64_$$" "/tmp/wired_x86_64_$$"
rm -rf "$BLDBASE"

# ── Copy helper scripts into the bundle resources folder ─────────────────────
cp "$SRCROOT/Wired Server/rebuild-index.sh" "$BUILT_PRODUCTS_DIR/Wired/rebuild-index.sh" \
    || { echo "ERROR: copy rebuild-index.sh failed"; exit 1; }
chmod 755 "$BUILT_PRODUCTS_DIR/Wired/rebuild-index.sh"

echo "=== wired.sh done ==="
