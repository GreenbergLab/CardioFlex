"""
CardioFlex core analysis engine.

This module is a line-by-line functional translation of the MATLAB analysis
logic found in CardioFlex.mlapp (Greenberg Lab). It is deliberately kept free
of any GUI toolkit so it can be tested/used headlessly and reused by the
PyQt5 front end in CardioFlex_PyGUI.py.

MATLAB -> Python translation notes
-----------------------------------
* MATLAB is 1-indexed with inclusive ranges; this module is 0-indexed. Any
  function that accepts a MATLAB-style 1-indexed "column number" (to stay
  compatible with the app's menu options, which literally say "Enter Column
  containing Time data") subtracts 1 internally.
* `smooth(x, span)` replicates MATLAB's `smooth` (moving average method),
  including its shrinking-window behavior at the edges.
* `find_peaks_matlab` wraps `scipy.signal.find_peaks` with MinPeakProminence
  / MinPeakDistance semantics matching MATLAB's `findpeaks`.
* `moving_average_trailing` replicates the Financial Toolbox `movavg(...,
  'linear', N)` trailing simple moving average used to line up stimulus
  markers on the y-axis.
* `detect_length_triggers` replaces MATLAB's `ischange(smooth(length,6),
  'mean','Threshold',100)`. Exactly reproducing ischange's internal
  changepoint algorithm is not practical (it's a proprietary MathWorks
  implementation), so this uses a threshold/clustering detector on the
  smoothed length signal's derivative. It was validated against the four
  real 8-step protocol files supplied by the lab and exactly reproduces the
  9 trigger points (8 stretches) MATLAB's hard-coded default trigger array
  encodes for this protocol. If your data is noisier or uses a different
  protocol shape, use "Manually Assign Stretch Timepoints" in the GUI, exactly
  as you would in the MATLAB app when ischange gets it wrong.
* `savgol_filter` (scipy) replaces MATLAB's `sgolayfilt`.
* `polyfit`/`polyval` (numpy) replace MATLAB's `polyfit`/`polyval`.
"""
from __future__ import annotations

import warnings
from dataclasses import dataclass, field
from typing import Optional

import numpy as np
from scipy.signal import find_peaks, savgol_filter

EXCEL_TABS = [
    "Length(mm)", "Passive_Force(mN)", "Active_Force(mN)", "BPM",
    "Contraction_90pct(ms)", "Contraction_75pct(ms)", "Contraction_50pct(ms)",
    "Relaxation_90pct(ms)", "Relaxation_75pct(ms)", "Relaxation_50pct(ms)",
    "Contraction_Velocity(mNperms)", "Relaxation_Velocity(mNperms)",
    "Force_Integral(mN)", "Work(mN.mm)", "SD1", "SD2", "SD12",
]


# --------------------------------------------------------------------------
# MATLAB-equivalent numeric helpers
# --------------------------------------------------------------------------

def smooth(x: np.ndarray, span: int) -> np.ndarray:
    """Replicates MATLAB's smooth(x, span) with the default 'moving' method:
    a centered moving average that shrinks its window near the edges instead
    of padding, matching MATLAB's edge behavior."""
    x = np.asarray(x, dtype=float)
    span = int(span)
    if span < 1:
        span = 1
    if span % 2 == 0:
        span -= 1  # MATLAB forces span to be odd
    if span <= 1:
        return x.copy()

    n = len(x)
    y = np.empty(n, dtype=float)
    half = span // 2
    # cumulative sum for O(n) sliding window
    csum = np.cumsum(np.insert(x, 0, 0.0))
    for i in range(n):
        w = min(i, n - 1 - i, half)
        lo, hi = i - w, i + w + 1
        y[i] = (csum[hi] - csum[lo]) / (hi - lo)
    return y


def moving_average_trailing(x: np.ndarray, window: int) -> np.ndarray:
    """Replicates Financial Toolbox movavg(x, 'linear', window): a trailing
    simple moving average. Output length == input length; the first
    window-1 samples use however many samples are available (MATLAB
    movavg actually returns NaN for those, but here we only ever index
    into the tail of the result so it doesn't matter)."""
    x = np.asarray(x, dtype=float)
    window = int(window)
    csum = np.cumsum(np.insert(x, 0, 0.0))
    y = np.full(len(x), np.nan)
    for i in range(window - 1, len(x)):
        y[i] = (csum[i + 1] - csum[i + 1 - window]) / window
    return y


