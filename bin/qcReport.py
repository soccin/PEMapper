#!/usr/bin/env python3
"""HTML QC report from the picard metrics PEMapper writes.

Run it through bin/qcReport.sh, which uses the plotly in bin/venv:

    qcReport.sh [-o REPORT.html] [-t TITLE] DIR [DIR ...]

Each DIR is a PEMapper output directory such as out___M. It is searched
at any depth for these files:

    <S>___AS.txt     CollectAlignmentSummaryMetrics; the PAIR row
    <S>___MD.txt     MarkDuplicates; one row, since LB is the sample
    <S>___INS.txt    CollectInsertSizeMetrics; metrics and histogram
    RUNSTATUS.txt    first line "PEMAP STATUS: OK|FAILED|RUNNING"

A sample is one directory. Its name comes from the metrics file names,
or from the directory name when the directory holds only RUNSTATUS.txt,
so a run that failed before picard ran still gets a row in the table.

The output is one HTML file with plotly.js embedded, so it opens
offline: a summary table, bar charts of reads, alignment, duplication
and median insert size, and the insert size distributions overlaid.
"""

import argparse
import html
import math
import os
import re
import subprocess
import sys
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path
from string import Template
from typing import Any, Callable

try:
    import plotly.graph_objects as go
    from plotly.offline import get_plotlyjs
    from plotly.subplots import make_subplots
except ImportError:
    sys.exit(
        f"FATAL ERROR: plotly is not installed for {sys.executable}\n"
        f"    install it with: "
        f"{Path(__file__).resolve().parent / 'venv/bin/pip'} install plotly"
    )

SDIR = Path(__file__).resolve().parent

METRIC_FILES = {"AS": "___AS.txt", "MD": "___MD.txt", "INS": "___INS.txt"}

#
# Colors are the dataviz reference palette, light mode. The categorical
# order is the validated one; do not reorder it. Slots 3-5 are under 3:1
# against the surface, which the summary table covers: every value
# plotted is also in it.
#
SURFACE = "#fcfcfb"
PAGE = "#f9f9f7"
INK_PRIMARY = "#0b0b0b"
INK_SECONDARY = "#52514e"
INK_MUTED = "#898781"
GRID = "#e1e0d9"
AXIS = "#c3c2b7"
SERIES = [
    "#2a78d6", "#eb6834", "#1baf7a", "#eda100",
    "#e87ba4", "#008300", "#6250d6", "#e34948",
]
FONT = 'system-ui, -apple-system, "Segoe UI", sans-serif'

# Height per sample in the horizontal bar charts. bargap 0.35 leaves
# each bar about 21px thick.
BAND_PX = 32
BARGAP = 0.35

PLOT_CONFIG = {
    "displaylogo": False,
    "responsive": True,
    "modeBarButtonsToRemove": ["lasso2d", "select2d"],
}


@dataclass
class Sample:
    """One PEMapper sample directory and the metrics read from it.

    Attributes:
        name: Sample name, from the metrics file names.
        directory: The directory the files were found in, as given.
        label: Name shown in the report; unique across all samples.
        status: First word after "PEMAP STATUS:" in RUNSTATUS.txt.
        reference: Reference FASTA name, from the picard command line.
        alignment: AlignmentSummaryMetrics row for the PAIR category.
        duplication: DuplicationMetrics row.
        insert: InsertSizeMetrics row for the dominant pair orientation.
        insert_hist: (insert size, percent of read pairs) points.
    """

    name: str
    directory: Path
    label: str = ""
    status: str = "missing"
    reference: str = ""
    alignment: dict[str, Any] = field(default_factory=dict)
    duplication: dict[str, Any] = field(default_factory=dict)
    insert: dict[str, Any] = field(default_factory=dict)
    insert_hist: list[tuple[float, float]] = field(default_factory=list)


def parse_value(text: str) -> Any:
    """Converts one picard field to int, float, str or None.

    Args:
        text: The field as it appears in the file.

    Returns:
        None for an empty field, else the narrowest of int, float or str
        that the text parses as.
    """
    if text == "":
        return None
    for cast in (int, float):
        try:
            return cast(text)
        except ValueError:
            pass
    return text


