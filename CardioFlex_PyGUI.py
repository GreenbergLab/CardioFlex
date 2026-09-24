"""
CardioFlex - Python/PyQt5 GUI

A faithful re-implementation of CardioFlex.mlapp (Greenberg Lab) for
analyzing tissue-mechanics stretch protocols (EHT force/length recordings).

Run with:
    python CardioFlex_PyGUI.py

Requires: PyQt5, matplotlib, numpy, scipy, pandas, openpyxl
"""
from __future__ import annotations

import math
import os
import sys
import traceback
from typing import Optional

import numpy as np
import pandas as pd
from matplotlib.lines import Line2D
from PyQt5.QtCore import Qt
from PyQt5.QtWidgets import (
    QApplication, QMainWindow, QWidget, QTabWidget, QVBoxLayout, QHBoxLayout,
    QGridLayout, QPushButton, QLabel, QListWidget, QListWidgetItem, QSpinBox,
    QLineEdit, QFileDialog, QMessageBox, QDialog, QDialogButtonBox, QFormLayout,
    QInputDialog, QGroupBox, QSizePolicy, QFrame, QButtonGroup,
)
from matplotlib.backends.backend_qt5agg import FigureCanvasQTAgg as FigureCanvas
from matplotlib.backends.backend_qt5agg import NavigationToolbar2QT as NavigationToolbar
from matplotlib.figure import Figure

import CardioFlex_Core as core

APP_TITLE = "CardioFlex (Python)"

# Fixed colors used for the 6 contraction/relaxation kinetics markers, kept
# consistent between the scatter points on Figure 4 and the color key next
# to them (matches core.StretchResult.markers_ms order: c50,c75,c90,r50,r75,r90)
KINETIC_MARKER_COLORS = ["#1f77b4", "#ff7f0e", "#2ca02c", "#d62728", "#9467bd", "#8c564b"]
KINETIC_LABELS = ["Contraction 50%", "Contraction 75%", "Contraction 90%",
                   "Relaxation 50%", "Relaxation 75%", "Relaxation 90%"]

GROUP_MARKERS = {1: ("*", "b"), 2: ("+", "g"), 3: ("x", "m")}


# ==========================================================================
# Reusable plot window: ALL figures live as tabs in ONE persistent window
# (replicating MATLAB's persistent figure(n) windows, but consolidated so
# the user isn't juggling ten separate pop-out dialogs).
# ==========================================================================

class FigureTabWindow(QDialog):
    """A single non-modal window holding every analysis figure as a tab.
    Figures are added lazily (on first request) and reused thereafter,
    matching MATLAB's figure(n) reuse-by-number behavior."""

    def __init__(self, parent=None):
        super().__init__(parent)
        self.setWindowTitle("CardioFlex Figures")
        self.setModal(False)
        self.resize(1150, 900)
        layout = QVBoxLayout(self)
        self.tabs = QTabWidget()
        layout.addWidget(self.tabs)

        self.figures: dict[int, Figure] = {}
        self.canvases: dict[int, FigureCanvas] = {}
        self.axes_map: dict[int, object] = {}
        self.tab_index: dict[int, int] = {}

    def get_or_create(self, num: int, title: str, nrows: int = 1, ncols: int = 1,
                       figsize=(9, 7), supxlabel: Optional[str] = None,
                       supylabel: Optional[str] = None):
        if num not in self.figures:
            fig = Figure(figsize=figsize, constrained_layout=True)
            canvas = FigureCanvas(fig)
            container = QWidget()
            vlayout = QVBoxLayout(container)
            vlayout.setContentsMargins(2, 2, 2, 2)
            toolbar = NavigationToolbar(canvas, container)
            vlayout.addWidget(toolbar)
            vlayout.addWidget(canvas)
            idx = self.tabs.addTab(container, f"{num}. {title}")

            if nrows * ncols > 1:
                axes = fig.subplots(nrows, ncols)
            else:
                axes = fig.add_subplot(111)
            if supxlabel:
                fig.supxlabel(supxlabel, fontsize=10)
            if supylabel:
                fig.supylabel(supylabel, fontsize=10)

            self.figures[num] = fig
            self.canvases[num] = canvas
            self.axes_map[num] = axes
            self.tab_index[num] = idx

    def ax(self, num: int, idx: Optional[int] = None):
        axes = self.axes_map[num]
        if idx is None:
            return axes
        flat = np.atleast_1d(axes).ravel()
        return flat[idx - 1]

    def clear_all(self, num: int):
        for a in np.atleast_1d(self.axes_map[num]).ravel():
            a.clear()

    def redraw(self, num: int, switch_tab: bool = True):
        self.canvases[num].draw_idle()
        if switch_tab:
            self.tabs.setCurrentIndex(self.tab_index[num])
        self.show()
        self.raise_()
        self.activateWindow()

    def reset(self):
        self.tabs.clear()
        self.figures = {}
        self.canvases = {}
        self.axes_map = {}
        self.tab_index = {}


class FigureHandle:
    """Lightweight per-figure handle into the shared FigureTabWindow, so
    call sites can keep using win.ax(...), win.figure, win.redraw() exactly
    as if each figure still had its own window."""

    def __init__(self, container: FigureTabWindow, num: int):
        self._container = container
        self.num = num

    @property
    def figure(self) -> Figure:
        return self._container.figures[self.num]

    def ax(self, idx: Optional[int] = None):
        return self._container.ax(self.num, idx)

    def clear_all(self):
        self._container.clear_all(self.num)

    def redraw(self, switch_tab: bool = True):
        self._container.redraw(self.num, switch_tab=switch_tab)


class PlotWindowManager:
    def __init__(self, parent):
        self.container = FigureTabWindow(parent)
        self.handles: dict[int, FigureHandle] = {}

    def get(self, num: int, title: str, nrows: int = 1, ncols: int = 1,
            figsize=(9, 7), supxlabel: Optional[str] = None,
            supylabel: Optional[str] = None) -> FigureHandle:
        if num not in self.handles:
            self.container.get_or_create(num, title, nrows, ncols, figsize=figsize,
                                          supxlabel=supxlabel, supylabel=supylabel)
            self.handles[num] = FigureHandle(self.container, num)
        return self.handles[num]

    def close_all(self):
        self.container.reset()
        self.handles = {}

    @property
    def windows(self) -> dict[int, FigureHandle]:
        """Back-compat alias used by on_save_data_and_figures, which just
        needs each handle's .figure to export."""
        return self.handles


# ==========================================================================
# Small dialogs (replace MATLAB inputdlg calls)
# ==========================================================================

