# Operations

Use `vellum-aio status` for the supervisor's state and `vellum-aio doctor` for the persisted identity and SQLite integrity checks. Use Docker logs for service errors. Test updates by stopping the container, backing up appdata and starting the approved image on the same bind. Keep the previous image digest and its matching snapshot.

For a consistent backup, stop Vellum AIO before archiving the entire appdata directory. Use a location outside appdata and keep the archive private because it contains credentials. For example, from a host shell with access to the backing files:

```sh
umask 077
tar --numeric-owner -czf /path/to/backup/vellum-aio.tar.gz -C /mnt/user/appdata/vellum-aio .
```

Restore into an empty appdata directory, retaining numeric ownership and file permissions. Start the matching image and verify `READY`, the same assistant and paired-device access before deleting the old backup.

## ChatGPT Subscription models

Vellum AIO includes GPT-6.1 Sol and GPT-6.1 Terra in the bundled model picker. OpenAI controls which models each ChatGPT account can use. Both models list a 128,000-token output limit and a 1,050,000-token total context window in the OpenAI API catalog. Subscription limits can vary. In Vellum, the context window setting is an input budget for conversation history, and the ChatGPT subscription transport leaves the output limit to OpenAI.

To pick up future models automatically, link your account using OpenAI's [Sign in with ChatGPT preview](https://developers.openai.com/siwc/token-sharing-open-source). Run this on the machine with your browser, from the repository checkout. Substitute the SSH login you use for your Unraid host.

```sh
python3 scripts/chatgpt-sign-in.py --ssh root@UNRAID_HOST
```

For a container running on the same machine as your browser, omit `--ssh`. Use `--engine podman` for Podman and `--container NAME` if you renamed the container. The callback listens only on your browser machine's loopback interface. No Caddy or container port changes are needed.

After authorizing, reload Vellum and choose a model under **Settings → Models & Services → Profiles** using **ChatGPT Subscription**. The active subscription connection now uses the signed-in account's catalog and the public Responses API. Saved profiles keep their model selections. If your account's catalog omits a saved model, choose one it offers.

Vellum AIO refreshes the account catalog every 15 minutes. To refresh it immediately, run `docker exec vellum-aio vellum-aio chatgpt refresh` on the container host, then reload Vellum. Re-run the sign-in command to renew authorization for the same account. To switch accounts, disconnect first and run sign-in with `--new-account`. Use `docker exec vellum-aio vellum-aio chatgpt disconnect` to revoke the session and clear its locally stored tokens. You can then use Vellum's built-in sign-in to return to the bundled catalog.