def read_picard(
    path: Path,
) -> tuple[list[dict[str, Any]], list[dict[str, Any]], str]:
    """Reads a picard metrics file.

    Args:
        path: The metrics file.

    Returns:
        A tuple (metrics, histogram, reference). metrics and histogram
        are lists of rows, each a dict keyed by column name; either is
        empty if the file has no such section. reference is the
        REFERENCE_SEQUENCE argument from the command line header, or ""
        if it is absent.
    """
    sections: dict[str, list[dict[str, Any]]] = {"METRICS": [], "HISTOGRAM": []}
    reference = ""
    current = None
    header: list[str] | None = None
    with path.open() as fh:
        for line in fh:
            line = line.rstrip("\n")
            if line.startswith("## METRICS CLASS"):
                current, header = "METRICS", None
            elif line.startswith("## HISTOGRAM"):
                current, header = "HISTOGRAM", None
            elif line.startswith("#"):
                match = re.search(r"REFERENCE_SEQUENCE=(\S+)", line)
                if match and not reference:
                    reference = match.group(1)
            elif not line.strip():
                current = None
            elif current is not None:
                fields = line.split("\t")
                if header is None:
                    header = fields
                else:
                    sections[current].append(
                        {k: parse_value(v) for k, v in zip(header, fields)}
                    )
    return sections["METRICS"], sections["HISTOGRAM"], reference


def read_status(path: Path) -> str:
    """Reads the verdict from a PEMapper RUNSTATUS.txt.

    Args:
        path: The RUNSTATUS.txt file.

    Returns:
        The word after "PEMAP STATUS:" on the first line (OK, FAILED or
        RUNNING), or "unreadable" if the line is not in that form.
    """
    with path.open() as fh:
        first = fh.readline()
    match = re.match(r"PEMAP STATUS:\s+(\S+)", first)
    return match.group(1) if match else "unreadable"


def reference_name(fasta: str) -> str:
    """Shortens a reference FASTA path to its assembly name.

    Args:
        fasta: Path to the FASTA, e.g. /x/mm10/mm10.fasta.

    Returns:
        The file name without its FASTA extension, e.g. mm10.
    """
    return re.sub(r"\.(fasta|fa|fna)(\.gz)?$", "", Path(fasta).name)


def pick_insert(
    rows: list[dict[str, Any]], hist: list[dict[str, Any]]
) -> tuple[dict[str, Any], list[tuple[float, float]]]:
    """Selects the dominant pair orientation from InsertSizeMetrics.

    picard writes one metrics row and one histogram column per pair
    orientation (FR, RF, TANDEM). The report uses the orientation with
    the most read pairs, which for a normal library is FR.

    Args:
        rows: InsertSizeMetrics rows.
        hist: Histogram rows, keyed insert_size and <level>.<orient>_count.

    Returns:
        A tuple (row, points). row is the metrics row for the dominant
        orientation, or {} if there are no rows. points are (insert
        size, percent of the histogram's read pairs), zero bins omitted.
    """
    if not rows:
        return {}, []
    row = max(rows, key=lambda r: num(r, "READ_PAIRS") or 0)
    suffix = f".{str(row.get('PAIR_ORIENTATION', 'fr')).lower()}_count"
    columns = [k for k in hist[0] if k.endswith(suffix)] if hist else []
    if not columns:
        return row, []
    points = [
        (h["insert_size"], h.get(columns[0]) or 0)
        for h in hist if h.get("insert_size") is not None
    ]
    total = sum(count for _, count in points)
    if not total:
        return row, []
    return row, [(x, 100 * count / total) for x, count in points if count]


def load_metrics(sample: Sample, kind: str, path: Path) -> None:
    """Reads one metrics file into a sample.

    Args:
        sample: The sample to fill in.
        kind: AS, MD or INS; a key of METRIC_FILES.
        path: The metrics file.
    """
    rows, hist, reference = read_picard(path)
    if reference and not sample.reference:
        sample.reference = reference_name(reference)
    if kind == "AS":
        by_category = {r.get("CATEGORY"): r for r in rows}
        sample.alignment = by_category.get("PAIR") or by_category.get(
            "UNPAIRED", {}
        )
    elif kind == "MD":
        sample.duplication = rows[0] if rows else {}
    else:
        sample.insert, sample.insert_hist = pick_insert(rows, hist)


