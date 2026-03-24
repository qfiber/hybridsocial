<script lang="ts">
	import '../app.css';
	import favicon from '$lib/assets/favicon.svg';
	import Analytics from '$lib/components/ui/Analytics.svelte';
	import { onMount } from 'svelte';
	import { initAuth } from '$lib/stores/auth.js';
	import { initializeI18n, isRtl } from '$lib/stores/i18n.js';
	import { applyTheme } from '$lib/stores/theme.js';
	import { getInstanceInfo } from '$lib/api/instance.js';
	import { browser } from '$app/environment';

	let { children } = $props();

	onMount(async () => {
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

	// Reactively set dir attribute based on locale direction
	$effect(() => {
		if (browser) {
			document.documentElement.dir = $isRtl ? 'rtl' : 'ltr';
		}
	});
</script>

<svelte:head>
	<link rel="icon" href={favicon} />
	<link rel="preconnect" href="https://fonts.googleapis.com" />
	<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin="anonymous" />
	<link href="https://fonts.googleapis.com/css2?family=Manrope:wght@400;500;600;700;800&family=Inter:wght@400;500;600&display=swap" rel="stylesheet" />
</svelte:head>

<Analytics />
{@render children()}
