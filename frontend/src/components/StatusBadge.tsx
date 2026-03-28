"use client";

type Status = "active" | "inactive" | "not-joined";

interface StatusBadgeProps {
  status: Status;
}

const CONFIG: Record<Status, { label: string; className: string }> = {
  active:      { label: "ACTIVE",      className: "badge badge-active" },
  inactive:    { label: "INACTIVE",    className: "badge badge-inactive" },
  "not-joined": { label: "NOT JOINED", className: "badge badge-not-joined" },
};

export function StatusBadge({ status }: StatusBadgeProps) {
  const { label, className } = CONFIG[status];
  return (
    <span id="status-badge" className={className}>
      {status === "active" && <span className="pulse-ring" />}
      {label}
    </span>
  );
}
