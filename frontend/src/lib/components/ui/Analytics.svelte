<script lang="ts">
  import { onMount } from 'svelte';
  import { browser } from '$app/environment';
  import { cookieConsent } from '$lib/stores/consent.js';
  import { getInstanceInfo } from '$lib/api/instance.js';

  interface AnalyticsConfig {
    provider: string;
    site_id: string;
    host: string;
  }

  let config: AnalyticsConfig | null = $state(null);
  let consented = $state(false);
  let injected = $state(false);

  cookieConsent.subscribe((v) => (consented = v));

  onMount(async () => {
    try {
      const info = await getInstanceInfo();
      if (info.analytics) {
        config = info.analytics as AnalyticsConfig;
      }
    } catch {
      // Non-critical
    }
  });

  $effect(() => {
    if (browser && consented && config && !injected && config.site_id) {
      injectAnalytics(config);
      injected = true;
    }
  });

  function injectAnalytics(c: AnalyticsConfig) {
    switch (c.provider) {
      case 'google':
        injectGoogle(c.site_id);
        break;
      case 'plausible':
        injectPlausible(c.host);
        break;
      case 'matomo':
        injectMatomo(c.host, c.site_id);
        break;
      case 'umami':
        injectUmami(c.host, c.site_id);
        break;
      case 'rybbit':
        injectRybbit(c.host, c.site_id);
        break;
    }
  }

  function injectGoogle(measurementId: string) {
    const script = document.createElement('script');
    script.async = true;
    script.src = `https://www.googletagmanager.com/gtag/js?id=${encodeURIComponent(measurementId)}`;
    document.head.appendChild(script);

    const inline = document.createElement('script');
    inline.textContent = `
      window.dataLayer = window.dataLayer || [];
      function gtag(){dataLayer.push(arguments);}
      gtag('js', new Date());
      gtag('config', '${measurementId}');
    `;
    document.head.appendChild(inline);
  }

  function injectPlausible(host: string) {
    const domain = window.location.hostname;
    const src = host
      ? `${host.replace(/\/$/, '')}/js/plausible.js`
      : 'https://plausible.io/js/plausible.js';

    const script = document.createElement('script');
    script.async = true;
    script.defer = true;
    script.dataset.domain = domain;
    script.src = src;
    document.head.appendChild(script);
  }

  function injectMatomo(host: string, siteId: string) {
    const url = host.replace(/\/$/, '');

    const inline = document.createElement('script');
    inline.textContent = `
      var _paq = window._paq = window._paq || [];
      _paq.push(['trackPageView']);
      _paq.push(['enableLinkTracking']);
      (function() {
        var u="${url}/";
        _paq.push(['setTrackerUrl', u+'matomo.php']);
        _paq.push(['setSiteId', '${siteId}']);
        var d=document, g=d.createElement('script'), s=d.getElementsByTagName('script')[0];
        g.async=true; g.src=u+'matomo.js'; s.parentNode.insertBefore(g,s);
      })();
    `;
    document.head.appendChild(inline);
  }

  function injectUmami(host: string, websiteId: string) {
    const src = host
      ? `${host.replace(/\/$/, '')}/script.js`
      : 'https://cloud.umami.is/script.js';

    const script = document.createElement('script');
    script.async = true;
    script.defer = true;
    script.dataset.websiteId = websiteId;
    script.src = src;
    document.head.appendChild(script);
  }

  function injectRybbit(host: string, siteId: string) {
    const src = `${host.replace(/\/$/, '')}/api/script.js`;

    const script = document.createElement('script');
    script.async = true;
    script.defer = true;
    script.dataset.siteId = siteId;
    script.src = src;
    document.head.appendChild(script);
  }
</script>
