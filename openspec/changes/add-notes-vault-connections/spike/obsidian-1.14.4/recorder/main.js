/* Throwaway spike plugin for Ratatoskr spikes 3.5 and 3.6. Plain CommonJS, no build step. */
'use strict';
const obsidian = require('obsidian');
const fs = require('fs');
const path = require('path');

const S = '<spike>';
const OUT = path.join(S, 'out');
const EVENTS = path.join(OUT, 'events.jsonl');
const ERRORS = path.join(OUT, 'errors.jsonl');
const PROGRESS = path.join(OUT, 'progress.jsonl');

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const esc = (s) => (s == null ? s : s.replace(/[^\x20-\x7e]/g, (c) => '\\u' + c.charCodeAt(0).toString(16).padStart(4, '0')));
const isNFC = (s) => s === s.normalize('NFC');

function logTo(file, obj) {
  fs.appendFileSync(file, JSON.stringify(obj) + '\n');
}
function progress(step, extra) {
  logTo(PROGRESS, Object.assign({ t: Date.now(), step }, extra || {}));
}
function errorLog(step, e) {
  logTo(ERRORS, { t: Date.now(), step, message: String(e && e.message ? e.message : e), stack: e && e.stack });
}

class RatatoskrSpike extends obsidian.Plugin {
  onload() {
    fs.mkdirSync(OUT, { recursive: true });
    progress('onload');
    this.phase = 'idle';
    this.action = null;
    this.app.workspace.onLayoutReady(() => {
      this.run().catch((e) => errorLog('run', e));
    });
  }

  vaultBase() {
    return this.app.vault.adapter.getBasePath();
  }

  waitResolved(ms) {
    const mc = this.app.metadataCache;
    return new Promise((resolve) => {
      let done = false;
      const ref = mc.on('resolved', () => {
        if (done) return;
        done = true;
        mc.offref(ref);
        resolve('resolved');
      });
      setTimeout(() => {
        if (done) return;
        done = true;
        mc.offref(ref);
        resolve('timeout');
      }, ms);
    });
  }

  registerEventLog() {
    const kind = (f) => (f instanceof obsidian.TFolder ? 'folder' : 'file');
    const rec = (event, f, extra) => {
      logTo(EVENTS, Object.assign({
        t: Date.now(),
        hr: Math.round(performance.now() * 1000) / 1000,
        phase: this.phase,
        action: this.action,
        event,
        type: f ? kind(f) : undefined,
        path: f ? f.path : undefined,
        pathEscaped: f ? esc(f.path) : undefined,
        pathIsNFC: f ? isNFC(f.path) : undefined,
      }, extra || {}));
    };
    const v = this.app.vault;
    const mc = this.app.metadataCache;
    this.registerEvent(v.on('create', (f) => rec('vault.create', f)));
    this.registerEvent(v.on('modify', (f) => rec('vault.modify', f)));
    this.registerEvent(v.on('delete', (f) => rec('vault.delete', f)));
    this.registerEvent(v.on('rename', (f, oldPath) => rec('vault.rename', f, { oldPath, oldPathEscaped: esc(oldPath) })));
    this.registerEvent(mc.on('changed', (f) => rec('metadataCache.changed', f)));
    this.registerEvent(mc.on('deleted', (f) => rec('metadataCache.deleted', f)));
    this.registerEvent(mc.on('resolved', () => rec('metadataCache.resolved', null)));
  }

  async run() {
    progress('layoutReady');
    const r = await this.waitResolved(6000);
    await sleep(1000);
    progress('initialResolve', { result: r });
    this.registerEventLog();

    const steps = [
      ['env', () => this.dumpEnv()],
      ['metadata', () => this.dumpMetadata()],
      ['credentials', () => this.probeCredentials()],
      ['goldens', () => this.renameGoldens()],
      ['events', () => this.vaultEvents()],
    ];
    const status = {};
    for (const [name, fn] of steps) {
      progress('start:' + name);
      try {
        await fn();
        status[name] = 'ok';
      } catch (e) {
        status[name] = 'error: ' + (e && e.message);
        errorLog(name, e);
      }
      progress('end:' + name, { status: status[name] });
    }
    // Metadata after the event spike, for comparison.
    try {
      await this.dumpMetadata('metadata-after-events.json');
    } catch (e) {
      errorLog('metadata-after', e);
    }
    fs.writeFileSync(path.join(OUT, 'DONE'), JSON.stringify({ t: Date.now(), status }, null, 2));
    progress('DONE', { status });
  }

