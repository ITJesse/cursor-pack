#!/bin/bash

# Parse command line arguments
LOCAL_APPIMAGE=""
while [[ $# -gt 0 ]]; do
  case $1 in
    --appimage=*)
      LOCAL_APPIMAGE="${1#*=}"
      shift
      ;;
    --appimage)
      LOCAL_APPIMAGE="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      echo "Usage: $0 [--appimage=/path/to/cursor.AppImage]"
      exit 1
      ;;
  esac
done

# Set download API URL
API_URL="https://www.cursor.com/api/download?platform=linux-x64&releaseTrack=latest"

# Get the directory where the script is located
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
ABSOLUTE_BUILD_DIR="$SCRIPT_DIR/build"

# Create build directory
mkdir -p "$ABSOLUTE_BUILD_DIR"

# Create temporary directory
TEMP_DIR=$(mktemp -d)
cd "$TEMP_DIR"

if [ -n "$LOCAL_APPIMAGE" ]; then
  # Use local AppImage file
  echo "Using local AppImage file: $LOCAL_APPIMAGE"
  
  # Convert to absolute path if it's a relative path
  if [[ ! "$LOCAL_APPIMAGE" = /* ]]; then
    LOCAL_APPIMAGE="$SCRIPT_DIR/$LOCAL_APPIMAGE"
    echo "Converted to absolute path: $LOCAL_APPIMAGE"
  fi
  
  if [ ! -f "$LOCAL_APPIMAGE" ]; then
    echo "Error: Specified AppImage file does not exist: $LOCAL_APPIMAGE"
    exit 1
  fi
  
  # Copy the file to temp directory
  echo "Copying AppImage to temporary directory..."
  cp "$LOCAL_APPIMAGE" .
  FILENAME=$(basename "$LOCAL_APPIMAGE")
  echo "Using file: $FILENAME"
else
  echo "Fetching download URL from API..."
  # Get the download URL from the API
  DOWNLOAD_URL=$(curl -s "$API_URL" | grep -o '"downloadUrl":"[^"]*"' | cut -d'"' -f4)

  if [ -z "$DOWNLOAD_URL" ]; then
      echo "Failed to get download URL from API"
      exit 1
  fi

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
  
  # Clean up headers file
  rm -f "$TEMP_HEADERS"
fi

# Ensure filename is correct
if [[ ! "$FILENAME" == *.AppImage ]]; then
    echo "Warning: File may not be in AppImage format, renaming to cursor.AppImage"
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

# Extract AppImage contents
echo "Extracting AppImage contents..."
./"$FILENAME" --appimage-extract

# Modify all JS files that might contain window configuration to add frameless mode
echo "Finding and modifying all relevant JS files to enable frameless mode..."
find squashfs-root/ -type f -name '*.js' \
  -exec grep -l ,minHeight {} \; \
  -exec sed -i 's/,minHeight/,frame:false,minHeight/g' {} \;

MODIFIED_COUNT=$(find squashfs-root/ -type f -name '*.js' -exec grep -l "frame:false" {} \; | wc -l)
echo "Successfully modified $MODIFIED_COUNT files to frameless mode"

# Prepare DEB package
echo "Preparing DEB package..."
DEB_DIR="cursor-$VERSION"
mv squashfs-root "$DEB_DIR"

# Create directory structure
mkdir -p "$DEB_DIR/DEBIAN"
mkdir -p "$DEB_DIR/usr/share/cursor"
mkdir -p "$DEB_DIR/usr/bin"

# Move all files to usr/share/cursor
echo "Moving files to usr/share/cursor..."
find "$DEB_DIR" -maxdepth 1 -not -name "usr" -not -name "$DEB_DIR" -not -name "DEBIAN" | xargs -I{} mv {} "$DEB_DIR/usr/share/cursor/"

# Create wrapper script to suppress output and keep running after terminal closes
cat > "$DEB_DIR/usr/share/cursor/cursor-wrapper" << 'EOF'
#!/bin/bash
nohup /usr/share/cursor/cursor "$@" > /dev/null 2>&1 &
EOF

# Make wrapper script executable
chmod 755 "$DEB_DIR/usr/share/cursor/cursor-wrapper"

# Update symlink to point to wrapper script - remove existing link first if it exists
( cd "$DEB_DIR/usr/bin/" && rm -f cursor && ln -s ../share/cursor/cursor-wrapper cursor )

# Create control file
cat > "$DEB_DIR/DEBIAN/control" << EOF
Package: cursor
Version: $VERSION
Architecture: amd64
Maintainer: Cursor Team <support@cursor.sh>
Installed-Size: $(du -s "$DEB_DIR" | cut -f1)
Section: misc
Priority: optional
Description: AI-first code editor
 Cursor is an AI-powered code editor built on VSCode,
 integrating powerful AI features to help developers
 write code more efficiently.
EOF

# Create postinst script to fix sandbox permissions
echo "Creating postinst script..."
cat > "$DEB_DIR/DEBIAN/postinst" << 'EOF'
#!/bin/sh
set -e

# Fix chrome-sandbox permissions
if [ -f /usr/share/cursor/chrome-sandbox ]; then
    echo "Setting correct permissions for chrome-sandbox..."
    chown root:root /usr/share/cursor/chrome-sandbox
    chmod 4755 /usr/share/cursor/chrome-sandbox
fi

exit 0
EOF

# Make postinst script executable
chmod 755 "$DEB_DIR/DEBIAN/postinst"

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
