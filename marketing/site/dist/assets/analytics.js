// Keep campaign attribution while dropping arbitrary URL parameters and referrer queries.
window.sayKukuAnalyticsFilter = function (_type, payload) {
  if (!payload || typeof payload.url !== 'string') return payload;

  const url = new URL(payload.url, window.location.origin);
  const campaign = new URLSearchParams();
  for (const key of ['utm_source', 'utm_medium', 'utm_campaign', 'utm_content', 'utm_term']) {
    const value = url.searchParams.get(key);
    if (value && /^[a-z0-9_-]{1,64}$/i.test(value)) campaign.set(key, value);
  }

  let referrer = payload.referrer;
  if (typeof referrer === 'string' && referrer) {
    try {
      const parsed = new URL(referrer);
      referrer = parsed.origin + parsed.pathname;
    } catch (_) {
      referrer = '';
    }
  }

  const query = campaign.toString();
  return {
    ...payload,
    url: url.pathname + (query ? '?' + query : ''),
    referrer,
  };
};
