// TMDB API key — get your free key at https://www.themoviedb.org/settings/api
const String tmdbApiKey = '0eca402bce9c731c02509d4671c72d6f';

// SubDL API key — register at https://subdl.com/
// Leave empty string to disable subtitles.
const String subdlApiKey = '_QFbdnITc00ZzFTFO6KtBJnt81h-pwLi';

// OpenSubtitles API key — register at https://www.opensubtitles.com/en/consumers
// Free tier: ~100 requests/day. Leave empty string to disable.
const String openSubtitlesApiKey = '';

// Stremio addon base URLs for torrent stream discovery
const String torrentioBaseUrl = 'https://torrentio.strem.fun';
const String thepiratebayBaseUrl = 'https://thepiratebay-plus.strem.fun';
const String meteorBaseUrl = 'https://meteorfortheweebs.midnightignite.me';

// TorBox configuration
// If you want to use the TorBox debrid service, paste your TorBox API key here.
// When configured, HYFLIX will stream torrents at high speeds directly over HTTPS.
const String torboxApiKey = '9c9f5759-e019-4cf0-a019-4bc4d09b088c';

// Custom Torrentio configuration URL (optional)
// Paste your custom-configured Torrentio installation link here (e.g. from torrentio.strem.fun/configure).
// Supports stremio:// or https:// formats.
// Example: 'stremio://torrentio.strem.fun/providers=yts,thepiratebay|torboxapi=YOUR_API_KEY/manifest.json'
// If non-empty, this takes precedence over the torboxApiKey.
const String customTorrentioUrl = '';

