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

# 询问用户选择安装方式
echo -e "${BLUE}请选择安装方式:${NC}"
echo -e "1) 从 GitHub Actions 下载最新构建"
echo -e "2) 使用构建脚本本地构建"
read -p "请输入选择 (1/2): " -n 1 -r INSTALL_METHOD
echo

if [[ $INSTALL_METHOD == "1" ]]; then
  # 从 GitHub Actions 下载最新构建
  echo -e "${GREEN}正在从 GitHub Actions 获取最新构建...${NC}"
  
  # 获取最新5个成功构建的 workflow runs
  WORKFLOW_RUNS=$(curl -s "https://api.github.com/repos/ITJesse/cursor-pack/actions/runs?status=success&per_page=5")
  
  if [ $? -ne 0 ]; then
    echo -e "${RED}获取 workflow runs 失败，请检查网络连接${NC}"
    exit 1
  fi
  
  # 创建数组存储有效构建的信息
  declare -a VALID_RUN_IDS
  declare -a VALID_RUN_NAMES
  declare -a VALID_RUN_DATES
  declare -a VALID_DEB_ARTIFACT_IDS
  declare -a VALID_DEB_ARTIFACT_NAMES
  declare -a VALID_DEB_ARTIFACT_SIZES
  declare -a VALID_DEB_COUNTS
  
  COUNT=$(echo "$WORKFLOW_RUNS" | jq -r '.workflow_runs | length')
  
  if [ "$COUNT" -eq 0 ]; then
    echo -e "${RED}未找到成功的构建${NC}"
    exit 1
  fi
  
  echo -e "${GREEN}正在并行检查构建是否包含 artifacts...${NC}"
  
  # 创建临时目录存储并行处理的结果
  PARALLEL_DIR=$(mktemp -d)
  
  # 限制最大并行数量
  MAX_PARALLEL=5
  
  # 跟踪当前运行的进程数量
  RUNNING=0
  
  # 并行处理每个构建
  for (( i=0; i<$COUNT && i<10; i++ )); do
    RUN_ID=$(echo "$WORKFLOW_RUNS" | jq -r ".workflow_runs[$i].id")
    RUN_NAME=$(echo "$WORKFLOW_RUNS" | jq -r ".workflow_runs[$i].name")
    RUN_DATE=$(echo "$WORKFLOW_RUNS" | jq -r ".workflow_runs[$i].created_at" | cut -d'T' -f1)
    RUN_TIME=$(echo "$WORKFLOW_RUNS" | jq -r ".workflow_runs[$i].created_at" | cut -d'T' -f2 | cut -d'Z' -f1)
    
    # 在后台检查该构建是否有 DEB 包 artifacts
    (
      # 检查该构建是否有 artifacts
      ARTIFACTS=$(curl -s "https://api.github.com/repos/ITJesse/cursor-pack/actions/runs/$RUN_ID/artifacts")
      ARTIFACT_COUNT=$(echo "$ARTIFACTS" | jq -r '.artifacts | length')
      
      # 检查是否有 DEB 包 artifacts
      for (( j=0; j<$ARTIFACT_COUNT; j++ )); do
        ARTIFACT_NAME=$(echo "$ARTIFACTS" | jq -r ".artifacts[$j].name")
        if [[ "$ARTIFACT_NAME" == *"deb"* ]]; then
          ARTIFACT_ID=$(echo "$ARTIFACTS" | jq -r ".artifacts[$j].id")
          
          # 获取 artifact 详细信息
          ARTIFACT_DETAILS=$(curl -s "https://api.github.com/repos/ITJesse/cursor-pack/actions/artifacts/$ARTIFACT_ID")
          ARTIFACT_NAME=$(echo "$ARTIFACT_DETAILS" | jq -r ".name")
          ARTIFACT_SIZE=$(echo "$ARTIFACT_DETAILS" | jq -r ".size_in_bytes")
          
          # 将结果写入临时文件
          echo "$RUN_ID|$RUN_NAME|$RUN_DATE $RUN_TIME|$ARTIFACT_ID|$ARTIFACT_NAME|$ARTIFACT_SIZE" > "$PARALLEL_DIR/$i-$j"
          break
        fi
      done
    ) &
    
    # 增加运行中的进程计数
    RUNNING=$((RUNNING+1))
    
    # 如果达到最大并行数，等待任意一个子进程完成
    if [ $RUNNING -ge $MAX_PARALLEL ]; then
      wait -n
      RUNNING=$((RUNNING-1))
    fi
  done
  
  # 等待所有后台任务完成
  wait
  
  # 收集并处理结果
  VALID_COUNT=0
  for RESULT_FILE in "$PARALLEL_DIR"/*; do
    if [ -f "$RESULT_FILE" ]; then
      IFS='|' read -r RUN_ID RUN_NAME RUN_DATE_TIME ARTIFACT_ID ARTIFACT_NAME ARTIFACT_SIZE < "$RESULT_FILE"
      
      VALID_RUN_IDS[$VALID_COUNT]=$RUN_ID
      VALID_RUN_NAMES[$VALID_COUNT]="$RUN_NAME"
      VALID_RUN_DATES[$VALID_COUNT]="$RUN_DATE_TIME"
      VALID_DEB_ARTIFACT_IDS[$VALID_COUNT]=$ARTIFACT_ID
      VALID_DEB_ARTIFACT_NAMES[$VALID_COUNT]="$ARTIFACT_NAME"
      VALID_DEB_ARTIFACT_SIZES[$VALID_COUNT]=$ARTIFACT_SIZE
      
      VALID_COUNT=$((VALID_COUNT+1))
      
      # 最多显示5个有效构建
      if [ "$VALID_COUNT" -ge 5 ]; then
        break
      fi
    fi
  done
  
  # 清理临时目录
  rm -rf "$PARALLEL_DIR"
  
  if [ "$VALID_COUNT" -eq 0 ]; then
    echo -e "${RED}未找到包含 DEB 包的构建${NC}"
    exit 1
  fi
  
  # 显示有效构建列表
  echo -e "${BLUE}可用的 DEB 包列表:${NC}"
  
  for (( i=0; i<$VALID_COUNT; i++ )); do
    SIZE_MB=$(echo "scale=2; ${VALID_DEB_ARTIFACT_SIZES[$i]}/1048576" | bc)
    echo -e "$((i+1))) ${VALID_DEB_ARTIFACT_NAMES[$i]} (构建时间: ${VALID_RUN_DATES[$i]}, 大小: ${SIZE_MB}MB)"
  done
  
  # 让用户选择构建
  read -p "请选择要安装的 DEB 包 (1-$VALID_COUNT): " -r BUILD_CHOICE
  
  # 验证用户输入
  if ! [[ "$BUILD_CHOICE" =~ ^[0-9]+$ ]] || [ "$BUILD_CHOICE" -lt 1 ] || [ "$BUILD_CHOICE" -gt "$VALID_COUNT" ]; then
    echo -e "${RED}无效的选择${NC}"
    exit 1
  fi
  
  # 获取选择的构建ID
  SELECTED_INDEX=$((BUILD_CHOICE-1))
  RUN_ID=${VALID_RUN_IDS[$SELECTED_INDEX]}
  ARTIFACT_ID=${VALID_DEB_ARTIFACT_IDS[$SELECTED_INDEX]}
  
  echo -e "${GREEN}已选择 DEB 包: ${VALID_DEB_ARTIFACT_NAMES[$SELECTED_INDEX]} (构建时间: ${VALID_RUN_DATES[$SELECTED_INDEX]})${NC}"
  
  # 获取 artifact 详细信息
  ARTIFACT_NAME=${VALID_DEB_ARTIFACT_NAMES[$SELECTED_INDEX]}
  SIZE_MB=$(echo "scale=2; ${VALID_DEB_ARTIFACT_SIZES[$SELECTED_INDEX]}/1048576" | bc)
  
  echo -e "${GREEN}DEB 包大小: ${SIZE_MB}MB${NC}"
  
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