  dumpEnv() {
    const env = {
      apiVersion: obsidian.apiVersion,
      userAgent: navigator.userAgent,
      processVersions: process.versions,
      platform: process.platform,
      isDesktopApp: obsidian.Platform.isDesktopApp,
      vaultBase: this.vaultBase(),
      vaultName: this.app.vault.getName(),
      appId: this.app.appId,
      config: {
        alwaysUpdateLinks: this.app.vault.getConfig('alwaysUpdateLinks'),
        newLinkFormat: this.app.vault.getConfig('newLinkFormat'),
        useMarkdownLinks: this.app.vault.getConfig('useMarkdownLinks'),
        trashOption: this.app.vault.getConfig('trashOption'),
      },
    };
    try {
      const remote = require('@electron/remote');
      env.electronAppVersion = remote.app.getVersion();
      env.userData = remote.app.getPath('userData');
    } catch (e) {
      env.remoteError = String(e.message);
    }
    fs.writeFileSync(path.join(OUT, 'env.json'), JSON.stringify(env, null, 2));
  }

  async dumpMetadata(outName) {
    const app = this.app;
    const mc = app.metadataCache;
    const all = app.vault.getAllLoadedFiles();
    const files = all.filter((f) => f instanceof obsidian.TFile).sort((a, b) => (a.path < b.path ? -1 : 1));
    const folders = all.filter((f) => f instanceof obsidian.TFolder).map((f) => f.path).sort();

    const resolvedLinks = mc.resolvedLinks;
    const unresolvedLinks = mc.unresolvedLinks;
    const backlinks = {};
    for (const [src, dests] of Object.entries(resolvedLinks)) {
      for (const [dst, n] of Object.entries(dests)) {
        (backlinks[dst] = backlinks[dst] || {})[src] = n;
      }
    }

    const perFile = {};
    for (const f of files) {
      const entry = {
        path: f.path,
        pathEscaped: esc(f.path),
        pathIsNFC: isNFC(f.path),
        name: f.name,
        basename: f.basename,
        extension: f.extension,
        size: f.stat.size,
      };
      const cache = mc.getFileCache(f);
      if (cache) {
        entry.cache = {
          links: cache.links,
          embeds: cache.embeds,
          headings: cache.headings,
          blocks: cache.blocks,
          tags: cache.tags,
          frontmatter: cache.frontmatter,
          frontmatterLinks: cache.frontmatterLinks,
          frontmatterPosition: cache.frontmatterPosition,
          sections: cache.sections ? cache.sections.map((s) => s.type) : undefined,
          listItems: cache.listItems ? cache.listItems.length : undefined,
        };
        entry.getAllTags = obsidian.getAllTags(cache);
        const refs = [];
        const push = (kind, arr) => {
          for (const l of arr || []) {
            const linkpath = obsidian.getLinkpath(l.link);
            const parsed = obsidian.parseLinktext(l.link);
            const dest = mc.getFirstLinkpathDest(linkpath, f.path);
            refs.push({
              kind,
              original: l.original,
              link: l.link,
              linkEscaped: esc(l.link),
              displayText: l.displayText,
              linkpath,
              subpath: parsed.subpath,
              dest: dest ? dest.path : null,
              destEscaped: dest ? esc(dest.path) : null,
            });
          }
        };
        push('link', cache.links);
        push('embed', cache.embeds);
        push('frontmatterLink', cache.frontmatterLinks);
        entry.firstLinkpathDest = refs;
      }
      entry.resolvedLinks = resolvedLinks[f.path] || null;
      entry.unresolvedLinks = unresolvedLinks[f.path] || null;
      entry.backlinks = backlinks[f.path] || {};
      try {
        if (typeof mc.getBacklinksForFile === 'function') {
          const bl = mc.getBacklinksForFile(f);
          entry.getBacklinksForFile = bl && bl.data ? Object.fromEntries(Array.from(bl.data instanceof Map ? bl.data.entries() : Object.entries(bl.data)).map(([k, v]) => [k, Array.isArray(v) ? v.length : v])) : null;
        }
      } catch (e) {
        entry.getBacklinksForFileError = String(e.message);
      }
      perFile[f.path] = entry;
    }

    const out = {
      generatedAt: new Date().toISOString(),
      apiVersion: obsidian.apiVersion,
      fileCount: files.length,
      markdownCount: files.filter((f) => f.extension === 'md').length,
      folders,
      resolvedLinks,
      unresolvedLinks,
      backlinks,
      files: perFile,
    };
    try { out.vaultTags = mc.getTags ? mc.getTags() : null; } catch (e) { out.vaultTagsError = String(e.message); }
    try { out.propertyInfos = mc.getAllPropertyInfos ? mc.getAllPropertyInfos() : null; } catch (e) { out.propertyInfosError = String(e.message); }
    try { out.propertyTypes = app.metadataTypeManager ? app.metadataTypeManager.types : null; } catch (e) { out.propertyTypesError = String(e.message); }
    fs.writeFileSync(path.join(OUT, outName || 'metadata.json'), JSON.stringify(out, null, 2));
  }

