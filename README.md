# Power Apps Utils

## hex2rgba

Converts from a hex color to an RGBA() call.

## Sanity

**Sanity** is a command‑line tool that generates PowerApps formulas representing the different state combinations of a UI component based on design system and component definition JSON files.

### Prerequisites

- PowerShell Core (pwsh) 7.x or higher

### Installation

1. Download **sanity.ps1** from this repository.
2. Ensure it has execute permissions:

   ```powershell
   chmod +x ./sanity.ps1
   ```

3. (Optional) Move to a directory in your PATH:

   ```powershell
   mv ./sanity.ps1 /usr/local/bin/sanity
   ```

### Usage

```powershell
./sanity.ps1 <DesignSystem.json> <Component.json> [-Property <PropertyName>]
```

- `<DesignSystem.json>`: JSON file containing design tokens (colors, fonts, spacing).
- `<Component.json>`: JSON file defining the UI component (name, modifiers, properties).
- `-Property` (optional): Specify a single property to generate formulas for. If omitted, the tool processes all properties.

### Examples

- Generate formulas for all properties:

  ```powershell
  ./sanity.ps1 fluid.json button.json
  ```

- Generate formula for the `Fill` property:

  ```powershell
  ./sanity.ps1 designSystem.json component.json -Property Fill
  ```

### Input File Schemas

The tool expects:

- `designSystem.json` conforming to the `designSystem.json` schema.
- `component.json` conforming to the `component.json` schema.

You can find example files in the `/examples` directory.

### Configuration File Syntax

**Design System (`designSystem.json`)**

- **Root Object**: Must contain a `tokens` property, an object mapping token names to values.  
- **Token Names**: Use alphanumeric characters, underscores, slashes, or hyphens (e.g., `background/brand/solid`, `font-size/text-sm`).  
- **Values**:
  - **Color Tokens**: Hex strings in `#RRGGBB` or `#RRGGBBAA` format.  
    - Optional opacity multiplier: append a dot and percentage (0–100), e.g. `$border/brand/strong.35` applies 35% opacity.  
  - **Numeric Tokens**: Plain numbers (e.g., spacing, font sizes).  
  - **Variable References**: To reference a token from elsewhere, use the `$path/to/token` syntax, optionally with an opacity suffix.

**Component Definition (`component.json`)**

- **Required Properties**:
  - `name` (string): Component name (e.g., `Button`).  
  - `modifiers` (string array): List of modifier names that define state axes (e.g., `Emphasis`, `Variant`).  
  - `properties` (object): Maps CSS-like property names (e.g., `Fill`, `BorderColor`) to either a single value or an array of conditional declarations.

- **Property Values**:
  1. **Single Value**: A string or number applies uniformly across all states.  

     ```json
     "PaddingTop": 16
     ```

  2. **Conditional Declarations**: An array where each item declares a `value` and optional modifier conditions:

     ```json
     "Fill": [
       { "value": "$background/brand/solid" },
       { "Emphasis": ["minimal","subtle"], "value": "$background/brand/primary/translucent/default" }
     ]
     ```

     - **`value`**: A string (possibly a `$` reference) or number.  
     - **Modifier Keys**: Match names in `modifiers`; each can be a string or an array of strings specifying when this declaration applies.
     - Declarations are evaluated in order: first match wins, with a default (no modifiers) always first.

Modifier combinations drive branching logic: the tool generates nested `If` or `Switch` formulas based on these declarations.

### How It Works

1. **Parse JSON**: Loads the design system and component definitions.
2. **Convert Values**: Transforms token values (colors, numbers) into PowerApps-friendly representations.
3. **Build Formulas**: Creates `Switch` formulas for each component property based on modifiers.
4. **Output**: Prints formulas to the console for use in PowerApps.