class PeakSelectionDialog(QDialog):
    """Equivalent of the MATLAB inputdlg that asks the user to enter/confirm
    which labeled stimulus peaks to use for beat analysis. Defaults to the
    most recent N peaks, exactly like the MATLAB app."""

    def __init__(self, defaults: list[int], n_labels: int, parent=None):
        super().__init__(parent)
        self.setWindowTitle("Choose peaks:")
        layout = QVBoxLayout(self)
        info = QLabel(f"Valid peak numbers: 1-{n_labels}. "
                       f"Defaults are the most recent {len(defaults)} beats.")
        info.setWordWrap(True)
        layout.addWidget(info)
        form = QFormLayout()
        self.fields: list[QLineEdit] = []
        for k, d in enumerate(defaults, start=1):
            le = QLineEdit(str(d))
            form.addRow(f"Enter Peak {k}", le)
            self.fields.append(le)
        layout.addLayout(form)
        btns = QDialogButtonBox(QDialogButtonBox.Ok | QDialogButtonBox.Cancel)
        btns.accepted.connect(self.accept)
        btns.rejected.connect(self.reject)
        layout.addWidget(btns)
        self.n_labels = n_labels

    def get_values(self) -> Optional[list[int]]:
        vals = []
        for f in self.fields:
            try:
                v = int(round(float(f.text())))
            except ValueError:
                return None
            if not (1 <= v <= self.n_labels):
                return None
            vals.append(v)
        return vals


class ManualTriggerDialog(QDialog):
    """Equivalent of ManuallyAssignStretchTimepointsMenuSelected.

    Each field is an absolute raw file line number (including the header),
    matching "Line# where stretching starts/ends" in the Data Range menu.
    The MATLAB app always shows the same hard-coded suggested values here
    (170316, 230316, ..., 680316) regardless of anything entered previously
    -- it doesn't try to reconstruct an absolute line number from
    app.triggerpts, which by the time it's stored has already been
    converted to a window-relative sample offset. This dialog matches that:
    it always prefills DEFAULTS, the same physical rows that
    core.FileFormatConfig's own data_start default points to
    (165265 + each step's original within-window offset).
    """

    DEFAULTS = [165265 + off for off in
                (5051, 65051, 125051, 185051, 245051, 305051, 365051, 425051, 515051)]

    def __init__(self, parent=None):
        super().__init__(parent)
        self.setWindowTitle("Stretch Line#:")
        layout = QVBoxLayout(self)
        info = QLabel("Each value is the raw file line number (including header lines) "
                       "where that stretch occurs.")
        info.setWordWrap(True)
        layout.addWidget(info)
        form = QFormLayout()
        self.fields: list[QLineEdit] = []
        labels = [f"Enter Stretch {i} Line#" for i in range(1, 9)] + ["Enter End Line#"]
        for lbl, v in zip(labels, self.DEFAULTS):
            le = QLineEdit(str(int(v)))
            form.addRow(lbl, le)
            self.fields.append(le)
        layout.addLayout(form)
        btns = QDialogButtonBox(QDialogButtonBox.Ok | QDialogButtonBox.Cancel)
        btns.accepted.connect(self.accept)
        btns.rejected.connect(self.reject)
        layout.addWidget(btns)

    def get_values(self) -> Optional[np.ndarray]:
        try:
            return np.array([float(f.text()) for f in self.fields])
        except ValueError:
            return None


# ==========================================================================
# Analysis tab
# ==========================================================================

class AnalysisTab(QWidget):
    def __init__(self, main_window: "MainWindow"):
        super().__init__()
        self.mw = main_window
        root = QVBoxLayout(self)

        top = QHBoxLayout()

        # --- left controls ---
        left = QVBoxLayout()
        self.select_files_btn = QPushButton("Select Files")
        self.select_files_btn.setStyleSheet("font-weight: bold; font-size: 14pt;")
        self.select_files_btn.clicked.connect(self.mw.on_select_files)
        left.addWidget(self.select_files_btn)

        beats_box = QHBoxLayout()
        beats_label = QLabel("Number of Beats")
        beats_label.setStyleSheet("font-weight: bold;")
        self.beats_spin = QSpinBox()
        self.beats_spin.setMinimum(1)
        self.beats_spin.setMaximum(1000)
        self.beats_spin.setValue(5)
        self.beats_spin.valueChanged.connect(self.mw.on_num_beats_changed)
        beats_box.addWidget(beats_label)
        beats_box.addWidget(self.beats_spin)
        left.addLayout(beats_box)
        left.addStretch()
        top.addLayout(left, 1)

        # --- selected files listbox ---
        mid = QVBoxLayout()
        mid_label = QLabel("Selected Files")
        mid_label.setStyleSheet("font-weight: bold; font-size: 13pt;")
        mid_label.setAlignment(Qt.AlignCenter)
        mid.addWidget(mid_label)
        click_label = QLabel("Click on file to start analysis")
        click_label.setStyleSheet("color: #b23; font-weight: bold;")
        click_label.setAlignment(Qt.AlignCenter)
        mid.addWidget(click_label)
        self.selected_files_list = QListWidget()
        self.selected_files_list.itemClicked.connect(self.mw.on_selected_file_clicked)
        mid.addWidget(self.selected_files_list)
        top.addLayout(mid, 1)

        # --- stretch listbox ---
        right = QVBoxLayout()
        right_label = QLabel("Select Stretch # to Plot/Analyze")
        right_label.setStyleSheet("font-weight: bold; font-size: 12pt;")
        right_label.setAlignment(Qt.AlignCenter)
        right.addWidget(right_label)
        self.stretch_list = QListWidget()
        self.stretch_list.itemClicked.connect(self.mw.on_stretch_clicked)
        right.addWidget(self.stretch_list)
        top.addLayout(right, 1)

        # --- action buttons ---
        actions = QVBoxLayout()
        self.combine_btn = QPushButton("Combine Selected Stretches")
        self.combine_btn.setStyleSheet("font-weight: bold; font-size: 11pt;")
        self.combine_btn.clicked.connect(self.mw.on_combine_stretches)
        actions.addWidget(self.combine_btn)
        self.save_btn = QPushButton("Save Data and Figures")
        self.save_btn.setStyleSheet("font-weight: bold; font-size: 11pt;")
        self.save_btn.clicked.connect(self.mw.on_save_data_and_figures)
        actions.addWidget(self.save_btn)
        self.next_file_btn = QPushButton("Next File")
        self.next_file_btn.setStyleSheet("font-weight: bold; font-size: 11pt;")
        self.next_file_btn.clicked.connect(self.mw.on_next_file)
        actions.addWidget(self.next_file_btn)
        warn_label = QLabel("Important: click to avoid overwriting data!!!")
        warn_label.setStyleSheet("color: #b23;")
        warn_label.setAlignment(Qt.AlignCenter)
        warn_label.setWordWrap(True)
        actions.addWidget(warn_label)
        actions.addStretch()
        top.addLayout(actions, 1)

        root.addLayout(top, 0)

        # --- main plot axes (UIAxes) ---
        self.figure = Figure(figsize=(11, 5.5), constrained_layout=True)
        self.canvas = FigureCanvas(self.figure)
        self.canvas.setSizePolicy(QSizePolicy.Expanding, QSizePolicy.Expanding)
        self.toolbar = NavigationToolbar(self.canvas, self)
        self.ax = self.figure.add_subplot(111)
        root.addWidget(self.toolbar)
        root.addWidget(self.canvas, 1)


