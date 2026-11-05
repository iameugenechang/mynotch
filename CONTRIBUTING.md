# Contributing to anotchup

This is an independent fork. Open issues and pull requests at [iameugenechang/mynotch](https://github.com/iameugenechang/mynotch), not in the upstream project.

Use Xcode to open `anotchup.xcodeproj` and select the `anotchup` scheme. Run `scripts/verify.sh` before submitting a change; use `scripts/verify.sh --build` when app wiring changes. These checks do not launch the app or request permissions.

Keep each change focused on one component. Follow [the architecture plan](docs/architecture-plan.md) and document behavioral contracts when moving code across boundaries. Preserve author notices and license terms.

Translations live in `anotchup/Localizable.xcstrings` and can be changed in a pull request. This fork does not use the upstream translation service.

Inherited publishing workflows are quarantined in `.github/disabled-workflows`. Do not enable them until signing, destinations, licenses, and release source publication have been reviewed for this fork.
