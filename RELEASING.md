# Releasing

Every client is versioned and released on its own, by pushing a tag with its prefix. The
[release workflow](.github/workflows/release.yml) runs that package's tests first and only
publishes when they pass. None of the packages has been published yet.

| Client | Tag | Where it goes | Needs before the first release |
|---|---|---|---|
| TypeScript | `ts-vX.Y.Z` | npm `@opensms/sdk` | npm org `opensms`, repository secret `NPM_TOKEN` |
| Python | `py-vX.Y.Z` | PyPI `opensms` | PyPI trusted publisher for this repo, environment `pypi` |
| .NET | `dotnet-vX.Y.Z` | NuGet `Opensms` | NuGet account, repository secret `NUGET_API_KEY` |
| Rust | `rust-vX.Y.Z` | crates.io `opensms` | repository secret `CARGO_REGISTRY_TOKEN` |
| Ruby | `ruby-vX.Y.Z` | RubyGems `opensms` | RubyGems trusted publisher for this repo |
| Java | `java-vX.Y.Z` | tests only for now | Maven Central namespace `io.opensms`, signing key and publishing plugin in `pom.xml` |
| Go | `go-vX.Y.Z` | tests only here | mirror repo `opensms-io/opensms-go`, tagged `vX.Y.Z` |
| PHP | `php-vX.Y.Z` | tests only here | mirror repo `opensms-io/opensms-php`, registered on Packagist |
| Swift | `swift-vX.Y.Z` | tests only here | mirror repo `opensms-io/opensms-swift`, tagged `X.Y.Z` |

## Steps

1. Bump the version in the package manifest (`package.json`, `pyproject.toml`, `Opensms.csproj`,
   `Cargo.toml`, `opensms.gemspec`, `pom.xml`) and in the client's user-agent string.
2. Run the package's unit tests and, against a sandbox, its live conformance suite
   (see [the root README](README.md#testing)).
3. Commit to `main`, then tag and push only that tag, for example
   `git tag py-v0.1.1 && git push origin py-v0.1.1`.
4. Watch the release workflow run in the Actions tab.

## Why Go, PHP and Swift have mirror repos

Go modules, Packagist and SwiftPM resolve a package from the root of a git repository, so a
client inside `packages/` cannot be installed from this monorepo. Their source is developed here
and copied to the mirror repo on release, where the version tag is pushed.
