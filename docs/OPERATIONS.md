# Operations

Use `vellum-aio status` for the supervisor's state and `vellum-aio doctor` for the persisted identity and SQLite integrity checks. Use Docker logs for service errors. Test updates by stopping the container, backing up appdata and starting the approved image on the same bind. Keep the previous image digest and its matching snapshot.

For a consistent backup, stop Vellum AIO before archiving the entire appdata directory. Use a location outside appdata and keep the archive private because it contains credentials. For example, from a host shell with access to the backing files:

```sh
umask 077
tar --numeric-owner -czf /path/to/backup/vellum-aio.tar.gz -C /mnt/user/appdata/vellum-aio .
```

Restore into an empty appdata directory, retaining numeric ownership and file permissions. Start the matching image and verify `READY`, the same assistant and paired-device access before deleting the old backup.
