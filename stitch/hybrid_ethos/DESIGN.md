# Design System Strategy: The Decentralized Editorial

## 1. Overview & Creative North Star
The Creative North Star for this design system is **"The Digital Curator."** 

In a world of cluttered, high-velocity social feeds, this system serves as a calm, authoritative sanctuary. We are merging the high-stakes precision of a Professional SaaS Dashboard with the fluid, human-centric nature of social media. This is achieved through **Soft Minimalism**: a philosophy that rejects the "busy-ness" of traditional grids in favor of intentional asymmetry, generous white space (utilizing the `16` and `20` spacing tokens), and a sophisticated hierarchy that feels more like a high-end magazine than a generic web app.

We break the "template" look by treating the UI as a physical desk of layered papers. We avoid the rigidity of 1px borders and instead use tonal shifts to define boundaries, ensuring the interface feels integrated, expansive, and premium.

---

## 2. Colors & Surface Logic
Our palette is rooted in a "Teal & Alabaster" sophisticated contrast. We utilize Material-inspired tokens to create a dynamic range of depth without relying on dated shadow techniques.

### The "No-Line" Rule
Traditional social platforms rely on 1px borders to separate posts. **We prohibit this.** Boundaries must be defined solely through background color shifts. For example, a post (using `surface_container_lowest`) should sit atop a feed container (`surface_container_low`), which sits on the global `background`. This "Layered Tone" approach creates a cleaner, more modern aesthetic.

### Surface Hierarchy & Nesting
Treat the UI as a stack of fine paper. 
- **Global Background:** `background` (#f8fafb) — the base canvas.
- **Structural Areas (Sidebars/Feeds):** `surface_container_low` (#f2f4f5) — used to group content.
- **Interactive Units (Cards/Posts):** `surface_container_lowest` (#ffffff) — the highest point of focus.
- **Elevated Overlays:** `surface_bright` — for floating menus or temporary states.

### The "Glass & Gradient" Rule
To elevate the "Professional SaaS" feel, use **Glassmorphism** for navigation bars and floating action buttons. Use `surface` at 80% opacity with a `backdrop-blur(12px)`. For primary CTAs, do not use flat colors alone; apply a subtle linear gradient from `primary` (#006a69) to `primary_container` (#0ea5a4) at a 135-degree angle to give the teal a "soul" and sense of motion.

---

## 3. Typography
We use a dual-typeface system to balance authority with utility.

- **Display & Headlines (Manrope):** We use Manrope for all `display` and `headline` tokens. Its geometric yet slightly warm character provides the "Editorial" feel. Use `headline-lg` (2rem) for page titles to command attention.
- **Interface & Content (Inter):** Inter is our workhorse. Used for `title`, `body`, and `label` tokens, it ensures maximum readability for decentralized data and long-form social posts.

**Hierarchy Strategy:** 
Always pair a `headline-sm` title with `body-sm` metadata in `on_surface_variant` (muted gray) to create a high-contrast relationship between the "Actor" and the "Context."

---

## 4. Elevation & Depth
In this design system, depth is a function of light and tone, not structure.

*   **The Layering Principle:** Avoid `z-index` battles. Use the `surface_container` tiers. A `surface_container_high` element should only ever appear on top of a `surface_container_low` base.
*   **Ambient Shadows:** If an element must "float" (like a Modal or Tooltip), use an ambient shadow. 
    *   *Spec:* `0px 12px 32px rgba(25, 28, 29, 0.06)` (a 6% tint of our `on_surface` color). This mimics natural light rather than a digital drop shadow.
*   **The "Ghost Border" Fallback:** If accessibility requirements demand a border, use the `outline_variant` token at **15% opacity**. It should be felt, not seen.
*   **Glassmorphism:** For the decentralized "Translucent" feel, use semi-transparent surfaces for sidebars, allowing the brand's teal accents to bleed through the blur, creating a sense of "Hybrid" space.

---

## 5. Components

### Buttons
*   **Primary:** Pill-shaped (`rounded-full`). Gradient of `primary` to `primary_container`. Text in `on_primary`.
*   **Secondary:** Pill-shaped. Background of `secondary_container` with `on_secondary_container` text.
*   **Tertiary:** No background. `on_surface` text with a subtle `primary` underline on hover.

### Input Fields
*   **Styling:** Forgo the four-sided border. Use a `surface_container_high` background with a `rounded-sm` (0.5rem) corner. 
*   **States:** On focus, transition the background to `surface_container_lowest` and add a 2px `primary` bottom-border only.

### Cards & Feed Items
*   **The Rule:** **No Dividers.**
*   **Implementation:** Separate feed items using `3.5rem` (spacing 10) of vertical whitespace. If the content is dense, use a subtle background shift from `surface` to `surface_container_low` to define the card area.
*   **Corners:** Use `DEFAULT` (1rem/16px) for cards to maintain a friendly social feel.

### Avatars & Identity
*   **Circular:** All user avatars must be perfectly circular to contrast against the soft-square cards.
*   **Identity Ring:** For "Verified" or "Decentralized Node" status, use a 2px offset ring in `primary`.

### Data Visualization (SaaS Elements)
*   **Hybrid Charts:** Use `primary` (Teal) and `tertiary` (Burnt Orange) for data lines. Use `surface_container_highest` for chart grid lines, keeping them extremely faint.

---

## 6. Do’s and Don'ts

### Do
*   **Do** use asymmetrical margins. A wider left margin in a feed creates an editorial, "curated" look.
*   **Do** embrace white space. If a layout feels "empty," it is likely working.
*   **Do** use `body-lg` for the first paragraph of a social post to create a "Lead-in" effect.

### Don't
*   **Don't** use 100% black. Always use `on_surface` (#191c1d) for text to keep the "Modern SaaS" softness.
*   **Don't** use standard "Shadow-2" or "Shadow-4" effects. Stick to tonal layering.
*   **Don't** use icons without labels in the main navigation. "The Digital Curator" is clear and accessible.
*   **Don't** use high-contrast dividers (`#E6E8EB` at 100%). If you must divide, use a 1px gap that reveals the `background` color underneath.