# Astralis 🌠
Astralis is a [Lune](https://github.com/Iconvault/Astralis) script that automates the process of fetching, rasterizing, packing, and uploading [Iconify](https://github.com/iconify/iconify) icon sets to Roblox as optimized sprite atlases.

It also powers **Iconvault**, providing users with thousands of high-quality icons. It’s also built to ensure you always have access to the latest icon sets, without any plugin updates required.

> Iconvault is coming soon. Stay tuned! 🤫

## ⚙️ What Astralis Does
1. Fetches the latest icon data from Iconify’s GitHub repository  
2. Generates normalized SVGs
3. Converts them to PNGs at the configured resolution  
4. Packs the icons into grid-aligned sprite atlases  
5. Applies alpha bleeding and losslessly compresses them
6. Uploads the atlases to Roblox using the Open Cloud API  
7. Generates a final `icons.json` file with asset IDs and coordinates  
8. Cleans up all intermediate files and makes a pull request to merge new icon changes.