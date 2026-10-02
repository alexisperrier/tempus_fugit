#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"
bash ./build.sh
open ./TimeTrackMenu.app
