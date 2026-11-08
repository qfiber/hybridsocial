<script lang="ts">
	import '../app.css';
	import favicon from '$lib/assets/favicon.svg';
	import Analytics from '$lib/components/ui/Analytics.svelte';
	import ExternalLinkWarning from '$lib/components/ui/ExternalLinkWarning.svelte';
	import { onMount } from 'svelte';
	import { initAuth } from '$lib/stores/auth.js';
	import { initializeI18n, isRtl, locale } from '$lib/stores/i18n.js';
	import { applyTheme, themeStore } from '$lib/stores/theme.js';
	import { getInstanceInfo } from '$lib/api/instance.js';
	import { browser, dev } from '$app/environment';
	import { page } from '$app/stores';

	let { children, data } = $props();

	// Unified OG/meta source. A page's +page.server.ts may inject
	// page-specific share metadata (post / profile) as page.data.og;
	// otherwise everything falls back to the instance defaults. Keeping
	// this in one place means exactly one set of og: tags per page.
	const instTitle = $derived(data?.instance?.title || 'HybridSocial');
	const pageOg = $derived(($page.data as Record<string, any>)?.og as
		| {
				title?: string;
				robots?: string;
				description?: string;
				image?: string;
				image_width?: number | null;
				image_height?: number | null;
				type?: string;
		  }
		| undefined);
	const ogTitle = $derived(pageOg?.title || instTitle);
	const ogDescription = $derived(pageOg?.description ?? data?.instance?.description ?? '');
	const ogType = $derived(pageOg?.type || 'website');
	const ogImage = $derived(pageOg?.image || data?.instance?.og_image_url || null);
	// Real dimensions of whichever image is in use (post attachment or the
	// instance social image). Emitted only when known — never assumed.
	const ogImageWidth = $derived(pageOg?.image_width ?? data?.instance?.og_image_width ?? null);
	const ogImageHeight = $derived(pageOg?.image_height ?? data?.instance?.og_image_height ?? null);
	const canonicalUrl = $derived(`${$page.url.origin}${$page.url.pathname}`);

	onMount(async () => {
		// Register the service worker for everyone, not only on push opt-in
		// (push.ts registers the same /sw.js — a no-op once it's here). Without
		// it the offline fallback and installability never applied to anyone
		// who hadn't enabled notifications. Skipped in dev so a cached worker
		// can't get in the way of local work.
		if (!dev && 'serviceWorker' in navigator) {
			navigator.serviceWorker.register('/sw.js').catch(() => {
				/* unsupported or blocked (e.g. private mode) — the app works without it */
			});
		}

		// Initialize i18n (auto-detects browser locale)
		await initializeI18n();

		// Initialize auth (restore session from storage)
		await initAuth();

		// Load instance theme
		try {
			const info = await getInstanceInfo();
			if (info.theme) {
				applyTheme(info.theme);
			}
		} catch {
			// Instance info not available yet — use defaults
		}
	});

	// Reactively set dir + lang on <html> from the active locale. dir drives
	// RTL/LTR layout; lang (previously hardcoded en in app.html) is needed for
	// a11y, correct font/hyphenation heuristics, and Arabic screen readers.
	$effect(() => {
		if (browser) {
			document.documentElement.dir = $isRtl ? 'rtl' : 'ltr';
			document.documentElement.lang = $locale;
		}
	});
</script>

<svelte:head>
	<title>{ogTitle}</title>
	{#if pageOg?.robots}
		<meta name="robots" content={pageOg.robots} />
	{/if}
	<meta property="og:title" content={ogTitle} />
	<meta property="og:site_name" content={instTitle} />
	<meta property="og:type" content={ogType} />
	<meta property="og:url" content={canonicalUrl} />
	<link rel="canonical" href={canonicalUrl} />
	{#if ogDescription}
		<meta name="description" content={ogDescription} />
		<meta property="og:description" content={ogDescription} />
	{/if}
	{#if ogImage}
		<meta property="og:image" content={ogImage} />
		<meta property="og:image:alt" content={ogTitle} />
		{#if ogImageWidth && ogImageHeight}
			<meta property="og:image:width" content={String(ogImageWidth)} />
			<meta property="og:image:height" content={String(ogImageHeight)} />
		{/if}
		<meta name="twitter:card" content="summary_large_image" />
	{/if}
	<link rel="icon" href={$themeStore?.favicon_url || data?.instance?.favicon_url || favicon} />
	<link rel="preconnect" href="https://fonts.googleapis.com" />
	<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin="anonymous" />
	<link href="https://fonts.googleapis.com/css2?family=Manrope:wght@400;500;600;700;800&family=Rubik:wght@400;500;600;700;800&display=swap" rel="stylesheet" />
</svelte:head>

<Analytics />
<ExternalLinkWarning />
{@render children()}