def natural_key(text: str) -> list[Any]:
    """Sort key that orders embedded numbers numerically (S2 before S10).

    Args:
        text: The string to sort on.

    Returns:
        The string split into alternating text and int parts.
    """
    return [int(p) if p.isdigit() else p.lower() for p in re.split(r"(\d+)", text)]


def find_samples(dirs: list[Path]) -> list[Sample]:
    """Finds every PEMapper sample under the given directories.

    Args:
        dirs: Directories to search recursively.

    Returns:
        The samples, sorted by name, each with a unique label set.
        A directory reached twice (say, out___M and out___M/mouse_mm10
        both given) yields its samples once.
    """
    samples: dict[tuple[Path, str], Sample] = {}

    def get(directory: Path, name: str) -> Sample:
        key = (directory.resolve(), name)
        if key not in samples:
            samples[key] = Sample(name=name, directory=directory)
        return samples[key]

    for top in dirs:
        for kind, suffix in METRIC_FILES.items():
            for path in sorted(top.rglob("*" + suffix)):
                load_metrics(get(path.parent, path.name[: -len(suffix)]), kind, path)
        for path in sorted(top.rglob("RUNSTATUS.txt")):
            get(path.parent, path.parent.name).status = read_status(path)

    found = sorted(
        samples.values(), key=lambda s: (natural_key(s.name), str(s.directory))
    )
    assign_labels(found)
    return found


def assign_labels(samples: list[Sample]) -> None:
    """Gives each sample the shortest label that is unique.

    Tries the sample name, then genome/sample (the parent directory in
    the out___<TAG>/<GENOME>/<SAMPLE> layout), then the sample directory
    relative to the deepest directory common to all samples, which
    tells out___M/mouse_mm10/S1 from out___M__NoClip/mouse_mm10/S1.
    The same level is used for every sample, so labels stay consistent.

    Args:
        samples: Samples to label in place.
    """
    if not samples:
        return
    common = os.path.commonpath([s.directory.resolve() for s in samples])

    def relative(s: Sample) -> str:
        rel = os.path.relpath(s.directory.resolve(), common)
        return rel if Path(rel).name == s.name else f"{rel}/{s.name}"

    makers: list[Callable[[Sample], str]] = [
        lambda s: s.name,
        lambda s: f"{s.directory.parent.name}/{s.name}",
        relative,
    ]
    labels: list[str] = []
    for make in makers:
        labels = [make(s) for s in samples]
        if len(set(labels)) == len(labels):
            break
    for sample, label in zip(samples, labels):
        sample.label = label


def num(row: dict[str, Any], key: str) -> float | None:
    """Returns a numeric metric, or None if absent, non-numeric or NaN.

    Args:
        row: A metrics row.
        key: Column name.

    Returns:
        The value as a number, or None.
    """
    value = row.get(key)
    if isinstance(value, (int, float)) and not (
        isinstance(value, float) and math.isnan(value)
    ):
        return value
    return None


def pct(row: dict[str, Any], key: str) -> float | None:
    """Returns a picard fraction (0-1) as a percent, or None.

    Args:
        row: A metrics row.
        key: Column name.

    Returns:
        100 times the value, or None.
    """
    value = num(row, key)
    return None if value is None else 100 * value


def read_counts(sample: Sample) -> tuple[float, float, float] | None:
    """Splits a sample's reads into unique aligned, duplicate and unaligned.

    MarkDuplicates examines the primary aligned reads, so its examined
    count equals PF_READS_ALIGNED and the two files can be combined.

    Args:
        sample: The sample.

    Returns:
        (unique aligned, duplicate, unaligned) read counts, or None if
        any input is missing.
    """
    total = num(sample.alignment, "TOTAL_READS")
    aligned = num(sample.alignment, "PF_READS_ALIGNED")
    unpaired_dups = num(sample.duplication, "UNPAIRED_READ_DUPLICATES")
    pair_dups = num(sample.duplication, "READ_PAIR_DUPLICATES")
    if (
        total is None or aligned is None
        or unpaired_dups is None or pair_dups is None
    ):
        return None
    dups = unpaired_dups + 2 * pair_dups
    return aligned - dups, dups, total - aligned


