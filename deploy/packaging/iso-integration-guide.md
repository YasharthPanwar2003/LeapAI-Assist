# openSUSE Custom ISO Integration Guide
# =============================================================================
# How to bake suse-ai into a custom openSUSE ISO image.
# Covers Leap 15.x (YaST/KIWI) and Leap 16.x (Agama/KIWI).
#
# Reference:
#   Leap 16 Agama: https://documentation.suse.com/sles/16.0/html/SLES-x86-64-agama-automated-installation/
#   KIWI: https://en.opensuse.org/Portal:KIWI
#   openSUSE Images: https://en.opensuse.org/Portal:KIWI/ImageDescriptions
#   OEM Installer: https://news.opensuse.org/2025/08/21/os-welcome-makeover
# =============================================================================

## Overview

There are **two paths** to create a custom ISO with suse-ai:

```
Path A: Leap 16.x (Current)
  └─ Use KIWI + Agama profile → modern approach

Path B: Leap 15.x (Legacy)
  └─ Use KIWI + YaST profile → traditional approach
```

Both paths use **KIWI (Kiwi Image Creation)** as the image builder.

---

## 1. Install KIWI

```bash
# Leap 16.x:
sudo zypper install -y kiwi osc

# Leap 15.x:
sudo zypper install -y kiwi osc python3-kiwi

# Verify:
kiwi --version
```

---

## 2. Project Structure

```
suse-ai-iso/
├── kiwi-description/
│   └── config.kiwi           ← KIWI image description
├── root/                     ← Files added to the ISO root
│   ├── usr/
│   │   ├── share/suse-ai/   ← Application files
│   │   └── lib/jeos-firstboot/modules/
│   │       └── 04_ai_assistant.sh
│   ├── etc/
│   │   ├── suse-ai/env       ← Default config
│   │   ├── systemd/system/   ← Systemd units
│   │   └── xdg/autostart/    ← Welcome launcher
│   └── var/lib/suse-ai/     ← Data directories
├── suse-ai-0.1.0.tar.gz      ← Source tarball
├── suse-ai.spec              ← RPM spec
└── build.sh                  ← Build script
```

---

## 3. KIWI Description for Leap 16.x (Agama)

Create `kiwi-description/config.kiwi`:

```xml
<?xml version="1.0" encoding="utf-8"?>
<image schemaversion="7.5" name="suse-ai-leap16">
  <!-- ============================================ -->
  <!-- Type: OEM — installed to disk with config  -->
  <!-- ============================================ -->
  <description type="oem">
    <author>SUSE AI Team</author>
    <contact>suse-ai@opensuse.org</contact>
    <specification>SUSE AI Assistant — openSUSE Leap 16</specification>
  </description>

  <!-- ==================== -->
  <!-- Preferences          -->
  <!-- ==================== -->
  <preferences>
    <version>0.1.0</version>
    <packagemanager>zypper</packagemanager>
    <locale>en_US</locale>
    <keytable>us</keytable>
    <timezone>UTC</timezone>
    <rpm-check-signatures>false</rpm-check-signatures>
    <bootsplash-theme>openSUSE</bootsplash-theme>
  </preferences>

  <!-- ==================== -->
  <!-- Repositories         -->
  <!-- ==================== -->
  <repository type="rpm-md" priority="100">
    <source path="obs://openSUSE:Leap:16.0/standard"/>
  </repository>
  <repository type="rpm-md" priority="100">
    <source path="obs://openSUSE:Leap:16.0/update"/>
  </repository>

  <!-- ==================== -->
  <!-- Bootstrap packages  -->
  <!-- ==================== -->
  <packages type="image">
    <!-- Base system -->
    <package name="patterns-base-minimal_base"/>
    <package name="patterns-yast-yast2_basis"/>  <!-- optional: YaST tools -->
    <package name="kernel-default"/>

    <!-- Python -->
    <package name="python313"/>
    <package name="python313-pip"/>
    <package name="python313-devel"/>

    <!-- Container runtime -->
    <package name="podman"/>
    <package name="podman-docker"/>
    <package name="buildah"/>
    <package name="skopeo"/>
    <package name="containers-common"/>

    <!-- System management -->
    <package name="systemd"/>
    <package name="curl"/>
    <package name="jq"/>

    <!-- First boot -->
    <package name="opensuse-welcome-launcher"/>  <!-- Leap 16 welcome -->
    <package name="gnome-tour"/>                  <!-- GNOME welcome -->
    <package name="plasma-welcome"/>              <!-- KDE welcome (if KDE) -->
    <package name="jeos-firstboot"/>              <!-- JeOS firstboot -->

    <!-- Cockpit (optional) -->
    <package name="cockpit"/>
    <package name="cockpit-podman"/>

    <!-- SUSE AI packages -->
    <package name="suse-ai"/>
    <package name="suse-ai-welcome"/>

    <!-- Bootloader -->
    <package name="grub2"/>
    <package name="grub2-x86_64-efi"/>
    <package name="shim"/>
    <package name="efibootmgr"/>
  </packages>

  <!-- ==================== -->
  <!-- OEM packages        -->
  <!-- ==================== -->
  <packages type="oem">
    <package name="gfxboot"/>
    <package name="grub2-branding-openSUSE"/>
  </packages>

  <!-- ==================== -->
  <!-- Exclude packages    -->
  <!-- ==================== -->
  <packages type="image" patternType="exclude">
    <package name="patterns-gnome-gnome_basis"/>  <!-- Exclude GNOME if JeOS -->
    <package name="patterns-kde-kde_basis"/>      <!-- Exclude KDE if JeOS -->
  </packages>
</image>
```

