#!/bin/bash
set -eo pipefail

function log {
    echo "$(date '+%Y-%m-%d %H:%M:%S'): $1"
}

function watch_certificate_secret {
    local source_secret=$1
    local target_namespace=$2

    while true; do
        log "Going to watch $source_secret for reflecting to $target_namespace"

        kubectl get secret $source_secret --watch --no-headers -o "custom-columns=:metadata.name" | \
        while read secret; do
            log "Trying to read and apply $source_secret to $target_namespace"
            kubectl get secret "$secret" -o yaml | \
            sed '/^\ \ namespace:.*/d; /^\ \ uid:.*/d; /^\ \ resourceVersion:.*/d; s/^\ \ creationTimestamp:.*/  creationTimestamp: null/' | \
            kubectl -n $target_namespace apply -f - || true
        done
        log "Sleeping 60 seconds in $source_secret watcher"
        sleep 60
    done
    log "Exiting for $source_secret => $target_namespace"
}

for source_secret in $SOURCE_SECRETS; do
    for target_namespace in $TARGET_NAMESPACES; do
        watch_certificate_secret $source_secret $target_namespace & \
            pidlist="$pidlist $!"
    done
done

# Wait the subprocesses to exit !=0 (when source secret does not exist)
if ! wait -n $pidlist; then
    log "Subprocess(es) died, exiting"
    for i in $pidlist; do
        # If one did kill them all
        kill $i 2>/dev/null
    done
    exit 1
fi
