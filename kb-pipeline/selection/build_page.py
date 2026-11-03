"""Build selection.html from the four CSVs in this folder (data embedded as JSON)."""
import csv
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent

TABLES = [
    ("cpu", "CPU 单元", "cpu.csv", [
        ("model", "型号"), ("series", "系列"), ("builtin_in", "内置输入"), ("builtin_out", "内置输出"),
        ("ethercat_port", "EtherCAT"), ("max_axes", "最大轴数"), ("ethernet_ports", "以太网口"),
        ("program_capacity", "程序容量"), ("max_expansion_units", "扩展单元台数"), ("max_io_points", "最大 I/O"),
        ("expansion_compat", "可接扩展单元"), ("other_ports", "其他接口"), ("builtin_io_type", "内置 I/O 类型"),
        ("notes", "备注")]),
    ("motion", "运动 / 定位", "motion_units.csv", [
        ("model", "型号"), ("category", "类别"), ("interface", "接口"), ("axes", "轴数"),
        ("pulse_output_type", "脉冲输出方式"), ("max_pulse_rate", "最高脉冲频率"), ("cw_ccw_supported", "CW/CCW"),
        ("compatible_cpus", "适用 CPU"), ("notes", "备注")]),
    ("io", "数字量 I/O", "io_units.csv", [
        ("model", "型号"), ("in_points", "输入点"), ("out_points", "输出点"), ("output_type", "输出类型"),
        ("out_current_per_point", "每点电流"), ("rated_voltage", "额定电压"), ("points_per_common", "公共端"),
        ("connector", "接线方式"), ("response_time", "响应时间"), ("input_type", "输入极性"),
        ("compatible_series", "适用系列"), ("notes", "备注")]),
    ("special", "模拟量 / 通信 / 特殊", "special_units.csv", [
        ("model", "型号"), ("category", "类别"), ("channels_or_ports", "通道 / 端口"),
        ("signal_range_or_protocol", "信号范围 / 协议"), ("resolution_or_speed", "分辨率 / 速度"),
        ("conversion_or_cycle_time", "转换 / 周期"), ("compatible_series", "适用系列"), ("manual", "手册"),
        ("notes", "备注")]),
]


def parse_evidence(s: str) -> dict:
    out = {}
    for part in (s or "").split(";"):
        if "=" in part:
            k, v = part.split("=", 1)
            out[k.strip()] = [x.strip() for x in v.split(",") if x.strip()]
    return out


def main():
    data = []
    for key, label, fname, cols in TABLES:
        rows = []
        for r in csv.DictReader(open(HERE / fname, encoding="utf-8-sig")):
            rows.append({"cells": {c: r.get(c, "") for c, _ in cols}, "ev": parse_evidence(r.get("evidence", ""))})
        data.append({"key": key, "label": label, "cols": cols, "rows": rows})
    tpl = (HERE / "selection.template.html").read_text(encoding="utf-8")
    out = tpl.replace("/*__DATA__*/null", json.dumps(data, ensure_ascii=False))
    (HERE / "selection.html").write_text(out, encoding="utf-8")
    print("rows:", {d["key"]: len(d["rows"]) for d in data}, "bytes:", len(out.encode("utf-8")))


if __name__ == "__main__":
    main()
