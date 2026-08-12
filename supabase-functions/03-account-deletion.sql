-- Required before chop-delete-account can anonymise purchase rows.
alter table public.chop_purchases alter column user_id drop not null;
