// See https://svelte.dev/docs/kit/types#app.d.ts
// for information about these interfaces
declare global {
	namespace App {
		// interface Error {}
		// interface Locals {}
		// interface PageData {}
		interface PageState {
			// The mobile More sheet is open (shallow routing, BottomTabs.svelte).
			moreSheet?: boolean;
			// The comments sheet is open (shallow routing, CommentsSheet.svelte).
			commentsSheet?: boolean;
		}
		// interface Platform {}
	}
}

export {};
