#!/usr/bin/env bash
set -euo pipefail

echo "🔍 Keystone USB Installer Validation Script"
echo "==========================================="

# Function to check if a file exists and contains expected content
check_file() {
    local file="$1"
    local content="$2"
    local description="$3"
    
    if [[ -f "$file" ]]; then
        if grep -q "$content" "$file"; then
            echo "✅ $description"
            return 0
        else
            echo "❌ $description - content missing"
            return 1
        fi
    else
        echo "❌ $description - file missing"
        return 1
    fi
}

echo ""
echo "📁 Checking file structure..."
passed=0
total=0

# Check main flake
((total++)) && check_file "flake.nix" "nixosConfigurations" "Main flake.nix has NixOS configurations" && ((passed++)) || true
((total++)) && check_file "flake.nix" "iso-installer" "Main flake.nix defines iso-installer" && ((passed++)) || true

# Check ISO module
((total++)) && check_file "modules/iso-installer.nix" "services.openssh" "ISO module enables SSH" && ((passed++)) || true
((total++)) && check_file "modules/iso-installer.nix" "sshKeys" "ISO module accepts SSH keys parameter" && ((passed++)) || true
((total++)) && check_file "modules/iso-installer.nix" "nixos-anywhere" "ISO module mentions nixos-anywhere compatibility" && ((passed++)) || true

# Check example
((total++)) && check_file "examples/iso-installer/flake.nix" "exampleSshKeys" "Example flake has SSH keys placeholder" && ((passed++)) || true
((total++)) && check_file "examples/iso-installer/flake.nix" "keystone.url" "Example flake references main keystone flake" && ((passed++)) || true
((total++)) && check_file "examples/iso-installer/README.md" "nixos-anywhere" "Example README mentions nixos-anywhere" && ((passed++)) || true

# Check GitHub Actions
((total++)) && check_file ".github/workflows/test-iso.yml" "nix flake check" "GitHub Actions includes flake validation" && ((passed++)) || true
((total++)) && check_file ".github/workflows/test-iso.yml" "examples/iso-installer" "GitHub Actions tests example" && ((passed++)) || true

# Check documentation
((total++)) && check_file "README.md" "USB Installer" "Main README documents USB installer feature" && ((passed++)) || true

echo ""
echo "🧪 Checking configuration structure..."

# Validate that the SSH key parameter is properly threaded through
((total++)) && if grep -q "_module.args.sshKeys" examples/iso-installer/flake.nix; then
    echo "✅ SSH keys are properly passed to configuration"
    ((passed++))
else
    echo "❌ SSH keys parameter not properly threaded"
fi

# Check for essential nixos-anywhere tools
((total++)) && if grep -q "parted\|cryptsetup\|util-linux" modules/iso-installer.nix; then
    echo "✅ Essential installation tools included"
    ((passed++))
else
    echo "❌ Missing essential installation tools"
fi

# Check for network configuration
((total++)) && if grep -q "dhcpcd\|networking" modules/iso-installer.nix; then
    echo "✅ Network configuration present"
    ((passed++))
else
    echo "❌ Missing network configuration"
fi

echo ""
echo "📦 Checking package structure..."

# Check that ISO package is defined
((total++)) && if grep -q "iso.*=.*nixosConfigurations.*isoImage" flake.nix; then
    echo "✅ ISO package output defined"
    ((passed++))
else
    echo "❌ ISO package output missing"
fi

# Check for convenience script
((total++)) && if grep -q "write-usb" examples/iso-installer/flake.nix; then
    echo "✅ USB writing convenience script provided"
    ((passed++))
else
    echo "❌ USB writing script missing"
fi

echo ""
echo "🔐 Checking security configuration..."

# Check SSH security settings
((total++)) && if grep -q "PasswordAuthentication = false" modules/iso-installer.nix; then
    echo "✅ Password authentication disabled"
    ((passed++))
else
    echo "❌ Password authentication not properly disabled"
fi

((total++)) && if grep -q "PubkeyAuthentication = true" modules/iso-installer.nix; then
    echo "✅ Public key authentication enabled"
    ((passed++))
else
    echo "❌ Public key authentication not enabled"
fi

echo ""
echo "🎯 Validation Summary"
echo "===================="

# Count files
total_files=(
    "flake.nix"
    "modules/iso-installer.nix" 
    "examples/iso-installer/flake.nix"
    "examples/iso-installer/README.md"
    ".github/workflows/test-iso.yml"
    ".gitignore"
)

existing_files=0
for file in "${total_files[@]}"; do
    if [[ -f "$file" ]]; then
        ((existing_files++))
    fi
done

echo "📊 Files created: $existing_files/${#total_files[@]}"
echo "📊 Checks passed: $passed/$total"

if [[ $existing_files -eq ${#total_files[@]} ]] && [[ $passed -eq $total ]]; then
    echo "🎉 All validation checks passed!"
    echo ""
    echo "🚀 Ready to use! Next steps:"
    echo "  1. Edit examples/iso-installer/flake.nix with your SSH keys"
    echo "  2. Run: cd examples/iso-installer && nix build .#iso"
    echo "  3. Write to USB: nix run .#write-usb /dev/sdX"
    echo "  4. Boot and install with: nixos-anywhere --flake .#config root@<ip>"
    exit 0
else
    echo "⚠️  Some checks failed. Please review the implementation."
    exit 1
fi