# Security Policy

## Reporting a vulnerability

Please **do not** report security issues in public GitHub issues,
discussions, or chat.

Report privately through GitHub's **[Security → Report a
vulnerability](https://github.com/dhaupin/synmergia/security/advisories/new)**
(GitHub Security Advisories). If you cannot use that, contact a
maintainer directly and ask for a private channel.

Please include, as best you can:

- What the issue is and where (file, service, endpoint, or game system).
- How to reproduce it, or a proof of concept.
- The impact you believe it has (what an attacker could do).
- Any suggested fix.

We will acknowledge your report as quickly as we can, keep you updated as
we work on it, and credit you in the fix if you would like.

## Scope

Synmergia is a networked game with an authoritative server, player
accounts, an in-game economy, and a payment seam. In scope:

- The authoritative server and its services (`game/core/`, `game/adapters/`).
- The web client and website (`web/`, `src/`, `functions/`).
- Authentication, accounts, sessions, and the `/play` + `/admin` gates.
- The economy, currency, and payment paths.
- Anti-cheat and rate-limiting bypasses.
- Anything that lets one player affect another's data or the server's
  integrity.

Out of scope: issues that require a compromised local machine, social
engineering, or findings only reachable by already having admin access.
Pure "the code is open, so here is a theoretical issue" reports without a
real impact path are welcome as issues, not advisories.

## Our posture

We assume the code will be read by everyone — that is the point of an
open source game. The server is authoritative; the client is never
trusted. If you find a place where the client is trusted, that is a bug
worth reporting.

## Supported versions

The default branch (`main`) is the supported version. There are no
long-term-support branches; fixes land on `main`.

## Secret handling

Secrets (database credentials, tokens, webhook and payment keys) live in
environment variables and deployment configuration, never in the
repository. If you believe a secret has been committed, report it
privately as above — do not open a public issue naming it.
