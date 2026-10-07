-- =============================================================================
-- 0005_documents.sql
-- Central document/file register. Files themselves live in Supabase Storage;
-- this table holds the metadata and the classification that drives access.
-- Created before the tables that link to it (tender_documents, delivery_documents).
-- =============================================================================

create table public.documents (
  id              uuid primary key default gen_random_uuid(),
  title           text,
  file_name       text not null,
  storage_bucket  text not null default 'documents',
  storage_path    text not null,
  mime_type       text,
  size_bytes      bigint,
  classification  text not null default 'internal',
  entity_table    text,
  entity_id       uuid,
  version         integer not null default 1,
  checksum        text,
  uploaded_by     uuid references public.users(id),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  created_by      uuid,
  updated_by      uuid,
  constraint documents_classification_chk check
    (classification in ('unclassified','internal','confidential','controlled','itar_ear')),
  constraint documents_path_unique unique (storage_bucket, storage_path),
  constraint documents_version_chk check (version >= 1),
  constraint documents_size_chk check (size_bytes is null or size_bytes >= 0)
);

comment on table public.documents is
  'Central register of uploaded files (tender docs, quotations, POs, inspection certificates, invoices, PODs). The file bytes live in Supabase Storage; access is via short-lived signed URLs.';
comment on column public.documents.classification is
  'unclassified | internal | confidential | controlled | itar_ear. controlled/itar_ear rows are limited to admin, management, technical and qa.';
comment on column public.documents.entity_table is
  'Optional generic link to any business table (used together with entity_id). Explicit link tables also exist (tender_documents, delivery_documents).';

create index documents_entity_idx on public.documents (entity_table, entity_id);
create index documents_classification_idx on public.documents (classification);
create index documents_uploaded_by_idx on public.documents (uploaded_by);
