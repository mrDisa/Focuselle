# Focuselle landing — local review

Static HTML/CSS/JS, deployed to GitHub Pages by `.github/workflows/deploy-pages.yml`. The workflow verifies the installer SHA-256, uploads `landing/dist/`, and deploys that exact artifact.

From the repository root, run in your own Terminal:

```sh
python3 -m http.server 4173 --bind 127.0.0.1 --directory landing/dist
```

Then open http://127.0.0.1:4173/. Stop the server with Ctrl+C.
You can also open `dist/index.html` directly in your browser; all assets are local.

The download links point to `downloads/Focuselle-0.4.1-arm64.dmg`.
Build the installer with `./scripts/package-dmg.sh`. The reviewed versioned binary and checksum are kept with the landing source.

Requirements: macOS 14+, Apple Silicon. The installer currently has an ad hoc signature,
not an Apple Developer ID signature or notarization ticket; macOS may block a downloaded copy.
Do not present this as a notarized public release.

The screenshot illustration is rendered from the app's timer and transport views, with
an example task and a presentation frame. Rebuild with `./scripts/render-preview.sh`.
The icon artwork is generated; theme variants live in `branding/`. `./scripts/make-icon.py` packages the dark tile into ICNS and copies the light tile for runtime Dock switching.

QA completed: app build and tests, ICNS format recognition, plist/Xcode project syntax,
DMG checksum verification, JS syntax, and existence of all local asset/download targets.
Browser layout QA remains pending: this execution environment refused to bind a local server,
and its browser policy does not permit file:// pages. Review desktop and mobile layouts before deployment.

GitHub repository Settings → Pages → Source must be **GitHub Actions**. Pushes changing `landing/dist/` deploy automatically. Expected project URL: https://mrDisa.github.io/Focuselle/ (confirm workflow success before treating it as live).
