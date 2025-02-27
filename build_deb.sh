#!/bin/bash

# Set download URL
DOWNLOAD_URL="https://downloader.cursor.sh/linux/appImage/x64"

# Get the directory where the script is located
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
ABSOLUTE_BUILD_DIR="$SCRIPT_DIR/build"

# Create build directory
mkdir -p "$ABSOLUTE_BUILD_DIR"

# Create temporary directory
TEMP_DIR=$(mktemp -d)
cd "$TEMP_DIR"

echo "Downloading Cursor AppImage from $DOWNLOAD_URL..."

# Use a single download operation to get the file and determine the filename
TEMP_HEADERS=$(mktemp)
wget -q --show-progress --server-response --content-disposition "$DOWNLOAD_URL" 2> "$TEMP_HEADERS"

# Ensure download was successful
if [ $? -ne 0 ]; then
    echo "Download failed, please check your network connection or if the URL is valid"
    rm -f "$TEMP_HEADERS"
    exit 1
fi

# Get filename from response headers
FILENAME=$(grep -i "Content-Disposition" "$TEMP_HEADERS" | sed -n 's/.*filename=\([^;]*\).*/\1/p' | tr -d '"')

# If unable to get filename from response headers, try to get from saved file
if [ -z "$FILENAME" ]; then
    # Find the most recent file in the current directory
    FILENAME=$(ls -t | head -1)
    # If the filename is not an AppImage, rename it to cursor.AppImage
    if [[ ! "$FILENAME" == *.AppImage ]]; then
        mv "$FILENAME" cursor.AppImage
        FILENAME="cursor.AppImage"
    fi
fi

echo "Downloaded filename: $FILENAME"

# Ensure filename is correct
if [[ ! "$FILENAME" == *.AppImage ]]; then
    echo "Warning: Downloaded file may not be in AppImage format, renaming to cursor.AppImage"
    mv "$FILENAME" cursor.AppImage
    FILENAME="cursor.AppImage"
fi

# Parse version number
if [ -n "$CURSOR_VERSION" ]; then
    # Use version number from environment variable (if exists)
    VERSION="$CURSOR_VERSION"
    echo "Using specified version number: $VERSION"
else
    # Parse version number from filename
    VERSION=$(echo "$FILENAME" | grep -oP '\d+\.\d+\.\d+' | head -1)

    if [ -z "$VERSION" ]; then
        echo "Unable to parse version number from filename, using current date as version"
        VERSION=$(date +"%Y.%m.%d")
    fi
    echo "Parsed version number: $VERSION"
fi

# Get Git short SHA (if in a Git repository)
if [ -n "$GIT_SHA" ]; then
    # Use SHA from environment variable (if exists)
    SHORT_SHA="${GIT_SHA:0:7}"
    echo "Using specified Git SHA: $SHORT_SHA"
else
    # Try to get from Git repository
    if git rev-parse --is-inside-work-tree &>/dev/null; then
        SHORT_SHA=$(git rev-parse --short HEAD)
        echo "Got SHA from Git repository: $SHORT_SHA"
    else
        # If not in a Git repository, use timestamp
        SHORT_SHA=$(date +"%Y%m%d%H%M%S" | tail -c 7)
        echo "Not in a Git repository, using timestamp: $SHORT_SHA"
    fi
fi

# Add short SHA to the end of version number
VERSION="${VERSION}-${SHORT_SHA}"
echo "Final version number: $VERSION"

# Make file executable
chmod +x "$FILENAME"

# Add frameless mode modification
echo "Modifying AppImage to enable frameless mode..."
# Extract AppImage contents
./"$FILENAME" --appimage-extract

# Modify all JS files that might contain window configuration to add frameless mode
echo "Finding and modifying all relevant JS files to enable frameless mode..."
find squashfs-root/ -type f -name '*.js' \
  -exec grep -l ,minHeight {} \; \
  -exec sed -i 's/,minHeight/,frame:false,minHeight/g' {} \;