  async probeCredentials() {
    const r = {};
    const app = this.app;
    const DUMMY_ID = 'ratatoskr-spike-probe';
    const DUMMY_VALUE = 'dummy-value-not-a-secret-7f3a';

    // 1. app.secretStorage
    const ss = app.secretStorage;
    r.secretStorage = { present: !!ss, type: typeof ss };
    if (ss) {
      const proto = Object.getPrototypeOf(ss);
      r.secretStorage.ownKeys = Object.keys(ss);
      r.secretStorage.protoMethods = proto ? Object.getOwnPropertyNames(proto) : [];
      try {
        const res = ss.setSecret(DUMMY_ID, DUMMY_VALUE);
        r.secretStorage.setReturn = res && typeof res.then === 'function' ? await res : res;
        let got = ss.getSecret(DUMMY_ID);
        if (got && typeof got.then === 'function') got = await got;
        r.secretStorage.roundTrip = got === DUMMY_VALUE;
        let list = ss.listSecrets ? ss.listSecrets() : undefined;
        if (list && typeof list.then === 'function') list = await list;
        r.secretStorage.listSecrets = list;
      } catch (e) {
        r.secretStorage.error = String(e.message);
      }
    }
    r.SecretComponentExported = typeof obsidian.SecretComponent;

    // 2. Electron safeStorage
    r.windowElectron = typeof window.electron;
    try {
      const electron = require('electron');
      r.electronRendererKeys = Object.keys(electron);
      r.electronSafeStorageInRenderer = typeof electron.safeStorage;
    } catch (e) {
      r.electronRequireError = String(e.message);
    }
    try {
      const remote = require('@electron/remote');
      r.remoteAvailable = true;
      const safe = remote.safeStorage;
      r.remoteSafeStorage = typeof safe;
      if (safe) {
        r.safeStorageEncryptionAvailable = safe.isEncryptionAvailable();
        if (typeof safe.getSelectedStorageBackend === 'function') {
          try { r.safeStorageBackend = safe.getSelectedStorageBackend(); } catch (e) { r.safeStorageBackendError = String(e.message); }
        }
        const enc = safe.encryptString(DUMMY_VALUE);
        r.safeStorageCipherBytes = enc.length;
        r.safeStorageCipherPrefix = Buffer.from(enc).subarray(0, 3).toString('latin1');
        r.safeStorageRoundTrip = safe.decryptString(enc) === DUMMY_VALUE;
      }
    } catch (e) {
      r.remoteError = String(e.message);
    }

    // 3. keytar / keychain
    for (const mod of ['keytar', 'node-keytar', '@napi-rs/keyring']) {
      try {
        require(mod);
        r['require_' + mod] = 'ok';
      } catch (e) {
        r['require_' + mod] = 'error: ' + String(e.message).split('\n')[0];
      }
    }
    try {
      require('child_process');
      r.childProcessAvailable = true;
      r.securityCliExists = fs.existsSync('/usr/bin/security');
      r.keychainNote = 'Not exercised: no item was written to the login keychain.';
    } catch (e) {
      r.childProcessAvailable = false;
    }

    // 4. app.loadLocalStorage / saveLocalStorage
    try {
      app.saveLocalStorage(DUMMY_ID, DUMMY_VALUE);
      r.loadLocalStorageRoundTrip = app.loadLocalStorage(DUMMY_ID) === DUMMY_VALUE;
      const keys = [];
      for (let i = 0; i < window.localStorage.length; i++) keys.push(window.localStorage.key(i));
      r.localStorageMatchingKeys = keys.filter((k) => k.includes(DUMMY_ID));
      r.localStorageRawValue = r.localStorageMatchingKeys.length ? window.localStorage.getItem(r.localStorageMatchingKeys[0]) : null;
      r.localStorageAllKeyCount = keys.length;
      r.localStorageKeyPrefixes = Array.from(new Set(keys.map((k) => k.split('-')[0]))).slice(0, 20);
      r.appId = app.appId;
      r.origin = window.location.origin;
    } catch (e) {
      r.localStorageError = String(e.message);
    }

    // 5. plugin data.json (inside the vault)
    try {
      await this.saveData({ probe: 'dummy-data-json' });
      r.dataJsonPath = path.join(this.vaultBase(), this.manifest.dir, 'data.json');
      r.dataJsonExists = fs.existsSync(r.dataJsonPath);
    } catch (e) {
      r.dataJsonError = String(e.message);
    }

    try {
      const remote = require('@electron/remote');
      r.userData = remote.app.getPath('userData');
    } catch (e) { /* recorded above */ }
    r.vaultBase = this.vaultBase();
    r.dummyId = DUMMY_ID;
    r.dummyValue = DUMMY_VALUE;
    fs.writeFileSync(path.join(OUT, 'credentials.json'), JSON.stringify(r, null, 2));
  }

