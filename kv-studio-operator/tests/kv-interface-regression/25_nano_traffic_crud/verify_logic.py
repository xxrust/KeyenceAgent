"""Offline semantic checks of source read back from the real saved project.

This small interpreter covers only the instructions in this traffic-light case.
It is not a KV STUDIO simulator or a PLC runtime acceptance test.
"""
import argparse
import ast
import itertools
import json
import operator
import re
from collections import Counter
from pathlib import Path


def device_key(device):
    return re.sub(r"\b(CR|MR|LR|R|DM)0+(\d+)\b", r"\1\2", device)


def expression(text, memory):
    text = re.sub(r"\bON\b", "1", text)
    text = re.sub(r"\bOFF\b", "0", text)
    text = re.sub(r"\bAND\b", "and", text)
    text = re.sub(r"(?<![<>=!])=(?!=)", "==", text)
    compare = {ast.Eq: operator.eq, ast.Lt: operator.lt, ast.GtE: operator.ge}

    def visit(node):
        if isinstance(node, ast.Expression):
            return visit(node.body)
        if isinstance(node, ast.Constant) and type(node.value) is int:
            return node.value
        if isinstance(node, ast.Name) and re.fullmatch(r"(?:CR|DM|MR|R)\d+", node.id):
            return memory.get(device_key(node.id), 0)
        if isinstance(node, ast.BinOp) and isinstance(node.op, ast.Add):
            return visit(node.left) + visit(node.right)
        if isinstance(node, ast.BoolOp) and isinstance(node.op, ast.And):
            return all(visit(value) for value in node.values)
        if isinstance(node, ast.Compare) and len(node.ops) == 1 and type(node.ops[0]) in compare:
            return compare[type(node.ops[0])](visit(node.left), visit(node.comparators[0]))
        raise ValueError(f"Unsupported expression: {text}")

    return visit(ast.parse(text, mode="eval"))


def script_scan(source, memory):
    stack = []
    active = True
    for raw in source.splitlines():
        line = raw.split("'", 1)[0].strip()
        if not line:
            continue
        if line.startswith("ELSE IF ") and line.endswith(" THEN"):
            frame = stack[-1]
            active = frame["parent"] and not frame["taken"] and bool(expression(line[8:-5], memory))
            frame["taken"] |= active
        elif line.startswith("IF ") and line.endswith(" THEN"):
            parent = active
            active = parent and bool(expression(line[3:-5], memory))
            stack.append({"parent": parent, "taken": active})
        elif line == "ELSE":
            frame = stack[-1]
            active = frame["parent"] and not frame["taken"]
            frame["taken"] |= active
        elif line == "END IF":
            active = stack.pop()["parent"]
        else:
            assignment = re.fullmatch(r"((?:DM|MR|R)\d+)\s*=\s*(.+)", line)
            if not assignment:
                raise ValueError(f"Unsupported statement: {line}")
            if active:
                memory[device_key(assignment[1])] = int(expression(assignment[2], memory))
    assert not stack, "Unclosed IF"


def ladder_scan(source, memory):
    accumulator = False
    for line in source.splitlines():
        if not line.strip():
            continue
        instruction, device = line.split()
        device = device_key(device)
        value = bool(memory.get(device, 0))
        if instruction == "LD":
            accumulator = value
        elif instruction == "LDB":
            accumulator = not value
        elif instruction == "ANB":
            accumulator = accumulator and not value
        elif instruction == "OUT":
            memory[device] = int(accumulator)
        else:
            raise ValueError(f"Unsupported instruction: {line}")


def lights(memory):
    return tuple(memory.get(f"R{index}", 0) for index in range(500, 506))


def check(phase, ladder):
    red = (1, 0, 0, 1, 0, 0)
    ns_green = (0, 0, 1, 1, 0, 0)
    ns_yellow = (0, 1, 0, 1, 0, 0)
    ew_green = (1, 0, 0, 0, 0, 1)
    ew_yellow = (1, 0, 0, 0, 1, 0)
    expected = [ns_green] * 10 + [ns_yellow] * 3 + [red] + [ew_green] * 10 + [ew_yellow] * 3 + [red]
    startup_cases = 0
    for initial_clock, retained_second, retained_edge in itertools.product((0, 1), (0, 9, 14, 26, 65535), (0, 1)):
        memory = {"CR2008": 1, "CR2006": initial_clock, "DM0": retained_second, "MR10": retained_edge}
        script_scan(phase, memory)
        ladder_scan(ladder, memory)
        assert memory["DM0"] == 27 and lights(memory) == red, memory
        startup_cases += 1
    memory = {"CR2008": 1, "CR2006": 0}
    script_scan(phase, memory)
    ladder_scan(ladder, memory)
    memory["CR2008"] = 0
    timeline = []
    for second in range(84):
        for scan in range(100):
            memory["CR2006"] = int(scan < 50)
            script_scan(phase, memory)
            ladder_scan(ladder, memory)
            assert memory["DM0"] == second % 28, (second, scan, memory)
            assert lights(memory) == expected[second % 28], (second, scan, memory)
            assert not (memory["R502"] and memory["R505"])
        timeline.append({"second": second, "cycle_second": memory["DM0"], "outputs": lights(memory)})
    fault_cases = 0
    for requests in itertools.product((0, 1), repeat=4):
        memory = dict(zip(("MR100", "MR101", "MR102", "MR103"), requests))
        ladder_scan(ladder, memory)
        assert not ((memory["R501"] or memory["R502"]) and (memory["R504"] or memory["R505"])), memory
        assert memory["R500"] == int(not (memory["R501"] or memory["R502"]))
        assert memory["R503"] == int(not (memory["R504"] or memory["R505"]))
        fault_cases += 1
    return {"ok": True, "kind": "offline_source_semantics", "plc_runtime_verified": False,
            "startup_cases": startup_cases, "scan_count": 8400, "cycle_count": 3,
            "request_combinations": fault_cases, "one_cycle_durations": dict(Counter(map(str, expected))),
            "timeline": timeline}


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--run", type=Path, required=True)
    options = parser.parse_args()
    phase_path = options.run / "21_persisted_phase/artifacts/operation/source_readback.txt"
    ladder_path = options.run / "final_ladder_readback.txt"
    result = check(phase_path.read_text(encoding="utf-8-sig"), ladder_path.read_text(encoding="utf-8-sig"))
    result.update(phase_path=str(phase_path), ladder_path=str(ladder_path))
    (options.run / "logic_verification.json").write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps({key: value for key, value in result.items() if key != "timeline"}, ensure_ascii=False))
