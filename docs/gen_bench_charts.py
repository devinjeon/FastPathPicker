#!/usr/bin/env python3
"""Generate benchmark charts for docs/benchmarks.md and README."""

import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import numpy as np
import os

OUT_DIR = os.path.dirname(__file__)

RUST = '#E4572E'
PYTHON = '#3776AB'

plt.rcParams.update({
    'font.family': 'sans-serif',
    'font.size': 12,
    'axes.spines.top': False,
    'axes.spines.right': False,
    'figure.facecolor': 'white',
})


def add_speedup_labels(ax, x, rust, python):
    for i in range(len(x)):
        speedup = python[i] / rust[i]
        top_y = python[i] + (ax.get_ylim()[1] * 0.02)
        ax.text(x[i], top_y, f'{speedup:.1f}x', ha='center', va='bottom',
                fontsize=9, fontweight='bold', color='#333333')


def add_bar_values(ax, bars, color):
    for bar in bars:
        h = bar.get_height()
        label = f'{int(h)}' if h < 1000 else f'{h/1000:.1f}s'
        ax.text(bar.get_x() + bar.get_width()/2, h + (ax.get_ylim()[1] * 0.01),
                label, ha='center', va='bottom', fontsize=8, color=color)


def chart_readme():
    """Single chart for README: real-world + synthetic."""
    labels = ['git diff\n14 files', 'git diff\ncolor', 'file list\n44 files',
              'long diff\n480 lines', 'synth\n1K lines', 'synth\n5K lines']
    rust =   [16,  17,  10,  16,  22,   86]
    python = [75,  76,  75,  84,  102,  256]

    x = np.arange(len(labels))
    w = 0.33

    fig, ax = plt.subplots(figsize=(10, 4.5))
    bars_r = ax.bar(x - w/2, rust, w, label='fpp2 (Rust)', color=RUST, zorder=3)
    bars_p = ax.bar(x + w/2, python, w, label='fpp (Python)', color=PYTHON, zorder=3)

    ax.set_ylabel('Time (ms) -- lower is better')
    ax.set_title('End-to-end Performance (non-interactive mode)', fontweight='bold', pad=12)
    ax.set_xticks(x)
    ax.set_xticklabels(labels, fontsize=10)
    ax.legend(frameon=False, fontsize=11)
    ax.set_ylim(0, 310)
    ax.grid(axis='y', alpha=0.3, zorder=0)
    add_speedup_labels(ax, x, rust, python)
    add_bar_values(ax, bars_r, RUST)
    add_bar_values(ax, bars_p, PYTHON)

    plt.tight_layout()
    fig.savefig(os.path.join(OUT_DIR, 'bench.png'), dpi=150)
    plt.close(fig)
    print('  bench.png')


def chart_realworld():
    """Bar chart: real-world inputs detail."""
    labels = ['git diff\n(14 files)', 'git diff\ncolor (19)', 'tons of\nfiles (44)',
              'git long\ndiff (480L)', 'git long\ndiff color']
    rust =   [16, 17, 10, 16, 17]
    python = [75, 76, 75, 84, 84]

    x = np.arange(len(labels))
    w = 0.35

    fig, ax = plt.subplots(figsize=(9, 4.5))
    bars_r = ax.bar(x - w/2, rust, w, label='fpp2 (Rust)', color=RUST, zorder=3)
    bars_p = ax.bar(x + w/2, python, w, label='fpp (Python)', color=PYTHON, zorder=3)

    ax.set_ylabel('Time (ms)')
    ax.set_title('Real-world Inputs', fontweight='bold', pad=12)
    ax.set_xticks(x)
    ax.set_xticklabels(labels, fontsize=9)
    ax.legend(frameon=False)
    ax.set_ylim(0, 110)
    ax.grid(axis='y', alpha=0.3, zorder=0)
    add_speedup_labels(ax, x, rust, python)
    add_bar_values(ax, bars_r, RUST)
    add_bar_values(ax, bars_p, PYTHON)

    plt.tight_layout()
    fig.savefig(os.path.join(OUT_DIR, 'bench_realworld.png'), dpi=150)
    plt.close(fig)
    print('  bench_realworld.png')


