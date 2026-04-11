# CLAUDE.md

## Testing

Run both unit and e2e tests before finishing work:

```sh
# Unit tests
xcodebuild test -project HardWayHome.xcodeproj -scheme HardWayHome -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:HardWayHomeTests

# E2E tests (simulator)
xcodebuild test -project HardWayHome.xcodeproj -scheme HardWayHomeUITests -destination 'platform=iOS Simulator,name=iPhone 16'
```

## Project

- Uses xcodegen (`project.yml`) — run `xcodegen generate` after changing targets or adding/removing files
- Swift 6 with `SWIFT_STRICT_CONCURRENCY: targeted`
- iOS 18.0 deployment target
