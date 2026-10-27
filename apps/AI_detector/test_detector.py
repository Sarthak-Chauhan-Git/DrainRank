#!/usr/bin/env python3
"""
Test harness for EfficientDet-Lite0 (TFLite, COCO, uint8 320x320).

Usage:
  python test_detector.py detect img1.jpg img2.jpg [--thr 0.1] [--out out/]
  python test_detector.py video clip.mp4|0 [--thr 0.1]        # 0 = webcam, q to quit
  python test_detector.py bench [--runs 100]                   # latency stats
  python test_detector.py eval images/ labels.json             # precision/recall vs ground truth
  python test_detector.py selftest [image.jpg]                 # sanity checks

labels.json format for `eval`: {"img.jpg": [{"label":"person","box":[x1,y1,x2,y2]}, ...]}  (pixel coords)

Deps: pip install ai-edge-litert opencv-python numpy   (or tflite-runtime / tensorflow)
"""
import argparse, json, sys, time, zipfile
from pathlib import Path

import cv2
import numpy as np

try:
    from ai_edge_litert.interpreter import Interpreter
except ImportError:
    try:
        from tflite_runtime.interpreter import Interpreter
    except ImportError:
        from tensorflow.lite.python.interpreter import Interpreter

MODEL = Path(__file__).with_name("1.tflite")


class Detector:
    def __init__(self, model_path=MODEL, num_threads=4):
        self.it = Interpreter(model_path=str(model_path), num_threads=num_threads)
        self.it.allocate_tensors()
        inp = self.it.get_input_details()[0]
        self.in_idx, self.in_dtype = inp["index"], inp["dtype"]
        _, self.h, self.w, _ = inp["shape"]
        # labelmap is zipped inside the .tflite (metadata)
        with zipfile.ZipFile(model_path) as z:
            self.labels = z.read("labelmap.txt").decode().splitlines()
        # Map outputs by shape/content rather than trusting tensor order
        self.out = {}
        for d in self.it.get_output_details():
            s = tuple(d["shape"])
            if len(s) == 3 and s[-1] == 4:
                self.out["boxes"] = d["index"]
            elif s == (1,):
                self.out["count"] = d["index"]
            else:
                self.out.setdefault("_2d", []).append(d["index"])
        self._2d_resolved = False

    def _resolve_2d(self):
        # scores in [0,1] and sorted desc; classes are whole numbers (can be >1)
        a, b = [self.it.get_tensor(i)[0] for i in self.out["_2d"]]
        a_is_scores = a.max() <= 1.0 and np.all(np.diff(a) <= 1e-6)
        self.out["scores"], self.out["classes"] = (
            self.out["_2d"] if a_is_scores else self.out["_2d"][::-1]
        )
        self._2d_resolved = True

    def detect(self, bgr, thr=0.1):
        """bgr: HxWx3 uint8 (OpenCV). Returns list of dicts, pixel coords on the ORIGINAL image."""
        H, W = bgr.shape[:2]
        rgb = cv2.cvtColor(cv2.resize(bgr, (self.w, self.h)), cv2.COLOR_BGR2RGB)
        self.it.set_tensor(self.in_idx, rgb[None].astype(self.in_dtype))
        self.it.invoke()
        if not self._2d_resolved:
            self._resolve_2d()
        g = lambda k: self.it.get_tensor(self.out[k])[0]
        boxes, scores, classes = g("boxes"), g("scores"), g("classes")
        n = int(self.it.get_tensor(self.out["count"])[0])
        dets = []
        for i in range(n):
            if scores[i] < thr:
                continue
            y1, x1, y2, x2 = boxes[i]  # normalized ymin,xmin,ymax,xmax
            c = int(classes[i])
            dets.append({
                "label": self.labels[c] if c < len(self.labels) else f"id{c}",
                "class_id": c,
                "score": float(scores[i]),
                "box": [max(0, x1 * W), max(0, y1 * H), min(W, x2 * W), min(H, y2 * H)],
            })
        return dets


