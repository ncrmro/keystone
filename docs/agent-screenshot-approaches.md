# Agent-Based VM Screenshot and Interaction Approaches

This document explores approaches for AI agents (like Claude Code) to capture screenshots from running VMs and interact with them for automated testing and workflow verification.

## Overview

The Keystone project uses libvirt VMs for testing NixOS installations. This document outlines methods for:

1. **Screenshot Capture**: Programmatically capturing VM display output
2. **Visual Verification**: Using AI agents to analyze screenshots
3. **VM Interaction**: Sending keyboard/mouse input to VMs
4. **Workflow Automation**: Combining screenshots + input for end-to-end testing

## Prerequisites

### Required Tools

```bash
# NixOS configuration.nix
virtualisation.libvirtd.enable = true;
environment.systemPackages = with pkgs; [
  libvirt
  virt-viewer
  netpbm          # For PPM to PNG conversion
  imagemagick     # Alternative image processing
  xdotool         # For advanced input automation (optional)
];

# User groups
users.users.<youruser>.extraGroups = [ "libvirtd" ];
```

### Python Dependencies

```python
# For programmatic libvirt control
pip install libvirt-python pillow
```

## Approach 1: Libvirt Screenshot API

### Method Overview

The `virsh screenshot` command and libvirt API provide direct framebuffer capture.

### Basic Usage

```bash
# Capture screenshot to PPM format
virsh screenshot <vm-name> screenshot.ppm

# Convert to PNG for agent viewing
pnmtopng screenshot.ppm > screenshot.png

# Or use ImageMagick
convert screenshot.ppm screenshot.png
```

### Python Implementation

```python
#!/usr/bin/env python3
"""
VM Screenshot Capture Script
Captures screenshots from libvirt VMs for agent analysis
"""

import libvirt
import subprocess
from pathlib import Path
from datetime import datetime

class VMScreenshotCapture:
    def __init__(self, vm_name: str):
        self.vm_name = vm_name
        self.conn = libvirt.open('qemu:///system')
        self.domain = self.conn.lookupByName(vm_name)

    def capture(self, output_path: str = None) -> Path:
        """
        Capture screenshot and convert to PNG

        Args:
            output_path: Optional path for output file

        Returns:
            Path to PNG screenshot
        """
        if output_path is None:
            timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
            output_path = f"screenshots/{self.vm_name}_{timestamp}.png"

        output_path = Path(output_path)
        output_path.parent.mkdir(parents=True, exist_ok=True)

        # Capture to PPM format
        ppm_path = output_path.with_suffix('.ppm')
        stream = self.conn.newStream(0)

        # Get screenshot (screen 0, format PPM)
        mime = self.domain.screenshot(stream, 0, 0)

        # Write PPM data
        with open(ppm_path, 'wb') as f:
            def write_chunk(stream, data, opaque):
                return f.write(data)
            stream.recvAll(write_chunk, None)
        stream.finish()

        # Convert to PNG
        subprocess.run(
            ['pnmtopng', str(ppm_path)],
            stdout=open(output_path, 'wb'),
            check=True
        )
        ppm_path.unlink()  # Clean up PPM

        return output_path

    def __del__(self):
        if hasattr(self, 'conn'):
            self.conn.close()

# Usage example
if __name__ == "__main__":
    import sys

    vm_name = sys.argv[1] if len(sys.argv) > 1 else "keystone-test-vm"

    capture = VMScreenshotCapture(vm_name)
    screenshot_path = capture.capture()
    print(f"Screenshot saved to: {screenshot_path}")
```

### Integration with bin/virtual-machine

```bash
# Add screenshot capability to bin/virtual-machine
./bin/virtual-machine --screenshot keystone-test-vm output.png
```

Add to `bin/virtual-machine`:

```python
def capture_screenshot(vm_name: str, output_path: str = None):
    """Capture VM screenshot"""
    try:
        conn = libvirt.open('qemu:///system')
        domain = conn.lookupByName(vm_name)

        if output_path is None:
            output_path = f"{vm_name}_screenshot.png"

        ppm_path = output_path.replace('.png', '.ppm')

        # Capture via libvirt
        stream = conn.newStream(0)
        domain.screenshot(stream, 0, 0)

        with open(ppm_path, 'wb') as f:
            def write_data(stream, data, opaque):
                return f.write(data)
            stream.recvAll(write_data, None)
        stream.finish()

        # Convert to PNG
        subprocess.run(['pnmtopng', ppm_path],
                      stdout=open(output_path, 'wb'), check=True)
        os.unlink(ppm_path)

        print(f"✓ Screenshot saved: {output_path}")
        conn.close()

    except Exception as e:
        print(f"✗ Screenshot failed: {e}", file=sys.stderr)
        sys.exit(1)
```

### Advantages

- **Direct framebuffer access** - No intermediate protocols
- **High fidelity** - Exact pixel-perfect capture
- **No guest cooperation** - Works even if VM is unresponsive
- **Format flexibility** - Easy conversion to any image format

### Limitations

- **PPM intermediate format** - Requires conversion step
- **No streaming** - Single frame capture only
- **Timing sensitivity** - Must poll for state changes

## Approach 2: SPICE Protocol Screenshot

### Method Overview

SPICE provides streaming display with built-in screenshot capabilities.

### Using remote-viewer

```bash
# Start VM with SPICE display (already default in bin/virtual-machine)
./bin/virtual-machine --name test-vm --start

# Connect with remote-viewer
remote-viewer $(virsh domdisplay test-vm)

# Screenshot via GUI: File → Screenshot
```

### Programmatic SPICE Screenshot

```python
"""
SPICE Screenshot via spice-client-glib-usb-acl-helper
Note: Requires more complex integration
"""

import subprocess
import time

def spice_screenshot(vm_name: str, output: str):
    """
    Capture via SPICE connection
    More complex but enables streaming
    """
    # Get SPICE connection URI
    uri = subprocess.check_output(
        ['virsh', 'domdisplay', vm_name],
        text=True
    ).strip()

    # Use custom SPICE client script
    # This requires custom implementation or external tools
    # like virt-viewer's screenshot functionality
    pass
```

### Advantages

- **Streaming capable** - Can monitor changes
- **Rich protocol** - Mouse/keyboard input included
- **Performance** - Optimized for remote display
- **Integration** - Works with virt-viewer tools

### Limitations

- **More complex** - Requires SPICE client libraries
- **Connection overhead** - Must establish session
- **Dependencies** - Additional packages needed

## Approach 3: VNC Protocol Screenshot

### Method Overview

VNC is an alternative to SPICE with wider tool support.

### Configuration

Modify VM to use VNC instead of SPICE:

```python
# In bin/virtual-machine, change graphics section:
<graphics type='vnc' port='5900' autoport='yes' listen='127.0.0.1'>
  <listen type='address' address='127.0.0.1'/>
</graphics>
```

### VNC Screenshot Capture

```bash
# Using vncsnapshot (if available)
vncsnapshot localhost:5900 screenshot.jpg

# Using Python vncdotool
pip install vncdotool
vncdo -s localhost:5900 capture screenshot.png
```

### Python Implementation

```python
"""
VNC Screenshot using vncdotool
"""

from vncdotool import api

def vnc_screenshot(host: str = 'localhost', port: int = 5900,
                   output: str = 'screenshot.png'):
    """Capture screenshot via VNC"""
    client = api.connect(f'{host}:{port}')
    client.captureScreen(output)
    client.disconnect()

# Usage
vnc_screenshot(port=5900, output='vm_screen.png')
```

### Advantages

- **Mature ecosystem** - Many tools available
- **Cross-platform** - Works everywhere
- **Simple protocol** - Easy to implement

### Limitations

- **Performance** - Generally slower than SPICE
- **Less features** - Fewer advanced capabilities
- **Security** - Less secure than SPICE by default

---

## VM Interaction: Sending Input

### Approach 1: virsh send-key

#### Basic Usage

