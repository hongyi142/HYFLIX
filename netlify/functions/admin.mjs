const ADMIN_USER = 'admin';
const ADMIN_PASS = '123';
const TOKEN_MAX_AGE = 24 * 60 * 60 * 1000;

const DEFAULT_CONFIG = {
  platforms: {
    android: { enabled: false, fileName: '', fileSize: 0, url: '' },
    windows: { enabled: false, fileName: '', fileSize: 0, url: '' },
    macos: { enabled: false, fileName: '', fileSize: 0, url: '' },
    ios: { enabled: false, fileName: '', fileSize: 0, url: '' },
    'android-tv': { enabled: false, fileName: '', fileSize: 0, url: '' },
    'apple-tv': { enabled: false, fileName: '', fileSize: 0, url: '' },
  },
};

function getConfig() {
  const raw = process.env.HYFLIX_CONFIG;
  if (!raw) return JSON.parse(JSON.stringify(DEFAULT_CONFIG));
  try {
    return JSON.parse(raw);
  } catch {
    return JSON.parse(JSON.stringify(DEFAULT_CONFIG));
  }
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

  if (action === 'login') {
    try {
      const { user, pass } = await request.json();
      if (user === ADMIN_USER && pass === ADMIN_PASS) {
        const token = btoa(JSON.stringify({ user: ADMIN_USER, ts: Date.now() }));
        return json({ ok: true, token });
      }
      return json({ ok: false, error: 'Invalid credentials' }, 401);
    } catch (e) {
      return json({ error: e.message || 'Login failed' }, 500);
    }
  }

  try {
    if (action === 'get-config') {
      return json(getConfig());
    }

    if (action === 'save') {
      if (!checkAuth(request)) return json({ error: 'Unauthorized' }, 401);
      const { config } = await request.json();
      if (!config) return json({ error: 'Missing config' }, 400);
      return json({ ok: true, config, message: 'Config received. Set HYFLIX_CONFIG env var in Netlify dashboard with this JSON.' });
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
