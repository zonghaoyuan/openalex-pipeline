-- OpenAlex DuckDB Views - Simplified Version
-- Strategy: ETL script now normalizes all schemas to VARCHAR for conflicting columns
--           Views can use simple SELECT * without type conversion logic
-- Updated: 2025-12-13

-- ============================================================================
-- Small Tables - Direct Read (no normalization needed in ETL)
-- ============================================================================

CREATE OR REPLACE VIEW domains AS
SELECT * FROM read_parquet('/data/domains/**/*.parquet', union_by_name=true);

CREATE OR REPLACE VIEW fields AS
SELECT * FROM read_parquet('/data/fields/**/*.parquet', union_by_name=true);

CREATE OR REPLACE VIEW subfields AS
SELECT * FROM read_parquet('/data/subfields/**/*.parquet', union_by_name=true);

CREATE OR REPLACE VIEW topics AS
SELECT * FROM read_parquet('/data/topics/**/*.parquet', union_by_name=true);

CREATE OR REPLACE VIEW publishers AS
SELECT * FROM read_parquet('/data/publishers/**/*.parquet', union_by_name=true);

CREATE OR REPLACE VIEW funders AS
SELECT * FROM read_parquet('/data/funders/**/*.parquet', union_by_name=true);

CREATE OR REPLACE VIEW concepts AS
SELECT * FROM read_parquet('/data/concepts/**/*.parquet', union_by_name=true);

-- ============================================================================
-- AUTHORS - Schema normalized in ETL
-- Normalized columns: orcid, affiliations, last_known_institutions, topics,
--                     topic_share, x_concepts, counts_by_year, ids
-- ============================================================================
CREATE OR REPLACE VIEW authors AS
SELECT * FROM read_parquet('/data/authors/**/*.parquet', union_by_name=true);

-- ============================================================================
-- INSTITUTIONS - Schema normalized in ETL
-- Normalized columns: image_url, image_thumbnail_url, display_name_acronyms,
--                     display_name_alternatives, repositories, associated_institutions,
--                     wikidata_id, ids
-- ============================================================================
CREATE OR REPLACE VIEW institutions AS
SELECT * FROM read_parquet('/data/institutions/**/*.parquet', union_by_name=true);

-- ============================================================================
-- SOURCES - Schema normalized in ETL
-- Normalized columns: issn_l, issn, host_organization, host_organization_name,
--                     host_organization_lineage, homepage_url, country_code,
--                     alternate_titles, apc_prices, apc_usd, is_in_doaj_since_year,
--                     is_high_oa_rate_since_year, oa_flip_year, topics, topic_share, ids
-- ============================================================================
CREATE OR REPLACE VIEW sources AS
SELECT * FROM read_parquet('/data/sources/**/*.parquet', union_by_name=true);

-- ============================================================================
-- WORKS - Schema normalized in ETL
-- Normalized columns: authorships, referenced_works, counts_by_year, indexed_in,
--                     biblio, locations, primary_location, best_oa_location,
--                     sustainable_development_goals, grants, awards, funders,
--                     mesh, ids, open_access
-- ============================================================================
CREATE OR REPLACE VIEW works AS
SELECT * FROM read_parquet('/data/works/**/*.parquet',
                          union_by_name=true,
                          hive_partitioning=true);

-- ============================================================================
-- NOTE: Nested fields (authorships, locations, etc.) are stored as VARCHAR
-- containing Python dict/list format. Use string functions to extract data
-- or query directly from the Parquet files if you need structured access.
-- ============================================================================
