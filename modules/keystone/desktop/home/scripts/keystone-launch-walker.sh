#!/bin/bash

# Simple wrapper for Walker with consistent menu dimensions
exec walker --width 644 --maxheight 300 --minheight 300 "$@"
