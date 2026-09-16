# Release Process

## Container Image

The `Publish container` workflow builds and publishes
`ghcr.io/kethort/iwave-g57m-lab` for version tags and manual runs.

```bash
git tag v0.1.0
git push origin v0.1.0
```

A version tag publishes both the versioned tag and `latest`.

## Website

The `Publish website` workflow deploys the Hugo site under `site/` when site
content changes on `main`. GitHub Pages must use **GitHub Actions** as its build
source.

## Executable Checksum

Create and verify the release checksum with:

```bash
sha256sum qt_boot_gui > qt_boot_gui.sha256
sha256sum --check qt_boot_gui.sha256
```

Keep the application source in its private repository. This public repository
contains only the stripped executable, release packaging, configuration
templates, documentation, and license notices.
