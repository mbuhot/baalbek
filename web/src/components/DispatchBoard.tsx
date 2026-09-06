import { useDispatchBoard } from "../hooks/useDispatchBoard";
import { formatDateTime } from "../lib/format";

/** Lists all jobs with their site and customer, for a dispatcher planning work. */
export function DispatchBoard() {
  const { rows, loading, error } = useDispatchBoard();

  if (loading) return <p>Loading dispatch board…</p>;
  if (error) return <p role="alert">{error}</p>;
  if (rows.length === 0) return <p>No jobs yet.</p>;

  return (
    <table>
      <caption>Dispatch board</caption>
      <thead>
        <tr>
          <th>Job</th>
          <th>Status</th>
          <th>Scheduled</th>
          <th>Site</th>
          <th>Customer</th>
        </tr>
      </thead>
      <tbody>
        {rows.map(({ job, site, customer }) => (
          <tr key={job.id}>
            <td>{job.attributes?.title}</td>
            <td>{job.attributes?.status}</td>
            <td>{formatDateTime(job.attributes?.scheduled_at)}</td>
            <td>{site?.attributes?.name ?? "Unknown site"}</td>
            <td>{customer?.attributes?.name ?? "Unknown customer"}</td>
          </tr>
        ))}
      </tbody>
    </table>
  );
}
