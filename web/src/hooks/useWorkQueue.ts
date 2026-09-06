import { useEffect, useState } from "preact/hooks";
import type { Job, WorkOrder } from "core-api-client";
import { coreApi } from "../api";

/** One work-queue row: a work order joined to its job, by id. */
export interface WorkQueueRow {
  workOrder: WorkOrder;
  job: Job | undefined;
}

interface WorkQueueState {
  rows: WorkQueueRow[];
  loading: boolean;
  error: string | undefined;
}

/**
 * Fetches work orders and jobs, joins them client-side, and sorts open/in-progress work first.
 *
 * This is a simplification: `identity` (technicians/dispatchers) is not exposed over HTTP yet
 * (see server/README.md), so there is no real per-technician assignment data. This view stands
 * in for "a technician's work queue" using the open work orders available today, not real
 * technician-filtered data — see web/README.md.
 */
export function useWorkQueue(): WorkQueueState {
  const [state, setState] = useState<WorkQueueState>({ rows: [], loading: true, error: undefined });

  useEffect(() => {
    let cancelled = false;

    async function load() {
      const [workOrdersRes, jobsRes] = await Promise.all([
        coreApi.GET("/work_orders", {}),
        coreApi.GET("/jobs", {}),
      ]);

      if (cancelled) return;

      const firstError = workOrdersRes.error ?? jobsRes.error;
      if (firstError) {
        setState({ rows: [], loading: false, error: "Failed to load work queue." });
        return;
      }

      const jobsById = new Map((jobsRes.data?.data ?? []).map((job) => [job.id, job]));

      const rows: WorkQueueRow[] = (workOrdersRes.data?.data ?? [])
        .map((workOrder) => ({
          workOrder,
          job: workOrder.attributes?.job_id ? jobsById.get(workOrder.attributes.job_id) : undefined,
        }))
        .sort((a, b) => Number(a.workOrder.attributes?.status === "completed") - Number(b.workOrder.attributes?.status === "completed"));

      setState({ rows, loading: false, error: undefined });
    }

    load();
    return () => {
      cancelled = true;
    };
  }, []);

  return state;
}
