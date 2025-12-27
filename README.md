# MSIX Version Patcher
`PatchMSIX.ps1` is a utility that relaxes Windows version compatibility restrictions for application packages. 

It performs the following steps:

- Prompts to manually enter a target Windows build version, or automatically uses the current host's versiom.
- Extracts the package (including nested bundles) and replaces the `MinVersion` in the XML manifests to match the target build.
- Generates a self-signed certificate, re-signs the modified package, and installs the patched version. 

I created this script when I couldn't install the Apple TV or Apple Music apps on Windows 10 IoT LTSC (10.0.19044) due to the requirment for Windows 10 22H2 (10.0.19045) or newer.

**This hack only works if the app _truly_ doesn't require functionality included with the newer versions of Windows.**

## Requirements:
 - **WinGet:**  Install by hand, or use a helper script like [Install-WingetV2.ps1](https://github.com/kkaminsk/InstallWinget-V2/blob/main/Install-WingetV2.ps1)
 - **MSIX Packaging Tool:**  Install the "Offline" version available [here](https://learn.microsoft.com/en-us/windows/msix/packaging-tool/tool-overview) or install it directly from the [Microsoft Store](https://www.microsoft.com/p/msix-packaging-tool/9n5lw3jbcxkf).
 - The `.APPX` / `.APPXBUNDLE` / `.MSIX` / `.MSIXBUNDLE` package you want to modify.

## Usage:
 - Run `PatchMSIX.ps1` and follow the prompts
   
<img width="720" height="450" alt="image" src="https://github.com/user-attachments/assets/4ba7c724-e69b-4d23-8433-35d6aebcbe1a" />
