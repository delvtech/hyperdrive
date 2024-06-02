# Contributing to Hyperdrive

## Bugfixes & issues

If you find a bug, we recommend that you post an [issue](https://github.com/delvtech/hyperdrive/issues) to allow for discussion before creating a pull request.

## Release steps

1. [ ] Double-check that the version in `contracts/src/libraries/Constants.sol` matches the version to be tagged. If it doesn't, open a PR to update the version before tagging.
2. [ ] Tag the release with `git tag vX.Y.Z`.
3. [ ] Push the release to Github with `git push --tags`
4. [ ] Go to the `releases` tab in Github and add the new tag as a release. Click the "Generate Release Notes" button to generate release notes.