def chart_scaling():
    """Line chart: scaling with input size."""
    sizes =        [100,  500,  1000, 5000, 10000]
    rust_match =   [15,   18,   22,   86,   236]
    python_match = [68,   84,   102,  256,  438]
    rust_nomatch = [10,   11,   11,   18,   25]
    python_nomatch=[75,   86,   101,  217,  355]

    labels = ['100', '500', '1K', '5K', '10K']

    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(12, 5))

    # Left: regex match
    ax1.plot(sizes, rust_match, 'o-', color=RUST, label='fpp2 (Rust)', linewidth=2, markersize=5)
    ax1.plot(sizes, python_match, 's-', color=PYTHON, label='fpp (Python)', linewidth=2, markersize=5)
    ax1.set_xlabel('Input lines')
    ax1.set_ylabel('Time (ms)')
    ax1.set_title('Regex Match (-nfc)', fontweight='bold')
    ax1.legend(frameon=False, loc='upper left')
    ax1.grid(alpha=0.3)
    ax1.set_xticks(sizes)
    ax1.set_xticklabels(labels, fontsize=9)
    # Custom y ticks in readable format
    ax1.set_yticks([0, 100, 200, 300, 400, 500])
    ax1.set_yticklabels(['0', '100ms', '200ms', '300ms', '400ms', '500ms'])

    # Right: no-match
    ax2.plot(sizes, rust_nomatch, 'o-', color=RUST, label='fpp2 (Rust)', linewidth=2, markersize=5)
    ax2.plot(sizes, python_nomatch, 's-', color=PYTHON, label='fpp (Python)', linewidth=2, markersize=5)
    ax2.set_xlabel('Input lines')
    ax2.set_ylabel('Time (ms)')
    ax2.set_title('No-match (plain text)', fontweight='bold')
    ax2.legend(frameon=False, loc='upper left')
    ax2.grid(alpha=0.3)
    ax2.set_xticks(sizes)
    ax2.set_xticklabels(labels, fontsize=9)
    ax2.set_yticks([0, 100, 200, 300, 400])
    ax2.set_yticklabels(['0', '100ms', '200ms', '300ms', '400ms'])

    plt.tight_layout()
    fig.savefig(os.path.join(OUT_DIR, 'bench_scaling.png'), dpi=150)
    plt.close(fig)
    print('  bench_scaling.png')


def chart_realfiles():
    """Bar chart: real files with validation."""
    labels = ['100', '500', '1K', '5K']
    rust =   [14,   23,   37,   161]
    python = [109,  240,  414,  1766]

    x = np.arange(len(labels))
    w = 0.35

    fig, ax = plt.subplots(figsize=(7, 4.5))
    bars_r = ax.bar(x - w/2, rust, w, label='fpp2 (Rust)', color=RUST, zorder=3)
    bars_p = ax.bar(x + w/2, python, w, label='fpp (Python)', color=PYTHON, zorder=3)

    ax.set_ylabel('Time (ms)')
    ax.set_xlabel('Input lines')
    ax.set_title('Real Files with Validation (default mode)', fontweight='bold', pad=12)
    ax.set_xticks(x)
    ax.set_xticklabels(labels)
    ax.legend(frameon=False)
    ax.grid(axis='y', alpha=0.3, zorder=0)
    ax.set_yticks([0, 500, 1000, 1500, 2000])
    ax.set_yticklabels(['0', '500ms', '1s', '1.5s', '2s'])
    add_speedup_labels(ax, x, rust, python)
    add_bar_values(ax, bars_r, RUST)
    add_bar_values(ax, bars_p, PYTHON)

    plt.tight_layout()
    fig.savefig(os.path.join(OUT_DIR, 'bench_realfiles.png'), dpi=150)
    plt.close(fig)
    print('  bench_realfiles.png')


def chart_memory():
    """Bar chart: memory comparison."""
    labels = ['100', '1K', '10K', '50K']
    rust =   [7, 7, 18, 76]
    python = [23, 29, 74, 263]

    x = np.arange(len(labels))
    w = 0.35

    fig, ax = plt.subplots(figsize=(7, 4.5))
    bars_r = ax.bar(x - w/2, rust, w, label='fpp2 (Rust)', color=RUST, zorder=3)
    bars_p = ax.bar(x + w/2, python, w, label='fpp (Python)', color=PYTHON, zorder=3)

    ax.set_ylabel('Peak RSS (MB)')
    ax.set_xlabel('Input lines')
    ax.set_title('Memory Usage', fontweight='bold', pad=12)
    ax.set_xticks(x)
    ax.set_xticklabels(labels)
    ax.legend(frameon=False)
    ax.grid(axis='y', alpha=0.3, zorder=0)

    for i in range(len(labels)):
        ratio = python[i] / rust[i]
        top_y = python[i] + 5
        ax.text(x[i], top_y, f'{ratio:.1f}x', ha='center', va='bottom',
                fontsize=9, fontweight='bold', color='#333333')

    add_bar_values(ax, bars_r, RUST)
    add_bar_values(ax, bars_p, PYTHON)

    plt.tight_layout()
    fig.savefig(os.path.join(OUT_DIR, 'bench_memory.png'), dpi=150)
    plt.close(fig)
    print('  bench_memory.png')


if __name__ == '__main__':
    print('Generating charts...')
    chart_readme()
    chart_realworld()
    chart_scaling()
    chart_realfiles()
    chart_memory()
    print('Done.')
