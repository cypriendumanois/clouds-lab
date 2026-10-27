# Phase 1 — Comparison Report

Copy this file to `submission/phase1_report.md`, fill in every answer slot, and commit it:

```bash
cp phase-1-echo-bot/report_template.md submission/phase1_report.md
```

**How to fill it in.** Each answer sits between a pair of `<!--answer:...-->` markers. Replace
the `TODO` line with your answer — **leave the markers themselves untouched**, they are how the
grader finds your answers. Anything you write outside the markers is ignored, so add extra
prose, tables or images freely.

Numbers must **match `submission/phase1_report.json`** exactly — that file is produced by
`measure.py` and is what your figures are checked against. Copy them across; do not retype from
memory.

---

## 1. Setup facts

**Your image size**, in MB, from `gcloud artifacts docker images list` (number only, e.g. `142`):

<!--answer:image_size_mb-->
49
<!--/answer-->

**The custom VPC and subnet you created** (names only):

<!--answer:vpc_name-->
echo-net
<!--/answer-->

<!--answer:subnet_name-->
echo-subnet
<!--/answer-->

---

## 2. Measurements

Copy these from `submission/phase1_report.json`. Cold is `cold_ms`; warm median is
`stats.median`. Numbers only, in milliseconds (e.g. `812.4`).

| Platform | Cold (ms) | Warm median (ms) |
|---|---|---|
| IaaS VM | <!--answer:vm_cold_ms-->273.8<!--/answer--> | <!--answer:vm_warm_median_ms-->212.1<!--/answer--> |
| Cloud Run | <!--answer:cloudrun_cold_ms-->3441.0<!--/answer--> | <!--answer:cloudrun_warm_median_ms-->634.5<!--/answer--> |
| Cloud Function | <!--answer:function_cold_ms-->957.9<!--/answer--> | <!--answer:function_warm_median_ms-->633.8<!--/answer--> |

Include your histogram or plot of the warm distribution below (an image, or the ASCII chart
`measure.py` prints). This is read by a human, not the grader:

<!--answer:latency_plot-->
```text
Warm latency distribution (20 requests each, from submission/phase1_report.json).
Measured from Cloud Shell; the VM is plain HTTP, Cloud Run and the function are HTTPS,
so each of their requests also pays a TLS handshake to us-central1.

IaaS VM: cold=273.8 ms, warm min/median/p95/max = 210.7/212.1/215.2/215.8 ms
   210.7-   211.3 ms | ############################## 7
   211.3-   212.0 ms | #########                      2
   212.0-   212.6 ms | #################              4
   212.6-   213.2 ms |                                0
   213.2-   213.9 ms | #############                  3
   213.9-   214.5 ms |                                0
   214.5-   215.2 ms |                                0
   215.2-   215.8 ms | #################              4

Cloud Run: cold=3441.0 ms, warm min/median/p95/max = 120.7/634.5/656.0/681.6 ms
   120.7-   190.8 ms | ##########                     5
   190.8-   260.9 ms |                                0
   260.9-   331.0 ms |                                0
   331.0-   401.1 ms |                                0
   401.1-   471.3 ms |                                0
   471.3-   541.4 ms |                                0
   541.4-   611.5 ms |                                0
   611.5-   681.6 ms | ############################## 15

Cloud Function: cold=957.9 ms, warm min/median/p95/max = 120.5/633.8/661.6/685.9 ms
   120.5-   191.2 ms | ################               7
   191.2-   261.9 ms |                                0
   261.9-   332.5 ms |                                0
   332.5-   403.2 ms |                                0
   403.2-   473.9 ms |                                0
   473.9-   544.5 ms |                                0
   544.5-   615.2 ms |                                0
   615.2-   685.9 ms | ############################## 13
```
<!--/answer-->

---

## 3. Per-platform analysis

**Scaling behaviour.** Imagine requests arriving one at a time, then ten at once, then a
hundred. For each of the three platforms, answer concretely:

- Does anything get created automatically to absorb the load — and if so, *what* exactly?
  (One platform here creates nothing at all.)
- What is the hard limit, and where does it come from — a flag you passed yourself, or the
  size of the machine you picked?

(~80 words. Your `--machine-type=e2-micro` and `--max-instances=3` are both concrete answers
to the second question.)

<!--answer:scaling_behaviour-->
VM: nothing is created automatically. One e2-micro (2 shared vCPUs, 1 GB RAM) runs one container with gunicorn (1 worker, 8 threads); ten or a hundred concurrent requests just queue on that machine. The limit is the machine type I picked. Cloud Run: new container instances of my image are started as concurrency grows (up to 80 requests per instance by default), and scaled back to zero when idle; the hard cap is the --max-instances=3 flag I passed. Cloud Function (gen 2): the same mechanism, since it is a Cloud Run service; each instance takes one request at a time (maxInstanceRequestConcurrency: 1), so it adds instances sooner, bounded by the function's max-instances setting (default 100).
<!--/answer-->

**Deployment effort.** What did you have to build, configure and maintain to get each of the
three running? (~100 words)

<!--answer:deployment_effort-->
VM: the most work. I wrote and built the image, pushed it to Artifact Registry, built a custom VPC (echo-net, subnet echo-subnet) with two firewall rules targeting the echo-http tag (8080 and 22), created the e2-micro with the right subnet, tag, Debian image and a service account allowed to read Artifact Registry, then installed and authenticated Docker on it and started the container (via a startup script). I would also own OS patching and restarts. Cloud Run: one command reusing the same image; Google provides HTTPS, the URL, scaling and the OS. Cloud Function: the least work: no Dockerfile, I deploy source (main.py + requirements.txt) and Cloud Build turns it into an image for me.
<!--/answer-->

---

## 4. Why do two of your three numbers look alike?

With Cloud Run and your Function both deployed, run `gcloud run services list` and paste the
**complete output** here, unedited:

<!--answer:run_services_list-->
```text
✔
SERVICE: echo
REGION: us-central1
URL: https://echo-427192738607.us-central1.run.app
LAST DEPLOYED BY: service-427192738607@gcf-admin-robot.iam.gserviceaccount.com
LAST DEPLOYED AT: 2026-10-27T20:52:31.099120Z

✔
SERVICE: echo-bot
REGION: us-central1
URL: https://echo-bot-427192738607.us-central1.run.app
LAST DEPLOYED BY: cyprien.dumanois@eurecom.fr
LAST DEPLOYED AT: 2026-10-27T20:51:37.105564Z
```
<!--/answer-->

Now explain what that output tells you about how your Function is actually being run, why its
cold start resembles Cloud Run's so closely, and what — if anything — genuinely differs between
the two deployment paths. (~120 words)

<!--answer:convergence_explanation-->
The list shows two Cloud Run services, not one: echo-bot, which I deployed, and echo, which I never created as a Cloud Run service. It was last deployed by the gcf-admin-robot service agent, not by me, and its labels include goog-managed-by: cloudfunctions. A gen-2 Cloud Function is therefore a Cloud Run service that Google creates and manages for me: gcloud functions deploy sent my source to Cloud Build, which built a container image with buildpacks (Functions Framework + main.py) and deployed it to Cloud Run. Both paths pay a container cold start on the same platform (Cloud Run 3441.0 ms, function 957.9 ms) and have almost identical warm medians (634.5 vs 633.8 ms) because requests take the same path: Google's front end, HTTPS, then a running container. The VM has no real cold start (273.8 vs 212.1 ms warm, the extra being the first TCP connection) because its container never stops. My cold numbers are single samples, so the gap between the two serverless cold starts mostly reflects one-off factors such as image pull and instance placement. What genuinely differs is who builds and owns the image (my Dockerfile vs. a buildpack image I never see), the defaults (one request per instance for the function vs. 80 for Cloud Run, max-instances 100 vs. my 3) and the deployment interface (source + entry point vs. an image).
<!--/answer-->
