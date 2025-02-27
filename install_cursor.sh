#!/bin/bash

# Set colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No color

# Display title
echo -e "${BLUE}=====================================${NC}"
echo -e "${BLUE}      Cursor Editor Installer        ${NC}"
echo -e "${BLUE}=====================================${NC}"

# Check if running as root
if [ "$EUID" -ne 0 ]; then
  echo -e "${YELLOW}Please run this script with sudo${NC}"
  exit 1
fi

echo -e "${GREEN}Starting Cursor editor installation...${NC}"

# Create temporary directory
TEMP_DIR=$(mktemp -d)
cd "$TEMP_DIR"

# Check system architecture
ARCH=$(uname -m)
if [ "$ARCH" != "x86_64" ]; then
  echo -e "${RED}Error: Only x86_64 architecture is supported, current architecture is $ARCH${NC}"
  exit 1
fi

# Check if necessary tools are installed
for cmd in wget dpkg curl jq unzip; do
  if ! command -v $cmd &> /dev/null; then
    echo -e "${YELLOW}Installing $cmd...${NC}"
    apt-get update && apt-get install -y $cmd
  fi
done

# Ask user to select installation method
echo -e "${BLUE}Please select installation method:${NC}"
echo -e "1) Download latest build from GitHub Actions"
echo -e "2) Build locally using build script"
read -p "Enter your choice (1/2): " -n 1 -r INSTALL_METHOD
echo

if [[ $INSTALL_METHOD == "1" ]]; then
  # Download latest build from GitHub Actions
  echo -e "${GREEN}Fetching latest builds from GitHub Actions...${NC}"
  
  # Get the latest 5 successful workflow runs
  WORKFLOW_RUNS=$(curl -s "https://api.github.com/repos/ITJesse/cursor-pack/actions/runs?status=success&per_page=5")
  
  if [ $? -ne 0 ]; then
    echo -e "${RED}Failed to get workflow runs, please check your network connection${NC}"
    exit 1
  fi
  
  # Create arrays to store valid build information
  declare -a VALID_RUN_IDS
  declare -a VALID_RUN_NAMES
  declare -a VALID_RUN_DATES
  declare -a VALID_DEB_ARTIFACT_IDS
  declare -a VALID_DEB_ARTIFACT_NAMES
  declare -a VALID_DEB_ARTIFACT_SIZES
  declare -a VALID_DEB_COUNTS
  
  COUNT=$(echo "$WORKFLOW_RUNS" | jq -r '.workflow_runs | length')
  
  if [ "$COUNT" -eq 0 ]; then
    echo -e "${RED}No successful builds found${NC}"
    exit 1
  fi
  
  echo -e "${GREEN}Checking builds for artifacts in parallel...${NC}"
  
  # Create temporary directory to store parallel processing results
  PARALLEL_DIR=$(mktemp -d)
  
  # Limit maximum parallel processes
  MAX_PARALLEL=5
  
  # Track number of running processes
  RUNNING=0
  
  # Process each build in parallel
  for (( i=0; i<$COUNT && i<10; i++ )); do
    RUN_ID=$(echo "$WORKFLOW_RUNS" | jq -r ".workflow_runs[$i].id")
    RUN_NAME=$(echo "$WORKFLOW_RUNS" | jq -r ".workflow_runs[$i].name")
    RUN_DATE=$(echo "$WORKFLOW_RUNS" | jq -r ".workflow_runs[$i].created_at" | cut -d'T' -f1)
    RUN_TIME=$(echo "$WORKFLOW_RUNS" | jq -r ".workflow_runs[$i].created_at" | cut -d'T' -f2 | cut -d'Z' -f1)
    
    # Check in background if this build has DEB package artifacts
    (
      # Check if this build has artifacts
      ARTIFACTS=$(curl -s "https://api.github.com/repos/ITJesse/cursor-pack/actions/runs/$RUN_ID/artifacts")
      ARTIFACT_COUNT=$(echo "$ARTIFACTS" | jq -r '.artifacts | length')
      
      # Check if there are DEB package artifacts
      for (( j=0; j<$ARTIFACT_COUNT; j++ )); do
        ARTIFACT_NAME=$(echo "$ARTIFACTS" | jq -r ".artifacts[$j].name")
        if [[ "$ARTIFACT_NAME" == *"deb"* ]]; then
          ARTIFACT_ID=$(echo "$ARTIFACTS" | jq -r ".artifacts[$j].id")
          
          # Get artifact details
          ARTIFACT_DETAILS=$(curl -s "https://api.github.com/repos/ITJesse/cursor-pack/actions/artifacts/$ARTIFACT_ID")
          ARTIFACT_NAME=$(echo "$ARTIFACT_DETAILS" | jq -r ".name")
          ARTIFACT_SIZE=$(echo "$ARTIFACT_DETAILS" | jq -r ".size_in_bytes")
          
          # Write results to temporary file
          echo "$RUN_ID|$RUN_NAME|$RUN_DATE $RUN_TIME|$ARTIFACT_ID|$ARTIFACT_NAME|$ARTIFACT_SIZE" > "$PARALLEL_DIR/$i-$j"
          break
        fi
      done
    ) &
    
    # Increment running process count
    RUNNING=$((RUNNING+1))
    
    # If maximum parallel count reached, wait for any child process to complete
    if [ $RUNNING -ge $MAX_PARALLEL ]; then
      wait -n
      RUNNING=$((RUNNING-1))
    fi
  done
  
  # Wait for all background tasks to complete
  wait
  
  # Collect and process results
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
      
      # Display at most 5 valid builds
      if [ "$VALID_COUNT" -ge 5 ]; then
        break
      fi
    fi
  done
  
  # Clean up temporary directory
  rm -rf "$PARALLEL_DIR"
  
  if [ "$VALID_COUNT" -eq 0 ]; then
    echo -e "${RED}No builds with DEB packages found${NC}"
    exit 1
  fi
  
  # Display list of valid builds
  echo -e "${BLUE}Available DEB packages:${NC}"
  
  for (( i=0; i<$VALID_COUNT; i++ )); do
    SIZE_MB=$(echo "scale=2; ${VALID_DEB_ARTIFACT_SIZES[$i]}/1048576" | bc)
    echo -e "$((i+1))) ${VALID_DEB_ARTIFACT_NAMES[$i]} (Build time: ${VALID_RUN_DATES[$i]}, Size: ${SIZE_MB}MB)"
  done
  
  # Let user select a build
  read -p "Select a DEB package to install (1-$VALID_COUNT): " -r BUILD_CHOICE
  
  # Validate user input
  if ! [[ "$BUILD_CHOICE" =~ ^[0-9]+$ ]] || [ "$BUILD_CHOICE" -lt 1 ] || [ "$BUILD_CHOICE" -gt "$VALID_COUNT" ]; then
    echo -e "${RED}Invalid selection${NC}"
    exit 1
  fi
  
  # Get selected build ID
  SELECTED_INDEX=$((BUILD_CHOICE-1))
  RUN_ID=${VALID_RUN_IDS[$SELECTED_INDEX]}
  ARTIFACT_ID=${VALID_DEB_ARTIFACT_IDS[$SELECTED_INDEX]}
  
  echo -e "${GREEN}Selected DEB package: ${VALID_DEB_ARTIFACT_NAMES[$SELECTED_INDEX]} (Build time: ${VALID_RUN_DATES[$SELECTED_INDEX]})${NC}"
  
  # Get artifact details
  ARTIFACT_NAME=${VALID_DEB_ARTIFACT_NAMES[$SELECTED_INDEX]}
  SIZE_MB=$(echo "scale=2; ${VALID_DEB_ARTIFACT_SIZES[$SELECTED_INDEX]}/1048576" | bc)
  
  echo -e "${GREEN}DEB package size: ${SIZE_MB}MB${NC}"
  
  # Download artifact
  echo -e "${GREEN}Downloading artifact...${NC}"
  curl -L -o artifact.zip "https://nightly.link/ITJesse/cursor-pack/actions/artifacts/$ARTIFACT_ID.zip"
  
  if [ $? -ne 0 ]; then
    echo -e "${RED}Failed to download artifact, please check your network connection${NC}"
    exit 1
  fi
  
  # Extract artifact
  echo -e "${GREEN}Extracting artifact...${NC}"
  unzip -q artifact.zip
  
  # Find DEB file
  DEB_FILE=$(find . -name "*.deb" | head -1)
  
  if [ -z "$DEB_FILE" ]; then
    echo -e "${RED}No DEB package found after extraction${NC}"
    exit 1
  fi
  
  echo -e "${GREEN}Found DEB package: $DEB_FILE${NC}"
  
