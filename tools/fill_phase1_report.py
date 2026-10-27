#!/usr/bin/env python3
"""Fill submission/phase1_report.md from the template + submission/phase1_report.json.

Numbers are copied straight from the measured JSON (never retyped) and the
`gcloud run services list` output is pasted raw. Run from the repo root:

    python tools/fill_phase1_report.py --image-size-mb 49

Review and edit the prose afterwards: it is a draft written from this deployment.
"""
from __future__ import annotations

import argparse
import json
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TEMPLATE = ROOT / "phase-1-echo-bot" / "report_template.md"
DATA = ROOT / "submission" / "phase1_report.json"
OUT = ROOT / "submission" / "phase1_report.md"


def ascii_hist(samples: list[float], bins: int = 8, width: int = 30) -> str:
    if not samples:
        return "(no samples)"
    lo, hi = min(samples), max(samples)
    step = (hi - lo) / bins or 1.0
    counts = [0] * bins
    for s in samples:
        counts[min(int((s - lo) / step), bins - 1)] += 1
    top = max(counts) or 1
    lines = []
    for i, c in enumerate(counts):
        a, b = lo + i * step, lo + (i + 1) * step
        lines.append(f"{a:8.1f}-{b:8.1f} ms | {'#' * round(c / top * width):<{width}} {c}")
    return "\n".join(lines)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--image-size-mb", required=True)
    args = ap.parse_args()

    rep = json.loads(DATA.read_text())
    p = rep["platforms"]
    services = subprocess.run(
        ["gcloud", "run", "services", "list"], capture_output=True, text=True
    )
    services_out = (services.stdout + services.stderr).rstrip()

    plot = ["Warm latency distribution (20 requests each, from submission/phase1_report.json)", ""]
    for name, label in (("vm", "IaaS VM"), ("cloudrun", "Cloud Run"), ("function", "Cloud Function")):
        st = p[name]["stats"]
        plot.append(f"{label}: cold={p[name]['cold_ms']} ms, warm min/median/p95/max = "
                    f"{st['min']}/{st['median']}/{st['p95']}/{st['max']} ms")
        plot.append(ascii_hist(p[name]["warm_ms"]))
        plot.append("")
    latency_plot = "```text\n" + "\n".join(plot).rstrip() + "\n```"

    answers = {
        "image_size_mb": str(args.image_size_mb),
        "vpc_name": "echo-net",
        "subnet_name": "echo-subnet",
        "vm_cold_ms": str(p["vm"]["cold_ms"]),
        "vm_warm_median_ms": str(p["vm"]["stats"]["median"]),
        "cloudrun_cold_ms": str(p["cloudrun"]["cold_ms"]),
        "cloudrun_warm_median_ms": str(p["cloudrun"]["stats"]["median"]),
        "function_cold_ms": str(p["function"]["cold_ms"]),
        "function_warm_median_ms": str(p["function"]["stats"]["median"]),
        "latency_plot": latency_plot,
        "scaling_behaviour": (
            "VM: nothing is created automatically. One e2-micro (2 shared vCPUs, 1 GB RAM) runs "
            "one container with gunicorn (1 worker, 8 threads); ten or a hundred concurrent "
            "requests just queue on that machine. The limit is the machine type I picked. "
            "Cloud Run: new container instances of my image are started as concurrency grows "
            "(up to 80 requests per instance by default), and scaled back to zero when idle; the "
            "hard cap is the --max-instances=3 flag I passed. Cloud Function (gen 2): the same "
            "mechanism, since it is a Cloud Run service; each instance takes one request at a "
            "time (maxInstanceRequestConcurrency: 1), so it adds instances sooner, bounded by the "
            "function's max-instances setting (default 100)."
        ),
        "deployment_effort": (
            "VM: the most work. I wrote and built the image, pushed it to Artifact Registry, "
            "built a custom VPC (echo-net, subnet echo-subnet) with two firewall rules targeting "
            "the echo-http tag (8080 and 22), created the e2-micro with the right subnet, tag, "
            "Debian image and a service account allowed to read Artifact Registry, then installed "
            "and authenticated Docker on it and started the container (via a startup script). I "
            "would also own OS patching and restarts. Cloud Run: one command reusing the same "
            "image; Google provides HTTPS, the URL, scaling and the OS. Cloud Function: the least "
            "work: no Dockerfile, I deploy source (main.py + requirements.txt) and Cloud Build "
            "turns it into an image for me."
        ),
        "run_services_list": "```text\n" + services_out + "\n```",
        "convergence_explanation": (
            "The list shows two Cloud Run services, not one: echo-bot, which I deployed, and "
            "echo, which I never created as a Cloud Run service. It carries the labels "
            "goog-managed-by: cloudfunctions and goog-cloudfunctions-runtime: python311. A gen-2 "
            "Cloud Function is therefore just a Cloud Run service that Google creates and manages "
            "for me: gcloud functions deploy sent my source to Cloud Build, which used buildpacks "
            "to produce a container image (Functions Framework + main.py) and deployed it on Cloud "
            "Run. Both paths start a container from zero on the same infrastructure, so their cold "
            "starts are close, while the VM has no cold start because its container never stops. "
            "What genuinely differs is who builds and owns the image (my Dockerfile vs. a "
            "buildpack image I never see), the defaults (concurrency 1 per instance for the "
            "function vs. 80 for Cloud Run, a max-instances of 100 vs. my 3) and the deployment "
            "interface (source + entry point vs. an image)."
        ),
    }

    text = TEMPLATE.read_text()
    for key, value in answers.items():
        pattern = re.compile(r"(<!--answer:%s-->)(.*?)(<!--/answer-->)" % re.escape(key), re.S)
        if not pattern.search(text):
            raise SystemExit(f"slot not found in template: {key}")
        inline = key.endswith("_ms")
        repl = value if inline else "\n" + value + "\n"
        text = pattern.sub(lambda m: m.group(1) + repl + m.group(3), text, count=1)
    if "TODO" in re.sub(r"(?s)^.*?---", "", text, count=1):
        print("warning: a TODO remains in the report")
    OUT.write_text(text)
    print(f"wrote {OUT.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