```bash
# Send individual keys
virsh send-key keystone-test-vm KEY_ENTER

# Send key combinations
virsh send-key keystone-test-vm KEY_LEFTCTRL KEY_C

# Send text (requires scripting)
echo "root" | while read -n1 char; do
    virsh send-key keystone-test-vm "KEY_$(echo $char | tr '[:lower:]' '[:upper:]')"
done
```

#### Python Implementation

```python
"""
VM Keyboard Input Automation
"""

import libvirt
import time

class VMKeyboardController:
    # Key code mapping
    KEY_MAP = {
        'a': 30, 'b': 48, 'c': 46, 'd': 32, 'e': 18, 'f': 33,
        'g': 34, 'h': 35, 'i': 23, 'j': 36, 'k': 37, 'l': 38,
        'm': 50, 'n': 49, 'o': 24, 'p': 25, 'q': 16, 'r': 19,
        's': 31, 't': 20, 'u': 22, 'v': 47, 'w': 17, 'x': 45,
        'y': 21, 'z': 44,
        '0': 11, '1': 2, '2': 3, '3': 4, '4': 5,
        '5': 6, '6': 7, '7': 8, '8': 9, '9': 10,
        '-': 12, '=': 13, '[': 26, ']': 27, '\\': 43,
        ';': 39, "'": 40, ',': 51, '.': 52, '/': 53,
        ' ': 57, '\n': 28,
        'ENTER': 28, 'ESC': 1, 'BACKSPACE': 14, 'TAB': 15,
        'SHIFT': 42, 'CTRL': 29, 'ALT': 56,
        'UP': 103, 'DOWN': 108, 'LEFT': 105, 'RIGHT': 106,
    }

    def __init__(self, vm_name: str):
        self.vm_name = vm_name
        self.conn = libvirt.open('qemu:///system')
        self.domain = self.conn.lookupByName(vm_name)

    def send_key(self, key: str, hold_time: float = 0.1):
        """Send a single key press"""
        if isinstance(key, str):
            key_code = self.KEY_MAP.get(key.lower(), self.KEY_MAP.get(key.upper()))
        else:
            key_code = key

        if key_code is None:
            raise ValueError(f"Unknown key: {key}")

        # Send key press
        self.domain.sendKey(libvirt.VIR_KEYCODE_SET_LINUX, hold_time, [key_code], 1, 0)
        time.sleep(0.05)  # Brief delay between keys

    def send_keys(self, keys: list, hold_time: float = 0.1):
        """Send multiple keys simultaneously (for combinations)"""
        key_codes = [self.KEY_MAP.get(k.lower(), self.KEY_MAP.get(k.upper()))
                     for k in keys]
        self.domain.sendKey(libvirt.VIR_KEYCODE_SET_LINUX, hold_time,
                           key_codes, len(key_codes), 0)
        time.sleep(0.05)

    def type_text(self, text: str, delay: float = 0.05):
        """Type a string of text"""
        for char in text:
            if char.isupper():
                # Shift + key for uppercase
                key_code = self.KEY_MAP.get(char.lower())
                self.domain.sendKey(libvirt.VIR_KEYCODE_SET_LINUX, 100,
                                   [42, key_code], 2, 0)  # 42 = SHIFT
            else:
                self.send_key(char)
            time.sleep(delay)

    def press_enter(self):
        """Press Enter key"""
        self.send_key('ENTER')

    def __del__(self):
        if hasattr(self, 'conn'):
            self.conn.close()

# Usage example
if __name__ == "__main__":
    controller = VMKeyboardController('keystone-test-vm')

    # Login example
    controller.type_text('root')
    controller.press_enter()
    time.sleep(1)
    controller.type_text('password')
    controller.press_enter()
```

#### Key Code Reference

Full Linux key codes: `/usr/include/linux/input-event-codes.h`

Common keys:
- `KEY_ENTER` (28) - Enter/Return
- `KEY_ESC` (1) - Escape
- `KEY_LEFTCTRL` (29) - Left Control
- `KEY_LEFTALT` (56) - Left Alt
- `KEY_UP/DOWN/LEFT/RIGHT` (103, 108, 105, 106) - Arrow keys

### Approach 2: QEMU Monitor Commands

