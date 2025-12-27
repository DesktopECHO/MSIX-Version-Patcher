# MSIX Version Patcher
**Patch Apps in the Windows Store to run on older versions of Windows**

When apps in the Window Store require a minimum OS version that is higher than your currently installed Windows version, you are prevented from installing the app.  

I created this script when I couldn't install the Apple TV or Apple Music apps on Windows 10 IoT LTSC (10.0.19044) due to the requirment for Windows 10 22H2 (10.0.19045) or newer.

**This hack works only if the app truly doesn't require functionality included in the newer versions of Windows.**

This script requires:
 - Microsoft Store:  Install it by hand, or use a helper like [LTSC-Add-MicrosoftStore](https://github.com/kkkgo/LTSC-Add-MicrosoftStore)
 - WinGet:  Install it by hand, or use a helper like [Install-WingetV2.ps1](https://github.com/kkaminsk/InstallWinget-V2/blob/main/Install-WingetV2.ps1)
 - The MSIX installer.  If you download a MSIXBUNDLE of the app, you need to extract the MSIX from the bundle using NanaZip

Run the script with admin rights. The script installs the MSIX Packaging Tool if needed, copies makeappx/signtool from the \SDK folder, prompts you to pick the MSIX, unpacks it, reads AppxManifest.xml, detects the package’s required OS build, and replaces that MinVersion with your actual OS build. It then generates and trusts a self-signed certificate, repacks the MSIX, signs it, and installs the patched package.

<img width="3840" height="2160" alt="AppleTV" src="https://github.com/user-attachments/assets/428c51f3-0275-4d24-8050-93c306381d0a" />