  snapshot() {
    const base = this.vaultBase();
    const out = {};
    const walk = (dir) => {
      for (const ent of fs.readdirSync(dir, { withFileTypes: true })) {
        if (ent.name === '.obsidian' || ent.name === '.trash') continue;
        const abs = path.join(dir, ent.name);
        if (ent.isDirectory()) walk(abs);
        else if (ent.name.endsWith('.md')) out[path.relative(base, abs)] = fs.readFileSync(abs, 'utf8');
      }
    };
    walk(base);
    return out;
  }

  async renameGoldens() {
    this.phase = 'goldens';
    const cases = [
      ['shortest-path-link', 'RenameTargets/Shortest.md', 'RenameTargets/Shortest Renamed.md'],
      ['aliased-link', 'RenameTargets/Aliased.md', 'RenameTargets/Aliased Renamed.md'],
      ['heading-link', 'RenameTargets/Headed.md', 'RenameTargets/Headed Renamed.md'],
      ['embed', 'RenameTargets/Embedded.md', 'RenameTargets/Embedded Renamed.md'],
      ['move-into-name-collision', 'RenameTargets/Collide.md', 'RenameTargets/Other/Epsilon.md'],
    ];
    const root = path.join(OUT, 'rename-goldens');
    fs.mkdirSync(root, { recursive: true });
    const settings = {
      alwaysUpdateLinks: this.app.vault.getConfig('alwaysUpdateLinks'),
      newLinkFormat: this.app.vault.getConfig('newLinkFormat'),
      useMarkdownLinks: this.app.vault.getConfig('useMarkdownLinks'),
    };
    fs.writeFileSync(path.join(root, 'settings.json'), JSON.stringify(settings, null, 2));
    for (const [name, from, to] of cases) {
      this.action = name;
      const dir = path.join(root, name);
      fs.mkdirSync(dir, { recursive: true });
      const before = this.snapshot();
      const file = this.app.vault.getAbstractFileByPath(from);
      if (!file) throw new Error('missing ' + from);
      const parent = path.posix.dirname(to);
      if (!this.app.vault.getAbstractFileByPath(parent)) await this.app.vault.createFolder(parent);
      const t0 = Date.now();
      await this.app.fileManager.renameFile(file, to);
      const settle = await this.waitResolved(3000);
      await sleep(800);
      const after = this.snapshot();
      const changed = [];
      const keys = new Set([...Object.keys(before), ...Object.keys(after)]);
      for (const k of Array.from(keys).sort()) {
        if (before[k] === after[k]) continue;
        changed.push(k);
        if (k in before) {
          const p = path.join(dir, 'before', k);
          fs.mkdirSync(path.dirname(p), { recursive: true });
          fs.writeFileSync(p, before[k]);
        }
        if (k in after) {
          const p = path.join(dir, 'after', k);
          fs.mkdirSync(path.dirname(p), { recursive: true });
          fs.writeFileSync(p, after[k]);
        }
      }
      fs.writeFileSync(path.join(dir, 'case.json'), JSON.stringify({ name, from, to, settings, settle, ms: Date.now() - t0, changed }, null, 2));
    }
    this.action = null;
  }

