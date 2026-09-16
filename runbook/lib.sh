# Shared helpers for the runbook scripts. Run them from the repository root.
hd(){ docker compose exec -T head "$@"; }
au(){ local u=$1; shift; docker compose exec -T -u "$u" -w "/shared/home/$u" head "$@"; }
onnode(){ local n=$1; shift; docker compose exec -T "$n" "$@"; }
