# C/A Tool

An on-screen measuring overlay for the **condylar (C)** and **axial (A)** circles used in
the EPIC and Advanced Orthogonal chiropractic techniques. It sits on top of whatever
window shows the X-ray or CBCT scan, so it works with any viewer.

**Windows 10 or 11. Nothing to install.** It uses the PowerShell that comes with Windows.

## Download and run

1. Go to the **[latest release](https://github.com/grungenut/ca-tool/releases/latest)** and
   download **`CA-Tool.exe`**.
2. Double-click it. That's it: there is no installer and nothing else to download. You
   can keep the file anywhere (Desktop, Documents, a USB stick).

**If Windows shows a warning** the first time: this is normal for programs downloaded
from the internet that aren't from a large publisher.
- *"Windows protected your PC"* → click **More info**, then **Run anyway**.
- *"Open File – Security Warning"* → click **Run**.

To skip these warnings for good: right-click `CA-Tool.exe` → **Properties** → tick
**Unblock** → **OK**.

To remove the tool, delete the file. Saved preferences are in `%APPDATA%\CATool`;
delete that folder too if you want them gone.

## Use it

- Click 4 points for **C**, then 4 points for **A**, in any order. The toolbox switches
  from C to A by itself; you can also pick C or A in the toolbox.
- **Hover** over a point to highlight it, then **drag** to move it. **Right-click** a
  point to delete it. **Ctrl+Z** undoes.
- **Pause** (button, or **F8** from anywhere) lets clicks go through to your image viewer.
  The key can be changed in Preferences. If you zoom or move the image while paused,
  the points will no longer line up.
- **Preferences**: inches or millimeters (inches by default), point size, the color of
  each set, the C reference length, whether to show the averaged circles, and the pause
  hotkey. Settings are remembered.
- **Exit** closes the tool.

## How the numbers are worked out

- In each set, the two **outside points** (the two ends of the arc) are found
  automatically. Each of the two **inside points** makes one circle with the outside
  points; the set's diameter is the **average** of those two circles' diameters.
- The distance between the two **C outside points** is taken as **55 mm** (adjustable)
  and used to convert screen distance into inches or millimeters for both sets.
- Only the **averaged circle** is drawn for each set: the average of the two radii,
  passing through both outside points.
- **Ratio C/A** is shown as **1:X** — C is set to 1, and X is the A average diameter
  divided by the C average diameter.

## Privacy

The tool never reads, saves, or sends the image or any patient information. It only
knows where you clicked, and it does not connect to the internet.

## For developers

The tool itself is `CATool.ps1` (Windows PowerShell + WPF). `CA-Tool.exe` is a small
launcher with that script embedded, built by `build.ps1` using only what ships with
Windows:

```
powershell -NoProfile -ExecutionPolicy Bypass -File build.ps1
```

You can also run the script directly:
`powershell -NoProfile -ExecutionPolicy Bypass -STA -File CATool.ps1`

## License

[MIT](LICENSE)
