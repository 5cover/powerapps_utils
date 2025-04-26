# Power Apps Utils

## hex2rgba

Converts from a hex color to an RGBA() call.

## sanity

Objective: generate nested switches for choosing property values in a cartesian product state.

Use case: Fluid components.

### Example: button component

Property|n|Values
-|-|-
emphasis|3|default, subtle, minimal
variant|4|default, secondary, destructive, inverse

3*4 = 12 unique states.

Affeced properties:

- BorderColor
- Color
- Fill

- FocusedBorderColor
- FocusedBorderThickness

- DisabledBorderColor
- DisabledColor
- DisabledFill

- HoverBorderColor
- HoverColor
- HoverFill

- PressedBorderColor
- PressedColor
- PressedFill

## Main idea

Series of values from least to most specific state for ech propety.

Reusable Design tokens index to reuse colors.

### Metalanguage used

Steps separated by whitespace.

`<rule>`: reference to another rule

`6step7`: min 6, max 7

`6step*`: min 6, max inf

if no min: 1

if no max: 1

### Syntax

#### Opacity postfix operator

`<expression> . <opacity_percentage>`

`<expresssion>` is an RGB or RGBA color.

#### Token reference

`$ <token_name>`

#### Color

`# 6<hex_digit>6 0<hex_digit>2`

6 for RGB

2 for alpha byte

#### Number

`<digit*>.?`

### Fluid Button 

property|emphasis|variant|value
-|-|-|-
Color|||$white
DisabledColor|||$white.35

### Fluid Design Tokens

token|value
-|-
main_color|#007acd
white|#ffffff

### PowerShell implementation

Array of properties

Array of records of "Declaration"

- on: `Record<string, any?>`
- value: `any`

Design tokens: constants

Helper funcions:

`alpha(color, percentage)`

`hex(rgb_or_rgba)`

- Iterate over declarations
- Build Power Fx formulas for each property
- Print them
- Accept a CLI argument to build a specific propety, otherwise do all

## new implementation idea

read declarations from the buttom up (most specific to least specific)

first one must always be default fallback

generate nested If() in an AST

optimize what can be optimized to Switch

- If Emphasis=subtle or minimal: $white
- Elseif Variant=secondary: $gray
- Else $main_color