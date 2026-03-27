#!/usr/bin/env bash

set -euo pipefail

exec keystone-launch-walker -m "menus:keystone-projects"