#### QMP (QEMU Machine Protocol)

```bash
# Access QEMU monitor via virsh
virsh qemu-monitor-command keystone-test-vm --hmp 'sendkey ctrl-alt-f1'

# Or via QMP JSON
virsh qemu-monitor-command keystone-test-vm \
    '{"execute":"input-send-event","arguments":{"events":[{"type":"key","data":{"down":true,"key":{"type":"number","data":28}}}]}}'
```

#### Python QMP Implementation

```python
"""
QMP-based input control
More powerful but complex
"""

import json

def qmp_send_key(vm_name: str, key_code: int, down: bool = True):
    """Send key via QMP"""
    event = {
        "execute": "input-send-event",
        "arguments": {
            "events": [{
                "type": "key",
                "data": {
                    "down": down,
                    "key": {"type": "number", "data": key_code}
                }
            }]
        }
    }

    cmd = ['virsh', 'qemu-monitor-command', vm_name, json.dumps(event)]
    subprocess.run(cmd, check=True)
```

### Approach 3: VNC/SPICE Protocol Input

```python
"""
Send input via VNC protocol
"""

from vncdotool import api

def vnc_type_text(text: str, host: str = 'localhost', port: int = 5900):
    """Type text via VNC"""
    client = api.connect(f'{host}:{port}')
    client.type(text)
    client.disconnect()

def vnc_send_keys(keys: str, host: str = 'localhost', port: int = 5900):
    """Send special keys via VNC"""
    client = api.connect(f'{host}:{port}')
    client.keyPress(keys)
    client.disconnect()

# Usage
vnc_type_text('root')
vnc_send_keys('enter')
vnc_type_text('nixos-install')
vnc_send_keys('enter')
```

---

## Extended Section: Agent-Driven Workflow Verification

### Overview

Combine screenshot capture + input automation + AI analysis for fully automated testing.

### Workflow Pattern

```
1. Agent sends command to VM
   ↓
2. Wait for visual state change
   ↓
3. Capture screenshot
   ↓
4. Agent analyzes screenshot
   ↓
5. Decide next action
   ↓
6. Repeat until workflow complete
```

### Implementation: Automated Installation Verifier

