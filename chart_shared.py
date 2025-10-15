#!/usr/bin/env python3
"""Shared helpers for telemetry chart generation."""

from __future__ import annotations

import hashlib
import json
from dataclasses import dataclass
from datetime import datetime, timezone, timedelta
from pathlib import Path
from typing import Dict, Iterable, List, Optional

import pandas as pd

CACHE_DIR = Path(".cache")
CACHE_DIR.mkdir(parents=True, exist_ok=True)

DEFAULT_TELEMETRY_COLORS = [
    "#1f77b4",
    "#ff7f0e",
    "#2ca02c",
    "#d62728",
    "#9467bd",
    "#8c564b",
    "#e377c2",
    "#7f7f7f",
    "#bcbd22",
    "#17becf",
]

DEFAULT_UTIL_COLORS = [
    "#2E86AB",
    "#A23B72",
    "#F18F01",
    "#C73E1D",
    "#4CAF50",
    "#9C27B0",
    "#FF9800",
    "#607D8B",
]


def _read_env_file(env_path: Path) -> Dict[str, str]:
    config: Dict[str, str] = {}
    if not env_path.exists():
        return config

    for raw_line in env_path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        value = value.split("#", 1)[0].strip().strip("\"\'")
        config[key.strip()] = value
    return config


def load_env_config(env_path: Path | None = None) -> Dict[str, str]:
    path = env_path or Path(".env")
    return _read_env_file(path)


def split_csv(values: Optional[str]) -> List[str]:
    if not values:
        return []
    return [part.strip() for part in values.split(",") if part.strip()]


def ensure_color_cycle(colors: Iterable[str], count: int, fallback: List[str]) -> List[str]:
    palette = [c.strip() for c in colors if c.strip()]
    if not palette:
        palette = list(fallback)
    if count <= len(palette):
        return palette[:count]
    # Extend palette deterministically when more colors are needed.
    extended = palette.copy()
    idx = 0
    while len(extended) < count:
        extended.append(palette[idx % len(palette)])
        idx += 1
    return extended


@dataclass(frozen=True)
class TelemetrySignature:
    telemetry_mtime: float
    nodes_mtime: float
    node_hash: str

    @classmethod
    def build(cls, telemetry_path: Path, nodes_path: Path, nodes: List[str]) -> "TelemetrySignature":
        tele_mtime = telemetry_path.stat().st_mtime if telemetry_path.exists() else 0.0
        node_mtime = nodes_path.stat().st_mtime if nodes_path.exists() else 0.0
        node_hash = hashlib.sha1(",".join(sorted(nodes)).encode("utf-8")).hexdigest()
        return cls(tele_mtime, node_mtime, node_hash)

    def to_dict(self) -> Dict[str, float | str]:
        return {
            "telemetry_mtime": self.telemetry_mtime,
            "nodes_mtime": self.nodes_mtime,
            "node_hash": self.node_hash,
        }

    @classmethod
    def from_dict(cls, data: Dict[str, float | str]) -> "TelemetrySignature":
        return cls(
            telemetry_mtime=float(data.get("telemetry_mtime", 0.0)),
            nodes_mtime=float(data.get("nodes_mtime", 0.0)),
            node_hash=str(data.get("node_hash", "")),
        )


def load_cache(cache_name: str) -> Dict[str, object]:
    cache_path = CACHE_DIR / cache_name
    if not cache_path.exists():
        return {}
    try:
        return json.loads(cache_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return {}


def save_cache(cache_name: str, data: Dict[str, object]) -> None:
    cache_path = CACHE_DIR / cache_name
    cache_path.write_text(json.dumps(data, indent=2, sort_keys=True), encoding="utf-8")


def read_telemetry_dataframe(csv_path: Path) -> pd.DataFrame:
    if not csv_path.exists():
        raise FileNotFoundError(f"Telemetry CSV not found: {csv_path}")
    df = pd.read_csv(
        str(csv_path),
        parse_dates=["timestamp"],
        on_bad_lines="skip",
    )
    expected = {"timestamp", "address", "status"}
    missing = expected - set(df.columns)
    if missing:
        raise ValueError(f"Telemetry CSV missing columns: {missing}")
    return df


def map_node_names(nodes_csv: Path, node_ids: List[str]) -> Dict[str, str]:
    if not nodes_csv.exists():
        return {node_id: node_id for node_id in node_ids}

    try:
        data = pd.read_csv(nodes_csv, on_bad_lines="skip")
    except Exception:
        return {node_id: node_id for node_id in node_ids}

    name_map: Dict[str, str] = {}
    for _, row in data.iterrows():
        node_id = str(row.get("ID", "")).strip()
        if not node_id or node_id not in node_ids:
            continue
        aka = str(row.get("AKA", "")).strip()
        user = str(row.get("User", "")).strip()
        if aka and aka not in {"N/A", node_id} and len(aka) <= 12:
            name_map[node_id] = aka
        elif user and user != "N/A":
            name_map[node_id] = user
    for node_id in node_ids:
        name_map.setdefault(node_id, node_id)
    return name_map


def recent_stats(series: pd.Series, now: Optional[datetime] = None, unit: str = "") -> str:
    if series.empty:
        return ""
    now = now or datetime.now(timezone.utc)
    df = pd.DataFrame({"time": pd.to_datetime(series.index, errors="coerce"), "value": series.values})
    df = df.dropna()
    if df.empty:
        return ""
    latest_row = df.iloc[-1]
    latest_ts = latest_row["time"].to_pydatetime()
    latest_val = float(latest_row.at["value"])
    delta = now - latest_ts
    age_hours = max(delta.total_seconds() / 3600, 0)
    if age_hours < 1:
        age_label = "<1h"
    elif age_hours < 24:
        age_label = f"{age_hours:.0f}h"
    else:
        age_label = f"{age_hours/24:.0f}d"

    window_hours = [3, 12, 24]
    parts = [f"{latest_val:.1f}{unit}" if unit else f"{latest_val:.1f}"]
    for window in window_hours:
        cutoff = now - timedelta(hours=window)
        window_vals = df[df["time"] >= cutoff]["value"]
        if window_vals.empty:
            continue
        avg = float(window_vals.mean())
        parts.append(f"{window}h:{avg:.1f}{unit}" if unit else f"{window}h:{avg:.1f}")
    return f"[{age_label}] " + " | ".join(parts)
