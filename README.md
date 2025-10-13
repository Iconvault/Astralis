# Astralis 🌠
Astralis is a [Lune](https://github.com/lune-org/lune) script that automates the process of fetching, rasterizing, packing, and uploading [Iconify](https://github.com/iconify/iconify) icon sets to Roblox as optimized sprite atlases.

It also powers **Iconvault**, providing users with thousands of high-quality icons every week. Astralis is purpose-built to ensure you always have access to the latest icon sets, without any plugin updates required.

> Iconvault is coming soon. Stay tuned! 🤫

## ⚙️ How does Astralis Work?
1. Fetches the latest icon data from Iconify's GitHub repository  
2. Generates normalized SVGs
3. Converts them to PNGs at the configured resolution  
4. Packs the icons into grid-aligned sprite atlases  
5. Applies alpha bleeding and losslessly compresses them
6. Uploads the atlases to Roblox using the Open Cloud API  
7. Generates a final `icons.json` file with asset IDs and coordinates  
8. Cleans up all intermediate files and makes a pull request to merge new icon changes

## 📋 Final Data Structure

Astralis outputs an `icons.json` file with the following structure:

```jsonc
{
  "iconsetName": {
    "name": "Iconset Display Name", // Display name of the icon set
    "iconCount": 1234, // Total number of icons in the set
    "author": "Author Name", // Original author of the icon set
    "license": {
      "name": "MIT License", // Full license name
      "spdx": "MIT" // SPDX license identifier
    },
    "samples": ["icon-1", "icon-2", "icon-3"], // Sample icon names from the set
    "lastRefreshed": 1234567890, // Unix timestamp when Astralis last processed this set
    "lastUpdated": 1234567890, // Unix timestamp of the iconset's last modification (from Iconify)
    "icons": {
      "123456789": { // Roblox asset ID (decal number, without rbxassetid:// prefix)
        "icon-name": {
          "x": 0, // X coordinate of icon's top-left corner in spritesheet (pixels)
          "y": 0 // Y coordinate of icon's top-left corner in spritesheet (pixels)
        },
        "another-icon": {
          "x": 128,
          "y": 0
        }
      }
    }
  }
}
```