```python
#!/usr/bin/env python3
"""
Agent-Driven VM Installation Verifier

This script demonstrates how an AI agent (Claude Code) can:
1. Interact with a VM via keyboard input
2. Capture screenshots at each step
3. Analyze screenshots to verify state
4. Make decisions about next actions

The agent performs visual verification of the Keystone installation process.
"""

import time
from pathlib import Path
from typing import Tuple, Optional
from dataclasses import dataclass

@dataclass
class WorkflowStep:
    """Represents a step in the installation workflow"""
    name: str
    action: callable
    verification_prompt: str  # Prompt for agent to verify screenshot
    max_wait: int = 30
    retry_count: int = 3

class AgentVMWorkflow:
    """
    Automated VM workflow verification using screenshots and AI analysis

    This class coordinates:
    - VM input (keyboard/mouse)
    - Screenshot capture
    - Agent analysis (via Claude Code's Read tool)
    - Workflow state management
    """

    def __init__(self, vm_name: str, screenshot_dir: str = "workflow_screenshots"):
        self.vm_name = vm_name
        self.screenshot_dir = Path(screenshot_dir)
        self.screenshot_dir.mkdir(exist_ok=True)

        self.keyboard = VMKeyboardController(vm_name)
        self.capture = VMScreenshotCapture(vm_name)

        self.step_counter = 0
        self.verification_results = []

    def execute_step(self, step: WorkflowStep) -> Tuple[bool, str]:
        """
        Execute a workflow step with agent verification

        Args:
            step: WorkflowStep to execute

        Returns:
            (success, screenshot_path)
        """
        print(f"\n{'='*60}")
        print(f"Step {self.step_counter}: {step.name}")
        print(f"{'='*60}")

        # Execute the action
        try:
            step.action()
            time.sleep(2)  # Wait for UI to update
        except Exception as e:
            print(f"✗ Action failed: {e}")
            return False, None

        # Capture screenshot
        screenshot_path = self.screenshot_dir / f"step_{self.step_counter:02d}_{step.name.replace(' ', '_')}.png"
        self.capture.capture(str(screenshot_path))
        print(f"📸 Screenshot: {screenshot_path}")

        # At this point, the agent (Claude Code) would analyze the screenshot
        # using the Read tool to view the image
        print(f"\n🤖 Agent Analysis Required:")
        print(f"   Verification: {step.verification_prompt}")
        print(f"   Screenshot: {screenshot_path}")
        print(f"\n   [Agent would now analyze screenshot and respond with verification]")

        # In actual implementation, this would return agent's analysis
        # For now, we simulate agent verification
        self.step_counter += 1

        return True, str(screenshot_path)

    def verify_boot_screen(self):
        """Verify VM has booted to installer"""
        def action():
            # Just wait for boot
            time.sleep(5)

        step = WorkflowStep(
            name="Verify Boot Screen",
            action=action,
            verification_prompt=(
                "Does this screenshot show the NixOS installer boot screen? "
                "Look for GRUB menu or NixOS branding."
            )
        )
        return self.execute_step(step)

    def login_to_installer(self):
        """Login to the installer as root"""
        def action():
            time.sleep(10)  # Wait for boot to complete
            self.keyboard.type_text('root')
            self.keyboard.press_enter()

        step = WorkflowStep(
            name="Login to Installer",
            action=action,
            verification_prompt=(
                "Does this screenshot show a root shell prompt? "
                "Look for # or root@ in the terminal."
            )
        )
        return self.execute_step(step)

    def verify_network(self):
        """Verify network connectivity"""
        def action():
            self.keyboard.type_text('ip addr show')
            self.keyboard.press_enter()
            time.sleep(2)

        step = WorkflowStep(
            name="Verify Network",
            action=action,
            verification_prompt=(
                "Does this screenshot show network interfaces with IP addresses? "
                "Look for inet 192.168.100.99 or similar."
            )
        )
        return self.execute_step(step)

    def start_ssh_daemon(self):
        """Start SSH daemon for remote deployment"""
        def action():
            self.keyboard.type_text('systemctl start sshd')
            self.keyboard.press_enter()
            time.sleep(1)

        step = WorkflowStep(
            name="Start SSH Daemon",
            action=action,
            verification_prompt=(
                "Does this screenshot show the command completed successfully? "
                "Look for a new prompt without errors."
            )
        )
        return self.execute_step(step)

    def verify_disk_detection(self):
        """Verify installation disk is detected"""
        def action():
            self.keyboard.type_text('lsblk')
            self.keyboard.press_enter()
            time.sleep(1)

        step = WorkflowStep(
            name="Verify Disk Detection",
            action=action,
            verification_prompt=(
                "Does this screenshot show storage devices listed? "
                "Look for vda, sda, or nvme devices."
            )
        )
        return self.execute_step(step)

    def run_full_workflow(self):
        """Execute complete installation verification workflow"""
        print("\n" + "="*60)
        print("Starting Agent-Driven Installation Verification")
        print("="*60)

        workflow = [
            self.verify_boot_screen,
            self.login_to_installer,
            self.verify_network,
            self.start_ssh_daemon,
            self.verify_disk_detection,
        ]

        results = []
        for step_func in workflow:
            success, screenshot = step_func()
            results.append((step_func.__name__, success, screenshot))

            if not success:
                print(f"\n✗ Workflow failed at: {step_func.__name__}")
                break

        # Generate report
        print("\n" + "="*60)
        print("Workflow Summary")
        print("="*60)

        for name, success, screenshot in results:
            status = "✓" if success else "✗"
            print(f"{status} {name}")
            if screenshot:
                print(f"    Screenshot: {screenshot}")

        return results

# Usage Example
if __name__ == "__main__":
    import sys

    vm_name = sys.argv[1] if len(sys.argv) > 1 else "keystone-test-vm"

    workflow = AgentVMWorkflow(vm_name)
    results = workflow.run_full_workflow()

    print("\n✓ Workflow complete!")
    print(f"  Screenshots saved to: {workflow.screenshot_dir}")
    print("\nNext steps:")
    print("  1. Review screenshots in the workflow_screenshots/ directory")
    print("  2. Agent (Claude Code) can view each screenshot using the Read tool")
    print("  3. Agent provides verification for each step")
    print("  4. Workflow continues or stops based on verification")
```