def find_peaks_matlab(x: np.ndarray, min_prominence: float, min_distance: float):
    """Wraps scipy.signal.find_peaks to match MATLAB findpeaks(x,
    'MinPeakProminence', p, 'MinPeakDistance', d) semantics."""
    peaks, _ = find_peaks(x, prominence=min_prominence, distance=max(1, min_distance))
    return x[peaks], peaks


def _trapz(y: np.ndarray) -> float:
    """np.trapz was renamed to np.trapezoid in NumPy 2.0 and removed in
    later releases; this small wrapper keeps CardioFlex_Core.py working
    across NumPy versions."""
    trapz_fn = getattr(np, "trapezoid", None) or getattr(np, "trapz", None)
    return float(trapz_fn(y))


def nearest(x: float) -> int:
    """MATLAB's nearest() rounds to nearest integer, ties away from zero."""
    return int(np.floor(x + 0.5)) if x >= 0 else int(np.ceil(x - 0.5))


# --------------------------------------------------------------------------
# Length-step (trigger) detection
# --------------------------------------------------------------------------

def detect_length_triggers(length_data: np.ndarray, smooth_span: int = 6,
                            min_gap: int = 200, threshold_factor: float = 10.0,
                            min_abs_threshold: float = 2e-4) -> np.ndarray:
    """Detects the sample indices where the stage length steps to a new
    plateau (equivalent to MATLAB's ischange(smooth(length,6),'mean',
    'Threshold',100) + find(df~=0)).

    Returns 0-indexed sample positions (relative to the start of
    length_data), one per detected transition, taken as the midpoint of
    each contiguous run of samples whose smoothed derivative exceeds an
    adaptive threshold.
    """
    length_data = np.asarray(length_data, dtype=float)
    smoothed = smooth(length_data, smooth_span)
    d = np.abs(np.diff(smoothed))
    if len(d) == 0:
        return np.array([], dtype=int)

    noise_floor = np.median(d) + 1e-12
    threshold = max(noise_floor * threshold_factor, min_abs_threshold)
    candidates = np.where(d > threshold)[0]
    if len(candidates) == 0:
        return np.array([], dtype=int)

    groups = []
    start = prev = candidates[0]
    for c in candidates[1:]:
        if c - prev > min_gap:
            groups.append((start, prev))
            start = c
        prev = c
    groups.append((start, prev))

    triggers = np.array([int((a + b) / 2) for a, b in groups], dtype=int)
    return triggers


# --------------------------------------------------------------------------
# Data containers
# --------------------------------------------------------------------------

@dataclass
class FileFormatConfig:
    """Mirrors the app's "File Format" menu settings.

    This matches the real MATLAB app's actual storage convention, confirmed
    against its source (startupFcn / StartMenuSelected / EndMenuSelected /
    ManuallyAssignStretchTimepointsMenuSelected):

    - data_start / data_end are stored as 1-indexed rows WITHIN the
      header-stripped data array (i.e. non_data_lines has ALREADY been
      subtracted). The MATLAB app computes this subtraction ONCE, at the
      moment the value is set (startup, or whenever the "Data start"/"Data
      end" dialog is submitted) -- using whatever non_data_lines happens to
      be at that moment -- and simply keeps the result from then on. It is
      NOT recomputed if non_data_lines changes afterwards. gui.py's
      on_data_start/on_data_end callbacks replicate this exactly: they take
      an absolute raw-file-line input from the dialog and do
      `cfg.data_start = entered_value - cfg.non_data_lines` right there,
      storing the relative result.
    - trigger_points, once set via "Manually Assign Stretch Timepoints", are
      likewise stored fully resolved -- i.e. already relative to the start
      of the analysis window (data_start), matching what
      detect_length_triggers() itself returns for the automatic path. The
      MATLAB app computes `app.triggerpts = entered - NonDataLines -
      Data_Start` once in the dialog callback; gui.py's on_manual_triggers
      does the same.
    - non_data_lines is the one value that's genuinely live: it's read
      directly wherever a file is loaded (skiprows=non_data_lines).

    Defaults: 165000 / 700000 for data_start/data_end (equal to the
    MATLAB startupFcn's 165265-265 / 700265-265), and None for
    trigger_points / initial_length_mm, matching the MATLAB app's
    commented-out defaults -- both are auto-computed unless the person
    explicitly sets them from the File Format menu.
    """
    non_data_lines: int = 265
    data_start: int = 165265 - 265   # = 165000 (relative to header-stripped data)
    data_end: int = 700265 - 265     # = 700000
    time_col: int = 1              # 1-indexed column numbers, as in the MATLAB menus
    length_col: int = 2
    force_col: int = 4
    stim_col: int = 9
    stim_value: float = 769.0
    trigger_points: Optional[np.ndarray] = None   # manual override: already window-relative sample offsets (see docstring)
    initial_length_mm: Optional[float] = None


