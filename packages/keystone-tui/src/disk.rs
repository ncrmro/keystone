//! Disk discovery for the Keystone installer.
//!
//! Enumerates block devices via /dev/disk/by-id/ and correlates with lsblk
//! to provide model, size, and transport information for disk selection.

use std::path::Path;

/// A discovered disk device suitable for installation.
#[derive(Debug, Clone)]
pub struct DiskEntry {
    /// Stable by-id path, e.g. /dev/disk/by-id/nvme-Samsung_SSD_980_PRO_2TB
    pub by_id_path: String,
    /// Human-readable model name
    pub model: String,
    /// Size string, e.g. "1.8T"
    pub size: String,
    /// Transport type: nvme, sata, usb, etc.
    pub transport: String,
}

impl DiskEntry {
    /// Sort priority — NVMe first, then SATA, then everything else.
    fn sort_key(&self) -> u8 {
        match self.transport.as_str() {
            "nvme" => 0,
            "sata" => 1,
            "usb" => 3,
            _ => 2,
        }
    }
}

/// Discover available disks by reading /dev/disk/by-id/ and correlating with lsblk.
///
/// Filters out partitions, device-mapper, loop devices, and CD-ROM entries.
/// Returns disks sorted by transport priority (NVMe > SATA > other > USB).
pub async fn discover_disks() -> anyhow::Result<Vec<DiskEntry>> {
    let by_id_dir = Path::new("/dev/disk/by-id");
    if !by_id_dir.exists() {
        return Ok(Vec::new());
    }

    // Get lsblk data for correlation
    let lsblk_output = tokio::process::Command::new("lsblk")
        .args(["--json", "-d", "-o", "NAME,SIZE,MODEL,TRAN,TYPE"])
        .output()
        .await?;

    let lsblk_json: serde_json::Value =
        serde_json::from_slice(&lsblk_output.stdout).unwrap_or_default();

    let blockdevices = lsblk_json
        .get("blockdevices")
        .and_then(|v| v.as_array())
        .cloned()
        .unwrap_or_default();

    // Read /dev/disk/by-id/ entries
    let mut entries = tokio::fs::read_dir(by_id_dir).await?;
    let mut raw_links: Vec<(String, String)> = Vec::new();

    while let Some(entry) = entries.next_entry().await? {
        let name = entry.file_name().to_string_lossy().to_string();

        // Filter out: partitions, wwn-*, dm-*, loop, CD-ROM
        if name.contains("-part")
            || name.starts_with("wwn-")
            || name.starts_with("dm-")
            || name.contains("loop")
            || name.contains("cdrom")
            || name.contains("CD-ROM")
            || name.contains("DVD")
            || name.contains("dvd")
        {
            continue;
        }

        // Resolve symlink to get the actual device name
        let full_path = by_id_dir.join(&name);
        if let Ok(target) = tokio::fs::read_link(&full_path).await {
            let dev_name = target
                .file_name()
                .map(|n| n.to_string_lossy().to_string())
                .unwrap_or_default();
            if !dev_name.is_empty() && !dev_name.starts_with("sr") {
                raw_links.push((name, dev_name));
            }
        }
    }

    // Deduplicate: for each underlying device, prefer nvme-* or ata-* prefix
    let mut device_map: std::collections::HashMap<String, String> =
        std::collections::HashMap::new();
    for (by_id_name, dev_name) in &raw_links {
        let existing = device_map.get(dev_name);
        let prefer_new = match existing {
            None => true,
            Some(old) => {
                // Prefer nvme- or ata- prefixed names over generic ones
                let new_prio = if by_id_name.starts_with("nvme-") || by_id_name.starts_with("ata-")
                {
                    0
                } else {
                    1
                };
                let old_prio = if old.starts_with("nvme-") || old.starts_with("ata-") {
                    0
                } else {
                    1
                };
                new_prio < old_prio
            }
        };
        if prefer_new {
            device_map.insert(dev_name.clone(), by_id_name.clone());
        }
    }

    // Build DiskEntry list by correlating with lsblk
    let mut disks: Vec<DiskEntry> = Vec::new();
    for (dev_name, by_id_name) in &device_map {
        let lsblk_info = blockdevices.iter().find(|d| {
            d.get("name")
                .and_then(|v| v.as_str())
                .map(|n| n == dev_name)
                .unwrap_or(false)
        });

        if lsblk_info
            .and_then(|d| d.get("type"))
            .and_then(|v| v.as_str())
            .is_some_and(|device_type| device_type != "disk")
        {
            continue;
        }

        let model = lsblk_info
            .and_then(|d| d.get("model"))
            .and_then(|v| v.as_str())
            .unwrap_or("Unknown")
            .trim()
            .to_string();

        let size = lsblk_info
            .and_then(|d| d.get("size"))
            .and_then(|v| v.as_str())
            .unwrap_or("?")
            .to_string();

        let transport = lsblk_info
            .and_then(|d| d.get("tran"))
            .and_then(|v| v.as_str())
            .unwrap_or("")
            .to_string();

        disks.push(DiskEntry {
            by_id_path: format!("/dev/disk/by-id/{}", by_id_name),
            model,
            size,
            transport,
        });
    }

    disks.sort_by_key(|d| (d.sort_key(), d.by_id_path.clone()));
    Ok(disks)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_sort_key_priority() {
        let nvme = DiskEntry {
            by_id_path: String::new(),
            model: String::new(),
            size: String::new(),
            transport: "nvme".to_string(),
        };
        let sata = DiskEntry {
            by_id_path: String::new(),
            model: String::new(),
            size: String::new(),
            transport: "sata".to_string(),
        };
        let usb = DiskEntry {
            by_id_path: String::new(),
            model: String::new(),
            size: String::new(),
            transport: "usb".to_string(),
        };

        assert!(nvme.sort_key() < sata.sort_key());
        assert!(sata.sort_key() < usb.sort_key());
    }
}
