import { execSync } from 'child_process';

export interface NetworkInterface {
  name: string;
  ipAddress?: string;
  isEthernet: boolean;
  isWireless: boolean;
}

/**
 * Get all network interfaces with their IP addresses
 */
export function getNetworkInterfaces(): NetworkInterface[] {
  try {
    // Get interface names and their addresses using ip command
    const output = execSync('ip -4 -o addr show', { encoding: 'utf-8' });
    const lines = output.trim().split('\n');
    
    const interfaces: NetworkInterface[] = [];
    const seenInterfaces = new Set<string>();
    
    for (const line of lines) {
      // Parse ip addr output: "2: eth0    inet 192.168.1.100/24 ..."
      const match = line.match(/^\d+:\s+(\S+)\s+inet\s+(\S+)/);
      if (match) {
        const name = match[1];
        const ipWithMask = match[2];
        const ipAddress = ipWithMask.split('/')[0];
        
        // Skip loopback
        if (name === 'lo' || ipAddress === '127.0.0.1') {
          continue;
        }
        
        if (!seenInterfaces.has(name)) {
          seenInterfaces.add(name);
          interfaces.push({
            name,
            ipAddress,
            isEthernet: name.startsWith('eth') || name.startsWith('en'),
            isWireless: name.startsWith('wl') || name.startsWith('wlan'),
          });
        }
      }
    }
    
    return interfaces;
  } catch (error) {
    console.error('Error getting network interfaces:', error);
    return [];
  }
}

/**
 * Check if there's an active Ethernet connection with an IP address
 */
export function hasEthernetConnection(): boolean {
  const interfaces = getNetworkInterfaces();
  return interfaces.some(iface => iface.isEthernet && iface.ipAddress);
}

/**
 * Scan for available WiFi networks
 */
export function scanWiFiNetworks(): string[] {
  try {
    // Use nmcli to scan for WiFi networks
    execSync('nmcli device wifi rescan', { encoding: 'utf-8', stdio: 'pipe' });
    
    // Wait a bit for scan to complete
    execSync('sleep 2', { encoding: 'utf-8' });
    
    // List available networks
    const output = execSync('nmcli -t -f SSID device wifi list', { 
      encoding: 'utf-8',
      stdio: 'pipe'
    });
    
    const networks = output
      .trim()
      .split('\n')
      .filter(ssid => ssid && ssid !== '--')
      .filter((ssid, index, self) => self.indexOf(ssid) === index); // Remove duplicates
    
    return networks;
  } catch (error) {
    console.error('Error scanning WiFi networks:', error);
    return [];
  }
}

/**
 * Connect to a WiFi network
 */
export function connectToWiFi(ssid: string, password: string): boolean {
  try {
    // Try to connect using nmcli
    execSync(`nmcli device wifi connect "${ssid}" password "${password}"`, {
      encoding: 'utf-8',
      stdio: 'pipe'
    });
    return true;
  } catch (error) {
    console.error('Error connecting to WiFi:', error);
    return false;
  }
}

/**
 * Get the current IP address (any interface)
 */
export function getCurrentIPAddress(): string | null {
  const interfaces = getNetworkInterfaces();
  if (interfaces.length > 0 && interfaces[0].ipAddress) {
    return interfaces[0].ipAddress;
  }
  return null;
}