@dataclass
class LoadedFile:
    time_min: np.ndarray            # minutes
    length_mm: np.ndarray
    force_mN: np.ndarray
    stimulus: np.ndarray
    trigger: np.ndarray             # sample indices (within the sliced arrays), 0-indexed
    initial_length_mm: float
    total_stretches: int
    force_wo_peak: np.ndarray = field(default_factory=lambda: np.array([]))


@dataclass
class StretchResult:
    stretch_index: int              # 1-indexed, matches "Stretch_N"
    length_mm: float
    passive_force_mN: float
    active_force_mN: float
    bpm: float
    contraction_90pct_ms: float
    contraction_75pct_ms: float
    contraction_50pct_ms: float
    relaxation_90pct_ms: float
    relaxation_75pct_ms: float
    relaxation_50pct_ms: float
    contraction_velocity: float
    relaxation_velocity: float
    force_integral: float
    avg_beat_waveform: np.ndarray            # length freq_stim+1
    time_step_s: np.ndarray                  # seconds, for the analyzed window
    force_step_smoothed: np.ndarray
    stimulus_locs: np.ndarray
    y_match_peaks: np.ndarray
    contraction_peak_locs: np.ndarray
    dist_between_beats: np.ndarray           # for Poincare
    force_step_edit: np.ndarray              # force with beats removed, for this window
    dt_velocity_curve: np.ndarray            # sgolay-filtered derivative curve
    markers_ms: np.ndarray                   # [c90,c75,c50,r90,r75,r50]
    beat_waveforms: np.ndarray = field(default_factory=lambda: np.zeros((1001, 0)))  # (freq_stim+1) x n_beats, individual beats
    length_ratio: float = np.nan             # length_step / initial_length, for plot titles
    freq_stim: int = 1000                    # detected inter-beat interval (samples/ms) for this stretch
    work_mN_mm: float = np.nan


# --------------------------------------------------------------------------
# File loading
# --------------------------------------------------------------------------

def load_file(path: str, cfg: FileFormatConfig) -> LoadedFile:
    """Equivalent of SelectedFilesListBoxValueChanged: reads the raw data
    file, slices out the analysis window, and detects (or applies manual)
    length-change triggers."""
    data = np.loadtxt(path, skiprows=cfg.non_data_lines)

    # data_start / data_end are ALREADY 1-indexed rows within the
    # header-stripped array (see FileFormatConfig's docstring) -- the
    # MATLAB app resolves the header subtraction once, at the moment the
    # value is set, not every time a file is loaded. Use them directly,
    # matching data_8x(Data_Start:Data_End,:).
    start0 = cfg.data_start - 1   # convert 1-indexed inclusive start to python 0-indexed
    end0 = cfg.data_end           # python slice end is exclusive == inclusive end
    sl = slice(start0, end0)

    time_data = data[sl, cfg.time_col - 1] / 60000.0     # minutes
    length_data = data[sl, cfg.length_col - 1]
    force_data = data[sl, cfg.force_col - 1]
    stim_data = data[sl, cfg.stim_col - 1]

    if cfg.initial_length_mm is not None:
        initial_length = cfg.initial_length_mm
    else:
        initial_length = round(float(np.mean(length_data[99:400])), 3)

    if cfg.trigger_points is not None and len(cfg.trigger_points) > 0:
        # trigger_points, once set via "Manually Assign Stretch Timepoints",
        # are already fully resolved sample offsets relative to the start
        # of the analysis window (see FileFormatConfig's docstring) --
        # exactly what detect_length_triggers() itself returns for the
        # automatic path, so both feed the rest of the pipeline identically.
        trig = np.asarray(cfg.trigger_points, dtype=float)
        trig = trig[trig >= 0]
        trigger = np.round(trig).astype(int)
    else:
        trigger = detect_length_triggers(length_data)

    trigger = trigger[trigger != 0]
    total_stretches = max(0, len(trigger) - 1)

    return LoadedFile(
        time_min=time_data,
        length_mm=length_data,
        force_mN=force_data,
        stimulus=stim_data,
        trigger=trigger,
        initial_length_mm=initial_length,
        total_stretches=total_stretches,
        force_wo_peak=np.full(len(force_data), np.nan),
    )


