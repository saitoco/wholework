# Contributing to Wholework

Contributions are welcome. Please read this guide before opening a pull request.

## Developer Certificate of Origin (DCO)

To protect the intellectual property hygiene of this OSS project, all commits must include a `Signed-off-by:` trailer. This is enforced automatically by a CI check on every pull request.

By signing off your commits, you certify that:

> You have the right to submit this contribution under the project's open source license (Apache 2.0), and that your contribution does not introduce code you do not have the right to contribute.

The full DCO text is available at <https://developercertificate.org/>.

### How to sign off

**New commits** — pass `-s` to `git commit`:

```sh
git commit -s -m "your commit message"
```

Git will automatically append a `Signed-off-by:` line using your configured `user.name` and `user.email`.

**Amending an existing commit** — add sign-off without changing the message:

```sh
git commit --amend --no-edit -s
```

**Persist sign-off for all future commits** — configure Git globally:

```sh
git config --global format.signoff true
```

### What `Signed-off-by` means

Adding `Signed-off-by: Your Name <you@example.com>` to a commit certifies (under the DCO) that you have the right to submit this work under the Apache 2.0 license. It is **not** a copyright assignment — you retain ownership of your contribution.

### CI enforcement

The `DCO` check in CI will fail if any commit in a pull request is missing the `Signed-off-by:` trailer. Fix missing sign-offs by amending commits (see above) before pushing again.
