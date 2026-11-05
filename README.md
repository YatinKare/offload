# Offload

Swipe through your iPhone photos and archive originals to an external drive.

Offload keeps review simple: a photo, a swipe, and a few controls. No account or photo uploads.

## How it works

- **Swipe left** to archive. A red edge fade follows the gesture.
- **Swipe right** to keep the photo on your phone. A green edge fade follows the gesture.
- **Wait five seconds** to keep automatically. Tap the timer ring to pause.
- **Undo** returns to the previous photo.

Connect a USB drive, choose a folder, and open Photos to begin. A short walkthrough explains the controls on first launch; the **?** button reopens it.

A swipe records your decision and moves to the next photo immediately. Copies run one at a time in a saved queue, so downloads and drive speed do not interrupt review.

The archive button opens a list with previews and waiting, copying, saved, or attention states. Open an item to **Check copy**, **Archive again**, or **Keep on phone**. Failed jobs can be retried; a disconnected drive pauses the queue until it is reconnected. Keep Offload open while copying. If the app closes, waiting work is retained and resumes after you select the drive again.

A swipe never deletes a photo. **Verify & remove** reads the saved copies and compares them with the current originals before offering removal. A changed metadata timestamp triggers a check rather than permanent rejection. Photos whose contents differ stay in the archive list for recovery; other verified photos can still be removed.

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

The UI tests cover slow-copy responsiveness, queue persistence, retry and undo, onboarding, legacy receipt migration, metadata-only changes, edited originals, corrupted copies, cancellation, and confirmed removal. They use generated sample images and a simulator-only destination.

## Storage and privacy

Photo processing runs on the device. Archives are written to `Offload/<archive ID>/` on the selected drive, alongside a receipt describing the original resources and their hashes. Live Photo components and other resources supplied by PhotoKit are preserved. An app-local journal retains queue decisions and verified receipts. Existing receipt indexes are migrated automatically. Undo or Keep may leave an already-written drive copy in place; neither action deletes originals or archive files.

**Deleting from iCloud Photos also deletes from other synced devices.** Recently Deleted can retain photos for 30 days, so removing them may not immediately free space. Offload does not empty Recently Deleted.

Originals stored in iCloud may need to download before archiving. Export also needs temporary space on the phone. Review currently supports photos, screenshots, and Live Photos; standalone videos are not included.

Keep another backup before permanently deleting irreplaceable originals.

## License

[MIT](LICENSE)