# --------------------------------------------------------------------------
# Per-stretch analysis
# --------------------------------------------------------------------------

def analyze_stretch_preview(lf: LoadedFile, stretch_1idx: int, stim_value: float):
    """First half of SelectStretchtoPlotAnalyzeListBoxClicked: everything up
    to (but not including) the user's beat selection. Returns the data
    needed to draw the labeled preview plot and to build the peak-selection
    dialog defaults.

    stretch_1idx is 1-indexed (Stretch_1 .. Stretch_N), matching the
    MATLAB listbox.
    """
    i = stretch_1idx  # MATLAB "current_stretch"
    lo = lf.trigger[i - 1] - 100
    hi = lf.trigger[i] + 1   # MATLAB's trigger(i+1) is an inclusive upper bound; +1 makes the Python slice inclusive too
    if lo < 0:
        lo = 0

    length_step = lf.length_mm[lo:hi]
    time_step = lf.time_min[lo:hi] * 60.0   # seconds
    force_step = lf.force_mN[lo:hi]
    stimulus_step = lf.stimulus[lo:hi]

    # find stimulus points where beat starts: keep only the LAST sample of
    # each contiguous run of stimulus==stim_value (matches MATLAB's
    # true_stim = diff(stimulus_locs)>1; stimulus_locs(true_stim==0) = [] --
    # true_stim(i) reflects the gap AFTER stimulus_locs(i), so deleting
    # where true_stim==0 keeps only the sample immediately before each gap,
    # i.e. the last sample of each run)
    stimulus_locs_all = np.where(stimulus_step == stim_value)[0]
    if len(stimulus_locs_all) > 1:
        keep = np.append(np.diff(stimulus_locs_all) > 1, True)
        stimulus_locs = stimulus_locs_all[keep]
    else:
        stimulus_locs = stimulus_locs_all
    if len(stimulus_locs) > 0:
        stimulus_locs = stimulus_locs[:-1]  # drop last (matches MATLAB stimulus_locs(1:end-1))

    # MATLAB's source computes app.freq_stim=floor(mean(diff(stimulus_locs))),
    # but a plain mean is not robust to a missed/extra trigger detection --
    # a single missed trigger doubles that one gap and measurably skews the
    # mean, which then narrows every downstream per-beat window and can
    # cause otherwise-good beats to fail peak detection. median() gives the
    # same answer as mean() whenever the data is clean (verified against
    # all 4 real files) but stays exactly correct even with several missed
    # triggers scattered through a stretch, so it's used here in place of
    # the literal formula.
    if len(stimulus_locs) > 1:
        freq_stim = int(np.floor(np.median(np.diff(stimulus_locs))))
    else:
        freq_stim = 1000
    freq_stim = max(freq_stim, 1)

    force_smooth25 = smooth(force_step, 25)
    _, contraction_peak_locs = find_peaks_matlab(force_smooth25, 0.01, 0.9 * freq_stim)

    n_time = len(time_step)
    bpm = nearest((len(contraction_peak_locs) * 60000.0) / n_time) if n_time else 0.0

    if len(force_step) > 100:
        movavg_peaks = moving_average_trailing(smooth(force_step[:-100], 25), freq_stim)
    else:
        movavg_peaks = moving_average_trailing(smooth(force_step, 25), freq_stim)
    sample_idx = np.arange(freq_stim - 1, len(movavg_peaks), freq_stim)
    y_samples = movavg_peaks[sample_idx] if len(sample_idx) else np.array([])
    # MATLAB: y_match_peaks = resize(y_match_peaks, size(stimulus_locs)) --
    # truncates/pads to length rather than interpolating/stretching (this
    # only affects where the small stimulus-location tick marks sit on the
    # preview plots, not any exported number, so an exact resize() replica
    # isn't necessary -- truncate if too long, repeat the last value if
    # too short).
    if len(y_samples) and len(stimulus_locs):
        n = len(stimulus_locs)
        if len(y_samples) >= n:
            y_match_peaks = y_samples[:n]
        else:
            y_match_peaks = np.pad(y_samples, (0, n - len(y_samples)), mode="edge")
    else:
        y_match_peaks = np.full(len(stimulus_locs), np.nanmean(force_step) if len(force_step) else 0.0)

    labels = [str(k) for k in range(1, len(stimulus_locs) + 1)]
    # MATLAB: mean(length_step(100:500)) -- replaced a fixed sample-30000
    # lookup (which assumed a long, ~1 Hz-paced window) with an average
    # over a small window near the start of the step, robust to whatever
    # the actual window length/pacing turns out to be.
    if len(length_step) > 99:
        length_ratio = round(float(np.mean(length_step[99:500])) / lf.initial_length_mm, 3)
    elif len(length_step):
        length_ratio = round(float(np.mean(length_step)) / lf.initial_length_mm, 3)
    else:
        length_ratio = np.nan

    return {
        "i": i, "lo": lo, "hi": hi,
        "length_step": length_step, "time_step": time_step,
        "force_step": force_step, "stimulus_step": stimulus_step,
        "force_smooth25": force_smooth25,
        "contraction_peak_locs": contraction_peak_locs, "bpm": bpm,
        "stimulus_locs": stimulus_locs, "y_match_peaks": y_match_peaks,
        "labels": labels, "length_ratio": length_ratio, "freq_stim": freq_stim,
    }


