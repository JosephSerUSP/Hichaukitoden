# Icon Sheet Documentation

## 📐 Icon Specifications
- **Icon size:** 12 × 12 pixels  
- **Icon sheet size:** 120 × *height* (height is flexible and not relevant)  
- **Reference system:** Icons are identified by **ID**.  
  - Example: **Icon ID 12** → located in the **2nd column, 2nd row**.  

## 🎨 Rendering Rules
- All icons **must** render with a **2px drop shadow** when drawn in the interface.  
- Icons are arranged in a grid layout based on their ID.  

## 🔢 Icon Groups
### Element - **IDs 1...10, 11...20 [...] 81...90:**  
- Represents the elements: **R (Red), G (Green), B (Blue), W (White), K (Black), - (None), -R+G(Yellow), R+B (Magenta), B+G (Cyan), - (None)**  

### Element Orbs
- **IDs 0X**  

### Element Orbs (Mini)
- **IDs 1X**  
- Designed to be **overlapped diagonally** for composite effects  

### Element Crystals
- **IDs 2X**  

### Element Books
- **IDs 3X**  

### Element Cards
- **IDs 4X**  

### Element Potions
- **IDs 5X**  

### Element Vials
- **IDs 6X**  

### Element Weapons
- **IDs 7X**  

### Element Armors
- **IDs 8X**  

## System
- **ID 101: Evolution (Locked), ID 102: Evolution (Available), ID 103: Passive Skill (status), ID 104: Passive Skill (reactive), ID 105: Passive Skill (Map).**

### Status Effects
- **ID 111: -, ID 112: KO, ID 113: Poison, ID 114: Blind, ID 115: silence, ID 116: Berserk, ID 117: Confuse, ID 118: Sleep, ID 119: Paralysis**

### Race
- **ID 121: Fey, ID 122: Divine, ID 123: Demon, ID 124: Construct, ID 125: Beast, ID 126: Undead, ID 127: Special**

## 📊 Icon Positioning
- Icons are indexed left-to-right, top-to-bottom.  
- Formula for position:  
  - **Column** = `(ID - 1) % 10 + 1`  
  - **Row** = `⌊(ID - 1) / 10⌋ + 1`  

Example:  
- **ID 12** → Column 2, Row 2  

## 🗂️ Usage Notes
- Use **IDs 1–5** for primary element representation.  
- Use **IDs 11–15** for secondary/overlay effects.  
- Always apply the **2px shadow** for consistency across the UI.  

---
This documentation ensures consistent usage of the icon sheet across the project.
