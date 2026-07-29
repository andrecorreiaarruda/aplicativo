insert into public.manufacturers(name) values
  ('Philips'),
  ('Elekta'),
  ('Siemens Healthineers'),
  ('GE HealthCare')
on conflict (name) do nothing;

insert into public.equipment_models(manufacturer_id, family, model, modality)
select id, 'Allura', 'Allura Xper FD10', 'Angiografia'
from public.manufacturers where name = 'Philips'
on conflict (manufacturer_id, model) do nothing;

insert into public.equipment_models(manufacturer_id, family, model, modality)
select id, 'Allura', 'Allura Xper FD20', 'Angiografia'
from public.manufacturers where name = 'Philips'
on conflict (manufacturer_id, model) do nothing;

insert into public.equipment_models(manufacturer_id, family, model, modality)
select id, 'Azurion', 'Azurion 7 M20', 'Angiografia'
from public.manufacturers where name = 'Philips'
on conflict (manufacturer_id, model) do nothing;

insert into public.equipment_models(manufacturer_id, family, model, modality)
select id, 'Versa HD', 'Versa HD', 'Radioterapia'
from public.manufacturers where name = 'Elekta'
on conflict (manufacturer_id, model) do nothing;
