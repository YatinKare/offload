# Offload

Swipe through your iPhone photos and archive originals to an external drive.

Offload keeps review simple: a photo, a swipe, and a few controls. No account or photo uploads.

## How it works

- **Swipe left** to archive. A red edge fade follows the gesture.
- **Swipe right** to keep the photo on your phone. A green edge fade follows the gesture.
- **Wait five seconds** to keep automatically. Tap the timer ring to pause.
- **Undo** returns to the previous photo.

Connect a USB drive, choose a folder, and open Photos to begin. A short walkthrough explains the controls on first launch; the **?** button reopens it.

Archiving copies the original files and checks the copied bytes using SHA-256. A swipe never deletes a photo. The checkmark and count open a separate removal confirmation, which verifies the copies again before asking Apple Photos to remove the originals.

## Requirements

- iPhone running iOS 18 or later
- An external drive accessible through Files
- Xcode 26 or later to build the app

## Build

```sh
git clone https://github.com/YatinKare/offload.git
cd offload
open Offload.xcodeproj
```

Select your signing team in **Signing & Capabilities**, choose your iPhone, and run. If iOS requests it, trust the development profile under **Settings → General → VPN & Device Management**.

The checked-in project is ready to open. To regenerate it from `project.yml`:

```sh
brew install xcodegen
xcodegen generate
```

## Testing

Run the `Offload` test scheme in Xcode, or use:

```sh
./scripts/test-e2e.sh
# Optionally select a particular simulator:
./scripts/test-e2e.sh SIMULATOR_UUID
```

The UI tests cover review gestures, undo, the timer, onboarding, archive verification, unavailable destinations, corrupted copies, and confirmed removal. They use generated sample images and a simulator-only destination.

## Storage and privacy

Photo processing runs on the device. Archives are written to `Offload/<archive ID>/` on the selected drive, alongside a receipt describing the original resources and their hashes. Live Photo components and other resources supplied by PhotoKit are preserved. An app-local receipt index tracks archives awaiting removal.

**Deleting from iCloud Photos also deletes from other synced devices.** Recently Deleted can retain photos for 30 days, so removing them may not immediately free space. Offload does not empty Recently Deleted.

Originals stored in iCloud may need to download before archiving. Export also needs temporary space on the phone. Review currently supports photos, screenshots, and Live Photos; standalone videos are not included.

Keep another backup before permanently deleting irreplaceable originals.

## License

[MIT](LICENSE)