### Integration with Claude Code

#### How Claude Code Views Screenshots

```bash
# 1. Run workflow to generate screenshots
python3 agent_vm_workflow.py keystone-test-vm

# 2. In Claude Code session, agent can read images:
# Agent automatically uses Read tool on image files
```

When Claude Code uses the `Read` tool on a PNG file, it can:
- **See the actual display** - Visual rendering of the image
- **Analyze content** - Text recognition, UI element detection
- **Verify state** - Confirm expected screens/prompts
- **Make decisions** - Determine next action based on visuals

#### Example Agent Conversation

```
User: Verify the Keystone VM installation process

Agent: I'll run the automated workflow and verify each step visually.

[Agent executes workflow script]
[Screenshots captured at each step]

Agent: [Reading step_01_Verify_Boot_Screen.png]

I can see the GRUB bootloader with the NixOS entry. The VM has successfully
booted to the installer. Proceeding to next step.

[Reading step_02_Login_to_Installer.png]

I can see the root shell prompt (root@nixos:~#). Login successful. The installer
is ready for configuration. Proceeding to network verification.

[Reading step_03_Verify_Network.png]

I can see the network interface ens3 has IP address 192.168.100.99. Network is
configured correctly and matches the keystone-net subnet. Proceeding to start SSH.

[Continues through all steps with visual verification]

✓ All installation verification steps completed successfully!
```

### Agent Decision Making with Screenshots

```python
"""
Example: Agent makes decisions based on screenshot analysis
"""

class AgentDecisionMaker:
    """
    Simulates how an AI agent analyzes screenshots and makes decisions

    In actual implementation, this would be Claude Code analyzing
    images via the Read tool
    """

    def analyze_screenshot(self, screenshot_path: str, verification_prompt: str) -> dict:
        """
        Analyze screenshot and return verification result

        In Claude Code, this happens automatically when the agent
        uses Read tool on an image file.

        Args:
            screenshot_path: Path to screenshot PNG
            verification_prompt: What to verify

        Returns:
            {
                'verified': bool,
                'confidence': float,
                'observations': str,
                'next_action': str
            }
        """

        # Claude Code would:
        # 1. Read the image using Read tool
        # 2. Analyze visual content
        # 3. Compare against verification criteria
        # 4. Return structured analysis

        print(f"\n🤖 Agent analyzing: {screenshot_path}")
        print(f"   Question: {verification_prompt}")
        print(f"   [Agent views image and analyzes...]")

        # Simulated agent response
        return {
            'verified': True,
            'confidence': 0.95,
            'observations': 'Screenshot shows expected state',
            'next_action': 'proceed'
        }

    def decide_next_step(self, analysis: dict, current_step: int,
                        workflow: list) -> Tuple[str, Optional[int]]:
        """
        Decide what to do based on screenshot analysis

        Returns:
            (action, next_step_index)
            action: 'proceed', 'retry', 'skip', 'abort'
        """

        if analysis['verified'] and analysis['confidence'] > 0.8:
            # High confidence verification - proceed
            return 'proceed', current_step + 1

        elif analysis['verified'] and analysis['confidence'] > 0.5:
            # Medium confidence - proceed with caution
            print("⚠️  Medium confidence - proceeding cautiously")
            return 'proceed', current_step + 1

        elif not analysis['verified']:
            # Verification failed - decide whether to retry or abort
            print("✗ Verification failed")

            # Could implement retry logic here
            return 'retry', current_step

        else:
            # Low confidence - ask for human verification
            print("? Low confidence - human verification recommended")
            return 'abort', None
```

### Advanced: Visual Regression Testing