def fmt_int(value: float) -> str:
    """Formats a count with thousands separators."""
    return f"{round(value):,}"


def fmt_dec(places: int) -> Callable[[float], str]:
    """Returns a formatter with a fixed number of decimal places."""
    return lambda value: f"{value:.{places}f}"


AS_SRC = "AlignmentSummaryMetrics, PAIR row"
MD_SRC = "DuplicationMetrics"
INS_SRC = "InsertSizeMetrics, dominant orientation"

# (header, source shown on hover, value getter, formatter)
COLUMNS: list[tuple[str, str, Callable[[Sample], Any], Callable[[float], str]]] = [
    ("Total reads", f"TOTAL_READS ({AS_SRC})",
     lambda s: num(s.alignment, "TOTAL_READS"), fmt_int),
    ("Aligned (%)", f"PCT_PF_READS_ALIGNED ({AS_SRC})",
     lambda s: pct(s.alignment, "PCT_PF_READS_ALIGNED"), fmt_dec(2)),
    ("In pairs (%)", f"PCT_READS_ALIGNED_IN_PAIRS ({AS_SRC})",
     lambda s: pct(s.alignment, "PCT_READS_ALIGNED_IN_PAIRS"), fmt_dec(2)),
    ("Duplication (%)", f"PERCENT_DUPLICATION ({MD_SRC})",
     lambda s: pct(s.duplication, "PERCENT_DUPLICATION"), fmt_dec(2)),
    ("Library size", f"ESTIMATED_LIBRARY_SIZE ({MD_SRC})",
     lambda s: num(s.duplication, "ESTIMATED_LIBRARY_SIZE"), fmt_int),
    ("Read length", f"MEAN_READ_LENGTH ({AS_SRC})",
     lambda s: num(s.alignment, "MEAN_READ_LENGTH"), fmt_dec(1)),
    ("Median insert", f"MEDIAN_INSERT_SIZE ({INS_SRC})",
     lambda s: num(s.insert, "MEDIAN_INSERT_SIZE"), fmt_int),
    ("Mean insert", f"MEAN_INSERT_SIZE ({INS_SRC})",
     lambda s: num(s.insert, "MEAN_INSERT_SIZE"), fmt_dec(1)),
    ("Mismatch (%)", f"PF_MISMATCH_RATE ({AS_SRC})",
     lambda s: pct(s.alignment, "PF_MISMATCH_RATE"), fmt_dec(2)),
    ("Chimeras (%)", f"PCT_CHIMERAS ({AS_SRC})",
     lambda s: pct(s.alignment, "PCT_CHIMERAS"), fmt_dec(2)),
    ("Adapter (%)", f"PCT_ADAPTER ({AS_SRC})",
     lambda s: pct(s.alignment, "PCT_ADAPTER"), fmt_dec(3)),
]


def summary_table(samples: list[Sample]) -> str:
    """Builds the summary table, one row per sample.

    Args:
        samples: The samples, in display order.

    Returns:
        An HTML table. Numeric cells carry the raw value in data-value
        for the sort script; a missing value is an empty data-value.
    """
    esc = html.escape
    head = [
        '<th class="text">Sample</th>',
        '<th class="text" title="REFERENCE_SEQUENCE in the picard command line">'
        "Reference</th>",
        '<th class="text" title="First line of RUNSTATUS.txt">Run status</th>',
    ]
    head += [f'<th title="{esc(src)}">{esc(name)}</th>' for name, src, _, _ in COLUMNS]
    rows = []
    for s in samples:
        cells = [
            f'<td class="text" title="{esc(str(s.directory))}">{esc(s.label)}</td>',
            f'<td class="text">{esc(s.reference)}</td>',
            f'<td class="text">{esc(s.status)}</td>',
        ]
        for _, _, get, fmt in COLUMNS:
            value = get(s)
            if value is None:
                cells.append('<td class="na" data-value="">&ndash;</td>')
            else:
                cells.append(f'<td data-value="{value:.10g}">{fmt(value)}</td>')
        rows.append("<tr>" + "".join(cells) + "</tr>")
    return (
        '<table class="sortable">\n<thead><tr>' + "".join(head) + "</tr></thead>\n"
        "<tbody>\n" + "\n".join(rows) + "\n</tbody>\n</table>"
    )


