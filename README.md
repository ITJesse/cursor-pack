# Cursor Installation Scripts

[中文文档](./README_zh.md)

This repository contains script tools for installing and building the Cursor editor.

## Features

- Automatically download and install the latest version of Cursor editor
- Support for DEB package building for Debian/Ubuntu systems
- Simple and easy-to-use command line interface

## Usage

### One-click Installation

Use the following command to directly download and execute the installation script from the network:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/ITJesse/cursor-pack/main/install_cursor.sh)"
```

### Install Cursor

Run the following command to download and install the latest version of Cursor:

```bash
bash install_cursor.sh
```

### Build DEB Package
If you want to build a DEB package for Debian/Ubuntu systems, you can use:

```bash
bash build_deb.sh
```

## System Requirements

- Linux operating system (Debian/Ubuntu series preferred)
- bash environment
- curl or wget (for downloading)

## Contribution

Bug reports and improvement suggestions are welcome! Please participate in the project through GitHub Issues or Pull Requests.

## License

MIT