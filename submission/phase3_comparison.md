# Phase 3 — Comparison Writeup

Copy this file to `submission/phase3_comparison.md`, fill in every answer slot, and commit it:

```bash
cp phase-3-mapreduce-spark/comparison_template.md submission/phase3_comparison.md
```

**How to fill it in.** Each answer sits between a pair of `<!--answer:...-->` markers. Replace
the `TODO` line with your answer — **leave the markers themselves untouched**, they are how the
grader finds your answers. Anything you write outside the markers is ignored, so add extra
prose, tables or images freely.

Numbers in section 1 must **match `submission/phase3_report.json`** — copy them across, do not
retype from memory; they are checked against it.

---

## 1. Facts from your runs

Numbers only (e.g. `12`, `20.3`, `0.041`).

| | Value |
|---|---|
| Map tasks in the cloud job (`mapreduce.num_splits`) | <!--answer:num_map_tasks-->12<!--/answer--> |
| Reduce tasks in the cloud job (`mapreduce.num_reducers`) | <!--answer:num_reduce_tasks-->4<!--/answer--> |
| Cloud MapReduce wall time, seconds (`mapreduce.cloud_elapsed_s`) | <!--answer:cloud_elapsed_s-->36.2<!--/answer--> |
| Local single-process wall time, seconds (`mapreduce.local_elapsed_s`) | <!--answer:local_elapsed_s-->0.019<!--/answer--> |
| Spark wall time for the `collect`, seconds (`tfidf.spark_elapsed_s`) | <!--answer:spark_elapsed_s-->9.0<!--/answer--> |
| Number of **stages** in the Spark job (read off notebook 2b / 3a) | <!--answer:num_stages-->4<!--/answer--> |
| Task **retries** you counted in your `--chaos` run (0 if none happened) | <!--answer:chaos_retries-->3<!--/answer--> |

**Explain the timings.** The three wall times above cover the same 60 documents, but not the
same job: the single-process run and the cloud MapReduce are *the same word count*; Spark's
time is for *TF-IDF*, which is more work (two `reduceByKey`s and a `join`). Rank the three and
explain what each is spending its time on. Say which comparison is like-for-like, and what the
Spark number — a heavier job, on one machine — tells you about where the cloud job's time goes.
(~80 words)

<!--answer:timing_explanation-->
Ranking: local 0.019 s < Spark 9.0 s < cloud MapReduce 36.2 s. Local vs cloud is the like-for-like pair: same word count, same code, same 60 documents. Locally it is pure in-memory Python. The cloud job spends its time on coordination, not computation: 16 Workflows HTTP calls, Cloud Run cold starts, ~65 Cloud Storage reads/writes for the shuffle, the barrier, and here the backoff of 3 retries (26.3 s without chaos). Spark does more work (two `reduceByKey`s and a `join`) in 9 s on one machine, mostly start-up and scheduling: the cloud job's time is overhead, not work.
<!--/answer-->

**What the counts tell you.** From your stage count: how many shuffles did the Spark job have,
and which operations in `spark_tfidf.py` caused them? From your retry count: roughly what
fraction of the 16 task attempts was retried, and is that what `--chaos 0.3` should produce?
(~50 words)

<!--answer:counts_interpretation-->
4 stages means 3 shuffles: the `reduceByKey` in `term_freq` (`spark_tfidf.py:31`), the `reduceByKey` in `doc_freq` (`:42`) and the `join` in `build_tfidf_rdd` (`:54`). 3 retries for 16 tasks: about 19% of the tasks were retried (3 of 19 attempts, 16%, failed). With p = 0.3 per attempt we would expect about 16 x 0.3/0.7 = 7 retries; 3 is lower, but within normal variation for only 16 tasks (about a 13% chance of 3 or fewer).
<!--/answer-->

---

## 2. Spark: transformations, actions, lineage

**Transformations vs actions.** Go through `spark_tfidf.py` and the notebook's Spark cells.
Name each RDD operation and say whether it is a transformation or an action. What happened
when you ran `build_tfidf_rdd` — and what happened when you ran `collect`? (~60 words)