  async act(name, fn, wait) {
    this.action = name;
    logTo(EVENTS, { t: Date.now(), phase: this.phase, action: name, event: 'ACTION_START' });
    let result;
    try {
      result = await fn();
    } catch (e) {
      logTo(EVENTS, { t: Date.now(), phase: this.phase, action: name, event: 'ACTION_ERROR', message: String(e.message) });
    }
    await sleep(wait || 1500);
    logTo(EVENTS, { t: Date.now(), phase: this.phase, action: name, event: 'ACTION_END', result: result === undefined ? null : result });
    this.action = null;
  }

  async vaultEvents() {
    this.phase = 'events';
    const v = this.app.vault;
    const fm = this.app.fileManager;
    const base = this.vaultBase();
    const get = (p) => v.getAbstractFileByPath(p);
    let note;
    await this.act('api:create', async () => { note = await v.create('Events/new-note.md', 'hello\n'); return note.path; });
    await this.act('api:modify', async () => { await v.modify(note, 'hello world\n'); });
    await this.act('api:rename', async () => { await fm.renameFile(note, 'Events/renamed-note.md'); return note.path; });
    await this.act('api:move', async () => { await fm.renameFile(note, 'Events/Sub/renamed-note.md'); return note.path; });
    await this.act('api:rename-folder-3-notes', async () => { await fm.renameFile(get('Events/Folder3'), 'Events/Folder3 Renamed'); }, 2500);
    await this.act('api:delete', async () => { await v.delete(get('Events/to-delete.md')); });
    await this.act('api:trash-local', async () => { await v.trash(get('Events/to-trash.md'), false); });
    const nfd = 'Events/Naïve Café.md';
    await this.act('api:create-nfd', async () => {
      const f = await v.create(nfd, 'nfd\n');
      const onDisk = fs.readdirSync(path.join(base, 'Events')).filter((n) => !/^[\x00-\x7f]*$/.test(n)).map(esc);
      return { returnedPath: esc(f.path), returnedIsNFC: isNFC(f.path), onDisk };
    });
    // External changes, made with Node fs behind Obsidian's back (as a sync tool would).
    const ext = (p) => path.join(base, p);
    await this.act('fs:create', async () => { fs.writeFileSync(ext('Events/ext-new.md'), 'ext\n'); }, 3000);
    await this.act('fs:modify', async () => { fs.appendFileSync(ext('Events/external.md'), 'more\n'); }, 3000);
    await this.act('fs:rename', async () => { fs.renameSync(ext('Events/external.md'), ext('Events/external-renamed.md')); }, 3000);
    await this.act('fs:rename-folder-2-notes', async () => { fs.renameSync(ext('Events/ExtFolder'), ext('Events/ExtFolder Renamed')); }, 3000);
    await this.act('fs:delete', async () => { fs.unlinkSync(ext('Events/ext-new.md')); }, 3000);
    await this.act('fs:create-nfd', async () => {
      fs.writeFileSync(ext('Events/Résumé ext.md'), 'nfd ext\n');
    }, 3000);
    this.phase = 'done';
  }
}

module.exports = RatatoskrSpike;