def default_peak_selection(preview: dict, n_beats: int) -> list[int]:
    """Matches: input = arrayfun(@(x) labels{numel(labels)-x+1}, 1:InputBeats)
    i.e. default to the LAST n_beats labeled peaks, most-recent first."""
    n_labels = len(preview["labels"])
    n_beats = min(n_beats, n_labels)
    return [n_labels - x + 1 for x in range(1, n_beats + 1)]


def analyze_stretch_beats(lf: LoadedFile, preview: dict, peak_numbers: list[int]) -> StretchResult:
    """Second half of SelectStretchtoPlotAnalyzeListBoxClicked: given the
    user's chosen peak numbers (1-indexed, into preview['stimulus_locs']),
    compute all per-beat and per-stretch metrics."""
    i = preview["i"]
    force_step = preview["force_step"]
    stimulus_locs = preview["stimulus_locs"]
    length_step = preview["length_step"]
    freq_stim = preview["freq_stim"]
    n_beats = len(peak_numbers)

    height_peaks = np.full(n_beats, np.nan)
    valley_peaks = np.full(n_beats, np.nan)
    c90 = np.full(n_beats, np.nan)
    c75 = np.full(n_beats, np.nan)
    c50 = np.full(n_beats, np.nan)
    r90 = np.full(n_beats, np.nan)
    r75 = np.full(n_beats, np.nan)
    r50 = np.full(n_beats, np.nan)
    integral_per_beat = np.full(n_beats, np.nan)
    last_n_beats = np.full((freq_stim + 1, n_beats), np.nan)

    for k, peak_no in enumerate(peak_numbers):
        loc = stimulus_locs[peak_no - 1]
        seg_lo = max(0, loc - freq_stim)
        seg = force_step[seg_lo:loc + 1]  # MATLAB (loc-freq_stim):loc is inclusive on both ends -> freq_stim+1 samples
        if len(seg) < freq_stim + 1:
            seg = np.pad(seg, (freq_stim + 1 - len(seg), 0), mode="edge")
        last_n_peaks = smooth(seg, 25)
        last_n_beats[:, k] = last_n_peaks

        try:
            # MinPeakProminence lowered from 0.05 to 0.01, and MinPeakDistance
            # now scales with the detected stimulation frequency (0.9*freq_stim)
            # instead of a hard-coded 900, matching the updated MATLAB source --
            # both improve detection of beats at frequencies other than ~1 Hz.
            peak_vals, peak_locs = find_peaks_matlab(last_n_peaks, 0.01, 0.9 * freq_stim)
            if len(peak_vals) == 0:
                raise ValueError("no peak")
            current_active_peak = peak_vals[0]
            current_active_peak_locs = peak_locs[0]

            height_peaks[k] = current_active_peak
            valley_peaks[k] = last_n_peaks[0]

            norm_beat = last_n_peaks - last_n_peaks[0]

            def first_cross(mask_slice, base_offset):
                """Returns MATLAB's exact find(...,1,'first') convention:
                the 1-indexed position within the slice, plus base_offset.
                idx (0-indexed position within the slice) + 1 reproduces
                MATLAB's 1-indexed find() result directly."""
                idx = np.where(mask_slice)[0]
                return (idx[0] + base_offset) if len(idx) else np.nan

            up_target = norm_beat[current_active_peak_locs] * 0.9
            c90[k] = first_cross(norm_beat[:current_active_peak_locs + 1] - up_target > 0, 1)
            up_target = norm_beat[current_active_peak_locs] * 0.75
            c75[k] = first_cross(norm_beat[:current_active_peak_locs + 1] - up_target > 0, 1)
            up_target = norm_beat[current_active_peak_locs] * 0.5
            c50[k] = first_cross(norm_beat[:current_active_peak_locs + 1] - up_target > 0, 1)

            # MATLAB: current_active_peak_locs + find(...,1,'first') -- the
            # find() here is 1-indexed *within a slice that itself starts
            # at current_active_peak_locs* (not current_active_peak_locs+1),
            # so MATLAB's own addition ends up one further than the crossing's
            # actual array position. Reproduced exactly via the +2 constant:
            # idx (0-indexed, within the same slice) + current_active_peak_locs
            # (0-indexed) + 2 == MATLAB's (1-indexed peak) + (1-indexed find).
            down_target = norm_beat[current_active_peak_locs] * 0.1
            r90[k] = first_cross(norm_beat[current_active_peak_locs:] - down_target < 0, current_active_peak_locs + 2)
            down_target = norm_beat[current_active_peak_locs] * 0.25
            r75[k] = first_cross(norm_beat[current_active_peak_locs:] - down_target < 0, current_active_peak_locs + 2)
            down_target = norm_beat[current_active_peak_locs] * 0.5
            r50[k] = first_cross(norm_beat[current_active_peak_locs:] - down_target < 0, current_active_peak_locs + 2)

            integral_per_beat[k] = _trapz(norm_beat)
        except Exception:
            height_peaks[k] = np.nan
            valley_peaks[k] = np.nan

    # a stretch where every beat's peak detection failed (e.g. freq_stim was
    # thrown off by an irregular stimulus gap elsewhere in this window) will
    # have all-NaN inputs here; the resulting NaN outputs are correct and
    # expected (matching MATLAB's own NaN-on-catch fallback) -- just silence
    # numpy's "Mean of empty slice" noise about it.
    with warnings.catch_warnings():
        warnings.simplefilter("ignore", category=RuntimeWarning)
        avg_last_n_beats = np.nanmean(last_n_beats, axis=1)
        integral_force_per_step = np.nanmean(integral_per_beat)

        contraction_90pct = np.nanmean(c90)
        contraction_75pct = np.nanmean(c75)
        contraction_50pct = np.nanmean(c50)
        relaxation_90pct = np.nanmean(r90)
        relaxation_75pct = np.nanmean(r75)
        relaxation_50pct = np.nanmean(r50)

    d_avg = np.diff(avg_last_n_beats)
    window = 81 if len(d_avg) >= 81 else (len(d_avg) - (1 - len(d_avg) % 2))
    if window >= 5:
        if window % 2 == 0:
            window -= 1
        df_dt = savgol_filter(d_avg, window_length=window, polyorder=2)
    else:
        df_dt = d_avg.copy()

    contraction_velocity = float(np.nanmax(df_dt) * 1000) if len(df_dt) else np.nan
    # relaxation_velocity=abs(min(df_dt(100:end)))*1000; -- MATLAB uses a
    # fixed cutoff (skip the first 100 samples of df_dt, 1-indexed) rather
    # than searching from the contraction-peak index onward. MATLAB's
    # df_dt(100:end) is 1-indexed inclusive, so the equivalent 0-indexed
    # Python slice starts at 99.
    relaxation_velocity = float(abs(np.nanmin(df_dt[99:])) * 1000) if len(df_dt) > 99 else np.nan

    markers = np.array([contraction_50pct, contraction_75pct, contraction_90pct,
                         relaxation_50pct, relaxation_75pct, relaxation_90pct])
    if np.any(np.isnan(markers)):
        markers = np.ones(6)

    dist_beats = np.diff(preview["contraction_peak_locs"])

    force_step_edit = smooth(force_step, 25).copy()
    n_peaks = len(preview["contraction_peak_locs"])
    for p in range(n_peaks):
        if p < len(stimulus_locs):
            s = stimulus_locs[p]
            e = int(s + np.floor(relaxation_90pct if not np.isnan(relaxation_90pct) else 0) + 50)
            e = min(e, len(force_step_edit))
            if s < e:
                force_step_edit[s:e] = np.nan
    force_step_edit = _fillmissing_movmedian(force_step_edit, 500)

    result = _build_stretch_result(
        i, length_step, valley_peaks, height_peaks, preview, contraction_90pct,
        contraction_75pct, contraction_50pct, relaxation_90pct, relaxation_75pct,
        relaxation_50pct, contraction_velocity, relaxation_velocity,
        integral_force_per_step, avg_last_n_beats, dist_beats, force_step_edit,
        df_dt, markers,
    )
    result.beat_waveforms = last_n_beats
    result.length_ratio = preview["length_ratio"]
    result.freq_stim = freq_stim
    return result


