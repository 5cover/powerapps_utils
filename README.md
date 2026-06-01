# Power Apps Utils

## hex2rgba

Converts from a hex color to an RGBA() call.

## Sanity

**Sanity** is a command-line tool that generates copy-pasteable Power Fx YAML markup for a control based on design-system tokens and component property definitions.

### Usage

```powershell
python .\sanity.py <DesignSystem.json> <Component.json> [-Property <PropertyName>] [-Name <ControlName>] [-Control <ControlType>] [-Precision <Digits>]
```

- `<DesignSystem.json>`: JSON file containing design tokens (colors, fonts, spacing).
- `<Component.json>`: JSON file defining the component name, modifier axes, and properties.
- `-Property` (optional): Generate only one property. If omitted, all properties are generated.
- `-Name` (optional): Control instance name in the YAML output. Defaults to the component filename without extension.
- `-Control` (optional): Power Fx control type/version. Defaults to `Classic/Button@2.2.0`.
- `-Precision` (optional): Maximum digits after the decimal point when formatting numbers. Defaults to `2`.

### Examples

- Generate YAML for all properties:

  ```powershell
  python .\sanity.py .\designSystems\fluid.json .\components\button.json -Name Button1
  ```

- Generate YAML for the `Fill` property only:

  ```powershell
  python .\sanity.py .\designSystems\fluid.json .\components\button.json -Property Fill -Name Button1
  ```

- Generate a different control type with more decimal precision:

  ```powershell
  python .\sanity.py .\designSystems\fluid.json .\components\button.json -Control Classic/Button@2.2.0 -Precision 3
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
    - Optional opacity multiplier on references: append a dot and percentage (0-100), e.g. `$border/brand/strong.35` applies 35% opacity.  
  - **Numeric Tokens**: Plain numbers (e.g., spacing, font sizes).  
  - **Formula Tokens**: Strings that are already valid Power Fx expressions (e.g., `Font.Lato`).

**Component Definition (`component.json`)**

- **Required Properties**:
  - `name` (string): Component name (e.g., `Button`).  
  - `modifiers` (string array): Ordered list of modifier names that define state axes (e.g., `Variant`, `Emphasis`).  
  - `properties` (object): Maps Power Apps property names (e.g., `Fill`, `BorderColor`) to either a single value or a nested modifier object.

- **Property Values**:
  1. **Single Value**: A string or number applies uniformly across all states.  

     ```json
     "PaddingTop": 16
     ```

  2. **Nested Modifier Object**: Each nesting level corresponds to the modifier at the same position in `modifiers`. Use `*` for the default case.

     ```json
     "Fill": {
       "*": {
         "*": "$background/brand/solid",
         "minimal": "$background/brand/primary/translucent/default",
         "subtle": "$background/brand/primary/translucent/default"
       },
       "destructive": {
         "*": "$background/status/danger/solid",
         "minimal": "$background/neutral/primary/translucent/default",
         "subtle": "$background/neutral/primary/translucent/default"
       }
     }
     ```

     - A leaf value can be a number, a Power Fx expression string, a hex color string, or a token reference.
     - Token references use `$path/to/token` and can include an opacity suffix, such as `$border/brand/strong.35`.
     - Nested objects generate nested `Switch(...)` formulas using English Power Fx syntax with comma separators.

### Output Format

The output is Power Fx YAML markup:

```yaml
- Button1:
    Control: Classic/Button@2.2.0
    Properties:
      Fill: =Switch(Button.Variant,"destructive",RGBA(219,55,53,1),RGBA(0,122,205,1))
      PaddingTop: =16
```

Number formatting uses dot decimal separators. Trailing nonsignificant digits are removed, so `1.0` becomes `1`. Nonzero values between `-1` and `1` are formatted with Power Fx percentage syntax after applying `-Precision`; for example, with `-Precision 2`, `0.25098039215686274` becomes `25.1%`. Fully transparent colors are normalized to `RGBA(0,0,0,0)`.

Modifier combinations drive branching logic: the tool generates nested `Switch` formulas based on these declarations.

### How It Works

1. **Parse JSON**: Loads the design system and component definitions.
2. **Resolve Values**: Resolves token references and converts colors and numbers to compact Power Fx expressions.
3. **Build Formulas**: Creates `Switch` formulas for component properties based on modifiers.
4. **Output**: Prints Power Fx YAML markup to the console.
