# Supabase setup

1. Create a Supabase project.
2. Run `SupabaseSchema.sql` in the SQL Editor.
3. Create a Storage bucket named `target-icons`.
4. Add these generated Info.plist keys to the app's local build configuration:

```text
SUPABASE_URL = https://ukiksqzsdsjszhhtpqjl.supabase.co
SUPABASE_ANON_KEY = sb_publishable_iaTMBFN570O3NfYjz_pjgw_RaJ28_RV
```

The app reads these values through `SupabaseConfiguration.current`. The anon key is intended for client use; never put a service-role key in the app.

The current store uses anonymous drawing rows. Before account-based drawings ship, replace the permissive policies in `SupabaseSchema.sql` with `owner_id = auth.uid()` policies and add authentication. Target images should move from local `imageData` into the `target-icons` Storage bucket, with only the storage path retained in drawing data.

## Data model

The schema includes normalized live tables for `drawing_targets`, `drawing_segments`, `drawing_line_definitions`, and `target_types`. Each target has both canvas coordinates and an optional PostGIS `location` point for GPS data. Segment endpoints reference target IDs and connection slots.

`drawings.data` is retained as a portable JSON snapshot for import/export and backward compatibility. The app's current anonymous sync still writes that snapshot; the next sync migration should write the normalized tables in one transaction and regenerate the snapshot for export.
