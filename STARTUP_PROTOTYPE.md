# Tesla SS Tools Startup Animation Prototype

This repository contains an isolated cinematic startup-animation test. It does not modify or connect to the production Tesla SS Tools project.

## Run from CMD

Download the repository or the included `TeslaStartupAnimationTest.zip`, extract it, open CMD in the folder containing the script, and run:

```cmd
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "TeslaStartupTest.ps1"
```

The script uses `$PSScriptRoot`, so its `assets` directory is resolved relative to the script rather than the current CMD directory.

## Included prototype

- Borderless dark WPF startup scene.
- Photorealistic transparent vehicle layers with headlights off and on.
- Low-opacity atmospheric fog layers.
- WPF spline animation with acceleration, scaling, rotation, and motion blur.
- Connected light-streak transition into a temporary test GUI.
- Replay and close controls; press `Esc` to skip the intro.

The intro is implemented with Windows PowerShell, built-in .NET/WPF, XAML, cached `BitmapImage` objects, and a WPF `Storyboard`. It requires no internet connection or third-party runtime.

## Repository layout

```text
TeslaStartupTest.ps1
assets/
  car-off.png
  car-on.png
  fog.png
TeslaStartupAnimationTest.zip
```

Production integration is intentionally excluded until the prototype has been tested and approved.
