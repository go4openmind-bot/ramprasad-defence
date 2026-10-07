import { TENDER_STATUSES, statusIndex } from '@/lib/tenderStatus';

/** Horizontal view of the 13-stage pipeline with the current stage highlighted. */
export function StatusPipeline({ current }: { current: string }) {
  const currentIdx = statusIndex(current);

  return (
    <div className="pipeline" aria-label="Tender status pipeline">
      {TENDER_STATUSES.map((s, i) => {
        const cls = i === currentIdx ? 'step current' : i < currentIdx ? 'step done' : 'step';
        return (
          <span key={s.code} className={cls}>
            {i + 1}. {s.label}
          </span>
        );
      })}
    </div>
  );
}