MODIFIED_COUNT=$(find squashfs-root/ -type f -name '*.js' -exec grep -l "frame:false" {} \; | wc -l)
echo "Successfully modified $MODIFIED_COUNT files to frameless mode"

# Download appimagetool
echo "Downloading appimagetool..."
wget -q --show-progress "https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage" -O ./appimagetool-x86_64.AppImage
chmod +x ./appimagetool-x86_64.AppImage

# Repackage AppImage
echo "Repackaging AppImage..."
./appimagetool-x86_64.AppImage squashfs-root/
MODIFIED_FILENAME=$(ls -t *.AppImage | head -1)
if [ "$MODIFIED_FILENAME" != "$FILENAME" ]; then
    mv "$MODIFIED_FILENAME" "$FILENAME"
fi

# Extract icon
echo "Extracting icon..."
./"$FILENAME" --appimage-extract usr/share/icons

# Create DEB package directory structure
DEB_DIR="cursor-$VERSION"
mkdir -p "$DEB_DIR/DEBIAN"
mkdir -p "$DEB_DIR/usr/bin"
mkdir -p "$DEB_DIR/usr/share/applications"
mkdir -p "$DEB_DIR/usr/share/icons/hicolor/512x512/apps"
mkdir -p "$DEB_DIR/opt/cursor"

# Create control file
cat > "$DEB_DIR/DEBIAN/control" << EOF
Package: cursor
Version: $VERSION
Section: development
Priority: optional
Architecture: amd64
Maintainer: Cursor Team <support@cursor.sh>
Description: AI-first code editor
 Cursor is an AI-powered code editor built on VSCode,
 integrating powerful AI features to help developers
 write code more efficiently.
EOF

# Create postinst script
cat > "$DEB_DIR/DEBIAN/postinst" << EOF
#!/bin/bash
chmod +x /opt/cursor/cursor.AppImage
update-desktop-database -q || true
EOF
chmod 755 "$DEB_DIR/DEBIAN/postinst"

# Create desktop file
cat > "$DEB_DIR/usr/share/applications/cursor.desktop" << EOF
[Desktop Entry]
Name=Cursor
Comment=AI-first code editor
Exec=/usr/bin/cursor %U
Icon=cursor
Terminal=false
Type=Application
Categories=Development;IDE;
StartupWMClass=Cursor
EOF

# Copy AppImage to DEB package
echo "Copying AppImage to DEB package..."
cp "$FILENAME" "$DEB_DIR/opt/cursor/cursor.AppImage"

# Copy icon
if [ -d "squashfs-root/usr/share/icons" ]; then
    find squashfs-root/usr/share/icons -name "*.png" -o -name "*.svg" | head -1 | xargs -I{} cp {} "$DEB_DIR/usr/share/icons/hicolor/512x512/apps/cursor.png"
else
    echo "Warning: Could not find icon file"
fi

# Create launcher script
cat > "$DEB_DIR/usr/bin/cursor" << EOF
#!/bin/bash
nohup /opt/cursor/cursor.AppImage "\$@" >/dev/null 2>&1 &
EOF
chmod 755 "$DEB_DIR/usr/bin/cursor"

# Build DEB package
echo "Building DEB package..."
dpkg-deb --build "$DEB_DIR"

# Move DEB package to build directory
DEB_FILENAME="${DEB_DIR}.deb"
if [ -f "$DEB_FILENAME" ]; then
    mv "$DEB_FILENAME" "$ABSOLUTE_BUILD_DIR/cursor_${VERSION}_amd64.deb"
    echo "Build complete! DEB package saved to build directory: $ABSOLUTE_BUILD_DIR/cursor_${VERSION}_amd64.deb"
else
    echo "Build failed, could not find generated DEB file: $DEB_FILENAME"
    ls -la
fi

# Clean up temporary files
cd ..
rm -rf "$TEMP_DIR"
rm -f "$TEMP_HEADERS"