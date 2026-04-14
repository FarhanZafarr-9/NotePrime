<div>
  <img src="assets/logo.png" alt="Note Safe App" width="200">
</div>

# Note Safe — Material You Fork

> A modern fork of [Note Safe by jeerovan](https://github.com/jeerovan/ntsapp) with Material You theming, a refined UI, and ongoing improvements.

Notes app with a chat-like interface and end-to-end encrypted cloud backup/sync.

---

## Install

> [!WARNING]  
> **Important Migration Notice:** If you are installing this fork seamlessly over the original Note Safe application, **you must safely back up your data first!** Because cryptographic security signatures and local database architectures may incrementally differ, please ensure you export all your notes as a secure `.zip` backup from within the original app *before* overwriting it with this version. You can then instantly restore your data inside the fork!

* Android — [GitHub Releases](https://github.com/FarhanZafarr-9/ntsapp/releases/)
* Original Play Store — [Note Safe on Play Store](https://play.google.com/store/apps/details?id=com.makenotetoself) *(original app by jeerovan)*
* Fork support for Windows / Linux / macOS / iOS — Coming soon

[<img src="https://raw.githubusercontent.com/mateusz-bak/openreads/master/doc/github/get-it-on-github.png"
    alt="Get it on Github"
    height="80">](https://github.com/FarhanZafarr-9/ntsapp/releases/)

---

## What's Different in This Fork

This fork builds on the solid foundation of the original Note Safe app and completely modernizes the experience:

### Overview of Enhancements
*   **Material 3 & Material You** — Implements dynamic color engines that seamlessly adapt to your system palette (Android 12+), fully transforming all UI components, dialogs, and panels.
*   **Refined Chat UI** — Overhauled the conversation view featuring asymmetric message bubbles, dynamic width constraints, dedicated swipe-to-reveal exact timestamps, and day-based visual grouping (`Today`, `Yesterday`).
*   **Intelligent Media Viewer** — Re-engineered standard viewers to automatically scale exceptionally wide panoramas and tall screenshots, enabling natural scrolling and edge-to-edge boundary tracking with 10.0x pinch-to-zoom limits and native *Save to Downloads* functionality.
*   **Advanced Formatting** — Restyled embedded location, contact, audio, and file widgets with sleek tonal backgrounds, circular borders, and contextual padding algorithms.
*   **Glance-Privacy Shield** — Introduced a granular per-group "Privacy Shield" that blurs sensitive text and media thumbnails with a premium glassmorphic effect. Content remains hidden until revealed with a tap, strictly gating all message interactions while active.
*   **Enhanced Security Layers** — Integrated a highly robust "App-Lock Shield" covering background modes and biometric-gated authentication setups that properly restore active screen matrices on unlock.
*   **Sleek Menus & Settings** — Standardized floating popup menus and completely refactored the settings layouts into deeply integrated Material 3 list tiles featuring inline high-precision color-picker dialogs.

### Differences at a Glance

| Feature / Interface | Original Implementation | Note Safe Fork |
| :--- | :--- | :--- |
| **Theming Engine** | Static custom themes and blocky elements | Full Material 3 support with system-level **Material You** integration |
| **Message Layouts** | Symmetrical blocks across the screen | Modern **asymmetric chat bubbles** adapting dynamically to content width |
| **Feed Experience** | Timestamps attached to every internal item | Grouped chronological headers with **swipe-to-reveal** item timestamps |
| **Media Previews** | Distorted borders or unscalable limits on long images | **Edge-to-edge** rendering, smart panorama detection, and smooth native panning |
| **Glance-Privacy** | No way to hide sensitive content from onlookers | Granular **per-group blur** with tap-to-reveal gesture |
| **Security Gates** | Basic lock overlays | Sophisticated **App-Lock Shield** routing handling app-lifecycle obfuscation |

---

## About Note Safe

Note Safe is a secure, open-source note-taking application designed for privacy and reliability. Built with a local-first approach, it works fully offline and lets you backup and restore your data at any time. Note Safe supports all types of multimedia notes with seamless cloud sync for effortless cross-device access.

What makes Note Safe truly special is its strong cryptographic security, powered by Libsodium APIs — a widely respected, modern, and high-performance encryption library. Libsodium provides end-to-end encryption, meaning only you can access your data, and no one — not even the cloud provider — can decrypt your notes.

With Supabase as the backend and a single Flutter codebase for cross-platform compatibility, Note Safe delivers a smooth, reliable, and highly secure note-taking experience across all devices.


---

## Security

If you believe you have found a security vulnerability, please email [getphonesafe@gmail.com](mailto:getphonesafe@gmail.com) instead of opening a new issue.

---

## Credits

Original app made with ❤️ by [jeerovan](https://github.com/jeerovan/ntsapp) and team [Olauncher](https://github.com/tanujnotes/Olauncher).

Fork maintained by [FarhanZafarr-9](https://github.com/FarhanZafarr-9).