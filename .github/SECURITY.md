# Security policy

## Scope

This repository contains an iOS game and an **optional** self-hosted backend.
There is no service operated by the maintainers — everything runs on machines
owned by the people who clone it.

That shapes what matters here:

| In scope | Out of scope |
|----------|--------------|
| Authentication and session handling | Local save editing on a jailbroken device |
| Injection, SSRF, or path traversal in the API | Extracting the run-signing secret from the app binary |
| Secrets or tokens leaking into logs or responses | Denial of service against your own localhost |
| Privilege escalation to the admin surface | Weak defaults you chose to keep in production |

The last item on the right is called out explicitly in
[docs/SECURITY-MODEL.md](../docs/SECURITY-MODEL.md): the anti-cheat raises the
cost of casual scripting, it does not make a public leaderboard tamper-proof.

## Supported versions

| Version | Supported |
|---------|:---------:|
| Latest `master` | ✅ |
| Latest tagged release | ✅ |
| Anything older | ❌ |

## Reporting a vulnerability

**Please do not open a public issue.**

1. Use [GitHub's private vulnerability reporting](https://github.com/hoangsonww/Flappy-Bird-Game/security/advisories/new), or
2. email **hoangson091104@gmail.com** with `SECURITY` in the subject.

Please include what you can:

- what the issue is and why it matters
- steps or a proof of concept
- affected version or commit
- the impact you think it has

You can expect an acknowledgement within **72 hours**, an assessment within a
week, and credit in the advisory unless you would rather not be named.

Please do not test against anything you do not own.

## If you run a public instance

The defaults are tuned for `localhost`. Before exposing the API:

```bash
JWT_ACCESS_SECRET=$(openssl rand -hex 48)
JWT_REFRESH_SECRET=$(openssl rand -hex 48)
ADMIN_TOKEN=$(openssl rand -hex 24)
NODE_ENV=production
DB_DRIVER=postgres
CORS_ORIGINS=https://your-domain
TRUST_PROXY=true
```

- Put TLS in front of it. The game accepts an explicit `https://` URL.
- `NODE_ENV=production` refuses to start without JWT secrets and rejects the
  in-memory driver — that is intentional.
- Keep `ADMIN_TOKEN` out of shell history and version control.
- Review [docs/SECURITY-MODEL.md](../docs/SECURITY-MODEL.md) first.

## What is already in place

- bcrypt password hashing (cost 11)
- Short-lived JWT access tokens; refresh tokens rotated and stored as SHA-256 hashes
- Session revocation on logout, password change, ban and account deletion
- Zod validation on every body, query and path parameter; 64 KB body cap
- Parameterised SQL throughout
- Three rate-limit buckets, `helmet` headers, a CORS allow-list
- Log redaction of credentials and tokens
- A non-root container running under `dumb-init`
