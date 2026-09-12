-- Remove the duplicate index introduced during remediation. The pre-existing
-- unique constraint/index `machine_consumables_machine_id_type_key` already
-- covers `(machine_id, type)`.

drop index if exists public.machine_consumables_machine_type_key;