def _build_stretch_result(i, length_step, valley_peaks, height_peaks, preview,
                           contraction_90pct, contraction_75pct, contraction_50pct,
                           relaxation_90pct, relaxation_75pct, relaxation_50pct,
                           contraction_velocity, relaxation_velocity,
                           integral_force_per_step, avg_last_n_beats, dist_beats,
                           force_step_edit, df_dt, markers) -> StretchResult:
    def r(v):
        return round(float(v), 3) if v is not None and not (isinstance(v, float) and np.isnan(v)) else np.nan

    # MATLAB: mean(length_step(100:500)) -- see analyze_stretch_preview's
    # length_ratio for why this replaced a fixed sample-30000 lookup.
    if len(length_step) > 99:
        length_val = float(np.mean(length_step[99:500]))
    elif len(length_step):
        length_val = float(np.mean(length_step))
    else:
        length_val = np.nan

    with warnings.catch_warnings():
        warnings.simplefilter("ignore", category=RuntimeWarning)
        passive_val = np.nanmean(valley_peaks)
        active_val = np.nanmean(height_peaks - valley_peaks)

    return StretchResult(
        stretch_index=i,
        length_mm=r(length_val),
        passive_force_mN=r(passive_val),
        active_force_mN=r(active_val),
        bpm=r(preview["bpm"]),
        contraction_90pct_ms=r(contraction_90pct),
        contraction_75pct_ms=r(contraction_75pct),
        contraction_50pct_ms=r(contraction_50pct),
        relaxation_90pct_ms=r(relaxation_90pct),
        relaxation_75pct_ms=r(relaxation_75pct),
        relaxation_50pct_ms=r(relaxation_50pct),
        contraction_velocity=r(contraction_velocity),
        relaxation_velocity=r(relaxation_velocity),
        force_integral=r(integral_force_per_step),
        avg_beat_waveform=avg_last_n_beats,
        time_step_s=preview["time_step"],
        force_step_smoothed=preview["force_smooth25"],
        stimulus_locs=preview["stimulus_locs"],
        y_match_peaks=preview["y_match_peaks"],
        contraction_peak_locs=preview["contraction_peak_locs"],
        dist_between_beats=dist_beats,
        force_step_edit=force_step_edit,
        dt_velocity_curve=df_dt,
        markers_ms=markers,
    )


