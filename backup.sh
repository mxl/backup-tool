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
        rsync@$SERVER_NAME:/ "$BACKUP_FS_TODAY"
else
    echo "Previous backup was found at $BACKUP_FS_LAST. Creating incremental backup..."
    rsync -z -e "ssh" \
	    --rsync-path="$RSYNC" \
	    --archive \
	    --exclude-from="$EXCLUDES" \
	    --numeric-ids \
	    --link-dest="$BACKUP_FS_LAST" \
        --progress \
        rsync@$SERVER_NAME:/ "$BACKUP_FS_TODAY"
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

    ssh rsync@$SERVER_NAME 'export PGPASSWORD="' + $PSQL_PASSWORD + '"; \
        pg_dumpall -U postgres -h localhost \
        | bzip2' > "$BACKUP_PSQL_CURRENT"
fi

cd "$BACKUP_FS"
ALL_BACKUPS=(*)
KEEP_BACKUPS=()

# keep one backup for each of last 7 days
for i in {1..7}
do
    DAY_BACKUPS=(`date -v "-${i}d" +"%Y%m%d"`*)
    if [ ${#DAY_BACKUPS[@]} > 0 ]; then
        KEEP_BACKUPS=("${KEEP_BACKUPS[@]}" "${DAY_BACKUPS[0]}")
    fi
done

# keep one backup for each of last 5 weeks
for i in {1..5}
do
    WEEK_START=`date -v "-$((i+1))w" +"%Y%m%d"`
    WEEK_END=`date -v "-${i}w" +"%Y%m%d"`
    WEEK_BACKUPS=($(echo ${ALL_BACKUPS[@]} | awk -v RS=" " "\$0 < \"$WEEK_END\" && \$0 >= \"$WEEK_START\""))
    if [ ${#WEEK_BACKUPS[@]} > 0 ]; then
        KEEP_BACKUPS=("${KEEP_BACKUPS[@]}" "${WEEK_BACKUPS[0]}")
    fi
done

# keep one backup for each of last 6 months
for i in {1..6}
do
    MONTH_START=`date -v "-$((i+1))m" +"%Y%m%d"`
    MONTH_END=`date -v "-${i}m" +"%Y%m%d"`
    MONTH_BACKUPS=($(echo ${ALL_BACKUPS[@]} | awk -v RS=" " "\$0 < \"$MONTH_END\" && \$0 >= \"$MONTH_START\""))
    if [ ${#MONTH_BACKUPS[@]} > 0 ]; then
        KEEP_BACKUPS=("${KEEP_BACKUPS[@]}" "${MONTH_BACKUPS[0]}")
    fi
done

for b in ${KEEP_BACKUPS[@]}
do
    ALL_BACKUPS=(${ALL_BACKUPS[@]/$b})
done

echo "Removing old backups..."

rm -rf ${ALL_BACKUPS[@]}

echo "Detaching backup image..."

if ! hdiutil detach "$BACKUP_MOUNT"
then
    echo "Could not detach mountpoint"
    exit 1
else 
    rm -rf "$BACKUP_MOUNT"
    echo "Compacting backup image..."
    hdiutil compact "$BACKUP_FILE"
fi

echo "Backup of $SERVER_NAME to $DESTINATION completed at `date +'%Y-%m-%d %H:%M.%S'`"
