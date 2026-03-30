#!/bin/sh
# rebuild-index.sh — pre-builds the wired file index as the logged-in user.
#
# macOS TCC (kTCCServiceSystemPolicyRemovableVolumes) denies opendir() with
# EPERM for LaunchDaemon processes on external volumes, even when uid=0.
# Running this script via "launchctl asuser <uid>" puts it in the logged-in
# user's session where TCC grants for removable volumes are honoured.
#
# The wired daemon (wd_index_index_files) checks index_metadata for a fresh
# cache and skips its own TCC-blocked re-indexing when found.

exec 2>&1

CONF="/Library/Wired/data/etc/wired.conf"
DB="/Library/Wired/data/database.sqlite3"

[ -f "$CONF" ] || { echo "rebuild-index: $CONF not found"; exit 0; }
[ -f "$DB" ]   || { echo "rebuild-index: $DB not found"; exit 0; }

# Read the configured files path from wired.conf
FILES_PATH=$(grep -m1 '^files = ' "$CONF" | sed 's/^files = //' | tr -d '[:space:]')
[ -z "$FILES_PATH" ] && { echo "rebuild-index: no files path in wired.conf"; exit 0; }

if [ ! -d "$FILES_PATH" ]; then
    echo "rebuild-index: directory not accessible: $FILES_PATH"
    exit 0
fi

echo "rebuild-index: indexing $FILES_PATH ..."

PATH_LEN=${#FILES_PATH}

# ── Count files BEFORE touching the database ──────────────────────────────────
# This lets us detect a TCC-blocked enumeration (find returns 0 even though the
# directory exists) and bail out before wiping the existing good index.
FILES_COUNT=$(find "$FILES_PATH" \( -name ".*" -prune \) -o -type f -print 2>/dev/null | wc -l | tr -d ' ')
DIR_COUNT=$(find "$FILES_PATH" -mindepth 1 \( -name ".*" \) -prune \
    -o -mindepth 1 -type d -print 2>/dev/null | wc -l | tr -d ' ')
FILES_SIZE=$(find "$FILES_PATH" \( -name ".*" -prune \) -o -type f -print0 2>/dev/null | \
    xargs -0 stat -f '%z' 2>/dev/null | awk '{s+=$1} END{print s+0}')

# ── TCC safety check ──────────────────────────────────────────────────────────
# If find returned 0 items but the previously stored counts were non-zero, the
# enumeration was almost certainly blocked by macOS TCC (opendir → EPERM).
# Keep the existing index and metadata intact rather than overwriting with zeros.
PREV_FILES=$(sqlite3 "$DB" "SELECT COALESCE(files_count,0) FROM index_metadata LIMIT 1;" 2>/dev/null)
PREV_DIRS=$(sqlite3 "$DB"  "SELECT COALESCE(directories_count,0) FROM index_metadata LIMIT 1;" 2>/dev/null)

if [ "${FILES_COUNT:-0}" -eq 0 ] && [ "${DIR_COUNT:-0}" -eq 0 ]; then
    if [ "${PREV_FILES:-0}" -gt 0 ] || [ "${PREV_DIRS:-0}" -gt 0 ]; then
        echo "rebuild-index: enumeration returned 0 items but previous metadata has ${PREV_FILES:-0} files"
        echo "rebuild-index: TCC likely blocked opendir(); keeping existing index and metadata intact"
        echo "WIREDSERVER_SCRIPT_OK"
        exit 0
    fi
fi

# ── Build the SQL in a temp file (single transaction for speed) ───────────────
# find prunes dot-named entries (matching wired's own skip logic).
# .timeout 5000 tells sqlite3 to wait up to 5 s if the daemon holds a read
# lock, preventing "database is locked" failures on the index write.
TMPFILE=$(mktemp /tmp/wired-index.XXXXXX.sql)

{
    printf '.timeout 5000\n'
    printf 'BEGIN TRANSACTION;\n'
    printf "DELETE FROM 'index';\n"

    find "$FILES_PATH" \( -name ".*" -prune \) \
         -o \( \( -type f -o -type d \) -print0 \) | \
    while IFS= read -r -d '' FILEPATH; do
        # Skip the root directory entry itself
        [ "$FILEPATH" = "$FILES_PATH" ] && continue
        [ -z "$FILEPATH" ] && continue

        NAME=$(basename -- "$FILEPATH")
        VIRTUAL="${FILEPATH:$PATH_LEN}"

        # Escape single quotes for SQL
        NAME_E=$(printf '%s' "$NAME"     | sed "s/'/''/g")
        VIRT_E=$(printf '%s' "$VIRTUAL"  | sed "s/'/''/g")
        REAL_E=$(printf '%s' "$FILEPATH" | sed "s/'/''/g")

        printf "INSERT OR IGNORE INTO 'index' (name, virtual_path, real_path, alias) VALUES ('%s', '%s', '%s', 0);\n" \
            "$NAME_E" "$VIRT_E" "$REAL_E"
    done

    printf 'COMMIT;\n'
} > "$TMPFILE"

if ! sqlite3 "$DB" < "$TMPFILE" 2>&1; then
    echo "rebuild-index: database write failed"
    rm -f "$TMPFILE"
    exit 1
fi
rm -f "$TMPFILE"

# ── Write index_metadata so the daemon finds a fresh cache ───────────────────
# IMPORTANT: use local time, NOT UTC.
# wi_date_with_sqlite3_string() in wired interprets the stored string as
# local time and appends the local UTC offset before parsing.  Storing UTC
# here would make the index appear (UTC_offset) seconds older than it is,
# causing the freshness check (interval < 60) to always fail.
NOW=$(date "+%Y-%m-%d %H:%M:%S")

sqlite3 -cmd ".timeout 5000" "$DB" \
    "DELETE FROM index_metadata; \
     INSERT INTO index_metadata (date, files_count, directories_count, files_size) \
     VALUES ('$NOW', ${FILES_COUNT:-0}, ${DIR_COUNT:-0}, ${FILES_SIZE:-0});" 2>/dev/null || {
    echo "rebuild-index: metadata write failed"
    exit 1
}

echo "rebuild-index: done — ${FILES_COUNT:-0} files, ${DIR_COUNT:-0} dirs indexed from $FILES_PATH"
echo "WIREDSERVER_SCRIPT_OK"
exit 0