def draw(img, dets):
    out = img.copy()
    rng = np.random.RandomState(7)
    colors = {}
    for d in dets:
        col = colors.setdefault(d["label"], tuple(int(x) for x in rng.randint(60, 255, 3)))
        x1, y1, x2, y2 = map(int, d["box"])
        cv2.rectangle(out, (x1, y1), (x2, y2), col, 2)
        txt = f'{d["label"]} {d["score"]:.2f}'
        (tw, th), _ = cv2.getTextSize(txt, cv2.FONT_HERSHEY_SIMPLEX, 0.5, 1)
        cv2.rectangle(out, (x1, max(0, y1 - th - 6)), (x1 + tw + 4, y1), col, -1)
        cv2.putText(out, txt, (x1 + 2, max(th, y1 - 4)), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (0, 0, 0), 1, cv2.LINE_AA)
    return out


def iou(a, b):
    ix1, iy1, ix2, iy2 = max(a[0], b[0]), max(a[1], b[1]), min(a[2], b[2]), min(a[3], b[3])
    inter = max(0, ix2 - ix1) * max(0, iy2 - iy1)
    ua = (a[2] - a[0]) * (a[3] - a[1]) + (b[2] - b[0]) * (b[3] - b[1]) - inter
    return inter / ua if ua > 0 else 0.0


# ---------------------------------------------------------------- commands
def cmd_detect(a):
    det = Detector()
    out_dir = Path(a.out); out_dir.mkdir(parents=True, exist_ok=True)
    for p in a.images:
        img = cv2.imread(p)
        if img is None:
            print(f"[skip] cannot read {p}"); continue
        t = time.perf_counter(); dets = det.detect(img, a.thr); ms = (time.perf_counter() - t) * 1e3
        print(f"\n{p}  ({ms:.1f} ms, {len(dets)} detections @ thr={a.thr})")
        for d in dets:
            print(f'  {d["label"]:<14} {d["score"]:.3f}  box={[int(v) for v in d["box"]]}')
        cv2.imwrite(str(out_dir / f"{Path(p).stem}_det.jpg"), draw(img, dets))
    print(f"\nAnnotated images -> {out_dir}/")


def cmd_video(a):
    det = Detector()
    cap = cv2.VideoCapture(int(a.source) if a.source.isdigit() else a.source)
    fps_hist = []
    while cap.isOpened():
        ok, frame = cap.read()
        if not ok: break
        t = time.perf_counter(); dets = det.detect(frame, a.thr); dt = time.perf_counter() - t
        fps_hist.append(1 / dt)
        vis = draw(frame, dets)
        cv2.putText(vis, f"{np.mean(fps_hist[-30:]):.1f} FPS", (10, 25), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (0, 255, 0), 2)
        cv2.imshow("EfficientDet-Lite0", vis)
        if cv2.waitKey(1) & 0xFF == ord("q"): break
    cap.release(); cv2.destroyAllWindows()


def cmd_bench(a):
    det = Detector()
    img = (np.random.RandomState(0).rand(480, 640, 3) * 255).astype(np.uint8)
    for _ in range(10): det.detect(img)  # warmup
    ts = []
    for _ in range(a.runs):
        t = time.perf_counter(); det.detect(img); ts.append((time.perf_counter() - t) * 1e3)
    ts = np.array(ts)
    print(f"runs={a.runs}  mean={ts.mean():.1f}ms  p50={np.percentile(ts,50):.1f}  "
          f"p95={np.percentile(ts,95):.1f}  p99={np.percentile(ts,99):.1f}  max={ts.max():.1f}  "
          f"-> {1000/ts.mean():.1f} FPS")


def cmd_eval(a):
    """Precision / recall / F1 at IoU>=a.iou and score>=a.thr, plus per-class breakdown."""
    det = Detector()
    gt_all = json.load(open(a.labels))
    stats = {}  # label -> [tp, fp, fn]
    for name, gts in gt_all.items():
        img = cv2.imread(str(Path(a.images_dir) / name))
        if img is None: print(f"[skip] {name}"); continue
        preds = sorted(det.detect(img, a.thr), key=lambda d: -d["score"])
        used = set()
        for p in preds:
            s = stats.setdefault(p["label"], [0, 0, 0])
            best, bj = 0, -1
            for j, g in enumerate(gts):
                if j in used or g["label"] != p["label"]: continue
                v = iou(p["box"], g["box"])
                if v > best: best, bj = v, j
            if best >= a.iou: s[0] += 1; used.add(bj)
            else: s[1] += 1
        for j, g in enumerate(gts):
            if j not in used: stats.setdefault(g["label"], [0, 0, 0])[2] += 1
    print(f"{'class':<14}{'TP':>5}{'FP':>5}{'FN':>5}{'prec':>8}{'rec':>8}{'F1':>8}")
    T = [0, 0, 0]
    for k, (tp, fp, fn) in sorted(stats.items()):
        T = [T[0] + tp, T[1] + fp, T[2] + fn]
        pr = tp / (tp + fp) if tp + fp else 0; rc = tp / (tp + fn) if tp + fn else 0
        print(f"{k:<14}{tp:>5}{fp:>5}{fn:>5}{pr:>8.2f}{rc:>8.2f}{2*pr*rc/(pr+rc+1e-9):>8.2f}")
    tp, fp, fn = T
    pr = tp / (tp + fp) if tp + fp else 0; rc = tp / (tp + fn) if tp + fn else 0
    print(f"{'ALL':<14}{tp:>5}{fp:>5}{fn:>5}{pr:>8.2f}{rc:>8.2f}{2*pr*rc/(pr+rc+1e-9):>8.2f}")


