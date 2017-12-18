#!/bin/bash
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root"
    exit 1
fi

if [ -z "$SERVER_NAME" ]; then
    echo "Please set SERVER_NAME"
    exit 1
fi

if [ -z "$DESTINATION" ]; then
    echo "Please set DESTINATION"
    exit 1
fi

echo "Starting backup of $SERVER_NAME to $DESTINATION at `date +'%Y-%m-%d %H:%M.%S'`"

BACKUP_NAME=$SERVER_NAME
CWD=$DESTINATION
#CWD="$( cd "$(dirname "$0")" ; pwd -P )"
RSYNC="/usr/bin/sudo /usr/bin/rsync"
BACKUP_FILE="$CWD/$BACKUP_NAME.sparsebundle"
BACKUP_MOUNT="$CWD/$BACKUP_NAME"
BACKUP_DB="$BACKUP_MOUNT/db"
BACKUP_FS="$BACKUP_MOUNT/fs"
EXCLUDES="$CWD/$BACKUP_NAME.excludes.rsync"
TODAY=`date +"%Y%m%d%H%M%S"`
BACKUP_FS_TODAY="$BACKUP_FS/$TODAY/"
SERVER_USER=${SERVER_USER:-rsync}

if [ ! -e "$EXCLUDES" ]; then
    echo "EXCLUDES file not found"
    exit 1
fi

echo "Backup bundle is $BACKUP_FILE"

if [ ! -e "$BACKUP_FILE" ]; then
    if ! hdiutil create -library SPUD -size 512g -nospotlight -fs "Case-sensitive Journaled HFS+" -type SPARSEBUNDLE -volname "$BACKUP_NAME backup" "$BACKUP_FILE"
    then
        echo "Could not create backup bundle"
        exit 1
    fi
fi

rm -rf "$BACKUP_MOUNT"

if ! mkdir -p "$BACKUP_MOUNT"
then
    echo "Could not create backup mount directory"
    exit 1
fi

if ! hdiutil attach -owners on -mountpoint "$BACKUP_MOUNT" "$BACKUP_FILE"
then
    rm -rf "$BACKUP_MOUNT"
    echo "Could not mound backup bundle"
    exit 1
fi

echo "Backing up to $BACKUP_FS_TODAY..."
BACKUP_FS_LAST="`find "$BACKUP_FS" -type d  -maxdepth 1 | sort | tail -n 1`/"
mkdir -p "$BACKUP_FS_TODAY"
# add to sudoers
# rsync	ALL=(ALL) NOPASSWD: /usr/bin/rsync --server --sender -logDtprze.iLsf --numeric-ids . /
if [ "$BACKUP_FS_LAST" == "$BACKUP_FS/./" ]; then
    echo "Previous backup was not found. Creating full backup..."
    rsync -z -e "ssh" \
	    --rsync-path="$RSYNC" \
	    --archive \
	    --exclude-from="$EXCLUDES" \
	    --numeric-ids \
        --progress \
        $SERVER_USER@$SERVER_NAME:/ "$BACKUP_FS_TODAY"
else
    echo "Previous backup was found at $BACKUP_FS_LAST. Creating incremental backup..."
    rsync -z -e "ssh" \
	    --rsync-path="$RSYNC" \
	    --archive \
	    --exclude-from="$EXCLUDES" \
	    --numeric-ids \
	    --link-dest="$BACKUP_FS_LAST" \
        --progress \
        $SERVER_USER@$SERVER_NAME:/ "$BACKUP_FS_TODAY"
fi

if [ -n "$MYSQL_PASSWORD" ]; then
    BACKUP_MYSQL="$BACKUP_DB/mysql"
    BACKUP_MYSQL_CURRENT="$BACKUP_MYSQL/$TODAY.mysql.bz2"
    mkdir -p "$BACKUP_MYSQL"

    echo "Backing up mysql to $BACKUP_MYSQL_CURRENT"

    ssh rsync@$SERVER_NAME "mysqldump \
	    --user=root \
	    --password="$MYSQL_PASSWORD" \
	    --all-databases \
	    --lock-tables \
	    | bzip2" > "$BACKUP_MYSQL_CURRENT"
fi

if [ -n "$PSQL_PASSWORD" ]; then
    BACKUP_PSQL="$BACKUP_DB/psql"
    BACKUP_PSQL_CURRENT="$BACKUP_PSQL/$TODAY.psql.bz2"
    mkdir -p "$BACKUP_PSQL"

    echo "Backing up postgresql to $BACKUP_PSQL_CURRENT"

    ssh $SERVER_USER@$SERVER_NAME 'export PGPASSWORD="' + $PSQL_PASSWORD + '"; \
        pg_dumpall -U postgres -h localhost \
        | bzip2' > "$BACKUP_PSQL_CURRENT"
fi

if ! hdiutil detach "$BACKUP_MOUNT"
then
    echo "Could not detach mountpoint"
    exit 1
else 
    rm -rf "$BACKUP_MOUNT"
fi

echo "Backup of $SERVER_NAME to $DESTINATION completed at `date +'%Y-%m-%d %H:%M.%S'`"
