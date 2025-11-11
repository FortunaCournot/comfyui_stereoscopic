import os
import time
import threading
from statistics import mean
from queue import Queue
import psutil
import matplotlib.pyplot as plt


# ---------- 1) Memory Monitor: Python + Child Processes ----------
class MemoryMonitor:
    def __init__(self, interval: float = 0.5, include_children: bool = True):
        self.interval = interval
        self.include_children = include_children
        self._stop_flag = threading.Event()
        self._thread = None
        self._rss_samples = []
        self._t0 = None
        self._t_samples = []

    def _monitor(self):
        pid = os.getpid()
        process = psutil.Process(pid)
        self._t0 = time.perf_counter()
        while not self._stop_flag.is_set():
            try:
                rss = process.memory_info().rss
                if self.include_children:
                    for child in process.children(recursive=True):
                        try:
                            rss += child.memory_info().rss
                        except psutil.NoSuchProcess:
                            pass
                self._rss_samples.append(rss)
                self._t_samples.append(time.perf_counter() - self._t0)
            except psutil.NoSuchProcess:
                break
            time.sleep(self.interval)

    def start(self):
        if self._thread is None:
            self._thread = threading.Thread(target=self._monitor, daemon=True)
            self._thread.start()

    def stop(self):
        self._stop_flag.set()
        if self._thread is not None:
            self._thread.join()

    def report(self):
        if not self._rss_samples:
            return None
        return {
            "RSS_avg_MB": round(mean(self._rss_samples) / 1024**2),
            "RSS_max_MB": round(max(self._rss_samples) / 1024**2)
        }

    def plot(self, show: bool = True, save_path: str | None = None):
        if not self._rss_samples:
            return
        plt.figure()
        plt.plot(self._t_samples, [x / 1024**2 for x in self._rss_samples], label="RSS MB")
        plt.xlabel("Time, s")
        plt.ylabel("Memory, MB")
        plt.title("Memory usage over time")
        plt.legend()
        if save_path:
            plt.savefig(save_path, bbox_inches="tight")
        if show:
            plt.show()
        plt.close()


# ---------- 2) Queue Monitor ----------
class QueueMonitor:
    """
    Measures qsize() of several queues with a given interval.
    Stores time series and calculates avg/max for each queue.
    Can plot a graph: all queues on one graph.
    """
    def __init__(self, queues: dict[str, Queue], interval: float = 0.5):
        """
        queues: dictionary {name: queue.Queue()}
        interval: polling period, sec
        """
        self.queues = queues
        self.interval = interval
        self._stop_flag = threading.Event()
        self._thread = None
        self._t0 = None

        # Time series: {name: {"t": [...], "size": [...], "maxsize": int}}
        self._series = {name: {"t": [], "size": [], "maxsize": q.maxsize} for name, q in queues.items()}

    def _monitor(self):
        self._t0 = time.perf_counter()
        while not self._stop_flag.is_set():
            now = time.perf_counter() - self._t0
            for name, q in self.queues.items():
                try:
                    sz = q.qsize()
                except NotImplementedError:
                    # just in case for exotic queues
                    sz = 0
                self._series[name]["t"].append(now)
                self._series[name]["size"].append(sz)
            time.sleep(self.interval)

    def start(self):
        if self._thread is None:
            self._thread = threading.Thread(target=self._monitor, daemon=True)
            self._thread.start()

    def stop(self):
        self._stop_flag.set()
        if self._thread is not None:
            self._thread.join()

    def stats(self) -> dict:
        """
        Returns a dictionary with avg/max and average % fill
        """
        out = {}
        for name, s in self._series.items():
            sizes = s["size"]
            if sizes:
                avg = mean(sizes)
                mx = max(sizes)
                cap = s["maxsize"] or 0
                avg_pct = (avg / cap * 100) if cap else None
                max_pct = (mx / cap * 100) if cap else None
                out[name] = {
                    "avg_size": round(avg, 2),
                    "max_size": mx,
                    "capacity": cap,
                    "avg_fill_pct": round(avg_pct, 1) if avg_pct is not None else None,
                    "max_fill_pct": round(max_pct, 1) if max_pct is not None else None,
                }
            else:
                out[name] = {"avg_size": None, "max_size": None, "capacity": s["maxsize"],
                             "avg_fill_pct": None, "max_fill_pct": None}
        return out

    def plot(self, show: bool = True, save_path: str | None = None, with_capacity: bool = True):
        """
        Draws all queues on one graph.
        """
        plt.figure()
        for name, s in self._series.items():
            if s["t"]:
                plt.plot(s["t"], s["size"], label=name)
        plt.xlabel("Time, s")
        plt.ylabel("Queue size (items)")
        plt.title("Queues over time")

        if with_capacity:
            # horizontal lines to the capacity using a dotted line
            for name, s in self._series.items():
                cap = s["maxsize"]
                if cap:  # 0 or None — "unlimited" queue
                    tmax = s["t"][-1] if s["t"] else 0
                    # draw a short line at the end so that the legend doesn't get cluttered
                    plt.hlines(cap, xmin=max(0, tmax - 1), xmax=tmax, linestyles="dashed")

        plt.legend()
        if save_path:
            plt.savefig(save_path, bbox_inches="tight")
        if show:
            plt.show()
        plt.close()
