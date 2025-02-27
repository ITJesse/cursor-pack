#!/bin/bash

# 设置下载URL
DOWNLOAD_URL="https://downloader.cursor.sh/linux/appImage/x64"

# 获取脚本开始时的目录
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
ABSOLUTE_BUILD_DIR="$SCRIPT_DIR/build"

# 创建构建目录
mkdir -p "$ABSOLUTE_BUILD_DIR"

# 创建临时目录
TEMP_DIR=$(mktemp -d)
cd "$TEMP_DIR"

echo "正在从 $DOWNLOAD_URL 下载Cursor AppImage..."

# 使用一次下载操作同时获取文件并确定文件名
TEMP_HEADERS=$(mktemp)
wget -q --show-progress --server-response --content-disposition "$DOWNLOAD_URL" 2> "$TEMP_HEADERS"

# 确保下载成功
if [ $? -ne 0 ]; then
    echo "下载失败，请检查网络连接或URL是否有效"
    rm -f "$TEMP_HEADERS"
    exit 1
fi

# 从响应头中获取文件名
FILENAME=$(grep -i "Content-Disposition" "$TEMP_HEADERS" | sed -n 's/.*filename=\([^;]*\).*/\1/p' | tr -d '"')

# 如果无法从响应头获取文件名，尝试从保存的文件名获取
if [ -z "$FILENAME" ]; then
    # 查找当前目录下最新的文件
    FILENAME=$(ls -t | head -1)
    # 如果文件名不是AppImage，重命名为cursor.AppImage
    if [[ ! "$FILENAME" == *.AppImage ]]; then
        mv "$FILENAME" cursor.AppImage
        FILENAME="cursor.AppImage"
    fi
fi

echo "下载的文件名: $FILENAME"

# 确保文件名正确
if [[ ! "$FILENAME" == *.AppImage ]]; then
    echo "警告：下载的文件可能不是AppImage格式，将重命名为cursor.AppImage"
    mv "$FILENAME" cursor.AppImage
    FILENAME="cursor.AppImage"
fi

# 解析版本号
if [ -n "$CURSOR_VERSION" ]; then
    # 使用环境变量中的版本号（如果存在）
    VERSION="$CURSOR_VERSION"
    echo "使用指定的版本号: $VERSION"
else
    # 从文件名解析版本号
    VERSION=$(echo "$FILENAME" | grep -oP '\d+\.\d+\.\d+' | head -1)

    if [ -z "$VERSION" ]; then
        echo "无法从文件名中解析版本号，将使用当前日期作为版本"
        VERSION=$(date +"%Y.%m.%d")
    fi
    echo "解析的版本号: $VERSION"
fi

# 获取Git短SHA（如果在Git仓库中）
if [ -n "$GIT_SHA" ]; then
    # 使用环境变量中的SHA（如果存在）
    SHORT_SHA="${GIT_SHA:0:7}"
    echo "使用指定的Git SHA: $SHORT_SHA"
else
    # 尝试从Git仓库获取
    if git rev-parse --is-inside-work-tree &>/dev/null; then
        SHORT_SHA=$(git rev-parse --short HEAD)
        echo "从Git仓库获取SHA: $SHORT_SHA"
    else
        # 如果不在Git仓库中，使用时间戳
        SHORT_SHA=$(date +"%Y%m%d%H%M%S" | tail -c 7)
        echo "不在Git仓库中，使用时间戳: $SHORT_SHA"
    fi
fi

# 在版本号末尾添加短SHA
VERSION="${VERSION}-${SHORT_SHA}"
echo "最终版本号: $VERSION"

# 使文件可执行
chmod +x "$FILENAME"

# 添加无边框模式修改
echo "正在修改AppImage以启用无边框模式..."
# 提取AppImage内容
./"$FILENAME" --appimage-extract

