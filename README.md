TheoSwingTimer

Lightweight swing timer for TBC 2.5.3 and 2.4.3 clients.

Features:
- Main-hand and off-hand swing bars
- White bar fills left to right
- Countdown timer to next swing
- Shows in combat
- Hides out of combat
- Enabled by default
- Drag/move/resize commands
- Supports both 2.5.3 and 2.4.3 combat log styles

Install:
Put the correct version in:

Interface\AddOns\TheoSwingTimer\

Final path should be:

Interface\AddOns\TheoSwingTimer\TheoSwingTimer.toc
Interface\AddOns\TheoSwingTimer\TheoSwingTimer.lua

Use:
- 20503 version for TBC Classic 2.5.3
- 20400 version for original TBC 2.4.3

Do not install both versions in the same client.

Commands:
/tsw help        - show commands
/tsw status      - show addon status
/tsw unlock      - show and unlock frame for moving
/tsw lock        - lock frame and return to combat-only mode
/tsw center      - move frame to center and turn test mode on
/tsw combatonly  - show only in combat, hide out of combat
/tsw teston      - force bars visible for testing
/tsw testoff     - turn test mode off
/tsw width 260   - set bar width
/tsw height 14   - set bar height
/tsw scale 1.0   - set frame scale
/tsw reset       - reset position and size
/tsw on          - enable addon
/tsw off         - disable addon

Recommended setup:
1. Install the correct version.
2. Log in.
3. Type /tsw center.
4. Drag the timer where you want it.
5. Type /tsw lock.
6. Enter combat to verify it appears.
7. Leave combat to verify it disappears.

If /tsw opens the normal WoW help window, the addon is not installed correctly.
Check that TheoSwingTimer.toc is directly inside the TheoSwingTimer folder.
