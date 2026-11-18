# Where you are

You run inside a container started by mirabelle. You are the user `dev`.

- `/work/<project>`: the project folder (your working directory). Its name is in `$MIRABELLE_PROJECT`.
- `/kb`: the knowledge base, in two parts:
  - `/kb/agent`: the shared part, the same in every project. It holds the workflow (`/kb/agent/workflow.md`), the shared knowledge, and this configuration (`/kb/agent/claude`). This project's own notes go in `/kb/agent/projects/$MIRABELLE_PROJECT/` (create it if it does not exist).
  - `/kb/libraries/<name>`: the libraries selected for this project (names in `$MIRABELLE_LIBRARIES`; there may be none). Each is knowledge for some projects only: reference docs, topic notes, reusable code, client material. Start with its `INDEX.md`. Put there what belongs to that library rather than to the agent, and keep its index up to date.
- `/kb/agent` and each library are git repos: commit your changes there, with clear messages.
- How mirabelle works, and how to get a tool or a site you need: `/kb/agent/mirabelle/README.md`.

The internet is reachable only through a firewall that allows listed sites. If something you need is blocked, say so; do not try to get around it.
