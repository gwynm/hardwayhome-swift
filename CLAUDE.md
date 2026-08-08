# CLAUDE.md

## Testing

Run both unit and e2e tests before finishing work:

```sh
# Unit tests
xcodebuild test -project HardWayHome.xcodeproj -scheme HardWayHome -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:HardWayHomeTests

# E2E tests (simulator)
xcodebuild test -project HardWayHome.xcodeproj -scheme HardWayHomeUITests -destination 'platform=iOS Simulator,name=iPhone 16'
```

## Installing on a phone

Only install **Release** builds on physical devices (`xcodebuild -configuration Release`);
Debug builds are for the simulator. DEBUG once enabled GRDB's erase-on-schema-change,
and a Debug install on the phone silently wiped all real workout data (the guard is now
simulator-only, but keep the rule). If a wipe ever happens anyway: the app keeps backups
on-device in `Documents/backups` inside its data container, and uploads them to Seafile
(`~/sea/hardwayhome/data` on the Mac).

## Project

- Uses xcodegen (`project.yml`) — run `xcodegen generate` after changing targets or adding/removing files
- Swift 6 with `SWIFT_STRICT_CONCURRENCY: targeted`
- iOS 18.0 deployment target
