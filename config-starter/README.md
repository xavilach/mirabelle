# mirabelle config

Your mirabelle configuration. It is yours, not the tool's: it is pushed to your
own home (`mirabelle home`), never to the plumbing's GitHub repo.

- `sites.txt`: sites every project may reach (on top of the plumbing's own)
- `libraries.txt`: the list of libraries
- `identities/<name>/`: git name, email, hosts, trusted certificates (tokens are in ~/mirabelle/secrets)
- `projects/<name>/sites.txt`: sites for one project
- `projects/<name>/Dockerfile`: extra image layer for one project (`ARG BASE` / `FROM ${BASE}`)
