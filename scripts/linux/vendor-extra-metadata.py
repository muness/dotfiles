#!/usr/bin/env python3
"""Current HQPlayer downloads and native Hyprmoncfg release metadata."""
from html.parser import HTMLParser
import json
import re
import subprocess
from urllib.parse import urljoin, urlparse


def fetch(url, fields=None):
    command = ['curl', '-fsSL', '--retry', '3', '--max-time', '30',
               '--proto', '=https', '--proto-redir', '=https', url]
    for key, value in (fields or {}).items():
        command.extend(['--data-urlencode', key + '=' + value])
    return subprocess.check_output(command, text=True)


class DownloadForms(HTMLParser):
    def __init__(self):
        super().__init__()
        self.forms = []
        self.form = None

    def handle_starttag(self, tag, attrs):
        if tag == 'form':
            self.form = {'fields': {}, 'text': ''}
        if tag == 'input' and self.form is not None:
            attrs = dict(attrs)
            if attrs.get('name'):
                self.form['fields'][attrs['name']] = attrs.get('value', '')

    def handle_data(self, text):
        if self.form is not None:
            self.form['text'] += text

    def handle_endtag(self, tag):
        if tag == 'form' and self.form is not None:
            self.forms.append(self.form)
            self.form = None


def hqplayer_desktop_url(html, architecture, submit=fetch):
    # Select the installed/licensed product line, not a paid major-version upgrade.
    section = re.search(r'HQPlayer 5 Desktop:.*?(?=<h[123][ >]|$)', html, re.S)
    if not section:
        raise ValueError('HQPlayer 5 Desktop download section not found')
    parser = DownloadForms()
    parser.feed(section.group())
    label = 'Debian 13' if architecture == 'aarch64' else 'generic AVX2'
    forms = [f for f in parser.forms if label in f['text']]
    if len(forms) != 1:
        raise ValueError('Expected one current HQPlayer 5 download form')
    fields = forms[0]['fields']
    fields['action'] = 'forminator_submit_form_custom-forms'
    response = json.loads(submit('https://signalyst.com/wp-admin/admin-ajax.php', fields))
    if not response.get('success') or not response.get('data', {}).get('success'):
        raise ValueError('Signalyst download form failed')
    return urljoin('https://signalyst.com/', response['data']['url'])


def resolve_hqplayer(app, architecture, index=None):
    if app == 'hqplayer5desktop':
        url = hqplayer_desktop_url(index if index is not None else fetch('https://signalyst.com/downloads/'), architecture)
        arch = 'arm64' if architecture == 'aarch64' else 'amd64'
        match = re.fullmatch(r'/bins/[a-z0-9]+/hqplayer5desktop_(5\.\d+\.\d+)-(\d+)_' + arch + r'\.deb', urlparse(url).path)
    else:
        # Keep the Fedora runtime ABI used by the existing native ARM64 package.
        base = 'https://signalyst.com/bins/hqplayerd/fc44/'
        html = index if index is not None else fetch(base)
        names = re.findall(r'href="(hqplayerd-(\d+(?:\.\d+)+)-(\d+)\.fc44\.' + re.escape(architecture) + r'\.rpm)"', html)
        if not names:
            raise ValueError('No compatible native HQPlayer Embedded RPM')
        name, _, _ = max(names, key=lambda n: (*map(int, n[1].split('.')), int(n[2])))
        url = base + name
        match = re.fullmatch(r'/bins/hqplayerd/fc44/hqplayerd-(\d+(?:\.\d+)+)-(\d+)\.fc44\.' + re.escape(architecture) + r'\.rpm', urlparse(url).path)
    if not match or urlparse(url).netloc != 'signalyst.com' or urlparse(url).scheme != 'https':
        raise ValueError('Unexpected Signalyst download URL')
    version, revision = match.groups()
    return dict(app=app, package=app, architecture=architecture, version=version + '-' + revision,
                pkgver=version, pkgrel=revision, url=url, sha256='-', size='unknown')


def resolve_hyprmoncfg(architecture, index):
    release = json.loads(index)
    tag = release.get('tag_name', '')
    match = re.fullmatch(r'v(\d+(?:\.\d+)+)', tag)
    if not match or release.get('draft') or release.get('prerelease'):
        raise ValueError('Expected stable Hyprmoncfg release')
    version = match.group(1)
    arch = {'aarch64': 'arm64', 'x86_64': 'amd64'}[architecture]
    name = f'hyprmoncfg_{version}_linux_{arch}.tar.gz'
    assets = [a for a in release.get('assets', []) if a.get('name') == name]
    if len(assets) != 1:
        raise ValueError('No native Hyprmoncfg release asset')
    asset = assets[0]
    digest = asset.get('digest', '')
    url = asset.get('browser_download_url', '')
    if not re.fullmatch(r'sha256:[a-fA-F0-9]{64}', digest) or url != f'https://github.com/crmne/hyprmoncfg/releases/download/{tag}/{name}':
        raise ValueError('Invalid Hyprmoncfg release metadata')
    return dict(app='hyprmoncfg', package='hyprmoncfg-bin', architecture=architecture,
                version=version, pkgver=version, pkgrel='1', url=url,
                sha256=digest[7:].lower(), size=asset['size'])