# 修改所有可能包含窗口配置的JS文件，添加无边框模式
echo "正在查找并修改所有相关JS文件以启用无边框模式..."
find squashfs-root/ -type f -name '*.js' \
  -exec grep -l ,minHeight {} \; \
  -exec sed -i 's/,minHeight/,frame:false,minHeight/g' {} \;

MODIFIED_COUNT=$(find squashfs-root/ -type f -name '*.js' -exec grep -l "frame:false" {} \; | wc -l)
echo "成功修改了 $MODIFIED_COUNT 个文件为无边框模式"

# 下载appimagetool
echo "正在下载appimagetool..."
wget -q --show-progress "https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage" -O ./appimagetool-x86_64.AppImage
chmod +x ./appimagetool-x86_64.AppImage

# 重新打包AppImage
echo "正在重新打包AppImage..."
./appimagetool-x86_64.AppImage squashfs-root/
MODIFIED_FILENAME=$(ls -t *.AppImage | head -1)
if [ "$MODIFIED_FILENAME" != "$FILENAME" ]; then
    mv "$MODIFIED_FILENAME" "$FILENAME"
fi

# 提取图标
echo "正在提取图标..."
./"$FILENAME" --appimage-extract usr/share/icons

# 创建DEB包目录结构
DEB_DIR="cursor-$VERSION"
mkdir -p "$DEB_DIR/DEBIAN"
mkdir -p "$DEB_DIR/usr/bin"
mkdir -p "$DEB_DIR/usr/share/applications"
mkdir -p "$DEB_DIR/usr/share/icons/hicolor/512x512/apps"
mkdir -p "$DEB_DIR/opt/cursor"

# 创建control文件
cat > "$DEB_DIR/DEBIAN/control" << EOF
Package: cursor
Version: $VERSION
Section: development
Priority: optional
Architecture: amd64
Maintainer: Cursor Team <support@cursor.sh>
Description: AI-first code editor
 Cursor是一个AI驱动的代码编辑器，基于VSCode构建，
 集成了强大的AI功能，帮助开发者更高效地编写代码。
EOF

# 创建postinst脚本
cat > "$DEB_DIR/DEBIAN/postinst" << EOF
#!/bin/bash
chmod +x /opt/cursor/cursor.AppImage
update-desktop-database -q || true
EOF
chmod 755 "$DEB_DIR/DEBIAN/postinst"

# 创建desktop文件
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

# 复制AppImage到DEB包
echo "正在复制AppImage到DEB包..."
cp "$FILENAME" "$DEB_DIR/opt/cursor/cursor.AppImage"

# 复制图标
if [ -d "squashfs-root/usr/share/icons" ]; then
    find squashfs-root/usr/share/icons -name "*.png" -o -name "*.svg" | head -1 | xargs -I{} cp {} "$DEB_DIR/usr/share/icons/hicolor/512x512/apps/cursor.png"
else
    echo "警告：无法找到图标文件"
fi

# 创建启动脚本
cat > "$DEB_DIR/usr/bin/cursor" << EOF
#!/bin/bash
nohup /opt/cursor/cursor.AppImage "\$@" >/dev/null 2>&1 &
EOF
chmod 755 "$DEB_DIR/usr/bin/cursor"

# 构建DEB包
echo "正在构建DEB包..."
dpkg-deb --build "$DEB_DIR"

# 移动DEB包到build目录
DEB_FILENAME="${DEB_DIR}.deb"
if [ -f "$DEB_FILENAME" ]; then
    mv "$DEB_FILENAME" "$ABSOLUTE_BUILD_DIR/cursor_${VERSION}_amd64.deb"
    echo "构建完成！DEB包已保存到build目录: $ABSOLUTE_BUILD_DIR/cursor_${VERSION}_amd64.deb"
else
    echo "构建失败，找不到生成的DEB文件: $DEB_FILENAME"
    ls -la
fi

# 清理临时文件
cd ..
rm -rf "$TEMP_DIR"
rm -f "$TEMP_HEADERS"