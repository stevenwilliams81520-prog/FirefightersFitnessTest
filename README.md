# Firefighters Fitness Test

Native SwiftUI iPhone app with an Apple Watch companion for the Chester Step Test.

- **Watch:** Start Test reads your starting heart rate and begins the test. Record HR logs the current stage. Live heart rate is streamed to the iPhone.
- **iPhone:** built-in metronome (up-up-down-down, 15/20/25/30/35 steps a minute, 2-minute stages), spoken stage prompts, stage readings, auto-stop above 80% of max heart rate, VO2max estimate and chart.

## Build (Windows + Codemagic)

The Xcode project is generated on Codemagic's Mac by XcodeGen from `project.yml`, so there is no `.xcodeproj` in this repo.

1. In the Apple Developer portal, create two App IDs:
   - `com.stevenwilliams.firefightersfitnesstest` (iOS app)
   - `com.stevenwilliams.firefightersfitnesstest.watchkitapp` (watch app), with the **HealthKit** capability ticked
2. Create the app record in App Store Connect with the iOS bundle ID.
3. Push this folder to a new GitHub repo and add it to Codemagic.
4. In `codemagic.yaml`, set your App Store Connect integration name and the environment group that holds `CERTIFICATE_PRIVATE_KEY`.
5. Run the `firefighters-fitness-test` workflow. The build goes to TestFlight.
