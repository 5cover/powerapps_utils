import json
import argparse
import sys
import re
from pathlib import Path

from typing import TypedDict, TypeAlias

class DesignSystem(TypedDict):
    tokens: dict[str, str | int | float]



PropBag: TypeAlias = dict[str, 'str | int | float | PropBag']
PropValue: TypeAlias = str | int | float | PropBag

class Component(TypedDict):
    name: str
    modifiers: tuple[str]
    properties: PropBag

def load_json(path: str):
    with open(path, 'r', encoding='utf-8') as f:
        return json.load(f)


def convert_to_powerapps_rgba(hex_color: str, opacity_percentage: float | None=None):
    hex_color = hex_color.lstrip('#')
    r = int(hex_color[0:2], 16)
    g = int(hex_color[2:4], 16)
    b = int(hex_color[4:6], 16)
    a = 1
    if len(hex_color) == 8:
        a = int(hex_color[6:8], 16) / 255
    if opacity_percentage is None:
        opacity_percentage = 100
    return f"RGBA({r},{g},{b},{a * (opacity_percentage / 100)})"


def convert_to_parsed_value(value: str, design_system: DesignSystem):
    m = re.match(r'^\$([\w/-]+)(.*)$', value)
    if m:
        var_name = m.group(1)
        if var_name not in design_system['tokens']:
            sys.exit(f"missing variable '{var_name}'")
        value = str(design_system['tokens'][var_name]) + m.group(2)
    m = re.match(r'^(#[A-Fa-f0-9]{6}(?:[A-Fa-f0-9]{2})?)(?:\.([0-9]*\.?[0-9]+))?', value)
    if m:
        hex_color = m.group(1)
        opacity = float(m.group(2)) if m.group(2) else None
        value = convert_to_powerapps_rgba(hex_color, opacity)
    return value


def convert_to_switch(switchee: str, cases: dict[str, str], default: str | None):
    if not cases:
        return default
    parts = [f'Switch({switchee},']
    for k, v in cases.items():
        parts.append(f'"{k}",{v},')
    parts.append(f'{default})')
    return ''.join(parts)


def convert_to_formula(decls: PropBag, component: Component, design_system: DesignSystem, level=0):
    try:
        switchee = component['modifiers'][level]
    except IndexError:
        sys.exit(f"too much nesting: {level}")

    cases = {}
    default = None
    for k, v in decls.items():
        if isinstance(v, dict):
            value = convert_to_formula(v, component, design_system, level + 1)
        else:
            value = convert_to_parsed_value(str(v), design_system)
        if k == '*':
            default = value
        else:
            cases[k] = value
    return convert_to_switch(f"{component['name']}.{switchee}", cases, default)


def convert_from_property(value: PropValue, component: Component, design_system: DesignSystem):
    if not isinstance(value, dict):
        value = {'*': value}
    return convert_to_formula(value, component, design_system)


def iter_property_formulas(component: Component, design_system: DesignSystem, property_name: str | None):
    if property_name:
        if property_name not in component['properties']:
            sys.exit(f"missing property '{property_name}'")
        yield property_name, convert_from_property(component['properties'][property_name], component, design_system)
    else:
        for prop, value in component['properties'].items():
            yield prop, convert_from_property(value, component, design_system)


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
    args = parser.parse_args()

    design_system: DesignSystem = load_json(args.DesignSystem)
    component: Component = load_json(args.Component)
    name = args.Name or Path(args.Component).stem

    print_powerfx_yaml(
        name,
        args.Control,
        iter_property_formulas(component, design_system, args.Property),
    )
