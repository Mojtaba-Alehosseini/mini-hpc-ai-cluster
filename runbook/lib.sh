# shellcheck shell=bash
# Shared helpers for the runbook scripts. Run them from the repository root.
# Sourced by the induce/verify scripts, so it carries no shebang of its own.
hd(){ docker compose exec -T head "$@"; }
au(){ local u=$1; shift; docker compose exec -T -u "$u" -w "/shared/home/$u" head "$@"; }
onnode(){ local n=$1; shift; docker compose exec -T "$n" "$@"; }
