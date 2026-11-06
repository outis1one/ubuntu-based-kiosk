# CLAUDE.md

## No user data in the repo

Never write anything specific to a person's kiosk, network or accounts into
this repository - not in code, tests, fixtures, docs, comments, commit
messages, branch names or pull request text.

That includes:

- WiFi network names (SSIDs), passwords, keys and tokens
- MAC addresses, IP addresses, hostnames and interface names taken from a
  real machine
- usernames, email addresses, PINs and passwords
- the URLs of someone's own sites or services
- log output, screenshots or terminal output pasted in by a user

When an example, test or fixture needs a value like these, use an obvious
placeholder (`ExampleNet`, `192.0.2.10`, `aa:bb:cc:dd:ee:ff`, `wlan0`,
`example.com`) instead of a real one. When debugging from output a user
shares, keep it in the conversation or the scratchpad, not in a file in this
repo, and leave it out of commit messages.
