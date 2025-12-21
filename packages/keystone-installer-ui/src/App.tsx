import React, { useState, useEffect, useCallback } from 'react';
import { Box, Text, useInput, useApp, useStdout } from 'ink';
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
// Theme Colors - Royal Green with Gold accents
// ============================================================================

const theme = {
  // Background
  bg: 'green' as const,
  // Primary text (gold/yellow)
  primary: 'yellow' as const,
  // Bright accent (bright gold)
  accent: 'yellowBright' as const,
  // Success indicator (bright gold on green bg)
  success: 'yellowBright' as const,
  // Warning
  warning: 'yellow' as const,
  // Error (stays red for visibility)
  error: 'red' as const,
  // Dim/secondary text
  dim: 'white' as const,
  // Borders
  border: 'yellow' as const,
  // Input prompt
  prompt: 'yellowBright' as const,
};

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
  const { stdout } = useStdout();

  // Get terminal dimensions for fullscreen layout
  const terminalWidth = stdout?.columns || 80;
  const terminalHeight = stdout?.rows || 24;

  // Fullscreen wrapper component
  const FullScreen: React.FC<{ children: React.ReactNode }> = ({ children }) => (
    <Box
      width={terminalWidth}
      height={terminalHeight}
      flexDirection="column"
      padding={1}
    >
      {children}
    </Box>
  );

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
      <Text bold color={theme.accent}>Keystone Installer</Text>
      {subtitle && <Text color={theme.dim}> - {subtitle}</Text>}
      {DEV_MODE && <Text color={theme.warning}> [DEV MODE]</Text>}
    </Box>
  );

  const renderBackHint = () => (
    screenHistory.length > 0 && !['installing', 'complete'].includes(screen) ? (
      <Box marginTop={1}>
        <Text color={theme.dim}>Press Escape to go back</Text>
      </Box>
    ) : null
  );

  // ============================================================================
  // Screen: Checking Network
  // ============================================================================

  if (screen === 'checking') {
    return (
      <FullScreen>
        {renderHeader()}
        <Box>
          <Text color={theme.accent}>
            <Spinner type="dots" />
          </Text>
          <Text color={theme.primary}> Checking network connectivity...</Text>
        </Box>
      </FullScreen>
    );
  }

  // ============================================================================
  // Screen: Ethernet Connected
  // ============================================================================

  if (screen === 'ethernet-connected') {
    const interfaces = getNetworkInterfaces();

    return (
      <FullScreen>
        {renderHeader()}
        <Box marginBottom={1}>
          <Text color={theme.success}>✓ Network Connected</Text>
        </Box>
        <Box flexDirection="column" marginBottom={1}>
          {interfaces.map(iface => (
            <Box key={iface.name}>
              <Text color={theme.primary}>
                Interface: <Text bold>{iface.name}</Text> - IP: <Text bold color={theme.accent}>{iface.ipAddress}</Text>
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
      </FullScreen>
    );
  }

  // ============================================================================
  // Screen: WiFi Setup
  // ============================================================================

  if (screen === 'wifi-setup') {
    return (
      <FullScreen>
        {renderHeader('WiFi Setup')}
        <Box marginBottom={1}>
          <Text color={theme.warning}>⚠ No Ethernet connection detected</Text>
        </Box>
        {errorMessage && (
          <Box marginBottom={1}>
            <Text color={theme.error}>{errorMessage}</Text>
          </Box>
        )}
        <Box marginBottom={1}>
          <Text color={theme.primary}>Would you like to set up WiFi?</Text>
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
      </FullScreen>
    );
  }

  // ============================================================================
  // Screen: WiFi Scanning
  // ============================================================================

  if (screen === 'wifi-scanning') {
    return (
      <FullScreen>
        {renderHeader('WiFi Setup')}
        <Box>
          <Text color={theme.accent}>
            <Spinner type="dots" />
          </Text>
          <Text color={theme.primary}> Scanning for WiFi networks...</Text>
        </Box>
      </FullScreen>
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
      <FullScreen>
        {renderHeader('WiFi Setup')}
        <Box marginBottom={1}>
          <Text color={theme.primary}>Select a WiFi network:</Text>
        </Box>
        <SelectInput items={items} onSelect={handleSelectWiFiNetwork} />
        {renderBackHint()}
      </FullScreen>
    );
  }

  // ============================================================================
  // Screen: WiFi Password
  // ============================================================================

  if (screen === 'wifi-password') {
    return (
      <FullScreen>
        {renderHeader('WiFi Setup')}
        <Box marginBottom={1}>
          <Text color={theme.primary}>Network: <Text bold color={theme.accent}>{selectedNetwork}</Text></Text>
        </Box>
        <Box marginBottom={1}>
          <Text color={theme.primary}>Enter password (press Enter when done):</Text>
        </Box>
        <Box>
          <Text color={theme.prompt}>&gt; </Text>
          <TextInput
            value={wifiPassword}
            onChange={setWifiPassword}
            onSubmit={handleWiFiPasswordSubmit}
            mask="*"
          />
        </Box>
        {renderBackHint()}
      </FullScreen>
    );
  }

  // ============================================================================
  // Screen: WiFi Connecting
  // ============================================================================

  if (screen === 'wifi-connecting') {
    return (
      <FullScreen>
        {renderHeader('WiFi Setup')}
        <Box>
          <Text color={theme.accent}>
            <Spinner type="dots" />
          </Text>
          <Text color={theme.primary}> Connecting to {selectedNetwork}...</Text>
        </Box>
      </FullScreen>
    );
  }

  // ============================================================================
  // Screen: WiFi Connected
  // ============================================================================

  if (screen === 'wifi-connected') {
    const interfaces = getNetworkInterfaces();

    return (
      <FullScreen>
        {renderHeader()}
        <Box marginBottom={1}>
          <Text color={theme.success}>✓ WiFi Connected to {selectedNetwork}</Text>
        </Box>
        <Box flexDirection="column" marginBottom={1}>
          {interfaces.map(iface => (
            <Box key={iface.name}>
              <Text color={theme.primary}>
                Interface: <Text bold>{iface.name}</Text> - IP: <Text bold color={theme.accent}>{iface.ipAddress}</Text>
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
      </FullScreen>
    );
  }

  // ============================================================================
  // Screen: WiFi Failed
  // ============================================================================

  if (screen === 'wifi-failed') {
    return (
      <FullScreen>
        {renderHeader('WiFi Setup')}
        <Box marginBottom={1}>
          <Text color={theme.error}>✗ Connection Failed</Text>
        </Box>
        <Box marginBottom={1}>
          <Text color={theme.primary}>{errorMessage}</Text>
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
      </FullScreen>
    );
  }

  // ============================================================================
  // Screen: Method Selection
  // ============================================================================

  if (screen === 'method-selection') {
    return (
      <FullScreen>
        {renderHeader('Installation Method')}
        <Box marginBottom={1}>
          <Text color={theme.primary}>How would you like to install NixOS?</Text>
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
          <Text color={theme.dim}>Remote: Run nixos-anywhere from another machine</Text>
          <Text color={theme.dim}>Local: Install directly on this machine</Text>
          <Text color={theme.dim}>Clone: Use an existing NixOS configuration</Text>
        </Box>
        {selectedMethod?.type === 'remote' && (
          <Box marginTop={1} flexDirection="column" borderStyle="round" borderColor={theme.border} padding={1}>
            <Text bold color={theme.accent}>Ready for Remote Installation</Text>
            <Text color={theme.dim}>From your deployment machine, run:</Text>
            <Text color={theme.accent}>{`nixos-anywhere --flake .#your-config root@${ipAddress}`}</Text>
          </Box>
        )}
        {renderBackHint()}
      </FullScreen>
    );
  }

  // ============================================================================
  // Screen: Disk Selection
  // ============================================================================

  if (screen === 'disk-selection') {
    if (disks.length === 0) {
      return (
        <FullScreen>
          {renderHeader('Disk Selection')}
          <Box marginBottom={1}>
            <Text color={theme.error}>✗ No suitable disks found</Text>
          </Box>
          <Text color={theme.dim}>Please check that your storage device is connected and detected.</Text>
          <Text color={theme.dim}>Disks must be at least 8GB in size.</Text>
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
        </FullScreen>
      );
    }

    const diskItems: SelectItem[] = disks.map(disk => ({
      label: `${disk.hasData ? '⚠️ ' : ''}${disk.name} - ${disk.sizeHuman}${disk.model ? ` (${disk.model})` : ''}`,
      value: disk.name,
    }));

    return (
      <FullScreen>
        {renderHeader('Disk Selection')}
        <Box marginBottom={1}>
          <Text color={theme.primary}>Select a disk for installation:</Text>
        </Box>
        {errorMessage && (
          <Box marginBottom={1}>
            <Text color={theme.error}>{errorMessage}</Text>
          </Box>
        )}
        <SelectInput items={diskItems} onSelect={handleDiskSelect} />
        <Box marginTop={1}>
          <Text color={theme.dim}>⚠️ = Disk contains existing data (will be erased)</Text>
        </Box>
        {renderBackHint()}
      </FullScreen>
    );
  }

  // ============================================================================
  // Screen: Disk Confirmation
  // ============================================================================

  if (screen === 'disk-confirmation') {
    return (
      <FullScreen>
        {renderHeader('Confirm Disk Selection')}
        <Box marginBottom={1} borderStyle="round" borderColor={theme.error} padding={1}>
          <Text color={theme.error} bold>⚠️ WARNING: ALL DATA WILL BE ERASED</Text>
        </Box>
        <Box flexDirection="column" marginBottom={1}>
          <Text color={theme.primary}>Selected disk: <Text bold color={theme.accent}>{selectedDisk?.name}</Text></Text>
          <Text color={theme.primary}>Size: <Text bold color={theme.accent}>{selectedDisk?.sizeHuman}</Text></Text>
          {selectedDisk?.model && <Text color={theme.primary}>Model: <Text bold color={theme.accent}>{selectedDisk.model}</Text></Text>}
          {selectedDisk?.byIdPath && <Text color={theme.dim}>Path: {selectedDisk.byIdPath}</Text>}
        </Box>
        <SelectInput
          items={[
            { label: '✓ Yes, erase this disk and continue', value: 'yes' },
            { label: '✗ No, go back and select a different disk', value: 'no' },
          ]}
          onSelect={(item) => handleDiskConfirm(item.value === 'yes')}
        />
      </FullScreen>
    );
  }

  // ============================================================================
  // Screen: Encryption Choice
  // ============================================================================

  if (screen === 'encryption-choice') {
    return (
      <FullScreen>
        {renderHeader('Encryption')}
        <Box marginBottom={1}>
          <Text color={theme.primary}>Choose disk encryption option:</Text>
        </Box>
        <SelectInput
          items={[
            { label: '🔒 Encrypted (ZFS + LUKS + TPM2) - Recommended', value: 'encrypted' },
            { label: '🔓 Unencrypted (ext4) - Simple', value: 'unencrypted' },
          ]}
          onSelect={handleEncryptionSelect}
        />
        <Box marginTop={1} flexDirection="column">
          <Text color={theme.dim}>Encrypted: Full disk encryption with automatic TPM2 unlock</Text>
          <Text color={theme.dim}>Unencrypted: Faster, simpler, suitable for testing</Text>
        </Box>
        {renderBackHint()}
      </FullScreen>
    );
  }

  // ============================================================================
  // Screen: TPM Warning
  // ============================================================================

  if (screen === 'tpm-warning') {
    return (
      <FullScreen>
        {renderHeader('TPM2 Not Available')}
        <Box marginBottom={1} borderStyle="round" borderColor={theme.warning} padding={1}>
          <Text color={theme.warning}>⚠️ TPM2 device not detected</Text>
        </Box>
        <Box flexDirection="column" marginBottom={1}>
          <Text color={theme.primary}>Your system does not have a TPM2 device available.</Text>
          <Text color={theme.primary}>Encryption will still work, but you will need to enter</Text>
          <Text color={theme.primary}>a password on every boot to unlock the disk.</Text>
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
      </FullScreen>
    );
  }

  // ============================================================================
  // Screen: Hostname Input
  // ============================================================================

  if (screen === 'hostname-input') {
    return (
      <FullScreen>
        {renderHeader('Hostname')}
        <Box marginBottom={1}>
          <Text color={theme.primary}>Enter a hostname for this machine:</Text>
        </Box>
        {hostnameError && (
          <Box marginBottom={1}>
            <Text color={theme.error}>{hostnameError}</Text>
          </Box>
        )}
        <Box>
          <Text color={theme.prompt}>&gt; </Text>
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
          <Text color={theme.dim}>Letters, numbers, and hyphens only (e.g., my-server)</Text>
        </Box>
        {renderBackHint()}
      </FullScreen>
    );
  }

  // ============================================================================
  // Screen: Username Input
  // ============================================================================

  if (screen === 'username-input') {
    return (
      <FullScreen>
        {renderHeader('Username')}
        <Box marginBottom={1}>
          <Text color={theme.primary}>Enter a username for the primary account:</Text>
        </Box>
        {usernameError && (
          <Box marginBottom={1}>
            <Text color={theme.error}>{usernameError}</Text>
          </Box>
        )}
        <Box>
          <Text color={theme.prompt}>&gt; </Text>
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
          <Text color={theme.dim}>Lowercase letters, numbers, and underscores only</Text>
        </Box>
        {renderBackHint()}
      </FullScreen>
    );
  }

  // ============================================================================
  // Screen: Password Input
  // ============================================================================

  if (screen === 'password-input') {
    return (
      <FullScreen>
        {renderHeader('Password')}
        <Box marginBottom={1}>
          <Text color={theme.primary}>Enter a password for {username}:</Text>
        </Box>
        {passwordError && (
          <Box marginBottom={1}>
            <Text color={theme.error}>{passwordError}</Text>
          </Box>
        )}
        <Box>
          <Text color={theme.prompt}>&gt; </Text>
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
      </FullScreen>
    );
  }

  // ============================================================================
  // Screen: Password Confirm
  // ============================================================================

  if (screen === 'password-confirm') {
    return (
      <FullScreen>
        {renderHeader('Confirm Password')}
        <Box marginBottom={1}>
          <Text color={theme.primary}>Confirm password for {username}:</Text>
        </Box>
        {passwordError && (
          <Box marginBottom={1}>
            <Text color={theme.error}>{passwordError}</Text>
          </Box>
        )}
        <Box>
          <Text color={theme.prompt}>&gt; </Text>
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
      </FullScreen>
    );
  }

  // ============================================================================
  // Screen: System Type Selection
  // ============================================================================

  if (screen === 'system-type-selection') {
    return (
      <FullScreen>
        {renderHeader('System Type')}
        <Box marginBottom={1}>
          <Text color={theme.primary}>Select the type of system to install:</Text>
        </Box>
        <SelectInput
          items={[
            { label: '🖥️  Server (headless, infrastructure services)', value: 'server' },
            { label: '🖱️  Client (Hyprland desktop, graphical)', value: 'client' },
          ]}
          onSelect={handleSystemTypeSelect}
        />
        <Box marginTop={1} flexDirection="column">
          <Text color={theme.dim}>Server: VPN, DNS, storage, and other services</Text>
          <Text color={theme.dim}>Client: Desktop workstation with Hyprland</Text>
        </Box>
        {renderBackHint()}
      </FullScreen>
    );
  }

  // ============================================================================
  // Screen: Repository URL
  // ============================================================================

  if (screen === 'repository-url') {
    return (
      <FullScreen>
        {renderHeader('Clone Repository')}
        <Box marginBottom={1}>
          <Text color={theme.primary}>Enter the git repository URL:</Text>
        </Box>
        {repositoryError && (
          <Box marginBottom={1}>
            <Text color={theme.error}>{repositoryError}</Text>
          </Box>
        )}
        <Box>
          <Text color={theme.prompt}>&gt; </Text>
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
          <Text color={theme.dim}>HTTPS: https://github.com/user/repo</Text>
          <Text color={theme.dim}>SSH: git@github.com:user/repo</Text>
        </Box>
        {renderBackHint()}
      </FullScreen>
    );
  }

  // ============================================================================
  // Screen: Repository Cloning
  // ============================================================================

  if (screen === 'repository-cloning') {
    return (
      <FullScreen>
        {renderHeader('Cloning Repository')}
        <Box>
          <Text color={theme.accent}>
            <Spinner type="dots" />
          </Text>
          <Text color={theme.primary}> Cloning {repositoryUrl}...</Text>
        </Box>
      </FullScreen>
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
      <FullScreen>
        {renderHeader('Select Host')}
        <Box marginBottom={1}>
          <Text color={theme.primary}>Select a host configuration to deploy:</Text>
        </Box>
        <SelectInput items={hostItems} onSelect={handleHostSelect} />
        {renderBackHint()}
      </FullScreen>
    );
  }

  // ============================================================================
  // Screen: Summary
  // ============================================================================

  if (screen === 'summary') {
    return (
      <FullScreen>
        {renderHeader('Installation Summary')}
        <Box flexDirection="column" marginBottom={1} borderStyle="single" borderColor={theme.border} padding={1}>
          <Text color={theme.primary}>Hostname: <Text bold color={theme.accent}>{hostname}</Text></Text>
          <Text color={theme.primary}>Username: <Text bold color={theme.accent}>{username}</Text></Text>
          <Text color={theme.primary}>System Type: <Text bold color={theme.accent}>{systemType}</Text></Text>
          {selectedDisk && (
            <>
              <Text color={theme.primary}>Disk: <Text bold color={theme.accent}>{selectedDisk.name}</Text> ({selectedDisk.sizeHuman})</Text>
              <Text color={theme.primary}>Encryption: <Text bold color={theme.accent}>
                {encryptionChoice?.encrypted ? 'ZFS + LUKS' : 'None (ext4)'}
              </Text></Text>
            </>
          )}
          {selectedMethod?.type === 'clone' && (
            <Text color={theme.primary}>Source: <Text bold color={theme.accent}>Cloned from repository</Text></Text>
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
      </FullScreen>
    );
  }

  // ============================================================================
  // Screen: Installing
  // ============================================================================

  if (screen === 'installing') {
    return (
      <FullScreen>
        {renderHeader('Installing')}
        <Box marginBottom={1}>
          <Text color={theme.accent}>
            <Spinner type="dots" />
          </Text>
          <Text color={theme.primary}> {installProgress?.currentOperation || 'Starting installation...'}</Text>
        </Box>
        {installProgress && (
          <Box marginBottom={1}>
            <Text color={theme.primary}>Progress: {installProgress.progress}%</Text>
          </Box>
        )}
        <Box flexDirection="column" marginTop={1}>
          <Text color={theme.dim}>Recent operations:</Text>
          {fileOperations.slice(-5).map((op, i) => (
            <Box key={i}>
              <Text color={op.success ? theme.success : theme.error}>
                {op.success ? '✓' : '✗'} {op.action}: {op.purpose}
              </Text>
            </Box>
          ))}
        </Box>
      </FullScreen>
    );
  }

  // ============================================================================
  // Screen: Complete
  // ============================================================================

  if (screen === 'complete') {
    return (
      <FullScreen>
        {renderHeader('Installation Complete')}
        <Box marginBottom={1}>
          <Text color={theme.success}>✓ NixOS has been successfully installed!</Text>
        </Box>
        <Box flexDirection="column" marginBottom={1}>
          <Text color={theme.primary}>Hostname: <Text bold color={theme.accent}>{hostname}</Text></Text>
          <Text color={theme.primary}>Username: <Text bold color={theme.accent}>{username}</Text></Text>
          <Text color={theme.primary}>System Type: <Text bold color={theme.accent}>{systemType}</Text></Text>
        </Box>
        <Box marginBottom={1} borderStyle="round" borderColor={theme.border} padding={1}>
          <Text color={theme.primary}>Configuration saved to: ~/nixos-config/</Text>
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
      </FullScreen>
    );
  }

  // ============================================================================
  // Screen: Error
  // ============================================================================

  if (screen === 'error') {
    // Find the last failed operation with output
    const lastFailedOp = fileOperations.filter(op => !op.success).pop();

    return (
      <FullScreen>
        {renderHeader('Installation Error')}
        <Box marginBottom={1}>
          <Text color={theme.error}>✗ Installation failed</Text>
        </Box>
        <Box marginBottom={1} borderStyle="round" borderColor={theme.error} padding={1}>
          <Text color={theme.primary}>{installError || 'An unknown error occurred'}</Text>
        </Box>
        {lastFailedOp?.output && (
          <Box marginBottom={1} flexDirection="column">
            <Text color={theme.dim}>Last output (truncated):</Text>
            <Box borderStyle="single" borderColor={theme.border} padding={1}>
              <Text color={theme.primary}>{lastFailedOp.output.slice(-500)}</Text>
            </Box>
          </Box>
        )}
        <Box marginBottom={1}>
          <Text color={theme.dim}>Full log: /tmp/keystone-install.log</Text>
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
      </FullScreen>
    );
  }

  return null;
};

export default App;
