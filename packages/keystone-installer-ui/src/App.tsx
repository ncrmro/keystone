import React, { useState, useEffect, useCallback } from 'react';
import { Box, Text, useInput, useApp } from 'ink';
import Spinner from 'ink-spinner';
import SelectInput from 'ink-select-input';
import TextInput from 'ink-text-input';
import {
  hasEthernetConnection,
  scanWiFiNetworks,
  connectToWiFi,
  getCurrentIPAddress,
  getNetworkInterfaces,
} from './network.js';
import {
  BlockDevice,
  InstallationMethod,
  EncryptionChoice,
  SystemType,
  FileOperation,
  InstallationProgress,
  DEV_MODE,
} from './types.js';
import { detectDisks, hasTPM2, validateDisk } from './disk.js';
import { validateHostname, validateUsername } from './config-generator.js';
import {
  runInstallation,
  cloneRepository,
  scanForHosts,
  validateGitUrl,
  getInstallationSummary,
} from './installation.js';

// ============================================================================
// Screen Types
// ============================================================================

type Screen =
  // Network setup screens (existing)
  | 'checking'
  | 'ethernet-connected'
  | 'wifi-setup'
  | 'wifi-scanning'
  | 'wifi-list'
  | 'wifi-password'
  | 'wifi-connecting'
  | 'wifi-connected'
  | 'wifi-failed'
  // Method selection
  | 'method-selection'
  // Disk selection (local installation)
  | 'disk-selection'
  | 'disk-confirmation'
  | 'encryption-choice'
  | 'tpm-warning'
  // Host configuration
  | 'hostname-input'
  | 'username-input'
  | 'password-input'
  | 'password-confirm'
  | 'system-type-selection'
  // Clone from repository
  | 'repository-url'
  | 'repository-cloning'
  | 'host-selection'
  // Installation
  | 'installing'
  | 'summary'
  | 'complete'
  | 'error';

// ============================================================================
// Select Item Interface
// ============================================================================

interface SelectItem {
  label: string;
  value: string;
}

// ============================================================================
// Main App Component
// ============================================================================