---

## 4. KIWI Description for Leap 15.x (YaST)

Same structure, but with different repositories and packages:

```xml
<?xml version="1.0" encoding="utf-8"?>
<image schemaversion="7.5" name="suse-ai-leap156">
  <description type="oem">
    <author>SUSE AI Team</author>
    <contact>suse-ai@opensuse.org</contact>
    <specification>SUSE AI Assistant — openSUSE Leap 15.6</specification>
  </description>

  <preferences>
    <version>0.1.0</version>
    <packagemanager>zypper</packagemanager>
    <locale>en_US</locale>
    <keytable>us</keytable>
    <timezone>UTC</timezone>
    <rpm-check-signatures>false</rpm-check-signatures>
    <bootsplash-theme>openSUSE</bootsplash-theme>
  </preferences>

  <!-- Leap 15.6 repositories -->
  <repository type="rpm-md" priority="100">
    <source path="obs://openSUSE:Leap:15.6/standard"/>
  </repository>
  <repository type="rpm-md" priority="100">
    <source path="obs://openSUSE:Leap:15.6/update"/>
  </repository>
  <repository type="rpm-md" priority="100">
    <source path="obs://openSUSE:Leap:15.6/non-oss"/>
  </repository>

  <packages type="image">
    <!-- Base -->
    <package name="patterns-base-minimal_base"/>
    <package name="kernel-default"/>

    <!-- Python (Leap 15.x uses Python 3.11 by default) -->
    <package name="python311"/>
    <package name="python311-pip"/>
    <package name="python311-devel"/>

    <!-- Container -->
    <package name="podman"/>
    <package name="podman-docker"/>
    <package name="buildah"/>

    <!-- First boot -->
    <package name="opensuse-welcome"/>  <!-- Leap 15.x welcome (Qt5) -->
    <package name="jeos-firstboot"/>

    <!-- SUSE AI -->
    <package name="suse-ai"/>
    <package name="suse-ai-welcome"/>

    <!-- Bootloader -->
    <package name="grub2"/>
    <package name="grub2-x86_64-efi"/>
    <package name="shim"/>
  </packages>

  <packages type="oem">
    <package name="gfxboot"/>
    <package name="grub2-branding-openSUSE"/>
  </packages>
</image>
```

---

## 5. Agama Profile for Automated Install (Leap 16)

Leap 16 uses **Agama** instead of YaST. Create an autoinstall profile:

```json
{
  "product": {
    "id": "openSUSE",
    "registration_code": ""
  },
  "language": {
    "id": "en_US"
  },
  "keyboard": {
    "layout": "us"
  },
  "timezone": {
    "timezone": "UTC"
  },
  "network": {
    "connections": [
      {
        "id": "eth0",
        "type": "ethernet",
        "autoconnect": true
      }
    ]
  },
  "storage": {
    "guided": {
      "target": "disk",
      "disk": "/dev/sda",
      "install_immediate": false,
      "encrypt": false
    }
  },
  "software": {
    "patterns": [
      "patterns-base-minimal_base",
      "suse-ai"
    ],
    "packages": [
      "podman",
      "python313",
      "opensuse-welcome-launcher",
      "jeos-firstboot"
    ]
  },
  "users": [
    {
      "username": "suseai",
      "fullname": "SUSE AI User",
      "password": "CHANGE_ME_IN_PRODUCTION",
      "auto_login": true
    }
  ],
  "firstboot": {
    "enable": true,
    "scripts": [
      {
        "name": "suse-ai-setup",
        "source": "/usr/bin/suse-ai-welcome-setup"
      }
    ]
  }
}
```

Embed this in the ISO or serve via HTTP for network install:

