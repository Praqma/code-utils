# Bitbucket Cookie Authentication for `bitbucket_get_repo_sizes.sh`

This guide explains how to get Bitbucket session cookies and use them with `bitbucket_get_repo_sizes.sh`.

## Why use cookies?

On some Bitbucket instances, endpoint:

- `/projects/<project_key>/repos/<repo_slug>/sizes/`

works in a browser session but may fail with `netrc`/basic auth.

The script supports cookie-based auth via environment variables:

- `BITBUCKET_COOKIE_HEADER`
- `BITBUCKET_COOKIE_JAR`

If one of these is set, the script does **not** use `netrc`.

## Option 1: Copy request from browser (fastest)

1. Open Bitbucket in Edge and make sure the sizes URL returns JSON in the browser.
2. Press `F12` -> **Network**.
3. Reload the page.
4. Select the `.../sizes/` request.
5. Right-click -> **Copy** -> **Copy as cURL (bash)**.
6. Use the copied `Cookie:` value as `BITBUCKET_COOKIE_HEADER`.

Example:

```bash
BITBUCKET_COOKIE_HEADER="bitbucket-lv1=...;BITBUCKETSESSIONID=...;_atl_bitbucket_remember_me=..." \
bitbucket_get_repo_sizes.sh -u code.tsw.vestas.net -a
```

## Option 2: Use a cookie jar file

Create `cookie.jar` in Netscape format:

```text
# Netscape HTTP Cookie File
code.tsw.vestas.net	FALSE	/	FALSE	0	bitbucket-lv1	YOUR_VALUE
code.tsw.vestas.net	FALSE	/	FALSE	0	BITBUCKETSESSIONID	YOUR_VALUE
code.tsw.vestas.net	FALSE	/	FALSE	0	_atl_bitbucket_remember_me	YOUR_VALUE
```

Run script with cookie jar:

```bash
BITBUCKET_COOKIE_JAR=/path/to/cookie.jar \
bitbucket_get_repo_sizes.sh -u code.tsw.vestas.net -a
```

## Quick endpoint test with cookies

```bash
curl -k -H "Accept: application/json" \
  -H "Cookie: bitbucket-lv1=...;BITBUCKETSESSIONID=...;_atl_bitbucket_remember_me=..." \
  "https://code.tsw.vestas.net/projects/ASC/repos/film_club/sizes/"
```

Expected JSON example:

```json
{"repository":1530880,"attachments":0}
```

## Security notes

- Cookies are sensitive credentials. Treat them like passwords/tokens.
- Do not commit cookie values to git.
- Rotate/sign out sessions after troubleshooting.

## Documentation links

- curl cookie handling: https://curl.se/docs/http-cookies.html
- Bitbucket Server/Data Center REST intro: https://developer.atlassian.com/server/bitbucket/rest/v1000/intro/
- Feature request context for sizes endpoint: https://jira.atlassian.com/browse/BSERV-4988