def base_layout(height: int) -> dict[str, Any]:
    """Layout settings shared by every figure.

    Args:
        height: Figure height in px, margins included.

    Returns:
        Keyword arguments for Figure.update_layout.
    """
    return dict(
        template="none",
        height=height,
        margin=dict(l=10, r=20, t=40, b=50),
        paper_bgcolor=SURFACE,
        plot_bgcolor=SURFACE,
        font=dict(family=FONT, size=12, color=INK_SECONDARY),
        hoverlabel=dict(font=dict(family=FONT)),
        showlegend=False,
    )


VALUE_AXIS = dict(
    showgrid=True, gridcolor=GRID, gridwidth=1, zeroline=False,
    showline=True, linecolor=AXIS, linewidth=1, ticks="", automargin=True,
    tickfont=dict(color=INK_MUTED), title_font=dict(color=INK_SECONDARY),
)
SAMPLE_AXIS = dict(
    showgrid=False, showline=True, linecolor=AXIS, linewidth=1, ticks="",
    autorange="reversed", automargin=True, tickfont=dict(color=INK_SECONDARY),
)


def bar_height(n_samples: int, extra: int) -> int:
    """Figure height for horizontal bars, one band per sample.

    Args:
        n_samples: Number of bars per panel.
        extra: Space for margins, legend and axis titles, in px.

    Returns:
        Height in px.
    """
    return max(BAND_PX * n_samples + extra, 200)


def reads_figure(samples: list[Sample]) -> go.Figure | None:
    """Stacked bars: unique aligned, duplicate and unaligned reads.

    Args:
        samples: The samples, in display order.

    Returns:
        The figure, or None if no sample has both AS and MD metrics.
    """
    counts = [read_counts(s) for s in samples]
    if not any(counts):
        return None
    labels = [s.label for s in samples]
    fig = go.Figure()
    for i, name in enumerate(["Unique aligned", "Duplicate", "Unaligned"]):
        values = [c[i] if c else None for c in counts]
        share = [100 * c[i] / sum(c) if c and sum(c) else None for c in counts]
        fig.add_trace(go.Bar(
            name=name, y=labels, x=values, orientation="h",
            marker=dict(color=SERIES[i], line=dict(color=SURFACE, width=2)),
            customdata=share,
            hovertemplate=(
                f"%{{y}}<br>{name}: %{{x:,}} reads "
                "(%{customdata:.1f}%)<extra></extra>"
            ),
        ))
    fig.update_layout(
        base_layout(bar_height(len(samples), 110)),
        barmode="stack", bargap=BARGAP, barcornerradius=4,
        showlegend=True,
        legend=dict(
            orientation="h", x=0, y=1, yanchor="bottom", traceorder="normal",
            font=dict(color=INK_SECONDARY),
        ),
    )
    fig.update_xaxes(VALUE_AXIS, tickformat="~s", title_text="Reads")
    fig.update_yaxes(SAMPLE_AXIS)
    return fig


