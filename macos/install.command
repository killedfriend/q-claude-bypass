#!/bin/bash
# Double-click entry point for Finder. macOS may ask for confirmation the first
# time because the package is not notarized; use right-click -> Open if needed.
cd "$(dirname "$0")" || exit 1
exec /bin/bash ./macos/install.sh "$@"
