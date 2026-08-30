-- 0015_optional_serial_number.sql
--
-- Torna o número de série opcional, mantendo a unicidade por organização.
--
-- A série continua sendo a identidade do equipamento e permanece única
-- dentro da organização, como convém a números de fábrica. Mas nem todo
-- equipamento em campo tem a etiqueta legível — placa apagada,
-- substituída em manutenção, ou instalada em posição inacessível. Exigir
-- a série impedia o cadastro justamente dos equipamentos antigos, que
-- são os que mais precisam de histórico.
--
-- A restrição `unique (organization_id, serial_number)` continua valendo
-- sem alteração: o PostgreSQL trata nulos como distintos entre si em
-- índices únicos (NULLS DISTINCT, o padrão), então vários equipamentos
-- sem série convivem, enquanto duas séries informadas iguais seguem
-- recusadas.
--
-- Cadeia vazia não serve para isso: '' é um valor como outro qualquer e
-- colidiria consigo mesmo na segunda ocorrência. O ausente precisa ser
-- nulo, e a migration normaliza o que porventura exista.

alter table public.equipments
  alter column serial_number drop not null;

update public.equipments
   set serial_number = null
 where btrim(serial_number) = '';

-- Impede que a cadeia vazia volte a ser gravada por qualquer caminho,
-- inclusive pela RPC de replay offline.
alter table public.equipments
  drop constraint if exists equipments_serial_number_not_blank;

alter table public.equipments
  add constraint equipments_serial_number_not_blank
  check (serial_number is null or btrim(serial_number) <> '');

comment on column public.equipments.serial_number is
  'Número de série de fábrica. Nulo quando não foi possível identificar. '
  'Único por organização quando informado; nulos não colidem entre si.';
