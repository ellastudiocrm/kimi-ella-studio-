import urllib.request, json, sys

url = 'https://api.github.com/repos/supabase/cli/releases/latest'
req = urllib.request.Request(url, headers={'Accept': 'application/vnd.github+json', 'User-Agent': 'python'})
data = urllib.request.urlopen(req).read()
j = json.loads(data)
assets = [a for a in j['assets'] if 'windows' in a['name'] and 'amd64' in a['name']]
if assets:
    print(assets[0]['browser_download_url'])
else:
    print('NOT_FOUND', file=sys.stderr)
    sys.exit(1)
