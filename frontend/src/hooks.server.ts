import type { HandleServerError } from '@sveltejs/kit';

export const handleError: HandleServerError = ({ error, event }) => {
	console.error('[SvelteKit Error]', event.url.pathname, error);
	return {
		message: 'An unexpected error occurred.',
		code: 'UNKNOWN'
	};
};
