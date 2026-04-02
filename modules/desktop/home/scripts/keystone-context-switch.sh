#!/usr/bin/env bash

set -euo pipefail

if [[ -x "$HOME/.local/bin/keystone-launch-walker" ]]; then
  exec "$HOME/.local/bin/keystone-launch-walker" -m menus:keystone-projects
fi

exec keystone-launch-walker -m menus:keystone-projects
