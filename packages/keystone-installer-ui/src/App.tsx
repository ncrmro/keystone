import React, { useState, useEffect } from 'react';
import { Box, Text } from 'ink';
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

type Screen = 'checking' | 'ethernet-connected' | 'wifi-setup' | 'wifi-scanning' | 'wifi-list' | 'wifi-password' | 'wifi-connecting' | 'wifi-connected' | 'wifi-failed';

interface SelectItem {
  label: string;
  value: string;
}

const App: React.FC = () => {
  const [screen, setScreen] = useState<Screen>('checking');
  const [ipAddress, setIpAddress] = useState<string | null>(null);
  const [wifiNetworks, setWifiNetworks] = useState<string[]>([]);
  const [selectedNetwork, setSelectedNetwork] = useState<string>('');
  const [password, setPassword] = useState<string>('');
  const [errorMessage, setErrorMessage] = useState<string>('');

  // Initial network check
  useEffect(() => {
    const checkNetwork = async () => {
      // Wait a moment for network to settle
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

  // WiFi scanning
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

  const handleStartWiFiSetup = () => {
    setScreen('wifi-scanning');
  };

  const handleSelectNetwork = (item: SelectItem) => {
    setSelectedNetwork(item.value);
    setScreen('wifi-password');
  };

  const handlePasswordSubmit = async () => {
    setScreen('wifi-connecting');
    
    // Try to connect
    const success = connectToWiFi(selectedNetwork, password);
    
    if (success) {
      // Wait a bit for connection to establish
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

  const handleRetry = () => {
    setPassword('');
    setSelectedNetwork('');
    setErrorMessage('');
    setScreen('wifi-setup');
  };

  if (screen === 'checking') {
    return (
      <Box flexDirection="column" padding={1}>
        <Box marginBottom={1}>
          <Text bold color="cyan">Keystone Installer</Text>
        </Box>
        <Box>
          <Text color="green">
            <Spinner type="dots" />
          </Text>
          <Text> Checking network connectivity...</Text>
        </Box>
      </Box>
    );
  }

  if (screen === 'ethernet-connected') {
    const interfaces = getNetworkInterfaces();
    
    return (
      <Box flexDirection="column" padding={1}>
        <Box marginBottom={1}>
          <Text bold color="cyan">Keystone Installer</Text>
        </Box>
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
        <Box flexDirection="column" borderStyle="round" borderColor="cyan" padding={1}>
          <Text bold>Ready for Installation</Text>
          <Text dimColor>From your deployment machine, run:</Text>
          <Text color="yellow">{`nixos-anywhere --flake .#your-config root@${ipAddress}`}</Text>
        </Box>
      </Box>
    );
  }

  if (screen === 'wifi-setup') {
    return (
      <Box flexDirection="column" padding={1}>
        <Box marginBottom={1}>
          <Text bold color="cyan">Keystone Installer</Text>
        </Box>
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
            { label: 'No, I\'ll configure manually', value: 'skip' },
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

  if (screen === 'wifi-scanning') {
    return (
      <Box flexDirection="column" padding={1}>
        <Box marginBottom={1}>
          <Text bold color="cyan">Keystone Installer</Text>
        </Box>
        <Box>
          <Text color="green">
            <Spinner type="dots" />
          </Text>
          <Text> Scanning for WiFi networks...</Text>
        </Box>
      </Box>
    );
  }

  if (screen === 'wifi-list') {
    const items: SelectItem[] = wifiNetworks.map(network => ({
      label: network,
      value: network,
    }));

    return (
      <Box flexDirection="column" padding={1}>
        <Box marginBottom={1}>
          <Text bold color="cyan">Keystone Installer - WiFi Setup</Text>
        </Box>
        <Box marginBottom={1}>
          <Text>Select a WiFi network:</Text>
        </Box>
        <SelectInput items={items} onSelect={handleSelectNetwork} />
      </Box>
    );
  }

  if (screen === 'wifi-password') {
    return (
      <Box flexDirection="column" padding={1}>
        <Box marginBottom={1}>
          <Text bold color="cyan">Keystone Installer - WiFi Setup</Text>
        </Box>
        <Box marginBottom={1}>
          <Text>Network: <Text bold>{selectedNetwork}</Text></Text>
        </Box>
        <Box marginBottom={1}>
          <Text>Enter password (press Enter when done):</Text>
        </Box>
        <Box>
          <Text color="green">&gt; </Text>
          <TextInput
            value={password}
            onChange={setPassword}
            onSubmit={handlePasswordSubmit}
            mask="*"
          />
        </Box>
      </Box>
    );
  }

  if (screen === 'wifi-connecting') {
    return (
      <Box flexDirection="column" padding={1}>
        <Box marginBottom={1}>
          <Text bold color="cyan">Keystone Installer - WiFi Setup</Text>
        </Box>
        <Box>
          <Text color="green">
            <Spinner type="dots" />
          </Text>
          <Text> Connecting to {selectedNetwork}...</Text>
        </Box>
      </Box>
    );
  }

  if (screen === 'wifi-connected') {
    const interfaces = getNetworkInterfaces();
    
    return (
      <Box flexDirection="column" padding={1}>
        <Box marginBottom={1}>
          <Text bold color="cyan">Keystone Installer</Text>
        </Box>
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
        <Box flexDirection="column" borderStyle="round" borderColor="cyan" padding={1}>
          <Text bold>Ready for Installation</Text>
          <Text dimColor>From your deployment machine, run:</Text>
          <Text color="yellow">{`nixos-anywhere --flake .#your-config root@${ipAddress}`}</Text>
        </Box>
      </Box>
    );
  }

  if (screen === 'wifi-failed') {
    return (
      <Box flexDirection="column" padding={1}>
        <Box marginBottom={1}>
          <Text bold color="cyan">Keystone Installer - WiFi Setup</Text>
        </Box>
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
              handleRetry();
            } else {
              setScreen('ethernet-connected');
            }
          }}
        />
      </Box>
    );
  }

  return null;
};

export default App;
