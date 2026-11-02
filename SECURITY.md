<!-- SPDX-License-Identifier: GPL-3.0-only -->

# Security Policy

🇫🇷 [Version française](SECURITY.fr.md)

nautilus-convert-images is maintained by one person, on a voluntary basis. This page explains how to report a security problem and what you can expect in return.

## Supported versions

Only the **latest release** receives security fixes. If you use an older version, please update first: the packages are on the [Releases page](https://github.com/gillesmagneville/nautilus-convert-images/releases) and the changes are listed in the [CHANGELOG](CHANGELOG.md).

## Reporting a vulnerability

**Please do not report a vulnerability in a public issue, pull request or discussion**: anyone could read it before a fix exists.

Report it privately, in one of these two ways:

1. **On GitHub**: open the [Security tab](https://github.com/gillesmagneville/nautilus-convert-images/security) of the repository and click **Report a vulnerability**. Only you and the maintainer can see the report.
2. **By email**: write to [gilles@magneville.fr](mailto:gilles@magneville.fr) with the subject "nautilus-convert-images security".

Please include, as far as you can:

- the version of the package (`dpkg -s nautilus-convert-images` or `rpm -q nautilus-convert-images`) and your distribution, with the Nautilus version (`nautilus --version`);
- a description of the problem and the steps to reproduce it;
- what you think the impact is;
- if the problem comes from a particular file, the file itself — only if you may share it.

## What to expect

These are goals, not guarantees, since there is only one maintainer:

- an acknowledgement of your report within **7 days**;
- an answer on whether it is considered a vulnerability, then news at least every few weeks until it is settled;
- a fix published in a **new release**, mentioned in the CHANGELOG; for a serious problem, a GitHub security advisory too;
- you are credited in the release notes, unless you prefer to stay anonymous.

Please keep the details private until a fixed version is available, so that users have the time to update.

## What is covered

nautilus-convert-images works on your computer, on your own photos, and does not send them anywhere. It does, however, **read image files that may come from anywhere** (a download, an email, a memory card). A report is relevant, for example, if:

- an image or RAW file makes the engine or the interface crash in an exploitable way, run code, or read or write files outside the chosen destination folder;
- a file or folder name makes the Nautilus extension or the interface run a command;
- the `.deb` or `.rpm` package, its installation script, or the release scripts can be abused;
- a file of a release does not match its published `.sha256` fingerprint.

## What is not covered

- A vulnerability in **Nautilus, nautilus-python, GTK or the system** itself: please report it to the project or the distribution concerned.
- A vulnerability in a **component developed by someone else**: please report it to that project. Some of these components are **built into the program** (the Rust image and RAW decoders such as `rawloader`, and LibRaw, compiled statically): users cannot update them separately, so do tell me as well, since the fix needs a new release of nautilus-convert-images.
- Problems that need a computer which is already compromised, or physical access to it.
- Ordinary bugs without security consequences: please open an [issue](https://github.com/gillesmagneville/nautilus-convert-images/issues) instead.

## Checking what you download

Download the packages only from the [Releases page](https://github.com/gillesmagneville/nautilus-convert-images/releases) of this repository. Each package is published with its own `.sha256` file (there is no global `SHA256SUMS`). To check a download, put the package and its `.sha256` file in the same folder:

```bash
sha256sum -c nautilus-convert-images_X.Y.Z_amd64.deb.sha256
```
