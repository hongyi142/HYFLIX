export default async (request) => {
  const url = new URL(request.url);
  const target = url.searchParams.get('url');
  const resolve = url.searchParams.get('resolve') === 'true';

  if (!target) {
    return new Response(JSON.stringify({ error: 'Missing url parameter' }), {
      status: 400,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  const corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type',
  };

  try {
    const upstream = new URL(decodeURIComponent(target));
    const res = await fetch(upstream.toString(), {
      headers: { 'User-Agent': 'Mozilla/5.0' },
    });

    // If resolve mode: fetch share page HTML, extract m3u8 URL, return constructed URL
    if (resolve) {
      const html = await res.text();
      // Match: const url = "/path.m3u8?sign=xxx" or var main = "/path.m3u8?sign=xxx"
      const match = html.match(/(?:const|let|var)\s+(?:url|main)\s*=\s*["']([^"']+\.m3u8[^"']*)["']/);
      if (match) {
        const m3u8Path = match[1];
        const base = `${upstream.protocol}//${upstream.host}`;
        const fullUrl = m3u8Path.startsWith('http') ? m3u8Path : base + m3u8Path;
        return new Response(JSON.stringify({ url: fullUrl }), {
          status: 200,
          headers: { 'Content-Type': 'application/json', ...corsHeaders },
        });
      }
      return new Response(JSON.stringify({ error: 'Could not extract m3u8 from share page', html: html.substring(0, 500) }), {
        status: 422,
        headers: { 'Content-Type': 'application/json', ...corsHeaders },
      });
    }

    const contentType = res.headers.get('Content-Type') || 'application/octet-stream';
    
    // Check if the upstream request is for an HLS (.m3u8) manifest file
    const isM3U8 = upstream.pathname.toLowerCase().endsWith('.m3u8') || 
                   upstream.pathname.toLowerCase().includes('.m3u8') || 
                   contentType.toLowerCase().includes('mpegurl') || 
                   contentType.toLowerCase().includes('m3u8');

    if (isM3U8) {
      const requestOrigin = url.origin;
      const proxyBase = `${requestOrigin}/api/proxy`;
      let bodyText = await res.text();
      
      // Parse the m3u8 file line by line and rewrite URIs to route through this proxy
      const lines = bodyText.split('\n');
      const rewrittenLines = lines.map(line => {
        const trimmed = line.trim();
        if (!trimmed) return line;

        if (trimmed.startsWith('#')) {
          // Replace relative/absolute URIs in tags (like key files or sub-playlists)
          return trimmed.replace(/URI="([^"]+)"/g, (match, relUrl) => {
            try {
              const absoluteUrl = new URL(relUrl, upstream.toString()).toString();
              return `URI="${proxyBase}?url=${encodeURIComponent(absoluteUrl)}"`;
            } catch (e) {
              return match;
            }
          });
        } else {
          // Replace relative/absolute URIs of segment files
          try {
            const absoluteUrl = new URL(trimmed, upstream.toString()).toString();
            return `${proxyBase}?url=${encodeURIComponent(absoluteUrl)}`;
          } catch (e) {
            return line;
          }
        }
      });

      bodyText = rewrittenLines.join('\n');
      
      return new Response(bodyText, {
        status: res.status,
        headers: {
          'Content-Type': contentType,
          ...corsHeaders,
          'Cache-Control': 'no-cache, no-store, must-revalidate',
        },
      });
    }

    const isText = contentType.includes('json') || contentType.includes('text');

    if (isText) {
      const body = await res.text();
      return new Response(body, {
        status: res.status,
        headers: {
          'Content-Type': contentType,
          ...corsHeaders,
          'Cache-Control': 'public, max-age=86400',
        },
      });
    } else {
      return new Response(res.body, {
        status: res.status,
        headers: {
          'Content-Type': contentType,
          ...corsHeaders,
          'Cache-Control': 'public, max-age=86400',
        },
      });
    }
  } catch (e) {
    return new Response(JSON.stringify({ error: e.message }), {
      status: 500,
      headers: { 'Content-Type': 'application/json', ...corsHeaders },
    });
  }
};

export const config = {
  path: '/api/proxy',
  method: 'GET',
};