def panels_figure(samples: list[Sample]) -> go.Figure:
    """Three bar panels sharing the sample axis.

    The panels are % aligned, % duplication and median insert size.
    Each is one series, so every bar takes series slot 1 and there is no
    legend; the panel title names the metric.

    Args:
        samples: The samples, in display order.

    Returns:
        The figure.
    """
    panels: list[tuple[str, Callable[[Sample], float | None], str, float | None]] = [
        ("Aligned (%)", lambda s: pct(s.alignment, "PCT_PF_READS_ALIGNED"),
         "{:.1f}%", 100),
        ("Duplication (%)", lambda s: pct(s.duplication, "PERCENT_DUPLICATION"),
         "{:.1f}%", None),
        ("Median insert size (bp)", lambda s: num(s.insert, "MEDIAN_INSERT_SIZE"),
         "{:.0f}", None),
    ]
    labels = [s.label for s in samples]
    fig = make_subplots(
        rows=1, cols=len(panels), shared_yaxes=True, horizontal_spacing=0.04,
        subplot_titles=[title for title, _, _, _ in panels],
    )
    for col, (title, get, fmt, top) in enumerate(panels, start=1):
        values = [get(s) for s in samples]
        present = [v for v in values if v is not None]
        upper = top if top is not None else max(present, default=1) * 1.15 or 1
        fig.add_trace(go.Bar(
            y=labels, x=values, orientation="h",
            marker=dict(color=SERIES[0]),
            text=[fmt.format(v) if v is not None else "" for v in values],
            textposition="auto", insidetextanchor="end", cliponaxis=False,
            insidetextfont=dict(color="#ffffff", size=11),
            outsidetextfont=dict(color=INK_SECONDARY, size=11),
            hovertemplate=f"%{{y}}<br>{title}: %{{text}}<extra></extra>",
        ), row=1, col=col)
        fig.update_xaxes(VALUE_AXIS, range=[0, upper], row=1, col=col)
    fig.update_layout(
        base_layout(bar_height(len(samples), 90)),
        bargap=BARGAP, barcornerradius=4,
    )
    fig.update_yaxes(SAMPLE_AXIS)
    fig.update_annotations(font=dict(color=INK_PRIMARY, size=13))
    return fig


def insert_figure(samples: list[Sample]) -> go.Figure | None:
    """Insert size distributions, one line per sample, on one axis.

    Up to 8 samples each get a categorical slot, in sample order. Past
    8 there are not enough distinct colors, so every line takes slot 1;
    hover names a line, and a double click on a legend entry shows that
    sample alone.

    Args:
        samples: The samples, in display order.

    Returns:
        The figure, or None if no sample has a histogram.
    """
    drawn = [s for s in samples if s.insert_hist]
    if not drawn:
        return None
    many = len(drawn) > len(SERIES)
    fig = go.Figure()
    for i, s in enumerate(drawn):
        x, y = zip(*s.insert_hist)
        fig.add_trace(go.Scatter(
            x=x, y=y, mode="lines", name=s.label,
            line=dict(color=SERIES[0] if many else SERIES[i],
                      width=1.5 if many else 2),
            opacity=0.5 if many else 1,
            hovertemplate=(
                "%{fullData.name}<br>%{x} bp: %{y:.3f}%<extra></extra>"
                if many else "%{fullData.name}: %{y:.3f}%<extra></extra>"
            ),
        ))
    fig.update_layout(
        base_layout(460),
        showlegend=True,
        legend=dict(font=dict(color=INK_SECONDARY)),
        hovermode="closest" if many else "x unified",
        # Top left: the plotly modebar takes the top right on hover.
        updatemenus=[dict(
            type="buttons", direction="right", showactive=True,
            x=0, xanchor="left", y=1.02, yanchor="bottom",
            bgcolor=SURFACE, bordercolor=AXIS, font=dict(color=INK_SECONDARY),
            buttons=[
                dict(label="Linear", method="relayout",
                     args=[{"yaxis.type": "linear"}]),
                dict(label="Log", method="relayout",
                     args=[{"yaxis.type": "log"}]),
            ],
        )],
    )
    fig.update_xaxes(VALUE_AXIS, title_text="Insert size (bp)", rangemode="tozero")
    # exponentformat none: the log ticks read 0.0001, not 100µ.
    fig.update_yaxes(
        VALUE_AXIS, title_text="Read pairs (%)", rangemode="tozero",
        exponentformat="none",
    )
    return fig


def figure_html(fig: go.Figure | None, missing: str) -> str:
    """Renders a figure as an HTML fragment, without plotly.js.

    Args:
        fig: The figure, or None if there was nothing to plot.
        missing: Text shown in place of a None figure.

    Returns:
        The HTML fragment.
    """
    if fig is None:
        return f'<p class="note">{html.escape(missing)}</p>'
    return fig.to_html(full_html=False, include_plotlyjs=False, config=PLOT_CONFIG)