# ==========================================================================
# Summary tab (single-tab layout, all 8 plots visible at once)
# ==========================================================================

class SummaryTab(QWidget):
    def __init__(self, main_window: "MainWindow"):
        super().__init__()
        self.mw = main_window
        root = QHBoxLayout(self)

        # --- left control panel ---
        left = QVBoxLayout()
        left.setSpacing(12)

        groups_box = QGroupBox("Groups")
        groups_layout = QGridLayout(groups_box)
        warn = QLabel("Change the name before selecting a new set of\n"
                       "files, to avoid overwriting a previous group.")
        warn.setStyleSheet("color: #b23; font-size: 9pt;")
        warn.setWordWrap(True)
        groups_layout.addWidget(warn, 0, 0, 1, 2)

        self.group1_btn = QPushButton("Group 1")
        self.group1_btn.setStyleSheet("font-weight: bold; color: #1173BE;")
        self.group1_edit = QLineEdit("Control")
        self.group2_btn = QPushButton("Group 2")
        self.group2_btn.setStyleSheet("font-weight: bold; color: #3BAA32;")
        self.group2_edit = QLineEdit("Treatment")
        self.group3_btn = QPushButton("Group 3")
        self.group3_btn.setStyleSheet("font-weight: bold; color: #8516D1;")
        self.group3_edit = QLineEdit("Mutant")
        groups_layout.addWidget(self.group1_btn, 1, 0)
        groups_layout.addWidget(self.group1_edit, 1, 1)
        groups_layout.addWidget(self.group2_btn, 2, 0)
        groups_layout.addWidget(self.group2_edit, 2, 1)
        groups_layout.addWidget(self.group3_btn, 3, 0)
        groups_layout.addWidget(self.group3_edit, 3, 1)
        left.addWidget(groups_box)

        self.group1_btn.clicked.connect(lambda: self.mw.on_group_button(1))
        self.group2_btn.clicked.connect(lambda: self.mw.on_group_button(2))
        self.group3_btn.clicked.connect(lambda: self.mw.on_group_button(3))
        self.group1_edit.editingFinished.connect(lambda: self.mw.on_group_name_changed(1, self.group1_edit.text()))
        self.group2_edit.editingFinished.connect(lambda: self.mw.on_group_name_changed(2, self.group2_edit.text()))
        self.group3_edit.editingFinished.connect(lambda: self.mw.on_group_name_changed(3, self.group3_edit.text()))

        graphs_box = QGroupBox("Time-Course Graphs")
        graphs_layout = QVBoxLayout(graphs_box)
        self.contraction_btn = QPushButton("Time for Contraction")
        self.relaxation_btn = QPushButton("Time for Relaxation")
        for b in (self.contraction_btn, self.relaxation_btn):
            b.setCheckable(True)
        self.graph_choice_group = QButtonGroup(self)
        self.graph_choice_group.setExclusive(True)
        self.graph_choice_group.addButton(self.contraction_btn, 1)
        self.graph_choice_group.addButton(self.relaxation_btn, 2)
        self.contraction_btn.setChecked(True)
        self.contraction_btn.clicked.connect(lambda: self.mw.on_optional_graph_selected(1))
        self.relaxation_btn.clicked.connect(lambda: self.mw.on_optional_graph_selected(2))
        graphs_layout.addWidget(self.contraction_btn)
        graphs_layout.addWidget(self.relaxation_btn)
        left.addWidget(graphs_box)

        self.start_over_btn = QPushButton("Start Over")
        self.start_over_btn.setStyleSheet("font-weight: bold;")
        left.addWidget(self.start_over_btn)
        self.start_over_btn.clicked.connect(self.mw.on_start_over)

        left.addStretch()
        left_frame = QFrame()
        left_frame.setLayout(left)
        left_frame.setFixedWidth(210)
        root.addWidget(left_frame)

        # --- all 8 plots in one 2-row x 4-column grid ---
        right_grid = QGridLayout()
        right_grid.setSpacing(6)
        self.canvases: dict[int, FigureCanvas] = {}
        self.axes: dict[int, "matplotlib.axes.Axes"] = {}

        def make_axes(key, title):
            fig = Figure(figsize=(3.6, 3.0), constrained_layout=True)
            canvas = FigureCanvas(fig)
            canvas.setMinimumSize(270, 230)
            canvas.setSizePolicy(QSizePolicy.Expanding, QSizePolicy.Expanding)
            ax = fig.add_subplot(111)
            ax.set_title(title, fontsize=9)
            ax.tick_params(labelsize=7)
            self.canvases[key] = canvas
            self.axes[key] = ax
            return canvas

        right_grid.addWidget(make_axes(2, "Passive Force"), 0, 0)
        right_grid.addWidget(make_axes(3, "Active Force"), 0, 1)
        right_grid.addWidget(make_axes(4, "Contraction Velocity"), 0, 2)
        right_grid.addWidget(make_axes(5, "Relaxation Velocity"), 0, 3)
        right_grid.addWidget(make_axes(6, "Force Integral"), 1, 0)
        right_grid.addWidget(make_axes(7, "50%"), 1, 1)
        right_grid.addWidget(make_axes(8, "75%"), 1, 2)
        right_grid.addWidget(make_axes(9, "90%"), 1, 3)
        root.addLayout(right_grid, 1)

    def redraw(self, key):
        self.canvases[key].draw_idle()

    def redraw_all(self):
        for c in self.canvases.values():
            c.draw_idle()


# ==========================================================================
# Main window
# ==========================================================================

