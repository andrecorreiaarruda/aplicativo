-- Private attachment bucket. File paths must begin with the organization UUID.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'service-attachments',
  'service-attachments',
  false,
  52428800,
  array[
    'application/pdf',
    'text/plain',
    'text/csv',
    'application/json',
    'image/jpeg',
    'image/png',
    'image/webp'
  ]
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

create policy service_attachments_read_own_org
on storage.objects for select to authenticated
using (
  bucket_id = 'service-attachments'
  and (storage.foldername(name))[1] = public.current_organization_id()::text
);

create policy service_attachments_insert_own_org
on storage.objects for insert to authenticated
with check (
  bucket_id = 'service-attachments'
  and (storage.foldername(name))[1] = public.current_organization_id()::text
);

create policy service_attachments_update_own_org
on storage.objects for update to authenticated
using (
  bucket_id = 'service-attachments'
  and (storage.foldername(name))[1] = public.current_organization_id()::text
)
with check (
  bucket_id = 'service-attachments'
  and (storage.foldername(name))[1] = public.current_organization_id()::text
);

create policy service_attachments_delete_own_org
on storage.objects for delete to authenticated
using (
  bucket_id = 'service-attachments'
  and (storage.foldername(name))[1] = public.current_organization_id()::text
);