def pemapper_version() -> str:
    """The checkout's version, as pipe.sh stamps it into the BAM @PG.

    Returns:
        git describe output, or "unknown" if git fails.
    """
    repo = SDIR.parent
    try:
        result = subprocess.run(
            ["git", f"--git-dir={repo / '.git'}", f"--work-tree={repo}",
             "describe", "--always", "--long"],
            capture_output=True, text=True, check=True,
        )
    except (OSError, subprocess.CalledProcessError):
        return "unknown"
    return result.stdout.strip() or "unknown"


PAGE_TEMPLATE = Template("""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>$title</title>
<script type="text/javascript">$plotlyjs</script>
<style>
:root { color-scheme: light; }
body {
  margin: 0; background: $page; color: $ink_primary;
  font-family: $font; font-size: 14px; line-height: 1.45;
}
main { max-width: 1400px; margin: 0 auto; padding: 24px; }
h1 { font-size: 22px; font-weight: 600; margin: 0 0 4px; }
h2 { font-size: 16px; font-weight: 600; margin: 0 0 4px; }
.meta, .note { color: $ink_secondary; margin: 0 0 12px; }
.card {
  background: $surface; border: 1px solid rgba(11, 11, 11, 0.10);
  border-radius: 8px; padding: 16px 20px; margin: 0 0 16px;
}
.dirs { margin: 0 0 16px; padding-left: 18px; color: $ink_secondary; }
.table-wrap { overflow-x: auto; }
table { border-collapse: collapse; width: 100%; font-variant-numeric: tabular-nums; }
th, td {
  padding: 6px 8px; text-align: right; white-space: nowrap;
  border-bottom: 1px solid $grid;
}
th {
  color: $ink_secondary; font-weight: 600; cursor: pointer; user-select: none;
  white-space: normal; vertical-align: bottom;
}
th.text, td.text { text-align: left; }
th[data-sort="asc"]::after { content: " \\25B2"; font-size: 10px; }
th[data-sort="desc"]::after { content: " \\25BC"; font-size: 10px; }
tbody tr:hover { background: #f0efec; }
td.na { color: $ink_muted; }
details { color: $ink_secondary; }
details table td { text-align: left; }
@media print { .card { break-inside: avoid; } }
</style>
</head>
<body>
<main>
<h1>$title</h1>
<p class="meta">$meta</p>
<ul class="dirs">$dirs</ul>

<section class="card">
<h2>Summary</h2>
<p class="note">One row per sample. Click a column header to sort;
hover over it for the picard field it comes from.</p>
<div class="table-wrap">
$table
</div>
</section>

<section class="card">
<h2>Reads</h2>
<p class="note">Unique aligned and duplicate reads are from MarkDuplicates;
unaligned is TOTAL_READS minus PF_READS_ALIGNED from the alignment
summary.</p>
$reads
</section>

<section class="card">
<h2>Alignment, duplication and insert size</h2>
$panels
</section>

<section class="card">
<h2>Insert size distribution</h2>
<p class="note">Percent of read pairs at each insert size, for each
sample's dominant pair orientation. Use Log to see the tails. Click a
legend entry to hide a sample; double click to show it alone.</p>
$insert
</section>

<details class="card">
<summary>Sample directories</summary>
<table><tbody>
$sources
</tbody></table>
</details>
</main>
<script>
document.querySelectorAll("table.sortable").forEach(function (table) {
  var heads = table.tHead.rows[0].cells;
  Array.prototype.forEach.call(heads, function (th, col) {
    th.addEventListener("click", function () {
      var asc = th.dataset.sort !== "asc";
      Array.prototype.forEach.call(heads, function (h) { delete h.dataset.sort; });
      th.dataset.sort = asc ? "asc" : "desc";
      var body = table.tBodies[0];
      var rows = Array.prototype.slice.call(body.rows);
      function key(row) {
        var cell = row.cells[col];
        return "value" in cell.dataset ? cell.dataset.value : cell.textContent;
      }
      rows.sort(function (a, b) {
        var x = key(a), y = key(b);
        if (x === "" || y === "") { return (x === "") - (y === ""); }
        var nx = Number(x), ny = Number(y);
        var cmp = (isNaN(nx) || isNaN(ny))
          ? x.localeCompare(y, undefined, {numeric: true}) : nx - ny;
        return asc ? cmp : -cmp;
      });
      rows.forEach(function (row) { body.appendChild(row); });
    });
  });
});
</script>
</body>
</html>
""")


