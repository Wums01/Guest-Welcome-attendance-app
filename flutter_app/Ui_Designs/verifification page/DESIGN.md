# Design System Strategy: The Welcoming Hearth

This design system is engineered to transform a standard administrative task—attendance tracking—into a premium, hospitality-driven experience. Moving away from the cold, utilitarian "spreadsheet" aesthetic, we utilize a "High-End Editorial" approach. We leverage deep tonal layering, light-emissive accents, and sophisticated typography to create a digital environment that feels as warm and intentional as a physical welcome center.

---

### 1. Creative North Star: "The Digital Concierge"
The North Star for this system is **The Digital Concierge**. It is authoritative yet approachable, professional yet personal. 

To break the "template" look, we reject the rigid, centered grid. Instead, we use **Intentional Asymmetry**. Key information (like a guest’s name) should feel anchored, while secondary actions (status chips) float with generous breathing room. We use overlapping elements—such as a profile image breaking the boundary of a card—to create a sense of organic movement and depth that "flat" systems lack.

---

### 2. Color & Atmospheric Depth
Our palette is not just a collection of hex codes; it is a system of atmospheric layers.

*   **Primary (#bfc5e4 / #0a1128):** Used for high-level brand moments and deep containment.
*   **Secondary/Tertiary (#fff9ef / #e9c400):** Our "Warm Gold." This is our candle-flicker—the light that guides the user’s eye to the most important action.
*   **The "No-Line" Rule:** 1px solid borders are strictly prohibited for sectioning. Boundaries must be defined solely through background color shifts. For example, a list of guests (`surface_container_low`) should sit on the main `surface` without a stroke.
*   **Surface Hierarchy & Nesting:** Treat the UI as stacked sheets of fine, dark paper. 
    *   **Level 0 (Background):** `surface` (#131313)
    *   **Level 1 (Section):** `surface_container_low` (#1c1b1b)
    *   **Level 2 (Card):** `surface_container` (#201f1f)
    *   **Level 3 (Elevated Element):** `surface_container_high` (#2a2a2a)
*   **The "Glass & Gradient" Rule:** To provide "soul," primary CTAs should not be flat. Use a subtle linear gradient from `primary` to `primary_container` at a 135-degree angle. For floating overlays (modals/drawers), use `surface_bright` at 80% opacity with a `24px` backdrop-blur to create a "frosted glass" effect.

---

### 3. Typography: Editorial Authority
We use **Plus Jakarta Sans** (the refined evolution of Poppins) to provide a clean, rounded, yet professional tone.

*   **Display (lg/md):** Use sparingly for "Welcome" moments. Set with tight letter-spacing (-0.02em) to feel like a premium magazine header.
*   **Headline & Title:** These are the "voice" of the app. Headlines should be high-contrast (Off-white `on_surface` against dark backgrounds) to ensure immediate hierarchy.
*   **Body & Labels:** Use `body-md` for guest details. To ensure a "ministry-focused" warmth, avoid pure white for long-form text; use `on_surface_variant` (#c6c6ce) to reduce eye strain and feel more inviting.

---

### 4. Elevation & Depth: Tonal Layering
Traditional drop shadows are often messy in dark mode. We achieve lift through light, not darkness.

*   **The Layering Principle:** Instead of shadows, move from `surface_dim` up to `surface_bright`. A guest card should "glow" slightly brighter than the floor it sits on.
*   **Ambient Shadows:** If an element must float (like a FAB), use a large 32px blur, 4% opacity shadow tinted with `surface_tint`. It should feel like a soft glow, not a dark smudge.
*   **The "Ghost Border":** If a button needs more definition against a similar background, use `outline_variant` at **15% opacity**. This provides a hint of a physical edge without creating a "boxed-in" feeling.

---

### 5. Signature Components

*   **Attendance Cards:** **Forbid dividers.** Use `1.5rem` (spacing-6) of vertical whitespace to separate guest entries. Use a vertical "accent bar" of `tertiary` (Warm Gold) on the far left of a card to indicate a "New Guest" status.
*   **Action Buttons:** 
    *   *Primary:* Gradient fill (`primary` to `primary_container`), `xl` (1.5rem) rounded corners.
    *   *Tertiary (Ghost):* No background, `on_surface` text, 10% `outline_variant` ghost border on hover.
*   **Status Indicators (The "Living" Chips):** 
    *   *Present:* A vibrant green (`#4ADE80`) dot next to `label-md` text. The chip background should be the color at 10% opacity.
    *   *Absent/Excused:* Use the same low-opacity "halo" effect. Avoid heavy, solid-colored blocks which feel like "errors."
*   **Inputs:** Use `surface_container_highest` for the field background. No bottom line. Use `md` (0.75rem) corners. The label should "float" in `tertiary_fixed_dim` when active to maintain that gold-accented warmth.
*   **Guest Timeline:** Instead of a vertical line, use a series of staggered `surface_container_high` cards that slightly overlap, creating a "shingled" effect that guides the eye downward.

---

### 6. Do’s and Don’ts

**Do:**
*   **Do** use asymmetrical margins (e.g., more space on the left than the right) for title sections to create an editorial look.
*   **Do** use `2.5rem` (spacing-10) for page gutters to give the content "room to breathe."
*   **Do** ensure all "Warm Gold" text has a 4.5:1 contrast ratio against navy surfaces for accessibility.

**Don’t:**
*   **Don’t** use pure black (#000000). It kills the "navy depth" and feels cold/electronic rather than ministry-focused.
*   **Don’t** use 1px dividers to separate list items; let the space do the work.
*   **Don’t** use "Alert Red" for anything other than a true system error. For "Absent" guests, use a muted, sophisticated rose-red to maintain the welcoming tone.