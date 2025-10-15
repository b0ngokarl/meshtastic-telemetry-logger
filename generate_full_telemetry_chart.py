#!/usr/bin/env python3
"""Generate the comprehensive multi-node telemetry chart."""

from __future__ import annotations

import argparse
import sys
from datetime import timezone
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.dates as mdates
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd

from chart_shared import (
	DEFAULT_TELEMETRY_COLORS,
	TelemetrySignature,
	ensure_color_cycle,
	load_cache,
	load_env_config,
	map_node_names,
	read_telemetry_dataframe,
	recent_stats,
	save_cache,
	split_csv,
)

OUTPUT_FILE = Path("multi_node_telemetry_chart.png")
CACHE_NAME = "telemetry_chart_cache.json"


def parse_args() -> argparse.Namespace:
	parser = argparse.ArgumentParser(description=__doc__)
	parser.add_argument("--nodes", help="Comma-separated node IDs to chart")
	parser.add_argument("--names", help="Comma-separated display names for --nodes")
	parser.add_argument(
		"--force",
		action="store_true",
		help="Force regeneration even when nothing changed",
	)
	return parser.parse_args()


def resolve_nodes(config: dict, args: argparse.Namespace) -> list[str]:
	if args.nodes:
		nodes = split_csv(args.nodes)
	else:
		nodes = split_csv(config.get("MONITORED_NODES"))
	if not nodes:
		raise SystemExit("No nodes configured for telemetry chart generation.")
	return nodes


def resolve_names(
	nodes: list[str], config: dict, args: argparse.Namespace, nodes_csv: Path
) -> dict[str, str]:
	if args.names:
		raw_names = split_csv(args.names)
	else:
		raw_names = split_csv(config.get("CHART_NODE_NAMES"))
	override_map = {node: raw_names[i] for i, node in enumerate(nodes) if i < len(raw_names)}
	resolved = map_node_names(nodes_csv, nodes)
	resolved.update({k: v for k, v in override_map.items() if v})
	return resolved


def should_skip(signature: TelemetrySignature, force: bool) -> bool:
	if force or not OUTPUT_FILE.exists():
		return False
	cache = load_cache(CACHE_NAME)
	cached_sig = cache.get("signature") if isinstance(cache, dict) else None
	if not isinstance(cached_sig, dict):
		return False
	return TelemetrySignature.from_dict(cached_sig) == signature


def finalise_cache(signature: TelemetrySignature, node_names: dict[str, str]) -> None:
	save_cache(
		CACHE_NAME,
		{
			"signature": signature.to_dict(),
			"nodes": node_names,
		},
	)


def prepare_node_frame(df: pd.DataFrame, node_id: str) -> pd.DataFrame:
	node_df = df[df["address"] == node_id].copy()
	if node_df.empty:
		return node_df
	node_df.sort_values("timestamp", inplace=True)
	node_df["timestamp"] = pd.to_datetime(node_df["timestamp"], errors="coerce")
	node_df = node_df.dropna(subset=["timestamp"])
	for column in ["battery", "voltage", "channel_util", "tx_util", "uptime"]:
		if column in node_df.columns:
			node_df[column] = pd.to_numeric(node_df[column], errors="coerce")
	if "uptime" in node_df.columns:
		node_df["uptime_hours"] = node_df["uptime"].divide(3600)
	return node_df


def build_label(series: pd.Series, unit: str = "") -> str:
	if series.empty:
		return ""
	series = series.dropna()
	if series.empty:
		return ""
	dates = pd.to_datetime(np.asarray(series.index), errors="coerce")
	mask = ~pd.isna(dates)
	if not mask.any():
		return ""
	filtered_values = np.asarray(series)[mask]
	ser = pd.Series(filtered_values, index=pd.Index(dates[mask]))
	return recent_stats(
		ser,
		now=pd.Timestamp.now(timezone.utc).to_pydatetime(),
		unit=unit,
	)


def render_chart(df: pd.DataFrame, node_names: dict[str, str], config: dict) -> None:
	width = float(config.get("CHART_FIGSIZE_WIDTH", 14))
	height = float(config.get("CHART_FIGSIZE_HEIGHT", 12))
	fig, axes = plt.subplots(4, 1, sharex=True, figsize=(width, height))
	fig.suptitle("Meshtastic Telemetry", fontsize=16, fontweight="bold")

	colors_cfg = split_csv(config.get("CHART_COLORS_TELEMETRY"))
	palette = ensure_color_cycle(colors_cfg, len(node_names), DEFAULT_TELEMETRY_COLORS)

	metrics = [
		("battery", axes[0], "%", "Battery (%)"),
		("voltage", axes[1], "V", "Voltage (V)"),
		("channel_util", axes[2], "%", "Channel Utilisation (%)"),
		("tx_util", axes[3], "%", "TX Utilisation (%)"),
	]
	axes[3].set_xlabel("Timestamp")

	for color, (node_id, display_name) in zip(palette, node_names.items()):
		node_df = prepare_node_frame(df, node_id)
		if node_df.empty:
			continue
		time_index = node_df["timestamp"]
		plot_index = pd.to_datetime(np.asarray(time_index), errors="coerce")
		mask = ~pd.isna(plot_index)
		if not mask.any():
			continue
		plot_index = plot_index[mask]
		for metric, axis, unit, label in metrics:
			if metric not in node_df:
				continue
			series = pd.to_numeric(node_df[metric], errors="coerce")
			series_array = np.asarray(series)[mask]
			if series_array.size == 0:
				continue
			label_series = pd.Series(series_array, index=pd.Index(plot_index))
			stats_label = build_label(label_series, unit)
			label_text = f"{display_name} {stats_label}".strip()
			axis.plot(plot_index, series_array, label=label_text, color=color, linewidth=1.8)
			axis.set_ylabel(label)
			axis.grid(True, alpha=0.25)

	axes[-1].xaxis.set_major_formatter(mdates.DateFormatter("%m-%d %H:%M"))
	for axis in axes:
		axis.legend(loc="upper left", fontsize=8)

	plt.xticks(rotation=35, ha="right")
	plt.tight_layout(rect=[0, 0.03, 1, 0.97])
	fig.savefig(str(OUTPUT_FILE), dpi=144, bbox_inches="tight")
	plt.close(fig)


def main() -> int:
	args = parse_args()
	config = load_env_config()
	telemetry_csv = Path(config.get("TELEMETRY_CSV", "telemetry_log.csv"))
	nodes_csv = Path(config.get("NODES_CSV", "nodes_log.csv"))

	nodes = resolve_nodes(config, args)
	node_names = resolve_names(nodes, config, args, nodes_csv)
	signature = TelemetrySignature.build(telemetry_csv, nodes_csv, nodes)

	if should_skip(signature, args.force):
		print("Telemetry chart up to date; skipping regeneration.")
		return 0

	df = read_telemetry_dataframe(telemetry_csv)
	df = df.loc[df["status"].str.lower() == "success"]
	df = df.loc[df["address"].isin(nodes)]
	if df.empty:
		print("No telemetry data available for the requested nodes.")
		return 0

	render_chart(df, node_names, config)
	finalise_cache(signature, node_names)
	print(f"Telemetry chart saved to {OUTPUT_FILE}")
	return 0


if __name__ == "__main__":
	sys.exit(main())
