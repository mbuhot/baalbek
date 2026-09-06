import { useWorkQueue } from "../hooks/useWorkQueue";
import { formatDateTime } from "../lib/format";

/**
 * A simplified stand-in for a technician's work queue.
 *
 * `identity` isn't exposed over HTTP yet, so there's no real per-technician
 * assignment to filter by (see web/README.md "Technician view simplification").
 * This lists all open work orders instead, open/in-progress first.
 */
export function TechnicianView() {
  const { rows, loading, error } = useWorkQueue();

  if (loading) return <p>Loading work queue…</p>;
  if (error) return <p role="alert">{error}</p>;
  if (rows.length === 0) return <p>No work orders yet.</p>;

  return (
    <table>
      <caption>My work queue (simplified — not filtered by technician)</caption>
      <thead>
        <tr>
          <th>Work order</th>
          <th>Status</th>
          <th>Job</th>
          <th>Completed</th>
        </tr>
      </thead>
      <tbody>
        {rows.map(({ workOrder, job }) => (
          <tr key={workOrder.id}>
            <td>{workOrder.attributes?.summary}</td>
            <td>{workOrder.attributes?.status}</td>
            <td>{job?.attributes?.title ?? "Unknown job"}</td>
            <td>{formatDateTime(workOrder.attributes?.completed_at)}</td>
          </tr>
        ))}
      </tbody>
    </table>
  );
}