```python
"""
Use screenshots for visual regression testing
"""

from PIL import Image
import imagehash

class VisualRegressionTester:
    """
    Compare screenshots against known-good baselines
    """

    def __init__(self, baseline_dir: str = "baseline_screenshots"):
        self.baseline_dir = Path(baseline_dir)
        self.baseline_dir.mkdir(exist_ok=True)

    def capture_baseline(self, step_name: str, screenshot_path: str):
        """Save a screenshot as baseline for future comparison"""
        baseline_path = self.baseline_dir / f"{step_name}.png"
        shutil.copy(screenshot_path, baseline_path)

        # Store perceptual hash for fuzzy matching
        img = Image.open(screenshot_path)
        hash_value = imagehash.average_hash(img)

        hash_file = self.baseline_dir / f"{step_name}.hash"
        hash_file.write_text(str(hash_value))

        print(f"✓ Baseline saved: {baseline_path}")

    def compare_against_baseline(self, step_name: str,
                                 screenshot_path: str) -> dict:
        """
        Compare screenshot against baseline

        Returns:
            {
                'matches': bool,
                'similarity': float,
                'differences': list
            }
        """
        baseline_path = self.baseline_dir / f"{step_name}.png"
        hash_file = self.baseline_dir / f"{step_name}.hash"

        if not baseline_path.exists():
            return {
                'matches': None,
                'similarity': 0.0,
                'differences': ['No baseline exists']
            }

        # Load images
        baseline_img = Image.open(baseline_path)
        current_img = Image.open(screenshot_path)

        # Compare perceptual hashes
        baseline_hash = imagehash.hex_to_hash(hash_file.read_text())
        current_hash = imagehash.average_hash(current_img)

        # Calculate similarity (0 = identical, higher = more different)
        hash_diff = baseline_hash - current_hash
        similarity = 1.0 - (hash_diff / 64.0)  # Normalize to 0-1

        matches = hash_diff < 5  # Threshold for "match"

        return {
            'matches': matches,
            'similarity': similarity,
            'hash_diff': hash_diff
        }

# Usage in workflow
regression_tester = VisualRegressionTester()

# First run: capture baselines
regression_tester.capture_baseline("boot_screen", "step_01.png")

# Subsequent runs: compare
result = regression_tester.compare_against_baseline("boot_screen", "step_01.png")
if result['matches']:
    print(f"✓ Visual regression test passed (similarity: {result['similarity']:.2%})")
else:
    print(f"✗ Visual regression test failed (diff: {result['hash_diff']})")
```

## Practical Example: Complete Installation Test

### Script: test_installation_workflow.py

```python
#!/usr/bin/env python3
"""
Complete end-to-end installation test with agent verification

This script demonstrates the full workflow:
1. Start VM
2. Capture screenshots at each step
3. Verify visual state
4. Interact with VM
5. Generate report

Designed to be used with Claude Code for visual verification.
"""

import sys
import time
import subprocess
from pathlib import Path

def main():
    vm_name = "keystone-test-vm"

    print("Starting Keystone Installation Test Workflow")
    print("=" * 60)

    # Step 1: Create and start VM
    print("\n[1/6] Creating VM...")
    subprocess.run([
        './bin/virtual-machine',
        '--name', vm_name,
        '--start'
    ], check=True)

    # Wait for boot
    print("Waiting for VM to boot (30s)...")
    time.sleep(30)

    # Step 2: Initialize workflow
    print("\n[2/6] Initializing workflow automation...")
    workflow = AgentVMWorkflow(vm_name)

    # Step 3: Run verification workflow
    print("\n[3/6] Running installation verification...")
    results = workflow.run_full_workflow()

    # Step 4: Generate report
    print("\n[4/6] Generating verification report...")
    report_path = Path("installation_verification_report.md")

    with open(report_path, 'w') as f:
        f.write("# Keystone Installation Verification Report\n\n")
        f.write(f"VM: {vm_name}\n\n")
        f.write("## Workflow Steps\n\n")

        for name, success, screenshot in results:
            status = "✅ PASSED" if success else "❌ FAILED"
            f.write(f"### {name}\n\n")
            f.write(f"Status: {status}\n\n")
            if screenshot:
                f.write(f"Screenshot: `{screenshot}`\n\n")
                f.write(f"![{name}]({screenshot})\n\n")

        f.write("\n## Agent Verification\n\n")
        f.write("The following screenshots should be reviewed by Claude Code:\n\n")
        for name, success, screenshot in results:
            f.write(f"- [ ] {name}: `{screenshot}`\n")

    print(f"✓ Report saved: {report_path}")

    # Step 5: Display next steps
    print("\n[5/6] Next steps for Claude Code agent:")
    print("  1. Use Read tool to view each screenshot in workflow_screenshots/")
    print("  2. Verify each step matches expected state")
    print("  3. Report any issues or unexpected states")
    print(f"  4. Review complete report: {report_path}")

    # Step 6: Summary
    print("\n[6/6] Test Summary:")
    passed = sum(1 for _, success, _ in results if success)
    total = len(results)
    print(f"  Passed: {passed}/{total}")
    print(f"  Screenshots: {workflow.screenshot_dir}/")
    print(f"  Report: {report_path}")

    return 0 if passed == total else 1

if __name__ == "__main__":
    sys.exit(main())
```

