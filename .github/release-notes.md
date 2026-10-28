### Install

```bash
curl -fsSL https://chavdaujjval.github.io/copycat/install | bash
```

or, with Homebrew:

```bash
brew install chavdaujjval/tap/copycat
```

### Verify this download

`Copycat.dmg` was built by GitHub Actions from this repository. To check it, download `Copycat.dmg` and `Copycat.dmg.sha256` into the same folder, then run:

```bash
shasum -a 256 -c Copycat.dmg.sha256
gh attestation verify Copycat.dmg -R ChavdaUjjval/copycat
```
