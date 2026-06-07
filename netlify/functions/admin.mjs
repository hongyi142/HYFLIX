import { BlobStore } from '@netlify/blobs';

const ADMIN_USER = 'admin';
const ADMIN_PASS = '123';
const TOKEN_MAX_AGE = 24 * 60 * 60 * 1000;

const DEFAULT_CONFIG = {
  platforms: {
    android: { enabled: false },
    windows: { enabled: false },
    macos: { enabled: false },
    ios: { enabled: false },
    'android-tv': { enabled: false },
    'apple-tv': { enabled: false },
  },
};

function getStore() {
  return new BlobStore();
}

function json(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      'Content-Type': 'application/json',
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type, Authorization',
    },
  });
}

function checkAuth(request) {
  const auth = request.headers.get('authorization');
  if (!auth || !auth.startsWith('Bearer ')) return false;
  try {
    const payload = JSON.parse(atob(auth.slice(7)));
    return payload.user === ADMIN_USER && Date.now() - payload.ts < TOKEN_MAX_AGE;
  } catch {
    return false;
  }
}

async function getConfig(store) {
  const data = await store.get('config.json', { type: 'json' });
  return data || JSON.parse(JSON.stringify(DEFAULT_CONFIG));
}

export default async (request) => {
  if (request.method === 'OPTIONS') {
    return new Response(null, {
      status: 204,
      headers: {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
        'Access-Control-Allow-Headers': 'Content-Type, Authorization',
      },
    });
  }

  const url = new URL(request.url);
  const action = url.searchParams.get('action');

  try {
    const store = getStore();

    if (action === 'login') {
      const { user, pass } = await request.json();
      if (user === ADMIN_USER && pass === ADMIN_PASS) {
        const token = btoa(JSON.stringify({ user: ADMIN_USER, ts: Date.now() }));
        return json({ ok: true, token });
      }
      return json({ ok: false, error: 'Invalid credentials' }, 401);
    }

    if (action === 'get-config') {
      const config = await getConfig(store);
      return json(config);
    }

    if (action === 'upload') {
      if (!checkAuth(request)) return json({ error: 'Unauthorized' }, 401);
      const { platform, fileName, fileSize, data } = await request.json();
      if (!platform || !fileName || !data) {
        return json({ error: 'Missing platform, fileName, or data' }, 400);
      }
      const blobKey = `files/${platform}/${fileName}`;
      const buffer = Uint8Array.from(atob(data), c => c.charCodeAt(0));
      await store.set(blobKey, buffer, { contentType: 'application/octet-stream' });
      const config = await getConfig(store);
      config.platforms[platform] = {
        enabled: true,
        fileName,
        fileSize: fileSize || buffer.length,
        blobKey,
        uploadedAt: new Date().toISOString(),
      };
      await store.set('config.json', JSON.stringify(config), { contentType: 'application/json' });
      return json({ ok: true });
    }

    if (action === 'delete') {
      if (!checkAuth(request)) return json({ error: 'Unauthorized' }, 401);
      const { platform } = await request.json();
      const config = await getConfig(store);
      const p = config.platforms[platform];
      if (p?.blobKey) {
        await store.delete(p.blobKey);
      }
      config.platforms[platform] = { enabled: false };
      await store.set('config.json', JSON.stringify(config), { contentType: 'application/json' });
      return json({ ok: true });
    }

    if (action === 'toggle') {
      if (!checkAuth(request)) return json({ error: 'Unauthorized' }, 401);
      const { platform, enabled } = await request.json();
      const config = await getConfig(store);
      if (config.platforms[platform]) {
        config.platforms[platform].enabled = enabled;
      }
      await store.set('config.json', JSON.stringify(config), { contentType: 'application/json' });
      return json({ ok: true });
    }

    if (action === 'download') {
      const file = url.searchParams.get('file');
      if (!file) return json({ error: 'Missing file parameter' }, 400);
      const data = await store.get(file);
      if (!data) return json({ error: 'File not found' }, 404);
      const fileName = file.split('/').pop();
      return new Response(data, {
        headers: {
          'Content-Type': 'application/octet-stream',
          'Content-Disposition': `attachment; filename="${fileName}"`,
          'Access-Control-Allow-Origin': '*',
        },
      });
    }

    return json({ error: 'Unknown action' }, 400);
  } catch (e) {
    return json({ error: e.message || 'Internal error' }, 500);
  }
};

export const config = {
  path: '/api/admin',
  method: ['GET', 'POST', 'OPTIONS'],
};
