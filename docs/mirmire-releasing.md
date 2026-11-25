# Releasing Mirmire Cartouche

Cartouche's own release steps are in [releasing.md](releasing.md); Mirmire Cartouche's are these, run by GitHub Actions.

A release is a GitHub release holding `mirmire-cartouche.apk`, signed with the release key. Mirmire downloads it from
`https://github.com/Mirmire-Launcher/mirmire-cartouche/releases/latest/download/mirmire-cartouche.apk` when it installs
or updates Mirmire Cartouche (Settings › Plugins). The workflow `.github/workflows/release.yml` makes it.

## Once: the release key

Every release must be signed with the same key, or Android refuses to update an installed copy. Make it once and
keep it safe (a password manager, a backup): a lost key means users have to uninstall to get the next version.

```sh
keytool -genkeypair -v -keystore mirmire-cartouche-release.keystore -alias mirmire-cartouche \
  -keyalg RSA -keysize 4096 -validity 10000
```

keytool asks for a password and for a name; use the same password for the key when asked. Then, in the repository
on GitHub, Settings › Secrets and variables › Actions › New repository secret, add three secrets:

| Secret | Value |
|---|---|
| `RELEASE_KEYSTORE_BASE64` | the keystore as base64: `base64 -i mirmire-cartouche-release.keystore` (macOS) or `base64 -w0 mirmire-cartouche-release.keystore` (Linux) |
| `RELEASE_KEYSTORE_USER` | the alias, `mirmire-cartouche` |
| `RELEASE_KEYSTORE_PASSWORD` | the password |

Never commit the keystore (`*.keystore` is ignored).

## Each release

1. Add what changed to `CHANGELOG.md`.
2. Tag the commit and push the tag:

   ```sh
   git tag v0.6.0
   git push origin v0.6.0
   ```

   Or, on GitHub, Actions › Release › Run workflow, with the version (`v0.6.0`).
3. The workflow builds and signs the APK and publishes the release "Mirmire Cartouche 0.6.0" with
   `mirmire-cartouche.apk` (about 20 minutes). Running it again for the same tag replaces the APK.

The version comes from the tag: `v0.6.0` is version 0.6.0, version code 600 (`major × 10000 + minor × 100 + patch`).
Each release needs a higher version than the last.

A copy installed from a debug build (signed with the debug key) cannot be updated by a release: uninstall it once.
