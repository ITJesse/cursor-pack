#!/bin/bash

# 设置颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # 无颜色

# 显示标题
echo -e "${BLUE}=====================================${NC}"
echo -e "${BLUE}      Cursor 编辑器安装脚本         ${NC}"
echo -e "${BLUE}=====================================${NC}"

# 检查是否为 root 用户
if [ "$EUID" -ne 0 ]; then
  echo -e "${YELLOW}请使用 sudo 运行此脚本${NC}"
  exit 1
fi

echo -e "${GREEN}开始安装 Cursor 编辑器...${NC}"

# 创建临时目录
TEMP_DIR=$(mktemp -d)
cd "$TEMP_DIR"

# 检查系统架构
ARCH=$(uname -m)
if [ "$ARCH" != "x86_64" ]; then
  echo -e "${RED}错误: 仅支持 x86_64 架构，当前架构为 $ARCH${NC}"
  exit 1
fi

# 检查是否安装了必要的工具
for cmd in wget dpkg curl jq unzip; do
  if ! command -v $cmd &> /dev/null; then
    echo -e "${YELLOW}正在安装 $cmd...${NC}"
    apt-get update && apt-get install -y $cmd
  fi
done

# 检查是否已安装 Cursor
if command -v cursor &> /dev/null; then
  echo -e "${YELLOW}检测到系统中已安装 Cursor。${NC}"
  read -p "是否继续安装最新版本？(y/n): " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${GREEN}安装已取消${NC}"
    exit 0
  fi
fi

# 询问用户选择安装方式
echo -e "${BLUE}请选择安装方式:${NC}"
echo -e "1) 从 GitHub Actions 下载最新构建"
echo -e "2) 使用构建脚本本地构建"
read -p "请输入选择 (1/2): " -n 1 -r INSTALL_METHOD
echo

if [[ $INSTALL_METHOD == "1" ]]; then
  # 从 GitHub Actions 下载最新构建
  echo -e "${GREEN}正在从 GitHub Actions 获取最新构建...${NC}"
  
  # 获取最新成功构建的 workflow run ID
  WORKFLOW_RUNS=$(curl -s "https://api.github.com/repos/ITJesse/cursor-pack/actions/runs?status=success&per_page=1")
  
  if [ $? -ne 0 ]; then
    echo -e "${RED}获取 workflow runs 失败，请检查网络连接${NC}"
    exit 1
  fi
  
  RUN_ID=$(echo "$WORKFLOW_RUNS" | jq -r '.workflow_runs[0].id')
  
  if [ -z "$RUN_ID" ] || [ "$RUN_ID" == "null" ]; then
    echo -e "${RED}未找到成功的构建${NC}"
    exit 1
  fi
  
  echo -e "${GREEN}找到最新构建 ID: $RUN_ID${NC}"
  
  # 获取 artifacts 列表
  ARTIFACTS=$(curl -s "https://api.github.com/repos/ITJesse/cursor-pack/actions/runs/$RUN_ID/artifacts")
  
  if [ $? -ne 0 ]; then
    echo -e "${RED}获取 artifacts 失败，请检查网络连接${NC}"
    exit 1
  fi
  
  # 查找 DEB 包 artifact
  ARTIFACT_ID=$(echo "$ARTIFACTS" | jq -r '.artifacts[] | select(.name | contains("deb")) | .id')
  ARTIFACT_NAME=$(echo "$ARTIFACTS" | jq -r '.artifacts[] | select(.name | contains("deb")) | .name')
  
  if [ -z "$ARTIFACT_ID" ] || [ "$ARTIFACT_ID" == "null" ]; then
    echo -e "${RED}未找到 DEB 包 artifact${NC}"
    exit 1
  fi
  
  echo -e "${GREEN}找到 artifact: $ARTIFACT_NAME (ID: $ARTIFACT_ID)${NC}"
  
  # 下载 artifact
  echo -e "${GREEN}正在下载 artifact...${NC}"
  curl -L -o artifact.zip "https://nightly.link/ITJesse/cursor-pack/actions/artifacts/$ARTIFACT_ID.zip"
  
  if [ $? -ne 0 ]; then
    echo -e "${RED}下载 artifact 失败，请检查网络连接${NC}"
    exit 1
  fi
  
  # 解压 artifact
  echo -e "${GREEN}正在解压 artifact...${NC}"
  unzip -q artifact.zip
  
  # 查找 DEB 文件
  DEB_FILE=$(find . -name "*.deb" | head -1)
  
  if [ -z "$DEB_FILE" ]; then
    echo -e "${RED}解压后未找到 DEB 包${NC}"
    exit 1
  fi
  
  echo -e "${GREEN}找到 DEB 包: $DEB_FILE${NC}"
  
else
  # 使用构建脚本本地构建
  echo -e "${GREEN}正在下载构建脚本...${NC}"
  wget -q https://raw.githubusercontent.com/ITJesse/cursor-pack/main/build_deb.sh -O build_deb.sh
  if [ $? -ne 0 ]; then
    echo -e "${RED}下载构建脚本失败，请检查网络连接${NC}"
    exit 1
  fi
  chmod +x build_deb.sh
  
  # 运行构建脚本
  echo -e "${GREEN}正在构建 Cursor DEB 包...${NC}"
  ./build_deb.sh
  
  # 查找 DEB 文件
  DEB_FILE=$(find ./build -name "*.deb" | head -1)
  
  if [ -z "$DEB_FILE" ]; then
    echo -e "${RED}错误: 未找到构建的 DEB 包${NC}"
    exit 1
  fi
fi

# 安装 DEB 包
echo -e "${GREEN}正在安装 Cursor...${NC}"
dpkg -i "$DEB_FILE"

# 处理依赖关系
if [ $? -ne 0 ]; then
  echo -e "${YELLOW}修复依赖关系...${NC}"
  apt-get -f install -y
fi

# 清理临时文件
cd /
rm -rf "$TEMP_DIR"

echo -e "${GREEN}Cursor 安装完成！${NC}"
echo -e "${GREEN}你可以通过应用菜单启动 Cursor，或在终端中输入 'cursor' 命令${NC}"
echo -e "${BLUE}=====================================${NC}"
echo -e "${BLUE}      安装成功完成                  ${NC}"
echo -e "${BLUE}=====================================${NC}" 