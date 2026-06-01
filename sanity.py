from collections.abc import Iterable
import json
import argparse
import sys
import re
from pathlib import Path

from typing import Sequence, TypedDict, TypeAlias


class DesignSystem(TypedDict):
    tokens: dict[str, str | int | float]


PropBag: TypeAlias = dict[str, 'str | int | float | PropBag']
PropValue: TypeAlias = str | int | float | PropBag


class Modifier(TypedDict):
    default: str
    values: list[str]


class Component(TypedDict):
    name: str
    modifiers: dict[str, Modifier]
    properties: PropBag


def load_json(path: str):
    with open(path, 'r', encoding='utf-8') as f:
        return json.load(f)


def format_decimal(value: int | float, precision: int):
    if precision < 0:
        sys.exit("Precision must be greater than or equal to 0")

    number = float(value)
    if number == 0:
        return '0'

    if -1 < number < 1:
        return f"{format_fixed(number * 100, precision)}%"

    return format_fixed(number, precision)


def format_fixed(value: float, precision: int):
    formatted = f"{round(value, precision):.{precision}f}"
    formatted = formatted.rstrip('0').rstrip('.')
    return '0' if formatted in ('-0', '') else formatted


def parse_number(value: str):
    if re.fullmatch(r'[+-]?(?:\d+(?:\.\d*)?|\.\d+)', value):
        return float(value)
    return None


def convert_to_powerapps_rgba(hex_color: str, precision: int, opacity_percentage: float | None = None):
    hex_color = hex_color.lstrip('#')
    r = int(hex_color[0:2], 16)
    g = int(hex_color[2:4], 16)
    b = int(hex_color[4:6], 16)
    a = 1
    if len(hex_color) == 8:
        a = int(hex_color[6:8], 16) / 255
    if opacity_percentage is None:
        opacity_percentage = 100
    alpha = a * (opacity_percentage / 100)
    if alpha == 0:
        return "RGBA(0,0,0,0)"
    return f"RGBA({r},{g},{b},{format_decimal(alpha, precision)})"


def convert_to_parsed_value(value: PropValue, design_system: DesignSystem, precision: int):
    if isinstance(value, int | float):
        return format_decimal(value, precision)

    value = str(value)
    m = re.match(r'^\$([\w/-]+)(.*)$', value)
    if m:
        var_name = m.group(1)
        if var_name not in design_system['tokens']:
            sys.exit(f"missing variable '{var_name}'")
        value = str(design_system['tokens'][var_name]) + str(m.group(2))

    number = parse_number(value)
    if number is not None:
        return format_decimal(number, precision)

    m = re.match(r'^(#[A-Fa-f0-9]{6}(?:[A-Fa-f0-9]{2})?)(?:\.([0-9]*\.?[0-9]+))?', value)
    if m:
        hex_color = m.group(1)
        opacity = float(m.group(2)) if m.group(2) else None
        value = convert_to_powerapps_rgba(hex_color, precision, opacity)
    return value


def convert_to_switch(switchee: str, cases: dict[str, str], default: str):
    if not cases:
        return default
    parts = [f'Switch({switchee},']
    for k, v in cases.items():
        parts.append(f'"{k}",{v},')
    parts.append(f'{default})')
    return ''.join(parts)


def convert_to_formula(
        decls: PropBag, component: Component, design_system: DesignSystem, precision: int, modifiers: Sequence[str]):
    switchee = modifiers[0]
    if not switchee:
        sys.exit(f"too much nesting at " + repr(decls))
    modifier = component['modifiers'][switchee]

    """ 
    "BorderColor": {
        "*"          : "$border/brand/strong",
        "destructive": "$border/status/danger/strong",
        "secondary"  : "$border/neutral/strong"
        },
    default variant=primary

    switch
        destructive: $border/status/danger/strong
        secondary:   $border/neutral/strong
        $border/brand/strong

    no changes, since star represents a single value and it is default

    "BorderColor": {
        "*"          : "$border/brand/strong",
        "primary": "$border/primary/strong",
        "secondary"  : "$border/neutral/strong"
        },
    default variant=primary

    switch
       secondary: $border/neutral/strong 
       destructive: $border/brand/strong
       $border/primary/strong

    * represents { destructive }. default is primary
    the switch default encompass modifier default

    general rule: when * and modifier default don't agree, expand star by minusing the set, keep modifier default

    """

    cases = {}
    modifiers = modifiers[1:]
    defaultValue = convert_prop_value(decls.get(modifier['default'], decls['*']), precision, modifiers)
    # expand star
    undeclared = set(modifier['values']) - decls.keys()
    cases = {}
    for k, v in decls.items():
        v = convert_prop_value(v, precision, modifiers)
        if v == defaultValue: continue
        if k == '*':
            for uk in undeclared:
                cases[uk] = v
        else:
            cases[k] = v

    return convert_to_switch(f"{component['name']}.{switchee}", cases, defaultValue)


def convert_prop_value(v: PropValue, precision: int, modifiers: Sequence[str]):
    if isinstance(v, dict):
        return convert_to_formula(v, component, design_system, precision, modifiers)
    else:
        return convert_to_parsed_value(v, design_system, precision)


def convert_from_property(value: PropValue, component: Component, design_system: DesignSystem, precision: int):
    if not isinstance(value, dict):
        value = {'*': value}
    return convert_to_formula(value, component, design_system, precision, list(component['modifiers'].keys()))


def iter_property_formulas(component: Component, design_system: DesignSystem, property_name: str | None, precision: int):
    if property_name:
        if property_name not in component['properties']:
            sys.exit(f"missing property '{property_name}'")
        yield property_name, convert_from_property(component['properties'][property_name], component, design_system, precision)
    else:
        for prop, value in component['properties'].items():
            yield prop, convert_from_property(value, component, design_system, precision)


def print_powerfx_yaml(name: str, control: str, property_formulas):
    print(f"- {name}:")
    print(f"    Control: {control}")
    print("    Properties:")
    for prop, formula in property_formulas:
        print(f"      {prop}: ={formula}")


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description="Generate PowerApps formulas for a UI component based on design system tokens.")
    parser.add_argument('DesignSystem', type=str, help='Path to the design system JSON file')
    parser.add_argument('Component', type=str, help='Path to the component JSON file')
    parser.add_argument('-Property', type=str, help='Name of a single property to generate', required=False)
    parser.add_argument('-Name', type=str, help='Name of the control instance in the generated YAML', required=False)
    parser.add_argument('-Control', type=str, help='Control type/version in the generated YAML', default='Classic/Button@2.2.0')
    parser.add_argument('-Precision', type=int, help='Maximum digits after the decimal point when formatting numbers', default=2)
    args = parser.parse_args()

    design_system: DesignSystem = load_json(args.DesignSystem)
    component: Component = load_json(args.Component)
    name = args.Name or Path(args.Component).stem

    print_powerfx_yaml(
        name,
        args.Control,
        iter_property_formulas(component, design_system, args.Property, args.Precision),
    )
