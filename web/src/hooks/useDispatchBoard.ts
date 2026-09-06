import { useEffect, useState } from "preact/hooks";
import type { Customer, Job, Site } from "core-api-client";
import { coreApi } from "../api";

/** One dispatch-board row: a job joined to its site and customer, by id. */
export interface DispatchRow {
  job: Job;
  site: Site | undefined;
  customer: Customer | undefined;
}

interface DispatchBoardState {
  rows: DispatchRow[];
  loading: boolean;
  error: string | undefined;
}

/** Fetches jobs, sites, and customers, and joins them client-side (the API declares no relationships). */
export function useDispatchBoard(): DispatchBoardState {
  const [state, setState] = useState<DispatchBoardState>({ rows: [], loading: true, error: undefined });

  useEffect(() => {
    let cancelled = false;

    async function load() {
      const [jobsRes, sitesRes, customersRes] = await Promise.all([
        coreApi.GET("/jobs", {}),
        coreApi.GET("/sites", {}),
        coreApi.GET("/customers", {}),
      ]);

      if (cancelled) return;

      const firstError = jobsRes.error ?? sitesRes.error ?? customersRes.error;
      if (firstError) {
        setState({ rows: [], loading: false, error: "Failed to load dispatch data." });
        return;
      }

      const sitesById = new Map((sitesRes.data?.data ?? []).map((site) => [site.id, site]));
      const customersById = new Map((customersRes.data?.data ?? []).map((customer) => [customer.id, customer]));

      const rows: DispatchRow[] = (jobsRes.data?.data ?? []).map((job) => {
        const site = job.attributes?.site_id ? sitesById.get(job.attributes.site_id) : undefined;
        const customer = site?.attributes?.customer_id ? customersById.get(site.attributes.customer_id) : undefined;
        return { job, site, customer };
      });

      setState({ rows, loading: false, error: undefined });
    }

    load();
    return () => {
      cancelled = true;
    };
  }, []);

  return state;
}
