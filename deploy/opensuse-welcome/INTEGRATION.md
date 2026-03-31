# opensuse-welcome-integration — How to integrate with the welcome screen
#
# OPEN SOURCE: https://github.com/openSUSE/openSUSE-welcome
# RELEASE NOTES: https://susedoc.github.io/release-notes/leap-16.0/html/release-notes (Section 2.4)
# ANNOUNCEMENT: https://news.opensuse.org/2025/08/21/os-welcome-makeover
#
# =============================================================================
# HOW openSUSE WELCOME WORKS (Leap 16)
# =============================================================================
#
# 1. opensuse-welcome-launcher is installed by default on Leap 16
# 2. On first login, the launcher detects the desktop environment:
#    - GNOME → launches gnome-tour
#    - KDE Plasma → launches plasma-welcome
# 3. The launcher manages autostart — NOT the greeter's own autostart mechanism
# 4. The launcher can also trigger after major system updates (new content)
# 5. To disable: remove opensuse-welcome-launcher package
#
# =============================================================================
# HOW TO ADD YOUR OWN PAGE (for SUSE AI Assistant)
# =============================================================================
#
# Method A: Desktop Autostart Entry (Recommended for Leap 16)
# ──────────────────────────────────────────────────────────
#   1. Copy suse-ai-welcome.desktop to /etc/xdg/autostart/
#   2. The desktop entry triggers suse-ai-welcome-setup on first login
#   3. The setup script shows a dialog, installs dependencies, and exits
#   4. After completion, it removes the autostart entry (one-time setup)
#
#   Pros: Works with both GNOME and KDE on Leap 16
#   Cons: Shows as a dialog, not integrated into the tour pages
#
# Method B: Custom gnome-tour page (GNOME only, Leap 16)
# ─────────────────────────────────────────────────────────
#   1. gnome-tour reads .json files from /usr/share/gnome-tour/
#   2. Create: /usr/share/gnome-tour/suse-ai.json with tour pages
#   3. Each page has: title, body (markdown), image, button (action)
#
#   Example /usr/share/gnome-tour/suse-ai.json:
#   {
#     "pages": [
#       {
#         "title": "SUSE AI Assistant",
#         "body": "Your local AI assistant is ready...",
#         "image": "/usr/share/pixmaps/suse-ai-welcome.png",
#         "button": {
#           "label": "Enable AI Assistant",
#           "action": "/usr/bin/suse-ai-welcome-setup"
#         }
#       }
#     ]
#   }
#
# Method C: plasma-welcome module (KDE only, Leap 16)
# ─────────────────────────────────────────────────────────
#   1. plasma-welcome supports KPackage plugins
#   2. Create a KPackage in: /usr/share/plasma/welcometour/
#   3. Package structure:
#      suse-ai/
#      └── contents/ui/Main.qml
#
# Method D: Legacy opensuse-welcome JSON (Leap 15.x only)
# ─────────────────────────────────────────────────────────
#   1. openSUSE-welcome (Qt5) reads JSON from /usr/share/opensuse-welcome/
#   2. Create: /usr/share/opensuse-welcome/suse-ai.json
#   3. Format:
#      {
#        "title": "SUSE AI Assistant",
#        "description": "...",
#        "button": "Enable",
#        "command": "/usr/bin/suse-ai-welcome-setup"
#      }
#
# Method E: jeos-firstboot module (JeOS / minimal install)
# ─────────────────────────────────────────────────────────
#   1. JeOS (minimal) does NOT have opensuse-welcome-launcher
#   2. Use: deploy/jeos-firstboot/04_ai_assistant.sh
#   3. Installed to: /usr/lib/jeos-firstboot/modules/
#   4. Numbered prefix (04_) controls execution order
#
# =============================================================================
# LEAP 15.x vs LEAP 16.x DIFFERENCES
# =============================================================================
#
# | Feature            | Leap 15.x              | Leap 16                    |
# |--------------------|------------------------|----------------------------|
# | Welcome system     | opensuse-welcome (Qt5) | opensuse-welcome-launcher  |
# | Greeter for GNOME  | opensuse-welcome       | gnome-tour (rebranded)     |
# | Greeter for KDE    | opensuse-welcome       | plasma-welcome             |
# | Content format     | JSON files             | Native tour pages         |
# | Custom pages       | /usr/share/opensuse-welcome/ | /usr/share/gnome-tour/ |
# | Autostart mgmt     | greeter's own          | launcher manages it        |
# | Post-update trigger| No                     | Yes (launcher re-shows)   |
# | Installer          | YaST                   | Agama (service-based)     |
# | JeOS support       | jeos-firstboot         | jeos-firstboot (same)     |
#
# =============================================================================
# RECOMMENDED INTEGRATION STRATEGY
# =============================================================================
#
# For your custom ISO/appliance:
#
# 1. Leap 16 (GNOME):
#    - Copy suse-ai-welcome.desktop to /etc/xdg/autostart/
#    - Copy suse-ai-welcome-setup to /usr/bin/
#    - Optionally create /usr/share/gnome-tour/suse-ai.json
#
# 2. Leap 16 (KDE):
#    - Copy suse-ai-welcome.desktop to /etc/xdg/autostart/
#    - Copy suse-ai-welcome-setup to /usr/bin/
#
# 3. Leap 15.x (both):
#    - Copy suse-ai-welcome.desktop to /usr/share/applications/
#    - Copy suse-ai.json to /usr/share/opensuse-welcome/
#    - Copy suse-ai-welcome-setup to /usr/bin/
#
# 4. JeOS (all versions):
#    - Copy 04_ai_assistant.sh to /usr/lib/jeos-firstboot/modules/
#    - No desktop needed (text-based)
#
# 5. Agama installer (Leap 16 ISO):
#    - Embed in Agama JSON profile (see packaging/iso-integration-guide.md)
#
# =============================================================================
