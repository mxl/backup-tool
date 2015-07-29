# backup-tool
Script for incremental backup to OS X Sparse Bundle with rsync over ssh.

## Prerequisites

Local host:
- install rsync;
- generate ssh key for root user;  

Remote host that will be backed up:
- run ssh daemon on port 22;
- install rsync on local and remote hosts;
- create `rsync` user on remote host:
`sudo useradd -m -s /bin/sh -N rsync`
- add this line to `sudoers` file:
`rsync  ALL=(ALL) NOPASSWD: /usr/bin/rsync --host --sender -logDtprze.iLsf --numeric-ids . /`
- append public key of generated ssh key to `/home/rsync/.ssh/authorized_keys` on remote host.


## Usage

Script must be runned as root.

Use following environment variables to configure script:

`host_NAME` (required) - domain  or ip of remote host that will be backed up.
`DESTINATION` (required) - destination folder for backup.
`EXCLUDES` (optional) - path to file that contains paths that should be excluded from backup and is used in `--exclude-from` option of `rsync`. 
`MYSQL_PASSWORD` (optional) - password for MySQL `root` user.
`PSQL_PASSWORD` (optional) - password for PostgreSQL `postgres` user.

Run script:

```shell
host_NAME=example.com DESTINATION=~/mybackup EXCLUDES=~/mybackup/excludes.rsync ./backup.sh
```
