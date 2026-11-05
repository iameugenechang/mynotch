# Disabled publishing workflows

These inherited release, nightly, update-feed website, and translation workflows are outside `.github/workflows`, so GitHub Actions will not execute them. Local project/product references were renamed, but upstream publishing destinations and Homebrew integration remain historical references, not fork release configuration.

Do not move them back without reviewing every publishing destination, repository permission, signing credential, updater key, and license/source-distribution requirement. The historical feeds in `updater/` are not anotchup releases and must not be published as such. The app does not enable an update feed.

Unsigned verification remains active. Renaming this fork does not rename external repositories or give it access to upstream infrastructure.
