# Where you are

You run inside a container started by mirabelle. You are the user `dev`.

- `/work/<project>`: the project folder (your working directory). Its name is in `$MIRABELLE_PROJECT`.
- `/kb`: the shared kb, the same folder in every project. It holds the workflow, the knowledge, and this configuration (`/kb/claude`).
- This project's own knowledge is in `/kb/projects/$MIRABELLE_PROJECT/` (create it if it does not exist).
- How the workflow is meant to go: `/kb/workflow.md`.
- How mirabelle works, and how to get a tool or a site you need: `/kb/mirabelle/README.md`.

The internet is reachable only through a firewall that allows listed sites. If something you need is blocked, say so; do not try to get around it.