class MainWindow(QMainWindow):
    def __init__(self):
        super().__init__()
        self.setWindowTitle(APP_TITLE)
        self.resize(1500, 900)

        # ---- state (mirrors the MATLAB app's private properties) ----
        self.cfg = core.FileFormatConfig()
        self.input_beats = 5
        self.file_map: dict[str, str] = {}
        self.current_loaded: Optional[core.LoadedFile] = None
        self.current_file_name: Optional[str] = None
        self.output_folder: Optional[str] = None
        self.stretch_results: dict[int, core.StretchResult] = {}
        self.combined_result: Optional[core.CombinedResult] = None
        # mirrors MATLAB's app.freq_stim: a persisted instance value that
        # holds whichever stretch's detected inter-beat interval was
        # computed most recently. figure(10)'s combine-step Poincare plot
        # uses this directly, same as the MATLAB source does.
        self.last_freq_stim = 1000
        self.group_names = {1: "Control", 2: "Treatment", 3: "Mutant"}
        # combined_group{g}[tab_name] -> list of 1-D arrays (one per loaded file)
        self.combined_group: dict[int, dict[str, list]] = {1: {}, 2: {}, 3: {}}
        self.combined_group_headers: dict[int, list[str]] = {1: [], 2: [], 3: []}
        self.last_optional_graph = 1

        self.plotwin = PlotWindowManager(self)

        self._build_menu()
        self._build_status_bar()
        self.tabs = QTabWidget()
        self.analysis_tab = AnalysisTab(self)
        self.summary_tab = SummaryTab(self)
        self.tabs.addTab(self.analysis_tab, "Analysis")
        self.tabs.addTab(self.summary_tab, "Summary")
        self.setCentralWidget(self.tabs)
        self._update_settings_summary()

    # ---------------------------------------------------------------
    # Menu (File Format) + a live settings readout so it's obvious the
    # toolbar's current values (and any edits) are actually in effect
    # ---------------------------------------------------------------
    def _build_status_bar(self):
        self.settings_label = QLabel()
        self.settings_label.setStyleSheet("color: #444; padding: 2px 6px;")
        self.statusBar().addPermanentWidget(self.settings_label, 1)

    def _update_settings_summary(self):
        c = self.cfg
        trig = "auto-detect" if c.trigger_points is None else "manual"
        l0 = "auto" if c.initial_length_mm is None else f"{c.initial_length_mm} mm"
        # data_start/data_end are stored relative to the header-stripped
        # array (matching the MATLAB app's internal Data_Start/Data_End);
        # show the reconstructed absolute line numbers here since that's
        # what was actually typed into the dialog.
        abs_start = c.data_start + c.non_data_lines
        abs_end = c.data_end + c.non_data_lines
        self.settings_label.setText(
            f"File Format  \u2014  Header lines: {c.non_data_lines}  |  "
            f"Data line (start\u2013end): {abs_start}\u2013{abs_end}  |  "
            f"Columns (Time/Length/Force/Stim): {c.time_col}/{c.length_col}/{c.force_col}/{c.stim_col}  |  "
            f"Stimulus value: {c.stim_value}  |  Triggers: {trig}  |  Initial length (L0): {l0}"
        )

    def _build_menu(self):
        menubar = self.menuBar()
        file_format = menubar.addMenu("File Format")

        act = file_format.addAction("Header Lines")
        act.triggered.connect(self.on_header_lines)

        data_range = file_format.addMenu("Select Data Range")
        a = data_range.addAction("Data start")
        a.triggered.connect(self.on_data_start)
        a = data_range.addAction("Data end")
        a.triggered.connect(self.on_data_end)

        data_cols = file_format.addMenu("Data Columns")
        a = data_cols.addAction("Time")
        a.triggered.connect(lambda: self.on_column_menu("time_col", "Time", self.cfg.time_col))
        a = data_cols.addAction("Length")
        a.triggered.connect(lambda: self.on_column_menu("length_col", "Length", self.cfg.length_col))
        a = data_cols.addAction("Force")
        a.triggered.connect(lambda: self.on_column_menu("force_col", "Force", self.cfg.force_col))
        a = data_cols.addAction("Stimulus")
        a.triggered.connect(lambda: self.on_column_menu("stim_col", "Stimulus", self.cfg.stim_col))

        act = file_format.addAction("Stimulus Value")
        act.triggered.connect(self.on_stimulus_value)

        act = file_format.addAction("Manually Assign Stretch Timepoints")
        act.triggered.connect(self.on_manual_triggers)

        act = file_format.addAction("Initial Length (L0 in mm)")
        act.triggered.connect(self.on_initial_length)

    def on_header_lines(self):
        val, ok = QInputDialog.getInt(self, "Header Lines", "Enter number of header lines",
                                       self.cfg.non_data_lines, 0, 10_000_000)
        if ok:
            self.cfg.non_data_lines = val
            self._update_settings_summary()

    def on_data_start(self):
        # MATLAB: data_start = inputdlg(..., string(165265)); app.Data_Start
        # = str2double(data_start) - app.NonDataLines -- resolved ONCE, here,
        # using non_data_lines as it stands right now; not retroactively
        # recomputed if non_data_lines changes later. The dialog always
        # suggests the reconstructed current absolute line number rather
        # than MATLAB's hard-coded 165265, which is friendlier when this is
        # reopened after an earlier edit but resolves identically either way
        # if left untouched.
        current_absolute = self.cfg.data_start + self.cfg.non_data_lines
        val, ok = QInputDialog.getInt(self, "Data start", "Enter Line# where data starts",
                                       current_absolute, 0, 100_000_000)
        if ok:
            self.cfg.data_start = val - self.cfg.non_data_lines
            self._update_settings_summary()

    def on_data_end(self):
        current_absolute = self.cfg.data_end + self.cfg.non_data_lines
        val, ok = QInputDialog.getInt(self, "Data end", "Enter Line# where data ends",
                                       current_absolute, 0, 100_000_000)
        if ok:
            self.cfg.data_end = val - self.cfg.non_data_lines
            self._update_settings_summary()

    def on_column_menu(self, attr, label, current):
        val, ok = QInputDialog.getInt(self, label, f"Enter Column# containing {label} data", current, 1, 1000)
        if ok:
            setattr(self.cfg, attr, val)
            self._update_settings_summary()

    def on_stimulus_value(self):
        val, ok = QInputDialog.getDouble(self, "Stimulus", "Enter Stimulus Value", self.cfg.stim_value,
                                          -1e12, 1e12, 3)
        if ok:
            self.cfg.stim_value = val
            self._update_settings_summary()

    def on_manual_triggers(self):
        # MATLAB: app.triggerpts = str2double(settriggers) - app.NonDataLines
        # - app.Data_Start -- resolved ONCE, here, into window-relative
        # sample offsets, using non_data_lines/data_start as they stand
        # right now. Like MATLAB, the dialog always suggests the same
        # static default line numbers rather than trying to reconstruct
        # absolute lines from any previously-set (and by then
        # window-relative) trigger_points.
        dlg = ManualTriggerDialog(self)
        if dlg.exec_() == QDialog.Accepted:
            vals = dlg.get_values()
            if vals is None:
                QMessageBox.warning(self, "Invalid input", "Please enter numeric values.")
                return
            self.cfg.trigger_points = vals - self.cfg.non_data_lines - self.cfg.data_start
            self._update_settings_summary()

    def on_initial_length(self):
        val, ok = QInputDialog.getDouble(self, "Initial Length", "Enter length value in Millimeters",
                                          self.cfg.initial_length_mm or 6.3, 0.0, 1000.0, 3)
        if ok:
            self.cfg.initial_length_mm = val
            self._update_settings_summary()

    # ---------------------------------------------------------------
    # Analysis tab callbacks
    # ---------------------------------------------------------------
    def on_select_files(self):
        files, _ = QFileDialog.getOpenFileNames(self, "Select One or More Files")
        if not files:
            return
        self.file_map = {os.path.basename(f): f for f in files}
        self.analysis_tab.selected_files_list.clear()
        self.analysis_tab.selected_files_list.addItems(list(self.file_map.keys()))
        print(f"Number of files selected: {len(files)}")

    def on_num_beats_changed(self, value):
        self.input_beats = value
        print(f"Number of Beats /length change: {value}")

    def on_selected_file_clicked(self, item: QListWidgetItem):
        filename = item.text()
        fullpath = self.file_map.get(filename)
        if fullpath is None:
            return
        clean = os.path.splitext(filename)[0]
        self.current_file_name = clean
        self.output_folder = os.path.join(os.getcwd(), clean + "_Output")
        os.makedirs(self.output_folder, exist_ok=True)

        try:
            lf = core.load_file(fullpath, self.cfg)
        except Exception as e:
            QMessageBox.critical(self, "File Read Error", f"Failed to read text data: {e}")
            return

        self.current_loaded = lf
        self.stretch_results = {}
        # figures 2/5/6's subplot grid is sized to this file's own
        # total_stretches (see _grid_nrows) -- reset so a previous file's
        # grid (built for a possibly different stretch count) can't linger
        # and be indexed out of range
        self.plotwin.close_all()

        self.analysis_tab.stretch_list.clear()
        self.analysis_tab.stretch_list.addItems([f"Stretch_{i}" for i in range(1, lf.total_stretches + 1)])
        self.analysis_tab.ax.clear()
        self.analysis_tab.canvas.draw_idle()

        win = self.plotwin.get(1, "Length and Force", nrows=2, ncols=1, figsize=(8, 6.5))
        win.clear_all()
        ax1, ax2 = win.ax(1), win.ax(2)
        ax1.plot(lf.time_min, lf.length_mm, color="k")
        ax1.set_title("Length")
        ax1.set_xlabel("Time (minutes)")
        ax1.set_ylabel("Length (mm)")
        ax2.plot(lf.time_min, lf.force_mN)
        ax2.set_title("Force")
        ax2.set_xlabel("Time (minutes)")
        ax2.set_ylabel("Force (mN)")
        win.redraw()

    def on_stretch_clicked(self, item: QListWidgetItem):
        if self.current_loaded is None:
            return
        stretch = int(item.text().split("_")[1])
        lf = self.current_loaded

        try:
            preview = core.analyze_stretch_preview(lf, stretch, self.cfg.stim_value)
        except Exception as e:
            QMessageBox.critical(self, "Analysis Error", f"Failed to analyze stretch: {e}\n\n{traceback.format_exc()}")
            return

        n_labels = len(preview["labels"])
        if n_labels == 0:
            QMessageBox.warning(self, "No stimulus detected",
                                 "No stimulus pulses were found in this stretch window. "
                                 "Check the Stimulus column / Stimulus Value settings.")
            return

        # --- preview plot in the main UIAxes, with labeled peaks ---
        ax = self.analysis_tab.ax
        ax.clear()
        ax.plot(preview["time_step"], preview["force_smooth25"], label="Raw force data", linewidth=1)
        ax.plot(preview["time_step"][preview["stimulus_locs"]], preview["y_match_peaks"],
                "|", markersize=12, linewidth=1, label="Stimulus location")
        # reserve headroom above the data so the rotated peak-number labels
        # never get clipped by the top of the axes
        ax.margins(y=0.28)
        n_peaks = len(preview["labels"])
        for k, lbl in enumerate(preview["labels"]):
            if k >= len(preview["stimulus_locs"]):
                continue
            # stagger label height in a 3-level zigzag so adjacent, closely
            # spaced beats don't overlap each other
            offset = 6 + (k % 3) * 9
            ax.annotate(lbl, (preview["time_step"][preview["stimulus_locs"][k]], preview["y_match_peaks"][k]),
                        textcoords="offset points", xytext=(0, offset), ha="center", va="bottom",
                        fontsize=6, rotation=90)
        lr = preview["length_ratio"]
        ax.set_title(f"Force vs time at length: {lr}*L_0" if lr == lr else "Force vs time")
        ax.set_xlabel("Time (seconds)")
        ax.set_ylabel("Force (mN)")
        if len(preview["stimulus_locs"]) >= 2:
            ax.set_xlim(preview["time_step"][preview["stimulus_locs"][0]] - 2,
                        preview["time_step"][preview["stimulus_locs"][-1]] + 2)
        ax.legend(loc="upper right", fontsize=8, framealpha=0.9)
        self.analysis_tab.canvas.draw_idle()

        # --- ask which peaks to use ---
        defaults = core.default_peak_selection(preview, self.input_beats)
        dlg = PeakSelectionDialog(defaults, n_labels, self)
        if dlg.exec_() != QDialog.Accepted:
            return
        peak_nums = dlg.get_values()
        if peak_nums is None:
            QMessageBox.warning(self, "Invalid input", f"Peak numbers must be integers between 1 and {n_labels}.")
            return

        try:
            res = core.analyze_stretch_beats(lf, preview, peak_nums)
        except Exception as e:
            QMessageBox.critical(self, "Analysis Error", f"Failed to analyze beats: {e}\n\n{traceback.format_exc()}")
            return

        self.stretch_results[stretch] = res
        lf.force_wo_peak[preview["lo"]:preview["hi"]] = res.force_step_edit

        self._plot_stretch_figures(stretch, preview, res)

    def _grid_nrows(self, ncols: int = 2) -> int:
        """MATLAB: subplot(app.total_stretches/2, 2, i) -- the per-stretch
        subplot grids (Figures 2, 5, 6) size their row count to however
        many stretches were actually detected for the currently loaded
        file, rather than assuming the standard 8-step protocol."""
        total = self.current_loaded.total_stretches if self.current_loaded else 8
        return max(1, math.ceil(total / ncols))

    def _plot_stretch_figures(self, stretch: int, preview: dict, res: core.StretchResult):
        lr_txt = f"{res.length_ratio}\u00b7L0" if res.length_ratio == res.length_ratio else "?"
        nrows = self._grid_nrows()
        self.last_freq_stim = res.freq_stim

        # figure(2): individual selected beats, overlaid per stretch subplot
        win2 = self.plotwin.get(2, "Selected Beats", nrows=nrows, ncols=2, figsize=(12, 3.25 * nrows),
                                 supxlabel="Time (ms)", supylabel="Force (mN)")
        ax2 = win2.ax(stretch)
        ax2.clear()
        for k in range(res.beat_waveforms.shape[1]):
            ax2.plot(res.beat_waveforms[:, k], linewidth=1)
        ax2.set_title(f"L={lr_txt}", fontsize=9)
        ax2.tick_params(labelsize=7)
        ax2.set_xlim(0, res.freq_stim)
        win2.redraw()

        # figure(3): average velocity curve, one line added per stretch.
        # Legend is recreated (not detached) each call so constrained_layout
        # always knows its current size and reserves exactly enough room.
        win3 = self.plotwin.get(3, "Average velocity of contraction/relaxation", nrows=1, ncols=1, figsize=(9.5, 6))
        ax3 = win3.ax()
        ax3.plot(res.dt_velocity_curve, label=lr_txt, linewidth=1.2)
        ax3.set_title("Average velocity of contraction/relaxation")
        ax3.set_xlabel("Time (ms)")
        ax3.set_ylabel("Velocity (mN/ms)")
        ax3.legend(loc="center left", bbox_to_anchor=(1.02, 0.5), fontsize=8, borderaxespad=0)
        win3.redraw()

        # figure(4): average time-course overlay, one line + markers per
        # stretch. The per-stretch length lines and the fixed marker color
        # key are combined into a SINGLE legend call each time (rather than
        # two independent ones), because a detached ("added as artist")
        # legend is invisible to constrained_layout's space-reservation and
        # is what was causing it to run off the edge of the figure.
        win4 = self.plotwin.get(4, "Average time course of contraction/relaxation", nrows=1, ncols=1, figsize=(10, 6.5))
        ax4 = win4.ax()
        valley_baseline = np.nanmin(res.avg_beat_waveform) if len(res.avg_beat_waveform) else 0.0
        norm_force = res.avg_beat_waveform - valley_baseline
        time_beat = np.arange(1, len(norm_force) + 1)
        ax4.plot(time_beat, norm_force, label=lr_txt, linewidth=1.2)
        markers = np.round(res.markers_ms).astype(int)
        markers = np.clip(markers, 0, len(norm_force) - 1)
        ax4.scatter(time_beat[markers], norm_force[markers], s=45, c=KINETIC_MARKER_COLORS,
                    edgecolors="k", linewidths=0.5, zorder=5)
        ax4.set_title("Average time course of contraction/relaxation")
        ax4.set_xlabel("Time (ms)")
        ax4.set_ylabel("Force (mN)")
        ax4.set_xlim(0, res.freq_stim)

        if not hasattr(ax4, "_marker_proxies"):
            ax4._marker_proxies = [Line2D([0], [0], marker="o", color="w", markerfacecolor=c,
                                           markeredgecolor="k", markersize=7) for c in KINETIC_MARKER_COLORS]
        line_handles, line_labels = ax4.get_legend_handles_labels()
        all_handles = line_handles + ax4._marker_proxies
        all_labels = line_labels + KINETIC_LABELS
        ax4.legend(all_handles, all_labels, loc="center left", bbox_to_anchor=(1.02, 0.5),
                   fontsize=7, borderaxespad=0)
        win4.redraw()

        # figure(5): Poincare plot per stretch
        win5 = self.plotwin.get(5, "Poincare plot per length", nrows=nrows, ncols=2, figsize=(11, 3.25 * nrows),
                                 supxlabel="R(n-1) to R(n) (ms)", supylabel="R(n) to R(n+1) (ms)")
        ax5 = win5.ax(stretch)
        ax5.clear()
        db = res.dist_between_beats
        if len(db) > 2:
            rr = db[:-1]
            rrp1 = db[1:]
            ax5.plot(rrp1, rr, ".", markersize=4)
        ax5.set_xlim(0.9 * res.freq_stim, 1.1 * res.freq_stim)
        ax5.set_ylim(0.9 * res.freq_stim, 1.1 * res.freq_stim)
        ax5.set_title(f"L={lr_txt}", fontsize=9)
        ax5.tick_params(labelsize=7)
        win5.redraw()

        # figure(6): force step with/without beats
        win6 = self.plotwin.get(6, "Contractions/beats", nrows=nrows, ncols=2, figsize=(12, 3.375 * nrows),
                                 supylabel="Force (mN)")
        ax6 = win6.ax(stretch)
        ax6.clear()
        ax6.plot(preview["time_step"], preview["force_smooth25"], linewidth=1, label="Raw force data")
        ax6.plot(preview["time_step"][res.stimulus_locs], res.y_match_peaks, "|", markersize=8,
                 linewidth=0.5, label="Stimulus location")
        ax6.plot(preview["time_step"], res.force_step_edit, linewidth=1, label="Active force removed")
        ax6.set_title(f"L={lr_txt}", fontsize=9)
        ax6.tick_params(labelsize=7)
        bottom_row_start = (nrows - 1) * 2 + 1
        if stretch >= bottom_row_start:
            # bottom-row subplots only, instead of a figure-wide supxlabel:
            # a supxlabel would sit in the same bottom strip as the
            # figure-level legend below and collide with it
            ax6.set_xlabel("Time (s)", fontsize=9)
        if len(res.contraction_peak_locs) > 1:
            lo_i = max(0, res.contraction_peak_locs[0] - 100)
            hi_i = min(len(preview["time_step"]) - 1, res.contraction_peak_locs[-1] + 500)
            ax6.set_xlim(preview["time_step"][lo_i], preview["time_step"][hi_i])
        if stretch == 1:
            # figure-level legend, drawn once, outside/below all subplots so
            # it never obscures subplot 1's data (constrained_layout
            # reserves the extra strip of space automatically)
            handles, labels_ = ax6.get_legend_handles_labels()
            win6.figure.legend(handles, labels_, loc="outside lower center", ncol=3, fontsize=9)
        win6.redraw()

    def on_combine_stretches(self):
        if self.current_loaded is None or not self.stretch_results:
            QMessageBox.warning(self, "Nothing to combine", "Analyze at least one stretch first.")
            return
        lf = self.current_loaded
        try:
            combined = core.combine_stretches(self.stretch_results, lf.initial_length_mm,
                                               total_stretches=lf.total_stretches)
        except Exception as e:
            QMessageBox.critical(self, "Combine Error", f"{e}\n\n{traceback.format_exc()}")
            return
        self.combined_result = combined

        # figure(7): full-protocol force with/without beats
        win7 = self.plotwin.get(7, "Force vs time with and without beats", nrows=1, ncols=1, figsize=(9.5, 6))
        ax7 = win7.ax()
        ax7.clear()
        lo, hi = lf.trigger[0], lf.trigger[-1] + 1   # MATLAB's trigger(end,:) is an inclusive upper bound
        ax7.plot(lf.force_mN[lo:hi], label="Raw force data", linewidth=0.8)
        ax7.plot(lf.force_wo_peak[lo:hi], label="Active force removed", linewidth=0.8)
        ax7.set_title("Force vs time with and without beats")
        ax7.set_xlabel("Time (samples)")
        ax7.set_ylabel("Force (mN)")
        # kept inside the axes (not pushed outside) so the plot area stays
        # full width; 'best' automatically picks the corner with the least
        # data to avoid overlap
        ax7.legend(loc="best", fontsize=8, framealpha=0.9)
        win7.redraw()

        # figure(8): active force vs length (Frank-Starling)
        win8 = self.plotwin.get(8, "Active force vs length", nrows=1, ncols=1, figsize=(8.5, 6.5))
        ax8 = win8.ax()
        ax8.clear()
        fit, xlen, yforce = combined.active_force_fit
        ax8.plot(xlen, yforce, "o", markerfacecolor="b", markeredgecolor="b", label="Raw data")
        if fit is not None:
            xs = np.linspace(np.nanmin(xlen), np.nanmax(xlen), 100)
            ax8.plot(xs, np.polyval(fit, xs), "-", label="Second order polynomial fit")
        ax8.set_title("Active force vs length")
        ax8.set_xlabel("Length / Initial Length (L/L0)")
        ax8.set_ylabel("Active Force (mN)")
        ax8.legend(loc="best", fontsize=8, framealpha=0.9)
        win8.redraw()

        # figure(9): passive force vs length
        win9 = self.plotwin.get(9, "Passive force vs length", nrows=1, ncols=1, figsize=(8.5, 6.5))
        ax9 = win9.ax()
        ax9.clear()
        fit, xlen, yforce = combined.passive_force_fit
        ax9.plot(xlen, yforce, "o", markerfacecolor="b", markeredgecolor="b", label="Raw data")
        if fit is not None:
            xs = np.linspace(np.nanmin(xlen), np.nanmax(xlen), 100)
            ax9.plot(xs, np.polyval(fit, xs), "-", label="Second order polynomial fit")
        ax9.set_title("Passive force vs length")
        ax9.set_xlabel("Length / Initial Length (L/L0)")
        ax9.set_ylabel("Passive Force (mN)")
        ax9.legend(loc="best", fontsize=8, framealpha=0.9)
        win9.redraw()

        # figure(10): combined Poincare plot with HRV ellipse
        win10 = self.plotwin.get(10, "Poincare plot", nrows=1, ncols=1, figsize=(9, 7.5))
        ax10 = win10.ax()
        ax10.clear()
        beats = combined.all_dist_beats
        if len(beats) > 2:
            RR, RRp1 = beats[:-1], beats[1:]
            mean_rr = float(np.mean(RR))
            ax10.plot(RRp1, RR, ".", markersize=4, label="RR Intervals")
            min_val, max_val = float(np.min(beats)) - 50, float(np.max(beats)) + 50
            ax10.plot([min_val, max_val], [min_val, max_val], "--", color="0.5",
                      linewidth=1.5, label="Identity Line (x=y)")
            theta = np.linspace(0, 2 * np.pi, 200)
            x_e = combined.sd2 * np.cos(theta)
            y_e = combined.sd1 * np.sin(theta)
            rot = np.array([[np.cos(np.pi / 4), -np.sin(np.pi / 4)],
                             [np.sin(np.pi / 4), np.cos(np.pi / 4)]]) @ np.vstack([x_e, y_e])
            ax10.plot(rot[0] + mean_rr, rot[1] + mean_rr, "r-", linewidth=2.5, label="HRV Ellipse")
            ax10.plot(mean_rr, mean_rr, "ro", markerfacecolor="r", markersize=8, label="Center (Mean)")
            ax10.text(0.03, 0.97, f"SD1 (short-term): {combined.sd1}\nSD2 (long-term): {combined.sd2}",
                      transform=ax10.transAxes, fontsize=8, va="top", ha="left",
                      bbox=dict(boxstyle="round", facecolor="white", alpha=0.85, edgecolor="0.7"))
            ax10.legend(loc="center left", bbox_to_anchor=(1.02, 0.5), fontsize=8, borderaxespad=0)
        ax10.set_xlim(0.9 * self.last_freq_stim, 1.1 * self.last_freq_stim)
        ax10.set_ylim(0.9 * self.last_freq_stim, 1.1 * self.last_freq_stim)
        ax10.set_title("Poincare plot")
        ax10.set_xlabel("R(n-1) to R(n) (ms)")
        ax10.set_ylabel("R(n) to R(n+1) (ms)")
        ax10.set_box_aspect(1)   # square box (MATLAB's "axis square"), independent of data-unit scaling
        win10.redraw()

    def on_save_data_and_figures(self):
        if self.current_loaded is None or self.combined_result is None or self.current_file_name is None:
            QMessageBox.warning(self, "Nothing to save",
                                 "Analyze stretches and click 'Combine Selected Stretches' first.")
            return
        lf = self.current_loaded
        combined = self.combined_result
        out_dir = self.output_folder
        os.makedirs(out_dir, exist_ok=True)

        try:
            # _output.txt is saved directly in the current working
            # directory (not the per-file _Output subfolder) so that the
            # results files for every analyzed file end up sitting
            # together in one flat location -- convenient for the Group
            # 1/2/3 file picker on the Summary tab, which needs to
            # multi-select several files' _output.txt at once.
            df = pd.DataFrame(combined.data_output, columns=core.EXCEL_TABS)
            output_txt_path = os.path.join(os.getcwd(), f"{self.current_file_name}_output.txt")
            df.to_csv(output_txt_path, sep="\t", index=False)

            lo, hi = lf.trigger[0], lf.trigger[-1] + 1   # MATLAB's trigger(end,:) is an inclusive upper bound
            np.savetxt(os.path.join(out_dir, f"{self.current_file_name}_force_wo_peaks_data.csv"),
                       lf.force_mN[lo:hi], delimiter=",")

            avg_beats = np.column_stack([
                self.stretch_results[k].avg_beat_waveform for k in sorted(self.stretch_results)
            ]) if self.stretch_results else np.array([])
            if avg_beats.size:
                np.savetxt(os.path.join(out_dir, f"{self.current_file_name}_average_selected_beats_per_length.csv"),
                           avg_beats, delimiter=",")

            names = {1: "_length_and_force", 2: "_selected_beats", 3: "_avg_velocity",
                     4: "_avg_time_course", 5: "_poincare_plot_per_length", 6: "_force_step_w_and_wo_peaks_per_length",
                     7: "_force_data_w_and_wo_peaks", 8: "_active_force_vs_length",
                     9: "_passive_force_vs_length", 10: "_poincare_plot"}
            for num, win in self.plotwin.windows.items():
                base = os.path.join(out_dir, f"{self.current_file_name}{names.get(num, f'_fig{num}')}")
                win.figure.savefig(base + ".png", dpi=150)
                win.figure.savefig(base + ".eps")

        except Exception as e:
            QMessageBox.critical(self, "Save Error", f"{e}\n\n{traceback.format_exc()}")
            return

        QMessageBox.information(self, "Complete", "All files and figures saved")

    def on_next_file(self):
        self.analysis_tab.ax.clear()
        self.analysis_tab.canvas.draw_idle()
        self.plotwin.close_all()

    # ---------------------------------------------------------------
    # Summary tab callbacks
    # ---------------------------------------------------------------
    def on_group_name_changed(self, group_num: int, text: str):
        self.group_names[group_num] = text

    def on_group_button(self, group_num: int):
        files, _ = QFileDialog.getOpenFileNames(self, "Select One or More Files",
                                                  filter="Text files (*.txt *.tsv *.csv);;All files (*)")
        if not files:
            QMessageBox.information(self, "Canceled", "No files were selected.")
            return

        headers = []
        combined = {tab: [] for tab in core.EXCEL_TABS}
        for f in files:
            try:
                data = pd.read_csv(f, sep=None, engine="python")
                headers.append(os.path.splitext(os.path.basename(f))[0])
                for tab in core.EXCEL_TABS:
                    if tab in data.columns:
                        combined[tab].append(data[tab].to_numpy())
                    else:
                        combined[tab].append(np.full(len(data), np.nan))
            except Exception as e:
                QMessageBox.warning(self, "File Error", f"Error reading file: {f}\n{e}")

        if not headers:
            return

        self.combined_group[group_num] = combined
        self.combined_group_headers[group_num] = headers

        group_name = self.group_names[group_num]
        try:
            out_path = f"{group_name}.xlsx"
            with pd.ExcelWriter(out_path, engine="openpyxl") as writer:
                for tab in core.EXCEL_TABS:
                    cols = combined[tab]
                    max_len = max((len(c) for c in cols), default=0)
                    padded = [np.pad(c.astype(float), (0, max_len - len(c)), constant_values=np.nan) for c in cols]
                    out_df = pd.DataFrame(np.column_stack(padded) if padded else np.empty((0, 0)), columns=headers)
                    out_df.to_excel(writer, sheet_name=tab[:31], index=False)
        except Exception as e:
            QMessageBox.warning(self, "Save Error", f"Could not write {group_name}.xlsx:\n{e}")

        self._plot_group_summary(group_num)

    def _median_across_files(self, group_num: int, tab_name: str) -> np.ndarray:
        cols = self.combined_group[group_num].get(tab_name, [])
        if not cols:
            return np.array([])
        max_len = max(len(c) for c in cols)
        padded = np.column_stack([np.pad(c.astype(float), (0, max_len - len(c)), constant_values=np.nan) for c in cols])
        return np.nanmedian(padded, axis=1)

    def _plot_one_summary_axis(self, ax_key: int, group_num: int, tab: str, title: str, ylabel: str):
        marker, color = GROUP_MARKERS[group_num]
        length_med = self._median_across_files(group_num, "Length(mm)")
        if length_med.size == 0:
            return
        y_med = self._median_across_files(group_num, tab)
        ax = self.summary_tab.axes[ax_key]
        valid = ~np.isnan(length_med) & ~np.isnan(y_med)
        if valid.sum() >= 1:
            ax.plot(length_med[valid], y_med[valid], marker, color=color, markersize=6)
        if valid.sum() >= 3:
            poly = np.polyfit(length_med[valid], y_med[valid], 2)
            xs = np.linspace(np.nanmin(length_med[valid]), np.nanmax(length_med[valid]), 100)
            ax.plot(xs, np.polyval(poly, xs), "-", linewidth=2, color=color)
        ax.set_title(title, fontsize=9)
        ax.set_xlabel("Length (mm)", fontsize=8)
        ax.set_ylabel(ylabel, fontsize=8)
        ax.tick_params(labelsize=7)
        self.summary_tab.redraw(ax_key)

    def _plot_group_summary(self, group_num: int):
        targets = [
            (2, "Passive_Force(mN)", "Passive Force", "Force (mN)"),
            (3, "Active_Force(mN)", "Active Force", "Force (mN)"),
            (4, "Contraction_Velocity(mNperms)", "Contraction Velocity", "Velocity (mN/ms)"),
            (5, "Relaxation_Velocity(mNperms)", "Relaxation Velocity", "Velocity (mN/ms)"),
            (6, "Force_Integral(mN)", "Force Integral", "Force Integral (mN)"),
        ]
        for key, tab, title, ylabel in targets:
            self._plot_one_summary_axis(key, group_num, tab, title, ylabel)
        self._refresh_optional_graphs(group_num)

    def on_optional_graph_selected(self, which: int):
        self.last_optional_graph = which
        for k in (7, 8, 9):
            self.summary_tab.axes[k].clear()
        for group_num in (1, 2, 3):
            self._refresh_optional_graphs(group_num)
        self.summary_tab.redraw_all()

    def _refresh_optional_graphs(self, group_num: int):
        which = self.last_optional_graph
        if which == 1:
            tabs = [(7, "Contraction_50pct(ms)", "Contraction: 50%"),
                    (8, "Contraction_75pct(ms)", "Contraction: 75%"),
                    (9, "Contraction_90pct(ms)", "Contraction: 90%")]
        else:
            tabs = [(7, "Relaxation_50pct(ms)", "Relaxation: 50%"),
                    (8, "Relaxation_75pct(ms)", "Relaxation: 75%"),
                    (9, "Relaxation_90pct(ms)", "Relaxation: 90%")]
        for ax_key, tab, title in tabs:
            self._plot_one_summary_axis(ax_key, group_num, tab, title, "Time (ms)")

    def on_start_over(self):
        for k in range(2, 10):
            self.summary_tab.axes[k].clear()
        self.summary_tab.redraw_all()
        self.combined_group = {1: {}, 2: {}, 3: {}}
        self.combined_group_headers = {1: [], 2: [], 3: []}


def main():
    app = QApplication(sys.argv)
    win = MainWindow()
    win.show()
    sys.exit(app.exec_())


if __name__ == "__main__":
    main()
