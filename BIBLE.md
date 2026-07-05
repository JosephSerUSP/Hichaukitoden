# Hichaukitoden - Development Bible & Guidelines

This document outlines key technical decisions, architectures, and design rules that must be followed during the development of Hichaukitoden.

---

## 1. Code Sharing and Reuse (CRITICAL)

All code—especially UI rendering coordinates and grid placements—must be shared and reuse components as much as possible. Do not copy-paste logic or coordinate mappings.

- **Unified Grid layouts**: Layout systems (such as the 2x2 Party Grid) must be defined as shared helper functions (e.g. `renderer.drawPartyGrid()`) and reused across both exploration menus, battle consoles, and target selection overlays.
- **In-Memory Physics & Dynamic Logic**: Math and physics calculations (like gravity/bouncing equations or interpolation logic) must reside in general updates rather than being ad-hoc and scattered.

---

## 2. UI Aesthetics and Theme

- **Rich Gradients**: Never use solid flat dark overlays for major menus. Use vertical dark gradient blends to establish atmosphere.
- **Micro-Animations**: All menus must feature clean, responsive layout animations (e.g. panels sliding in/out dynamically using timer states).
- **Element Icons**: Elements must be represented by small colored orb bullets mapped directly from the system iconset.

---

## 3. Battle Systems and Tactile Feedback

- **Dynamic Gauges**: Gauges must never jump instantly. They must animate using smooth interpolation filters to visualize healing and damage transitions.
- **Action Flashes**: Actors must visual flash white/cyan when initiating actions, and flash red when receiving impacts.
- **Tactile Damage Numbers**: Damage numbers must launch with vertical velocity and bounce physically against target planes using gravity dynamics.