def _fillmissing_movmedian(x: np.ndarray, window: int) -> np.ndarray:
    """Approximates MATLAB's fillmissing(x,'movmedian',window): fills NaNs
    using the median of the surrounding `window` samples (centered),
    iterated until no NaNs remain (matches the MATLAB code's per-peak loop
    which re-runs fillmissing after each peak is blanked)."""
    x = x.copy()
    half = window // 2
    nan_mask = np.isnan(x)
    if not nan_mask.any():
        return x
    idxs = np.where(nan_mask)[0]
    valid = ~nan_mask
    for idx in idxs:
        lo = max(0, idx - half)
        hi = min(len(x), idx + half + 1)
        window_vals = x[lo:hi]
        window_valid = window_vals[~np.isnan(window_vals)]
        if len(window_valid):
            x[idx] = np.median(window_valid)
    # any leftover NaNs (fully NaN neighborhoods) -> forward/back fill
    if np.isnan(x).any():
        good = ~np.isnan(x)
        if good.any():
            x = np.interp(np.arange(len(x)), np.where(good)[0], x[good])
        else:
            x[:] = 0.0
    return x


# --------------------------------------------------------------------------
# Combine Selected Stretches (Frank-Starling + Poincare-all)
# --------------------------------------------------------------------------

@dataclass
class CombinedResult:
    data_output: np.ndarray            # (total_stretches, 17) matches EXCEL_TABS minus header col
    length_change: np.ndarray
    active_force_fit: tuple
    passive_force_fit: tuple
    sd1: float
    sd2: float
    sd12: float
    all_dist_beats: np.ndarray


