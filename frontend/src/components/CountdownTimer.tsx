"use client";

import { useEffect, useState } from "react";

interface CountdownTimerProps {
  deadline: bigint | null; // Unix timestamp (seconds)
  interval: bigint | null; // total interval seconds (for % calculation)
}

function formatTime(seconds: number): string {
  if (seconds <= 0) return "00:00:00";
  const h = Math.floor(seconds / 3600);
  const m = Math.floor((seconds % 3600) / 60);
  const s = seconds % 60;
  return [h, m, s].map((v) => String(v).padStart(2, "0")).join(":");
}

export function CountdownTimer({ deadline, interval }: CountdownTimerProps) {
  const [remaining, setRemaining] = useState<number>(0);

  useEffect(() => {
    if (!deadline) return;

    const update = () => {
      const nowSec = Math.floor(Date.now() / 1000);
      const rem    = Math.max(0, Number(deadline) - nowSec);
      setRemaining(rem);
    };

    update();
    const id = setInterval(update, 1000);
    return () => clearInterval(id);
  }, [deadline]);

  if (!deadline) {
    return <div className="timer timer-idle">--:--:--</div>;
  }

  const totalSec   = interval ? Number(interval) : 86400;
  const pct        = Math.max(0, Math.min(100, (remaining / totalSec) * 100));
  const isDanger   = pct < 15;
  const isWarning  = pct < 40 && !isDanger;

  return (
    <div id="countdown-timer" className="timer-container">
      <div className={`timer ${isDanger ? "timer-danger" : isWarning ? "timer-warning" : "timer-ok"}`}>
        {formatTime(remaining)}
      </div>
      <div className="timer-bar-track">
        <div
          className={`timer-bar-fill ${isDanger ? "fill-danger" : isWarning ? "fill-warning" : "fill-ok"}`}
          style={{ width: `${pct}%` }}
        />
      </div>
      <p className="timer-label">
        {remaining > 0 ? "until next heartbeat deadline" : "deadline passed — you can be slashed"}
      </p>
    </div>
  );
}