### Usage

```bash
# Run complete test workflow
./test_installation_workflow.py

# Claude Code agent then reviews screenshots
# Agent uses Read tool on each image for verification
```

## Summary: Agent Capabilities

### What Claude Code Can Do

1. **View Screenshots** - Read tool displays PNG images visually
2. **Analyze Content** - Recognize text, UI elements, states
3. **Verify Workflows** - Confirm expected screens appear
4. **Make Decisions** - Determine next actions based on visual state
5. **Generate Reports** - Document findings with image references
6. **Detect Issues** - Identify errors, warnings, unexpected states

### Recommended Workflow

```
┌─────────────────────────────────────────────────────────────┐
│ 1. Script captures screenshots during VM operation          │
└──────────────────────────┬──────────────────────────────────┘
                           │
┌──────────────────────────▼──────────────────────────────────┐
│ 2. Screenshots saved to designated directory                │
└──────────────────────────┬──────────────────────────────────┘
                           │
┌──────────────────────────▼──────────────────────────────────┐
│ 3. Claude Code uses Read tool to view each screenshot       │
└──────────────────────────┬──────────────────────────────────┘
                           │
┌──────────────────────────▼──────────────────────────────────┐
│ 4. Agent analyzes and verifies expected state               │
└──────────────────────────┬──────────────────────────────────┘
                           │
┌──────────────────────────▼──────────────────────────────────┐
│ 5. Agent decides: proceed, retry, or report issue           │
└──────────────────────────┬──────────────────────────────────┘
                           │
┌──────────────────────────▼──────────────────────────────────┐
│ 6. Next command sent to VM, loop continues                  │
└─────────────────────────────────────────────────────────────┘
```

## Future Enhancements

### Potential Improvements

1. **Real-time Screenshot Streaming**
   - Continuous monitoring vs. polling
   - WebSocket-based screenshot feed

2. **OCR Integration**
   - Tesseract for text extraction
   - Structured data extraction from screenshots

3. **Mouse Input Support**
   - Click coordinates
   - Drag and drop operations

4. **Video Recording**
   - Full session recording
   - Automated replay for debugging

5. **Multi-VM Orchestration**
   - Test interactions between VMs
   - Network service verification

6. **AI-Driven Test Generation**
   - Agent generates test scenarios
   - Learns from previous runs

## References

- libvirt Python API: https://libvirt.org/python.html
- virsh screenshot documentation: `man virsh`
- QEMU Monitor Protocol: https://wiki.qemu.org/Documentation/QMP
- Linux Input Event Codes: `/usr/include/linux/input-event-codes.h`
- SPICE Protocol: https://www.spice-space.org/
- VNC Protocol: https://github.com/sibson/vncdotool

## Contributing

To add new workflow verification steps:

1. Extend `AgentVMWorkflow` class with new methods
2. Add verification prompts for agent analysis
3. Update workflow sequence in `run_full_workflow()`
4. Test with actual VM and review screenshots
5. Update this documentation with examples
