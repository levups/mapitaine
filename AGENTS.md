# Mapitaine

XML sitemaps for Rails sites in many languages: one `Mapitaine::Source` class per kind of page, hreflang links
written from the languages of each record, files cut by ranges of ids, and builds that rewrite only the ranges
whose count or latest change moved.

`README.md` covers usage, `STYLE.md` code style, `CONTRIBUTING.md` contributions; this file adds what they leave out.

## Commands

```sh
bundle exec rake test                                            # the newest Rails (Gemfile)
BUNDLE_GEMFILE=gemfiles/rails_8_0.gemfile bundle exec rake test  # the oldest maintained Rails
bundle exec rubocop
bundle exec ruby [--yjit] bench/build.rb                         # 30,000 records in 24 languages
```

CI also runs `ruby-head`, and every Ruby with each Gemfile. A new Rails gets a `gemfiles/rails_X_Y.gemfile` and
joins CI's `rails` matrix.

## Traps

- Active Record, Action Pack and aws-sdk-s3 stay out of the gemspec: a source duck-types its relation, the Railtie
  brings the route helpers, and `Storage::S3` requires the SDK when it is built.
- Mapitaine never requests a page of the site, and never hooks into models: a build reads the database and the
  manifest of the last build, nothing else.
- A file name is a promise: the same ids land in the same file at every build. Anything that moves them (the shard
  size, the slug, the file name) belongs in `Configuration#digest` or rewrites everything by itself.
- A build publishes the sitemap files, then the index, then deletes, then writes the manifest. Keep that order: it
  is what lets the next build repair one that died midway.
- `priority`, `changefreq` and the ping endpoints are left out on purpose.
- The README's table comes from `bench/build.rb`: run it again when the build path changes.

## Rules for all our gems

This section and the next two read the same in super-slim, gamba, crumbly, agentry and mapitaine: change all five
together.

- Every maintained Ruby and Rails (https://endoflife.date), nothing older. The oldest sets `required_ruby_version`,
  `TargetRubyVersion` and the Rails floor, and leaves in the release after its end of life.
- CI runs RuboCop and the tests on each maintained Ruby. No macOS job: we test on our Macs.
- `.claude/hooks/rubocop.sh` autocorrects each Ruby file you edit.
- Measure performance without JIT and with YJIT. A Performance cop the numbers contradict is disabled on its line,
  with the reason. A pure performance change pins no internals in tests.
- Test and bench data are anonymized: `alice`, `Post`, `example.com`.
- Everything in the repository is in English (code, comments, commits, pull requests, issues, reviews, replies),
  whatever the conversation's language.
- No AI attribution in anything people read; commits flag AI help with `Assisted-by`, never `Co-Authored-By`.

## Pull requests and issues

- `main` takes no direct push: every change, releases included, goes through a pull request that merges itself once
  CI is green (`gh pr merge --auto --squash`).
- Drafts run no CI. Confident: open it ready, auto-merge on. Not yet: a draft, then `gh pr ready` when it needs CI.
- Never edit `CHANGELOG.md` in a pull request, they would all conflict: it is written at release time.
- Title: the change as a user sees it (an issue: the finding), in plain words, under 70 characters.
- Body, no headings: two short paragraphs, the problem then the change (an issue: what to do); 3 to 5 bullets, each
  opening with a **bold 2–4 word lead-in**; the proof (reproduction, tests, benchmarks) folded in one `<details>`.
  Nothing the diff or CI already says.
- Never hard-wrap a pull request, an issue or a comment: GitHub renders every line break. One line per paragraph and
  per bullet.

## Releases

The user is needed twice: a working git signing key (the tag is signed) and one click approving the `release`
environment on GitHub.

1. Another session may have just released: `git fetch --tags origin`, and `gh pr list --search "head:release/"`
   must be empty. Unreleased changes: `git log --first-parent --oneline $(git describe --tags --abbrev=0 origin/main)..origin/main`,
   then `gh pr view <n>` for each.
2. Write the release under `## [Unreleased]` in `CHANGELOG.md`, uncommitted: a one-sentence lede, then **Breaking**,
   **New**, **Faster** (measured), **Fixed**, only those with entries. One entry per change users see, written for
   them; CI, refactoring, docs and tests get none. No version, date or link: `bin/release` adds them.
3. Show it to the user, wait for their go. From `main` level with `origin/main`, `CHANGELOG.md` its only change:
   `bin/release minor --dry-run`, then `bin/release minor --yes` (or `patch`, `major`). It opens `release/vX.Y.Z`,
   waits for it to merge itself, pushes the signed tag. Signing fails: the user fixes it, never an unsigned tag.
   Interrupted after the merge: `bin/release --tag X.Y.Z`.
4. The tag runs `release.yml`, which waits for the user to approve the `release` environment, then publishes to
   RubyGems and GitHub. Open that run in their browser, where they click Review deployments, `release`, Approve:
   `gh run view --web $(gh run list --workflow release.yml --branch vX.Y.Z --json databaseId -q '.[0].databaseId')`,
   once the run exists: it starts a few seconds after the tag, and without `--branch` the previous release's run
   opens.
   Then check RubyGems.

RubyGems trusts only that workflow: never `gem push`, except a new gem name's first version. `bin/release` and
`release.yml` are identical in all five gems.