else
  # Build locally using build script
  echo -e "${GREEN}Downloading build script...${NC}"
  wget -q https://raw.githubusercontent.com/ITJesse/cursor-pack/main/build_deb.sh -O build_deb.sh
  if [ $? -ne 0 ]; then
    echo -e "${RED}Failed to download build script, please check your network connection${NC}"
    exit 1
  fi
  chmod +x build_deb.sh
  
  # Run build script
  echo -e "${GREEN}Building Cursor DEB package...${NC}"
  ./build_deb.sh
  
  # Find DEB file
  DEB_FILE=$(find ./build -name "*.deb" | head -1)
  
  if [ -z "$DEB_FILE" ]; then
    echo -e "${RED}Error: No built DEB package found${NC}"
    exit 1
  fi
fi

# Install DEB package
echo -e "${GREEN}Installing Cursor...${NC}"
dpkg -i "$DEB_FILE"

# Handle dependencies
if [ $? -ne 0 ]; then
  echo -e "${YELLOW}Fixing dependencies...${NC}"
  apt-get -f install -y
fi

# Clean up temporary files
cd /
rm -rf "$TEMP_DIR"

echo -e "${GREEN}Cursor installation completed!${NC}"
echo -e "${GREEN}You can launch Cursor from the application menu or by typing 'cursor' in terminal${NC}"
echo -e "${BLUE}=====================================${NC}"
echo -e "${BLUE}      Installation Successful        ${NC}"
echo -e "${BLUE}=====================================${NC}" 