import type { HandleServerError, Handle } from '@sveltejs/kit';

export const handle: Handle = async ({ event, resolve }) => {
	const response = await resolve(event, {
		preload: ({ type }) => {
			// Add crossorigin to preloaded assets to prevent credentials mismatch
			return type === 'js' || type === 'css' || type === 'font';
		}
	});
	return response;
};

export const handleError: HandleServerError = ({ error, event }) => {
	console.error('[SvelteKit Error]', event.url.pathname, error);
	return {
		message: 'An unexpected error occurred.',
		code: 'UNKNOWN'
	};
};