def cmd_selftest(a):
    det = Detector(); fails = 0
    def check(name, cond, info=""):
        nonlocal fails
        print(f"[{'PASS' if cond else 'FAIL'}] {name} {info}"); fails += (not cond)

    check("input is uint8 320x320", (det.h, det.w) == (320, 320) and det.in_dtype == np.uint8)
    check("labelmap loaded (90 entries)", len(det.labels) == 90, f"got {len(det.labels)}")

    blank = np.full((480, 640, 3), 127, np.uint8)
    check("blank image -> no detections @0.1", len(det.detect(blank, 0.1)) == 0)
    noise = (np.random.RandomState(1).rand(480, 640, 3) * 255).astype(np.uint8)
    check("noise image -> <=2 detections @0.5", len(det.detect(noise, 0.5)) <= 2)

    img = cv2.imread(a.image) if a.image else None
    if img is not None:
        d1, d2 = det.detect(img, 0.3), det.detect(img, 0.3)
        check("deterministic across runs", [x["box"] for x in d1] == [x["box"] for x in d2])
        check("scores sorted desc & in [0,1]", all(0 <= x["score"] <= 1 for x in d1)
              and [x["score"] for x in d1] == sorted([x["score"] for x in d1], reverse=True))
        H, W = img.shape[:2]
        check("boxes inside image & valid", all(0 <= x["box"][0] < x["box"][2] <= W and 0 <= x["box"][1] < x["box"][3] <= H for x in d1))
        # resolution invariance: half-size image should find mostly the same classes
        small = cv2.resize(img, (W // 2, H // 2))
        a_ = {x["label"] for x in d1 if x["score"] > .5}; b_ = {x["label"] for x in det.detect(small, .3) if x["score"] > .5}
        check("class set stable at 0.5x resolution", a_ <= b_ or len(a_ ^ b_) <= 1, f"{sorted(a_)} vs {sorted(b_)}")
        # flip equivariance
        f = cv2.flip(img, 1); df = det.detect(f, .3)
        check("horizontal flip keeps same top class", bool(d1) and bool(df) and d1[0]["label"] in {x["label"] for x in df[:3]})
        print("\ndetections on", a.image)
        for x in d1: print(f'  {x["label"]:<12}{x["score"]:.2f}')
    else:
        print("(pass an image to selftest for the content-based checks)")
    print(f"\n{'ALL PASSED' if not fails else str(fails) + ' FAILED'}")
    sys.exit(1 if fails else 0)


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("detect"); s.add_argument("images", nargs="+"); s.add_argument("--thr", type=float, default=0.1); s.add_argument("--out", default="out"); s.set_defaults(f=cmd_detect)
    s = sub.add_parser("video"); s.add_argument("source"); s.add_argument("--thr", type=float, default=0.1); s.set_defaults(f=cmd_video)
    s = sub.add_parser("bench"); s.add_argument("--runs", type=int, default=100); s.set_defaults(f=cmd_bench)
    s = sub.add_parser("eval"); s.add_argument("images_dir"); s.add_argument("labels"); s.add_argument("--thr", type=float, default=0.1); s.add_argument("--iou", type=float, default=0.5); s.set_defaults(f=cmd_eval)
    s = sub.add_parser("selftest"); s.add_argument("image", nargs="?"); s.set_defaults(f=cmd_selftest)
    a = ap.parse_args(); a.f(a)