<!--answer:transformations_vs_actions-->
Transformations (lazy): `parallelize` (creates `docs_rdd`), `flatMap` + `reduceByKey` in `term_freq`, `map` + `reduceByKey` in `doc_freq`, then `map` (`tf_by_term`), `join` and `map(to_row)` in `build_tfidf_rdd`. The only action is `collect` (`build_tfidf_rows`, notebook 2c); `toDebugString` only prints the lineage, and `save_parquet` is pyarrow on the driver, not Spark. Calling `build_tfidf_rdd` returned instantly: it only recorded the lineage graph, no task ran. `collect` made the DAG scheduler cut that graph into 4 stages (12 tasks), run them in 9.0 s and ship the 5,975 rows back to the driver.
<!--/answer-->

**Lineage and recovery.** Using the lineage you printed in 2b and the timeline in 3a: if the
worker holding one output partition of the *first* `reduceByKey` died, what would Spark have
to recompute, and what could it reuse? Name the stage or shuffle boundary where the recovery
starts. (~50 words)

<!--answer:lineage_recovery-->
The first `reduceByKey` (`term_freq`, line 31) is the `ShuffledRDD[3]` boundary between stage 0 and stages 1-2. If a worker holding one of its output partitions died, Spark would re-run only that partition's tasks, re-fetching their input from the stage-0 shuffle files; if that worker also held stage-0 map outputs, only those map tasks would be recomputed from `ParallelCollectionRDD[0]`. Everything else is reused, as table 3a shows: stage 0 wrote 51.0 KB once, and both stage 1 and stage 2 read it.
<!--/answer-->

---

## 3. Your cloud MapReduce, mapped onto Hadoop

Name the GCP service or file that played each role (one line each):

- **JobTracker** (schedules tasks, waits for the map phase, retries failures):
  <!--answer:role_jobtracker-->Cloud Workflows, the `mr-wordcount` workflow (`workflow.yaml`): `parallel` + `for` fan-out, an implicit barrier, `try`/`retry`.<!--/answer-->
- **Workers** (run your map and reduce code):
  <!--answer:role_workers-->The `mr-worker` Cloud Run function (2nd gen, `main.py`, running as `mr-runner`), invoked once per map or reduce task.<!--/answer-->
- **HDFS** (holds inputs, shuffle files, outputs):
  <!--answer:role_hdfs-->Cloud Storage, bucket `eurecomgpt-cyprien-eurecomgpt`, under `<job>/input/`, `<job>/shuffle/` and `<job>/output/`.<!--/answer-->
- **Partitioner** (decides which reducer owns a key):
  <!--answer:role_partitioner-->`partition()` in `mapreduce.py` (`zlib.crc32(word) % num_reducers`), called by `run_map` in `main.py`.<!--/answer-->

**The barrier.** There is no explicit "wait for all mappers" step in `workflow.yaml`. Where,
exactly, is the barrier between the map and reduce phases — which construct provides it?
(~30 words)

<!--answer:barrier_location-->
At the end of the `map_phase` step: a `parallel` step only completes when all its branches (all 12 map calls, retries included) have returned, so the next step, `reduce_phase`, cannot start before then.
<!--/answer-->

**Idempotence.** The workflow retries a task that failed. Why is that safe with the worker as
written, and what would go wrong if `run_map` *appended* its pairs to the shuffle file instead
of overwriting it? (~60 words)

<!--answer:idempotence-->
Each map task reads its immutable input split and overwrites fixed object names (`<job>/shuffle/split-i/part-r.json`) with complete uploads; each reducer overwrites `<job>/output/part-r.json`. Running a task twice leaves exactly the same objects, so a retry is harmless. If `run_map` appended instead, a task that had already written its files and was then retried (lost response, timeout) would add its pairs twice: reducers would double-count those words and the cloud counts would no longer match the local reference.
<!--/answer-->

**The chaos run.** What did you see in the execution log and in Logs Explorer when you ran
with `--chaos 0.3`? Did the job still succeed, and was the final answer still identical to the
local reference? (~50 words)

<!--answer:chaos_observations-->
The `--chaos 0.3` execution still SUCCEEDED, in 36.2 s against 26.3 s for the normal run; the extra time is retry backoff. Cloud Logging (Logs Explorer query on the `mr-worker` service, HTTP status 503) showed 3 failed requests during that execution, the simulated worker crashes, and the workflow retried each of them successfully: all 12 map and 4 reduce task records are present. The result was identical to the local reference: 2,221 distinct words, `matches_local: true`.
<!--/answer-->
