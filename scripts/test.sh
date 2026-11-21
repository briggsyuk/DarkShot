#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/checks
swiftc Sources/DarkShot/Geometry.swift Sources/DarkShot/Annotation.swift \
    Tests/DarkShotChecks/Checks.swift -o .build/checks/DarkShotChecks
.build/checks/DarkShotChecks
swiftc -swift-version 5 Sources/DarkShot/Geometry.swift Sources/DarkShot/Annotation.swift \
    Sources/DarkShot/CaptureToolbar.swift Sources/DarkShot/CaptureCanvas.swift \
    Tests/DarkShotChecks/InteractionChecks.swift -o .build/checks/InteractionChecks
.build/checks/InteractionChecks
swiftc -swift-version 5 Sources/DarkShot/ShortcutCombination.swift Sources/DarkShot/ShortcutRecorder.swift \
    Sources/DarkShot/LaunchAtLogin.swift Sources/DarkShot/SettingsWindowController.swift \
    Tests/DarkShotChecks/ShortcutChecks.swift -o .build/checks/ShortcutChecks
.build/checks/ShortcutChecks
