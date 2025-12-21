#!/usr/bin/env node
import React from 'react';
import { render } from 'ink';
import App from './App.js';

// Set up royal green theme with custom palette
// Linux VTs use a 16-color palette (0-F), we redefine it for our theme
const setupTheme = () => {
  const rows = process.stdout.rows || 24;
  const cols = process.stdout.columns || 80;

  // Redefine Linux console palette for royal green + gold theme
  // Format: \x1B]P<index><RRGGBB> where index is 0-F hex
  const palette = {
    '0': '0a140f',  // Black/BG → dark forest green
    '1': 'cc4444',  // Red → softer red
    '2': '44aa44',  // Green → medium green
    '3': 'd4a017',  // Yellow → gold
    '4': '6699cc',  // Blue → soft sky blue (readable on green)
    '5': 'aa66aa',  // Magenta
    '6': '55aaaa',  // Cyan → teal
    '7': 'dddddd',  // White → light gray
    '8': '1a2f20',  // Bright black → slightly lighter green
    '9': 'ff6666',  // Bright red
    'A': '66cc66',  // Bright green
    'B': 'ffd700',  // Bright yellow → bright gold
    'C': '88bbee',  // Bright blue → lighter blue
    'D': 'cc88cc',  // Bright magenta
    'E': '77cccc',  // Bright cyan
    'F': 'ffffff',  // Bright white
  };

  // Apply palette (works on Linux VTs)
  for (const [idx, color] of Object.entries(palette)) {
    process.stdout.write(`\x1B]P${idx}${color}`);
  }

  // Also set OSC sequences for modern terminals
  process.stdout.write('\x1B]11;rgb:0a/14/0f\x1B\\');  // Background
  process.stdout.write('\x1B]10;rgb:dd/dd/dd\x1B\\');  // Foreground

  // Clear screen with new palette
  process.stdout.write('\x1B[0m');     // Reset attributes
  process.stdout.write('\x1B[2J');     // Clear screen
  process.stdout.write('\x1B[0;0H');   // Move to top-left

  // Fill every row with spaces to ensure coverage
  const line = ' '.repeat(cols);
  for (let i = 0; i < rows; i++) {
    process.stdout.write(line);
  }

  // Move cursor back to top-left for Ink to render
  process.stdout.write('\x1B[0;0H');
};

setupTheme();

// Reset terminal on exit
const cleanup = () => {
  // Reset all attributes, clear screen, move to top-left
  process.stdout.write('\x1B[0m\x1B[2J\x1B[0;0H');
};
process.on('exit', cleanup);
process.on('SIGINT', () => { cleanup(); process.exit(); });
process.on('SIGTERM', () => { cleanup(); process.exit(); });

// Render the app
render(<App />);