```bash
# For network install, serve the profile:
python3 -m http.server 8080 &

# Boot from ISO with:
# agama autoinstall=http://192.168.56.1:8080/agama-profile.json
```

---

## 6. Build the Custom ISO

```bash
#!/bin/bash
# build.sh — Build custom openSUSE ISO with suse-ai

set -euo pipefail

LEAP_VERSION="${1:-16.0}"
IMAGE_NAME="suse-ai-leap${LEAP_VERSION}"
DESCRIPTION_DIR="kiwi-description"
OUT_DIR="./output"

echo "Building ${IMAGE_NAME}..."

# Create output directory
mkdir -p "${OUT_DIR}"

# Run KIWI
sudo kiwi-ng \
  --type oem \
  --profile default \
  --description "${DESCRIPTION_DIR}" \
  --target-dir "${OUT_DIR}" \
  build

echo ""
echo "Build complete!"
echo "ISO: ${OUT_DIR}/${IMAGE_NAME}-*.iso"
echo ""
echo "To test in VirtualBox:"
echo "  VBoxManage createvm --name 'suse-ai-test' --register"
echo "  VBoxManage storagectl 'suse-ai-test' add storage --type dvddrive --medium ${OUT_DIR}/${IMAGE_NAME}-x86_64-*.iso"
echo "  VBoxManage startvm 'suse-ai-test'"
```

---

## 7. Build on OBS (Automated)

For automated ISO builds on the openSUSE Build Service:

```bash
# Create an image project
osc meta prj home:yourusername:suse-ai-image -e << 'EOF'
<project name="home:yourusername:suse-ai-image">
  <title>SUSE AI ISO Image</title>
  <description>Custom openSUSE ISO with SUSE AI Assistant pre-installed</description>
  <repository name="images">
    <path project="openSUSE:Leap:16.0" repository="standard"/>
    <arch>x86_64</arch>
  </repository>
</project>
EOF

# Create the KIWI package
osc mkpac home:yourusername:suse-ai-image suse-ai-iso
cd home:yourusername:suse-ai-image/suse-ai-iso

# Copy KIWI description and source files
cp config.kiwi .   # The KIWI description
cp suse-ai-0.1.0.tar.gz .
osc add *

# For KIWI builds, add _kiwi_rules file
cat > _kiwi_rules << 'EOF'
<kiwi file="config.kiwi"/>
EOF
osc add _kiwi_rules

osc commit -m "Initial ISO image build configuration"
```

---

## 8. Testing the ISO

### In VirtualBox:

```bash
# Create VM
VBoxManage createvm --name "suse-ai-test" --register
VBoxManage modifyvm "suse-ai-test" --memory 8192 --cpus 4
VBoxManage storagectl "suse-ai-test" --name "SATA" --add sata

# Attach ISO
VBoxManage storageattach "suse-ai-test" --storagectl "SATA" \
  --port 0 --device 0 --type dvddrive \
  --medium ./output/suse-ai-leap16-x86_64-0.1.0.iso

# Create virtual disk (20GB)
VBoxManage createhd --filename ./suse-ai-test.vdi --size 20480
VBoxManage storageattach "suse-ai-test" --storagectl "SATA" \
  --port 1 --device 0 --type hdd --medium ./suse-ai-test.vdi

# Boot
VBoxManage startvm "suse-ai-test"
```

### Verify suse-ai is installed:

```bash
# After boot and first-boot setup:
rpm -qa | grep suse-ai
systemctl --user status suse-ai.socket
podman images | grep suse-ai
ls /var/lib/suse-ai/
```

---

## 9. Leap 15.x vs 16.x Differences

| Aspect | Leap 15.x | Leap 16.x |
|--------|-----------|-----------|
| **Installer** | YaST installer | Agama (service-based) |
| **Autoinstall** | AutoYaST XML profile | Agama JSON profile |
| **Welcome** | opensuse-welcome (Qt5) | opensuse-welcome-launcher + gnome-tour/plasma-welcome |
| **Python** | python311 default, python313 optional | python313 default |
| **Podman** | 4.x (built-in compose) | 5.4.2 (Quadlet, improved compose) |
| **KIWI** | kiwi v9.x | kiwi v10.x (minor syntax changes) |
| **SELinux** | AppArmor (default) | SELinux (AppArmor deprecated) |
| **Systemd** | 254 | 256 |
| **Bootloader** | grub2 (same) | grub2 (same) |

### Handling both in one spec:

```bash
# Detect Leap version in post-install script:
if [ -f /etc/os-release ]; then
    . /etc/os-release
    case "$VERSION_ID" in
        15.*) echo "Leap 15.x detected" ;;
        16.*) echo "Leap 16.x detected" ;;
    esac
fi
```