const App: React.FC = () => {
  const { exit } = useApp();

  // Network state
  const [screen, setScreen] = useState<Screen>('checking');
  const [ipAddress, setIpAddress] = useState<string | null>(null);
  const [wifiNetworks, setWifiNetworks] = useState<string[]>([]);
  const [selectedNetwork, setSelectedNetwork] = useState<string>('');
  const [wifiPassword, setWifiPassword] = useState<string>('');
  const [errorMessage, setErrorMessage] = useState<string>('');

  // Installation method state
  const [selectedMethod, setSelectedMethod] = useState<InstallationMethod | null>(null);

  // Disk selection state
  const [disks, setDisks] = useState<BlockDevice[]>([]);
  const [selectedDisk, setSelectedDisk] = useState<BlockDevice | null>(null);
  const [encryptionChoice, setEncryptionChoice] = useState<EncryptionChoice | null>(null);

  // Host configuration state
  const [hostname, setHostname] = useState<string>('');
  const [hostnameError, setHostnameError] = useState<string>('');
  const [username, setUsername] = useState<string>('');
  const [usernameError, setUsernameError] = useState<string>('');
  const [password, setPassword] = useState<string>('');
  const [passwordConfirm, setPasswordConfirm] = useState<string>('');
  const [passwordError, setPasswordError] = useState<string>('');
  const [systemType, setSystemType] = useState<SystemType>('server');

  // Repository clone state
  const [repositoryUrl, setRepositoryUrl] = useState<string>('');
  const [repositoryError, setRepositoryError] = useState<string>('');
  const [clonedHosts, setClonedHosts] = useState<string[]>([]);
  const [selectedHost, setSelectedHost] = useState<string>('');

  // Installation progress state
  const [fileOperations, setFileOperations] = useState<FileOperation[]>([]);
  const [installProgress, setInstallProgress] = useState<InstallationProgress | null>(null);
  const [installError, setInstallError] = useState<string>('');

  // Screen history for back navigation
  const [screenHistory, setScreenHistory] = useState<Screen[]>([]);

  // ============================================================================
  // Navigation Helpers
  // ============================================================================

  const navigateTo = useCallback((newScreen: Screen) => {
    setScreenHistory(prev => [...prev, screen]);
    setScreen(newScreen);
  }, [screen]);

  const goBack = useCallback(() => {
    if (screenHistory.length > 0) {
      const prevScreen = screenHistory[screenHistory.length - 1];
      setScreenHistory(prev => prev.slice(0, -1));
      setScreen(prevScreen);
    }
  }, [screenHistory]);

  // Handle Escape key for back navigation
  useInput((input, key) => {
    if (key.escape && screenHistory.length > 0) {
      // Don't allow going back during installation
      if (!['installing', 'complete'].includes(screen)) {
        goBack();
      }
    }
  });

  // ============================================================================
  // Network Check Effect
  // ============================================================================

  useEffect(() => {
    const checkNetwork = async () => {
      await new Promise(resolve => setTimeout(resolve, 2000));

      if (hasEthernetConnection()) {
        const ip = getCurrentIPAddress();
        setIpAddress(ip);
        setScreen('ethernet-connected');
      } else {
        setScreen('wifi-setup');
      }
    };

    checkNetwork();
  }, []);

  // ============================================================================
  // WiFi Scanning Effect
  // ============================================================================

  useEffect(() => {
    if (screen === 'wifi-scanning') {
      const scan = async () => {
        const networks = scanWiFiNetworks();
        if (networks.length > 0) {
          setWifiNetworks(networks);
          setScreen('wifi-list');
        } else {
          setErrorMessage('No WiFi networks found. Please try again.');
          setScreen('wifi-setup');
        }
      };
      scan();
    }
  }, [screen]);

  // ============================================================================
  // Disk Detection Effect
  // ============================================================================

  useEffect(() => {
    if (screen === 'disk-selection') {
      const detectedDisks = detectDisks();
      setDisks(detectedDisks);
    }
  }, [screen]);

  // ============================================================================
  // Repository Cloning Effect
  // ============================================================================

  useEffect(() => {
    if (screen === 'repository-cloning') {
      const clone = async () => {
        const destPath = DEV_MODE ? '/tmp/keystone-dev/cloned-config' : '/tmp/nixos-config-clone';
        const result = await cloneRepository(repositoryUrl, destPath, (op) => {
          setFileOperations(prev => [...prev, op]);
        });

        if (result.success) {
          setClonedHosts(result.hosts);
          if (result.hosts.length === 0) {
            setRepositoryError('No host configurations found in repository. Check that hosts/ directory exists.');
            setScreen('repository-url');
          } else {
            navigateTo('host-selection');
          }
        } else {
          setRepositoryError(result.error || 'Clone failed');
          setScreen('repository-url');
        }
      };
      clone();
    }
  }, [screen, repositoryUrl, navigateTo]);

  // ============================================================================
  // Event Handlers
  // ============================================================================

  const handleStartWiFiSetup = () => {
    setScreen('wifi-scanning');
  };

  const handleSelectWiFiNetwork = (item: SelectItem) => {
    setSelectedNetwork(item.value);
    setScreen('wifi-password');
  };

  const handleWiFiPasswordSubmit = async () => {
    setScreen('wifi-connecting');

    const success = connectToWiFi(selectedNetwork, wifiPassword);

    if (success) {
      await new Promise(resolve => setTimeout(resolve, 3000));

      const ip = getCurrentIPAddress();
      if (ip) {
        setIpAddress(ip);
        setScreen('wifi-connected');
      } else {
        setErrorMessage('Connected but no IP address obtained. Please check your network settings.');
        setScreen('wifi-failed');
      }
    } else {
      setErrorMessage('Failed to connect to WiFi. Please check your password and try again.');
      setScreen('wifi-failed');
    }
  };

  const handleRetryWiFi = () => {
    setWifiPassword('');
    setSelectedNetwork('');
    setErrorMessage('');
    setScreen('wifi-setup');
  };

  const handleContinueToMethodSelection = () => {
    navigateTo('method-selection');
  };

  const handleMethodSelect = (item: SelectItem) => {
    if (item.value === 'remote') {
      // Stay on current screen showing SSH command
      setSelectedMethod({ type: 'remote', description: 'SSH installation via nixos-anywhere' });
    } else if (item.value === 'local') {
      setSelectedMethod({ type: 'local', description: 'Local installation' });
      navigateTo('disk-selection');
    } else if (item.value === 'clone') {
      setSelectedMethod({ type: 'clone', repositoryUrl: '', description: 'Clone from repository' });
      navigateTo('repository-url');
    }
  };

  const handleDiskSelect = (item: SelectItem) => {
    const disk = disks.find(d => d.name === item.value);
    if (disk) {
      const validation = validateDisk(disk);
      if (validation.success) {
        setSelectedDisk(disk);
        navigateTo('disk-confirmation');
      } else {
        setErrorMessage(validation.error || 'Invalid disk selection');
      }
    }
  };

  const handleDiskConfirm = (confirmed: boolean) => {
    if (confirmed) {
      navigateTo('encryption-choice');
    } else {
      goBack();
    }
  };

  const handleEncryptionSelect = (item: SelectItem) => {
    const encrypted = item.value === 'encrypted';

    if (encrypted) {
      const tpmAvailable = hasTPM2();
      if (!tpmAvailable) {
        setEncryptionChoice({
          encrypted: true,
          tpm2Available: false,
          passwordFallbackAcknowledged: false
        });
        navigateTo('tpm-warning');
        return;
      }
      setEncryptionChoice({
        encrypted: true,
        tpm2Available: true,
        passwordFallbackAcknowledged: false
      });
    } else {
      setEncryptionChoice({
        encrypted: false,
        tpm2Available: false,
        passwordFallbackAcknowledged: false
      });
    }
    navigateTo('hostname-input');
  };

  const handleTpmWarningAcknowledge = () => {
    setEncryptionChoice(prev => prev ? {
      ...prev,
      passwordFallbackAcknowledged: true
    } : null);
    navigateTo('hostname-input');
  };

  const handleHostnameSubmit = () => {
    const validation = validateHostname(hostname);
    if (!validation.valid) {
      setHostnameError(validation.error || 'Invalid hostname');
      return;
    }
    setHostnameError('');
    navigateTo('username-input');
  };

  const handleUsernameSubmit = () => {
    const validation = validateUsername(username);
    if (!validation.valid) {
      setUsernameError(validation.error || 'Invalid username');
      return;
    }
    setUsernameError('');
    navigateTo('password-input');
  };

  const handlePasswordSubmit = () => {
    if (!password) {
      setPasswordError('Password is required');
      return;
    }
    setPasswordError('');
    navigateTo('password-confirm');
  };

  const handlePasswordConfirmSubmit = () => {
    if (password !== passwordConfirm) {
      setPasswordError('Passwords do not match');
      return;
    }
    setPasswordError('');
    navigateTo('system-type-selection');
  };

  const handleSystemTypeSelect = (item: SelectItem) => {
    setSystemType(item.value as SystemType);
    navigateTo('summary');
  };

  const handleRepositoryUrlSubmit = () => {
    const validation = validateGitUrl(repositoryUrl);
    if (!validation.valid) {
      setRepositoryError(validation.error || 'Invalid URL');
      return;
    }
    setRepositoryError('');
    navigateTo('repository-cloning');
  };

  const handleHostSelect = (item: SelectItem) => {
    setSelectedHost(item.value);
    setHostname(item.value);
    // For clone method, skip to summary
    navigateTo('summary');
  };

  const handleStartInstallation = async () => {
    navigateTo('installing');

    const config = {
      hostname,
      username,
      password,
      diskDevice: selectedDisk?.byIdPath || `/dev/${selectedDisk?.name}` || '',
      encrypted: encryptionChoice?.encrypted || false,
      systemType,
      swapSize: '8G'
    };

    const result = await runInstallation(
      config,
      (progress) => setInstallProgress(progress),
      (op) => setFileOperations(prev => [...prev, op])
    );

    if (result.success) {
      navigateTo('complete');
    } else {
      setInstallError(result.error?.message || 'Installation failed');
      navigateTo('error');
    }
  };

  const handleReboot = () => {
    if (!DEV_MODE) {
      try {
        require('child_process').execSync('reboot', { encoding: 'utf-8' });
      } catch {
        // Ignore errors
      }
    }
    exit();
  };

  // ============================================================================
  // Render Functions
  // ============================================================================

  const renderHeader = (subtitle?: string) => (
    <Box marginBottom={1}>
      <Text bold color="cyan">Keystone Installer</Text>
      {subtitle && <Text dimColor> - {subtitle}</Text>}
      {DEV_MODE && <Text color="yellow"> [DEV MODE]</Text>}
    </Box>
  );

  const renderBackHint = () => (
    screenHistory.length > 0 && !['installing', 'complete'].includes(screen) ? (
      <Box marginTop={1}>
        <Text dimColor>Press Escape to go back</Text>
      </Box>
    ) : null
  );

  // ============================================================================
  // Screen: Checking Network
  // ============================================================================

  if (screen === 'checking') {
    return (
      <Box flexDirection="column" padding={1}>
        {renderHeader()}
        <Box>
          <Text color="green">
            <Spinner type="dots" />
          </Text>
          <Text> Checking network connectivity...</Text>
        </Box>
      </Box>
    );
  }

  // ============================================================================
  // Screen: Ethernet Connected
  // ============================================================================

  if (screen === 'ethernet-connected') {
    const interfaces = getNetworkInterfaces();

    return (
      <Box flexDirection="column" padding={1}>
        {renderHeader()}
        <Box marginBottom={1}>
          <Text color="green">✓ Network Connected</Text>
        </Box>
        <Box flexDirection="column" marginBottom={1}>
          {interfaces.map(iface => (
            <Box key={iface.name}>
              <Text>
                Interface: <Text bold>{iface.name}</Text> - IP: <Text bold color="yellow">{iface.ipAddress}</Text>
              </Text>
            </Box>
          ))}
        </Box>
        <Box marginTop={1}>
          <SelectInput
            items={[
              { label: 'Continue to Installation →', value: 'continue' }
            ]}
            onSelect={() => handleContinueToMethodSelection()}
          />
        </Box>
      </Box>
    );
  }

  // ============================================================================
  // Screen: WiFi Setup
  // ============================================================================

  if (screen === 'wifi-setup') {
    return (
      <Box flexDirection="column" padding={1}>
        {renderHeader('WiFi Setup')}
        <Box marginBottom={1}>
          <Text color="yellow">⚠ No Ethernet connection detected</Text>
        </Box>
        {errorMessage && (
          <Box marginBottom={1}>
            <Text color="red">{errorMessage}</Text>
          </Box>
        )}
        <Box marginBottom={1}>
          <Text>Would you like to set up WiFi?</Text>
        </Box>
        <SelectInput
          items={[
            { label: 'Yes, scan for WiFi networks', value: 'scan' },
            { label: "No, I'll configure manually", value: 'skip' },
          ]}
          onSelect={(item: SelectItem) => {
            if (item.value === 'scan') {
              handleStartWiFiSetup();
            } else {
              setScreen('ethernet-connected');
            }
          }}
        />
      </Box>
    );
  }

  // ============================================================================
  // Screen: WiFi Scanning
  // ============================================================================

  if (screen === 'wifi-scanning') {
    return (
      <Box flexDirection="column" padding={1}>
        {renderHeader('WiFi Setup')}
        <Box>
          <Text color="green">
            <Spinner type="dots" />
          </Text>
          <Text> Scanning for WiFi networks...</Text>
        </Box>
      </Box>
    );
  }

  // ============================================================================
  // Screen: WiFi List
  // ============================================================================

  if (screen === 'wifi-list') {
    const items: SelectItem[] = wifiNetworks.map(network => ({
      label: network,
      value: network,
    }));

    return (
      <Box flexDirection="column" padding={1}>
        {renderHeader('WiFi Setup')}
        <Box marginBottom={1}>
          <Text>Select a WiFi network:</Text>
        </Box>
        <SelectInput items={items} onSelect={handleSelectWiFiNetwork} />
        {renderBackHint()}
      </Box>
    );
  }

  // ============================================================================
  // Screen: WiFi Password
  // ============================================================================

  if (screen === 'wifi-password') {
    return (
      <Box flexDirection="column" padding={1}>
        {renderHeader('WiFi Setup')}
        <Box marginBottom={1}>
          <Text>Network: <Text bold>{selectedNetwork}</Text></Text>
        </Box>
        <Box marginBottom={1}>
          <Text>Enter password (press Enter when done):</Text>
        </Box>
        <Box>
          <Text color="green">&gt; </Text>
          <TextInput
            value={wifiPassword}
            onChange={setWifiPassword}
            onSubmit={handleWiFiPasswordSubmit}
            mask="*"
          />
        </Box>
        {renderBackHint()}
      </Box>
    );
  }

  // ============================================================================
  // Screen: WiFi Connecting
  // ============================================================================

  if (screen === 'wifi-connecting') {
    return (
      <Box flexDirection="column" padding={1}>
        {renderHeader('WiFi Setup')}
        <Box>
          <Text color="green">
            <Spinner type="dots" />
          </Text>
          <Text> Connecting to {selectedNetwork}...</Text>
        </Box>
      </Box>
    );
  }

  // ============================================================================
  // Screen: WiFi Connected
  // ============================================================================

  if (screen === 'wifi-connected') {
    const interfaces = getNetworkInterfaces();

    return (
      <Box flexDirection="column" padding={1}>
        {renderHeader()}
        <Box marginBottom={1}>
          <Text color="green">✓ WiFi Connected to {selectedNetwork}</Text>
        </Box>
        <Box flexDirection="column" marginBottom={1}>
          {interfaces.map(iface => (
            <Box key={iface.name}>
              <Text>
                Interface: <Text bold>{iface.name}</Text> - IP: <Text bold color="yellow">{iface.ipAddress}</Text>
              </Text>
            </Box>
          ))}
        </Box>
        <Box marginTop={1}>
          <SelectInput
            items={[
              { label: 'Continue to Installation →', value: 'continue' }
            ]}
            onSelect={() => handleContinueToMethodSelection()}
          />
        </Box>
      </Box>
    );
  }

  // ============================================================================
  // Screen: WiFi Failed
  // ============================================================================

  if (screen === 'wifi-failed') {
    return (
      <Box flexDirection="column" padding={1}>
        {renderHeader('WiFi Setup')}
        <Box marginBottom={1}>
          <Text color="red">✗ Connection Failed</Text>
        </Box>
        <Box marginBottom={1}>
          <Text>{errorMessage}</Text>
        </Box>
        <SelectInput
          items={[
            { label: 'Try again', value: 'retry' },
            { label: 'Skip WiFi setup', value: 'skip' },
          ]}
          onSelect={(item: SelectItem) => {
            if (item.value === 'retry') {
              handleRetryWiFi();
            } else {
              setScreen('ethernet-connected');
            }
          }}
        />
      </Box>
    );
  }

  // ============================================================================
  // Screen: Method Selection
  // ============================================================================

  if (screen === 'method-selection') {
    return (
      <Box flexDirection="column" padding={1}>
        {renderHeader('Installation Method')}
        <Box marginBottom={1}>
          <Text>How would you like to install NixOS?</Text>
        </Box>
        <SelectInput
          items={[
            { label: '🖥️  Remote via SSH (nixos-anywhere)', value: 'remote' },
            { label: '💻 Local installation (on this machine)', value: 'local' },
            { label: '📦 Clone from existing repository', value: 'clone' },
          ]}
          onSelect={handleMethodSelect}
        />
        <Box marginTop={1} flexDirection="column">
          <Text dimColor>Remote: Run nixos-anywhere from another machine</Text>
          <Text dimColor>Local: Install directly on this machine</Text>
          <Text dimColor>Clone: Use an existing NixOS configuration</Text>
        </Box>
        {selectedMethod?.type === 'remote' && (
          <Box marginTop={1} flexDirection="column" borderStyle="round" borderColor="cyan" padding={1}>
            <Text bold>Ready for Remote Installation</Text>
            <Text dimColor>From your deployment machine, run:</Text>
            <Text color="yellow">{`nixos-anywhere --flake .#your-config root@${ipAddress}`}</Text>
          </Box>
        )}
        {renderBackHint()}
      </Box>
    );
  }

  // ============================================================================
  // Screen: Disk Selection
  // ============================================================================

  if (screen === 'disk-selection') {
    if (disks.length === 0) {
      return (
        <Box flexDirection="column" padding={1}>
          {renderHeader('Disk Selection')}
          <Box marginBottom={1}>
            <Text color="red">✗ No suitable disks found</Text>
          </Box>
          <Text dimColor>Please check that your storage device is connected and detected.</Text>
          <Text dimColor>Disks must be at least 8GB in size.</Text>
          <SelectInput
            items={[
              { label: 'Refresh disk list', value: 'refresh' },
              { label: 'Go back', value: 'back' },
            ]}
            onSelect={(item) => {
              if (item.value === 'refresh') {
                setDisks(detectDisks());
              } else {
                goBack();
              }
            }}
          />
        </Box>
      );
    }

    const diskItems: SelectItem[] = disks.map(disk => ({
      label: `${disk.hasData ? '⚠️ ' : ''}${disk.name} - ${disk.sizeHuman}${disk.model ? ` (${disk.model})` : ''}`,
      value: disk.name,
    }));

    return (
      <Box flexDirection="column" padding={1}>
        {renderHeader('Disk Selection')}
        <Box marginBottom={1}>
          <Text>Select a disk for installation:</Text>
        </Box>
        {errorMessage && (
          <Box marginBottom={1}>
            <Text color="red">{errorMessage}</Text>
          </Box>
        )}
        <SelectInput items={diskItems} onSelect={handleDiskSelect} />
        <Box marginTop={1}>
          <Text dimColor>⚠️ = Disk contains existing data (will be erased)</Text>
        </Box>
        {renderBackHint()}
      </Box>
    );
  }

  // ============================================================================
  // Screen: Disk Confirmation
  // ============================================================================

  if (screen === 'disk-confirmation') {
    return (
      <Box flexDirection="column" padding={1}>
        {renderHeader('Confirm Disk Selection')}
        <Box marginBottom={1} borderStyle="round" borderColor="red" padding={1}>
          <Text color="red" bold>⚠️ WARNING: ALL DATA WILL BE ERASED</Text>
        </Box>
        <Box flexDirection="column" marginBottom={1}>
          <Text>Selected disk: <Text bold>{selectedDisk?.name}</Text></Text>
          <Text>Size: <Text bold>{selectedDisk?.sizeHuman}</Text></Text>
          {selectedDisk?.model && <Text>Model: <Text bold>{selectedDisk.model}</Text></Text>}
          {selectedDisk?.byIdPath && <Text dimColor>Path: {selectedDisk.byIdPath}</Text>}
        </Box>
        <SelectInput
          items={[
            { label: '✓ Yes, erase this disk and continue', value: 'yes' },
            { label: '✗ No, go back and select a different disk', value: 'no' },
          ]}
          onSelect={(item) => handleDiskConfirm(item.value === 'yes')}
        />
      </Box>
    );
  }

  // ============================================================================
  // Screen: Encryption Choice
  // ============================================================================

  if (screen === 'encryption-choice') {
    return (
      <Box flexDirection="column" padding={1}>
        {renderHeader('Encryption')}
        <Box marginBottom={1}>
          <Text>Choose disk encryption option:</Text>
        </Box>
        <SelectInput
          items={[
            { label: '🔒 Encrypted (ZFS + LUKS + TPM2) - Recommended', value: 'encrypted' },
            { label: '🔓 Unencrypted (ext4) - Simple', value: 'unencrypted' },
          ]}
          onSelect={handleEncryptionSelect}
        />
        <Box marginTop={1} flexDirection="column">
          <Text dimColor>Encrypted: Full disk encryption with automatic TPM2 unlock</Text>
          <Text dimColor>Unencrypted: Faster, simpler, suitable for testing</Text>
        </Box>
        {renderBackHint()}
      </Box>
    );
  }

  // ============================================================================
  // Screen: TPM Warning
  // ============================================================================

  if (screen === 'tpm-warning') {
    return (
      <Box flexDirection="column" padding={1}>
        {renderHeader('TPM2 Not Available')}
        <Box marginBottom={1} borderStyle="round" borderColor="yellow" padding={1}>
          <Text color="yellow">⚠️ TPM2 device not detected</Text>
        </Box>
        <Box flexDirection="column" marginBottom={1}>
          <Text>Your system does not have a TPM2 device available.</Text>
          <Text>Encryption will still work, but you will need to enter</Text>
          <Text>a password on every boot to unlock the disk.</Text>
        </Box>
        <SelectInput
          items={[
            { label: '✓ I understand, continue with encryption', value: 'continue' },
            { label: '← Go back and choose unencrypted', value: 'back' },
          ]}
          onSelect={(item) => {
            if (item.value === 'continue') {
              handleTpmWarningAcknowledge();
            } else {
              goBack();
            }
          }}
        />
      </Box>
    );
  }

  // ============================================================================
  // Screen: Hostname Input
  // ============================================================================

  if (screen === 'hostname-input') {
    return (
      <Box flexDirection="column" padding={1}>
        {renderHeader('Hostname')}
        <Box marginBottom={1}>
          <Text>Enter a hostname for this machine:</Text>
        </Box>
        {hostnameError && (
          <Box marginBottom={1}>
            <Text color="red">{hostnameError}</Text>
          </Box>
        )}
        <Box>
          <Text color="green">&gt; </Text>
          <TextInput
            value={hostname}
            onChange={(value) => {
              setHostname(value.toLowerCase());
              setHostnameError('');
            }}
            onSubmit={handleHostnameSubmit}
            placeholder="my-server"
          />
        </Box>
        <Box marginTop={1}>
          <Text dimColor>Letters, numbers, and hyphens only (e.g., my-server)</Text>
        </Box>
        {renderBackHint()}
      </Box>
    );
  }

  // ============================================================================
  // Screen: Username Input
  // ============================================================================

  if (screen === 'username-input') {
    return (
      <Box flexDirection="column" padding={1}>
        {renderHeader('Username')}
        <Box marginBottom={1}>
          <Text>Enter a username for the primary account:</Text>
        </Box>
        {usernameError && (
          <Box marginBottom={1}>
            <Text color="red">{usernameError}</Text>
          </Box>
        )}
        <Box>
          <Text color="green">&gt; </Text>
          <TextInput
            value={username}
            onChange={(value) => {
              setUsername(value.toLowerCase());
              setUsernameError('');
            }}
            onSubmit={handleUsernameSubmit}
            placeholder="user"
          />
        </Box>
        <Box marginTop={1}>
          <Text dimColor>Lowercase letters, numbers, and underscores only</Text>
        </Box>
        {renderBackHint()}
      </Box>
    );
  }

  // ============================================================================
  // Screen: Password Input
  // ============================================================================

  if (screen === 'password-input') {
    return (
      <Box flexDirection="column" padding={1}>
        {renderHeader('Password')}
        <Box marginBottom={1}>
          <Text>Enter a password for {username}:</Text>
        </Box>
        {passwordError && (
          <Box marginBottom={1}>
            <Text color="red">{passwordError}</Text>
          </Box>
        )}
        <Box>
          <Text color="green">&gt; </Text>
          <TextInput
            value={password}
            onChange={(value) => {
              setPassword(value);
              setPasswordError('');
            }}
            onSubmit={handlePasswordSubmit}
            mask="*"
          />
        </Box>
        {renderBackHint()}
      </Box>
    );
  }

  // ============================================================================
  // Screen: Password Confirm
  // ============================================================================

  if (screen === 'password-confirm') {
    return (
      <Box flexDirection="column" padding={1}>
        {renderHeader('Confirm Password')}
        <Box marginBottom={1}>
          <Text>Confirm password for {username}:</Text>
        </Box>
        {passwordError && (
          <Box marginBottom={1}>
            <Text color="red">{passwordError}</Text>
          </Box>
        )}
        <Box>
          <Text color="green">&gt; </Text>
          <TextInput
            value={passwordConfirm}
            onChange={(value) => {
              setPasswordConfirm(value);
              setPasswordError('');
            }}
            onSubmit={handlePasswordConfirmSubmit}
            mask="*"
          />
        </Box>
        {renderBackHint()}
      </Box>
    );
  }

  // ============================================================================
  // Screen: System Type Selection
  // ============================================================================

  if (screen === 'system-type-selection') {
    return (
      <Box flexDirection="column" padding={1}>
        {renderHeader('System Type')}
        <Box marginBottom={1}>
          <Text>Select the type of system to install:</Text>
        </Box>
        <SelectInput
          items={[
            { label: '🖥️  Server (headless, infrastructure services)', value: 'server' },
            { label: '🖱️  Client (Hyprland desktop, graphical)', value: 'client' },
          ]}
          onSelect={handleSystemTypeSelect}
        />
        <Box marginTop={1} flexDirection="column">
          <Text dimColor>Server: VPN, DNS, storage, and other services</Text>
          <Text dimColor>Client: Desktop workstation with Hyprland</Text>
        </Box>
        {renderBackHint()}
      </Box>
    );
  }

  // ============================================================================
  // Screen: Repository URL
  // ============================================================================

  if (screen === 'repository-url') {
    return (
      <Box flexDirection="column" padding={1}>
        {renderHeader('Clone Repository')}
        <Box marginBottom={1}>
          <Text>Enter the git repository URL:</Text>
        </Box>
        {repositoryError && (
          <Box marginBottom={1}>
            <Text color="red">{repositoryError}</Text>
          </Box>
        )}
        <Box>
          <Text color="green">&gt; </Text>
          <TextInput
            value={repositoryUrl}
            onChange={(value) => {
              setRepositoryUrl(value);
              setRepositoryError('');
            }}
            onSubmit={handleRepositoryUrlSubmit}
            placeholder="https://github.com/user/nixos-config"
          />
        </Box>
        <Box marginTop={1} flexDirection="column">
          <Text dimColor>HTTPS: https://github.com/user/repo</Text>
          <Text dimColor>SSH: git@github.com:user/repo</Text>
        </Box>
        {renderBackHint()}
      </Box>
    );
  }

  // ============================================================================
  // Screen: Repository Cloning
  // ============================================================================

  if (screen === 'repository-cloning') {
    return (
      <Box flexDirection="column" padding={1}>
        {renderHeader('Cloning Repository')}
        <Box>
          <Text color="green">
            <Spinner type="dots" />
          </Text>
          <Text> Cloning {repositoryUrl}...</Text>
        </Box>
      </Box>
    );
  }

  // ============================================================================
  // Screen: Host Selection
  // ============================================================================

  if (screen === 'host-selection') {
    const hostItems: SelectItem[] = clonedHosts.map(host => ({
      label: host,
      value: host,
    }));

    return (
      <Box flexDirection="column" padding={1}>
        {renderHeader('Select Host')}
        <Box marginBottom={1}>
          <Text>Select a host configuration to deploy:</Text>
        </Box>
        <SelectInput items={hostItems} onSelect={handleHostSelect} />
        {renderBackHint()}
      </Box>
    );
  }

  // ============================================================================
  // Screen: Summary
  // ============================================================================

  if (screen === 'summary') {
    return (
      <Box flexDirection="column" padding={1}>
        {renderHeader('Installation Summary')}
        <Box flexDirection="column" marginBottom={1} borderStyle="single" padding={1}>
          <Text>Hostname: <Text bold color="cyan">{hostname}</Text></Text>
          <Text>Username: <Text bold color="cyan">{username}</Text></Text>
          <Text>System Type: <Text bold color="cyan">{systemType}</Text></Text>
          {selectedDisk && (
            <>
              <Text>Disk: <Text bold color="cyan">{selectedDisk.name}</Text> ({selectedDisk.sizeHuman})</Text>
              <Text>Encryption: <Text bold color={encryptionChoice?.encrypted ? 'green' : 'yellow'}>
                {encryptionChoice?.encrypted ? 'ZFS + LUKS' : 'None (ext4)'}
              </Text></Text>
            </>
          )}
          {selectedMethod?.type === 'clone' && (
            <Text>Source: <Text bold color="cyan">Cloned from repository</Text></Text>
          )}
        </Box>
        <SelectInput
          items={[
            { label: '✓ Start Installation', value: 'start' },
            { label: '← Go back and make changes', value: 'back' },
          ]}
          onSelect={(item) => {
            if (item.value === 'start') {
              handleStartInstallation();
            } else {
              goBack();
            }
          }}
        />
      </Box>
    );
  }

  // ============================================================================
  // Screen: Installing
  // ============================================================================

  if (screen === 'installing') {
    return (
      <Box flexDirection="column" padding={1}>
        {renderHeader('Installing')}
        <Box marginBottom={1}>
          <Text color="green">
            <Spinner type="dots" />
          </Text>
          <Text> {installProgress?.currentOperation || 'Starting installation...'}</Text>
        </Box>
        {installProgress && (
          <Box marginBottom={1}>
            <Text>Progress: {installProgress.progress}%</Text>
          </Box>
        )}
        <Box flexDirection="column" marginTop={1}>
          <Text dimColor>Recent operations:</Text>
          {fileOperations.slice(-5).map((op, i) => (
            <Box key={i}>
              <Text color={op.success ? 'green' : 'red'}>
                {op.success ? '✓' : '✗'} {op.action}: {op.purpose}
              </Text>
            </Box>
          ))}
        </Box>
      </Box>
    );
  }

  // ============================================================================
  // Screen: Complete
  // ============================================================================

  if (screen === 'complete') {
    return (
      <Box flexDirection="column" padding={1}>
        {renderHeader('Installation Complete')}
        <Box marginBottom={1}>
          <Text color="green">✓ NixOS has been successfully installed!</Text>
        </Box>
        <Box flexDirection="column" marginBottom={1}>
          <Text>Hostname: <Text bold>{hostname}</Text></Text>
          <Text>Username: <Text bold>{username}</Text></Text>
          <Text>System Type: <Text bold>{systemType}</Text></Text>
        </Box>
        <Box marginBottom={1} borderStyle="round" borderColor="cyan" padding={1}>
          <Text>Configuration saved to: ~/nixos-config/</Text>
        </Box>
        <SelectInput
          items={[
            { label: '🔄 Reboot now', value: 'reboot' },
            { label: '📋 Exit without rebooting', value: 'exit' },
          ]}
          onSelect={(item) => {
            if (item.value === 'reboot') {
              handleReboot();
            } else {
              exit();
            }
          }}
        />
      </Box>
    );
  }

  // ============================================================================
  // Screen: Error
  // ============================================================================

  if (screen === 'error') {
    // Find the last failed operation with output
    const lastFailedOp = fileOperations.filter(op => !op.success).pop();

    return (
      <Box flexDirection="column" padding={1}>
        {renderHeader('Installation Error')}
        <Box marginBottom={1}>
          <Text color="red">✗ Installation failed</Text>
        </Box>
        <Box marginBottom={1} borderStyle="round" borderColor="red" padding={1}>
          <Text>{installError || 'An unknown error occurred'}</Text>
        </Box>
        {lastFailedOp?.output && (
          <Box marginBottom={1} flexDirection="column">
            <Text dimColor>Last output (truncated):</Text>
            <Box borderStyle="single" padding={1}>
              <Text>{lastFailedOp.output.slice(-500)}</Text>
            </Box>
          </Box>
        )}
        <Box marginBottom={1}>
          <Text dimColor>Full log: /tmp/keystone-install.log</Text>
        </Box>
        <SelectInput
          items={[
            { label: '🔄 Try again', value: 'retry' },
            { label: '📋 Exit', value: 'exit' },
          ]}
          onSelect={(item) => {
            if (item.value === 'retry') {
              setInstallError('');
              setFileOperations([]);
              navigateTo('summary');
            } else {
              exit();
            }
          }}
        />
      </Box>
    );
  }

  return null;
};

export default App;
