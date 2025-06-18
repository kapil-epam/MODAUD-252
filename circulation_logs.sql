CREATE EXTENSION IF NOT EXISTS unaccent WITH SCHEMA public;
CREATE SCHEMA diku_mod_audit;
SET search_path TO diku_mod_audit;
CREATE FUNCTION diku_mod_audit.concat_items_barcodes(jsonb_array jsonb) RETURNS text
    LANGUAGE sql IMMUTABLE STRICT PARALLEL SAFE
    AS $_$
  SELECT string_agg(item->>'itemBarcode', ' ')
  FROM jsonb_array_elements($1) as item
  WHERE item->>'itemBarcode' IS NOT NULL;
$_$;
CREATE FUNCTION diku_mod_audit.f_unaccent(text) RETURNS text
    LANGUAGE sql IMMUTABLE STRICT PARALLEL SAFE
    AS $_$
  SELECT public.unaccent('public.unaccent', $1)  -- schema-qualify function and dictionary
$_$;
CREATE FUNCTION diku_mod_audit.get_tsvector(text) RETURNS tsvector
    LANGUAGE sql IMMUTABLE STRICT PARALLEL SAFE
    AS $_$
  SELECT to_tsvector('simple', translate($1, '&', ','));
$_$;
CREATE FUNCTION diku_mod_audit.tsquery_and(text) RETURNS tsquery
    LANGUAGE sql IMMUTABLE STRICT PARALLEL SAFE
    AS $_$
  SELECT to_tsquery('simple', string_agg(CASE WHEN length(v) = 0 OR v = '*' THEN ''
                                              WHEN right(v, 1) = '*' THEN '''' || left(v, -1) || ''':*'
                                              ELSE '''' || v || '''' END,
                                         '&'))
  FROM (SELECT regexp_split_to_table(translate($1, '&''', ',,'), ' +')) AS x(v);
$_$;
CREATE FUNCTION diku_mod_audit.tsquery_phrase(text) RETURNS tsquery
    LANGUAGE sql IMMUTABLE STRICT PARALLEL SAFE
    AS $_$
  SELECT replace(diku_mod_audit.tsquery_and($1)::text, '&', '<->')::tsquery;
$_$;
CREATE TABLE diku_mod_audit.circulation_logs (
    id uuid NOT NULL,
    jsonb jsonb NOT NULL
);
ALTER TABLE ONLY diku_mod_audit.circulation_logs
    ADD CONSTRAINT circulation_logs_pkey PRIMARY KEY (id);
CREATE INDEX circulation_logs_date_idx ON circulation_logs USING btree ("left"(lower(f_unaccent((jsonb ->> 'date'::text))), 600));
CREATE INDEX circulation_logs_itembarcode_idx_ft ON circulation_logs USING gin (get_tsvector(f_unaccent(concat_items_barcodes((jsonb -> 'items'::text)))));

INSERT INTO diku_mod_audit.circulation_logs values (
  md5(generate_Series(1, 3000000)::text)::uuid,
  jsonb_build_object(
    'date', generate_series(1, 3000000)::text,
    'items', jsonb_build_array(jsonb_build_object('itemBarcode', generate_series(1, 3000000)::text))));

EXPLAIN ANALYSE
  SELECT jsonb from diku_mod_audit.circulation_logs
  WHERE get_tsvector(concat_items_barcodes(jsonb->'items')) @@ tsquery_phrase('ITEM_BARCODE_000354')
  ORDER BY left(lower(f_unaccent(circulation_logs.jsonb->>'date')),600) DESC, lower(f_unaccent(circulation_logs.jsonb->>'date')) DESC
  LIMIT 1000 OFFSET 0;

EXPLAIN ANALYZE
  SELECT jsonb from diku_mod_audit.circulation_logs
  WHERE get_tsvector(concat_items_barcodes(jsonb->'items')) @@ tsquery_phrase('ITEM_BARCODE_000354')
  ORDER BY left(lower(f_unaccent(circulation_logs.jsonb->>'date')),600) DESC, lower(f_unaccent(circulation_logs.jsonb->>'date')) DESC
  LIMIT 100 OFFSET 0;

EXPLAIN ANALYZE
  SELECT jsonb from diku_mod_audit.circulation_logs
  WHERE get_tsvector(concat_items_barcodes(jsonb->'items')) @@ tsquery_phrase('ITEM_BARCODE_000354')
  ORDER BY left(lower(f_unaccent(circulation_logs.jsonb->>'date')),600) DESC, lower(f_unaccent(circulation_logs.jsonb->>'date')) DESC
  LIMIT 10 OFFSET 0;