def render_page(title: str, dirs: list[Path], samples: list[Sample]) -> str:
    """Assembles the complete report.

    Args:
        title: Page title and heading.
        dirs: The directories searched, as given.
        samples: The samples, in display order.

    Returns:
        The HTML document.
    """
    esc = html.escape
    statuses: dict[str, int] = {}
    for s in samples:
        statuses[s.status] = statuses.get(s.status, 0) + 1
    status_text = ", ".join(f"{n} {status}" for status, n in sorted(statuses.items()))
    meta = (
        f"Generated {datetime.now():%Y-%m-%d %H:%M} by PEMapper "
        f"{esc(pemapper_version())} &middot; {len(samples)} samples "
        f"&middot; run status: {esc(status_text)}"
    )
    return PAGE_TEMPLATE.substitute(
        title=esc(title),
        plotlyjs=get_plotlyjs(),
        page=PAGE, surface=SURFACE, grid=GRID, font=FONT,
        ink_primary=INK_PRIMARY, ink_secondary=INK_SECONDARY, ink_muted=INK_MUTED,
        meta=meta,
        dirs="".join(f"<li>{esc(str(d.resolve()))}</li>" for d in dirs),
        table=summary_table(samples),
        reads=figure_html(
            reads_figure(samples),
            "No sample has both ___AS.txt and ___MD.txt.",
        ),
        panels=figure_html(panels_figure(samples), ""),
        insert=figure_html(
            insert_figure(samples), "No ___INS.txt histograms found."
        ),
        sources="\n".join(
            f"<tr><td>{esc(s.label)}</td>"
            f"<td>{esc(str(s.directory.resolve()))}</td></tr>"
            for s in samples
        ),
    )


def parse_args(argv: list[str] | None) -> argparse.Namespace:
    """Parses the command line.

    Args:
        argv: Arguments without the program name; None for sys.argv.

    Returns:
        The parsed arguments.
    """
    parser = argparse.ArgumentParser(
        prog="qcReport.sh",
        description="HTML QC report from PEMapper picard metrics.",
    )
    parser.add_argument(
        "dirs", nargs="+", type=Path, metavar="DIR",
        help="PEMapper output directory, e.g. out___M; searched recursively",
    )
    parser.add_argument(
        "-o", "--output", type=Path, default=Path("qcReport.html"),
        help="HTML file to write (default: qcReport.html)",
    )
    parser.add_argument(
        "-t", "--title", default="PEMapper QC report",
        help="report title (default: %(default)s)",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    """Finds the samples, writes the report, and reports what it did.

    Args:
        argv: Arguments without the program name; None for sys.argv.

    Returns:
        Exit status: 0 on success, 1 on any error.
    """
    args = parse_args(argv)
    bad = [d for d in args.dirs if not d.is_dir()]
    if bad:
        for d in bad:
            print(f"FATAL ERROR: not a directory [{d}]", file=sys.stderr)
        return 1
    if not args.output.resolve().parent.is_dir():
        print(f"FATAL ERROR: no directory for output [{args.output}]", file=sys.stderr)
        return 1

    samples = find_samples(args.dirs)
    if not samples:
        print(
            "FATAL ERROR: no PEMapper metrics or RUNSTATUS.txt found under "
            + " ".join(str(d) for d in args.dirs),
            file=sys.stderr,
        )
        return 1

    for s in samples:
        absent = [
            suffix for suffix, row in (
                ("___AS.txt", s.alignment),
                ("___MD.txt", s.duplication),
                ("___INS.txt", s.insert),
            ) if not row
        ]
        if s.status == "missing":
            absent.append("RUNSTATUS.txt")
        if absent:
            print(f"WARNING: {s.label}: no {', '.join(absent)}", file=sys.stderr)

    args.output.write_text(render_page(args.title, args.dirs, samples))
    print(f"qcReport: {len(samples)} samples -> {args.output}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
