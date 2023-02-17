#!/usr/bin/env python3
import argparse
import concurrent.futures
from dataclasses import dataclass
import functools
import os
import time

from typing import Any, List

import psutil
import librosa
import numpy as np

import babycat


DEFAULT_FRAME_RATE_HZ = 44100
DEFAULT_NUM_WORKERS = 0
DEFAULT_REPEAT = 20

DEFAULT_FILENAMES = [
    f"/audio/{name}/track.mp3"
    for name in [
        "andreas-theme",
        "blippy-trance",
        "circus-of-freaks",
        "left-channel-tone",
        "on-hold-for-you",
        "voxel-revolution",
    ]
]

@dataclass
class Result:
    data: List[Any]
    args: Any
    elapsed_time: float
    elapsed_memory: float


def memory_bytes() -> int:
    process = psutil.Process(os.getpid())
    return process.memory_info().rss


def bench(func):
    @functools.wraps(func)
    def wrapped(
        *args,
        **kwargs,
    ):
        start_memory = memory_bytes()
        start_time = time.perf_counter()
        data = func(
            *args, **kwargs
        )
        end_time = time.perf_counter()
        end_memory = memory_bytes()
        return Result(
            data=data,
            args=args,
            elapsed_time=end_time - start_time,
            elapsed_memory=end_memory - start_memory
        )
    return wrapped


@bench
def babycat_benchmark(
    *,
    repeated_filenames: List[str],
    args,
) -> Result:
    return babycat.batch.waveforms_from_files_into_numpys_unwrapped(
        filenames=repeated_filenames,
        frame_rate_hz=args.frame_rate_hz,
        num_workers=args.num_workers,
    )


@bench
def librosa_benchmark(
    *,
    repeated_filenames: List[str],
    args,
):
    max_workers = args.num_workers or None
    def _load(path):
        return librosa.load(path, sr=args.frame_rate_hz, mono=False, offset=0.0, duration=None, dtype=np.float32)
    with concurrent.futures.ThreadPoolExecutor(max_workers=max_workers) as executor:
        values = [
            waveform.swapaxes(0,1)
            for waveform, _frame_rate in executor.map(_load, repeated_filenames)
        ]
        return values


def run_benchmark(
    fn,
    filenames: List[str],
    args,
):
    repeated_filenames = filenames * args.repeat
    print("Beginning benchmark", flush=True)
    results = fn(
        repeated_filenames=repeated_filenames,
        args=args,
    )
    print("Benchmark completed", flush=True)

    total_frames = sum([len(r) for r in results.data])
    total_seconds = total_frames / args.frame_rate_hz
    print(f"""Benchmark results:
Memory allocated: {results.elapsed_memory} bytes ({results.elapsed_memory / 1024**3} GiB)
Frames decoded: {total_frames}
Time decoded: {total_seconds} seconds ({total_seconds / 60} minutes)
Elapsed: {results.elapsed_time} seconds
""",
        flush=True
    )


def main():
    parser = argparse.ArgumentParser(
        prog = "benchmark",
        description = "Runs Babycat benchmarks",
        epilog = "Text at the bottom of help"
    )
    parser.add_argument("--library", choices=["babycat", "librosa"], required=True)
    parser.add_argument("--frame-rate-hz", type=int, default=DEFAULT_FRAME_RATE_HZ)
    parser.add_argument("--num-workers", type=int, default=DEFAULT_NUM_WORKERS)
    parser.add_argument("--repeat", type=int, default=DEFAULT_REPEAT)
    parser.add_argument(
        "--convert-to-mono",
        action='store_true'
    )
    args = parser.parse_args()
    kw = dict(
        filenames=DEFAULT_FILENAMES,
        args=args,
    )
    if args.library == "babycat":
        run_benchmark(
            fn=babycat_benchmark,
            **kw,
        )
    elif args.library == "librosa":
        run_benchmark(
            fn=librosa_benchmark,
            **kw,
        )

if __name__ == "__main__":
    main()