def combine_stretches(stretch_results: dict[int, StretchResult], initial_length_mm: float,
                       total_stretches: Optional[int] = None) -> CombinedResult:
    """Equivalent of CombineSelectedStretchesButtonPushed. stretch_results
    keys are 1-indexed stretch numbers. Pass total_stretches (e.g.
    LoadedFile.total_stretches) so the output table has one row per stretch
    in the protocol even if some weren't analyzed yet, matching MATLAB's
    preallocated DataOutput=NaN(total_stretches,...)."""
    n = total_stretches if total_stretches is not None else max(stretch_results.keys())
    data = np.full((n, 17), np.nan)
    all_dist_beats = []
    for idx, res in sorted(stretch_results.items()):
        work = res.force_integral * res.length_mm if not np.isnan(res.force_integral) else np.nan
        row = [res.length_mm, res.passive_force_mN, res.active_force_mN, res.bpm,
               res.contraction_90pct_ms, res.contraction_75pct_ms, res.contraction_50pct_ms,
               res.relaxation_90pct_ms, res.relaxation_75pct_ms, res.relaxation_50pct_ms,
               res.contraction_velocity, res.relaxation_velocity, res.force_integral,
               round(work, 3) if not np.isnan(work) else np.nan, np.nan, np.nan, np.nan]
        data[idx - 1, :] = row
        all_dist_beats.append(res.dist_between_beats)

    length_change = data[:, 0] / initial_length_mm
    active_force = data[:, 2]
    passive_force = data[:, 1]

    valid = ~np.isnan(length_change) & ~np.isnan(active_force)
    active_fit = np.polyfit(length_change[valid], active_force[valid], 2) if valid.sum() >= 3 else None
    valid_p = ~np.isnan(length_change) & ~np.isnan(passive_force)
    passive_fit = np.polyfit(length_change[valid_p], passive_force[valid_p], 2) if valid_p.sum() >= 3 else None

    all_beats = np.concatenate(all_dist_beats) if all_dist_beats else np.array([])
    if len(all_beats) > 2:
        RR = all_beats[:-1]
        RRp1 = all_beats[1:]
        sd1 = round(float(np.std(RR - RRp1, ddof=1) / np.sqrt(2)), 3)
        sd2 = round(float(np.std(RR + RRp1, ddof=1) / np.sqrt(2)), 3)
        sd12 = round(sd1 / sd2, 3) if sd2 else np.nan
    else:
        sd1 = sd2 = sd12 = np.nan

    data[0, 14:17] = [sd1, sd2, sd12]

    return CombinedResult(
        data_output=data, length_change=length_change,
        active_force_fit=(active_fit, length_change, active_force),
        passive_force_fit=(passive_fit, length_change, passive_force),
        sd1=sd1, sd2=sd2, sd12=sd12, all_dist_beats=all_beats,
    )
