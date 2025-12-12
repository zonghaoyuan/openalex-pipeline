-- ============================================================================
-- OpenAlex DuckDB Schema Initialization with Deduplication
-- Purpose: Create deduplicated wildcard views for all entity types
-- Author: Senior Data Engineer
-- Date: 2025-12-12
-- Updated: Added deduplication logic to handle entity movements between partitions
-- ============================================================================

-- IMPORTANT: These views include deduplication logic to handle cases where:
-- 1. The same entity appears in multiple partitions (during updates)
-- 2. Orphan Parquet files temporarily exist before cleanup
-- 3. OpenAlex data has anomalies
--
-- Deduplication ensures that each entity (by id) appears only once,
-- with the most recent version (by updated_date) being selected.

-- ============================================================================
-- AUTHORS
-- ============================================================================
CREATE OR REPLACE VIEW authors AS
SELECT * EXCLUDE (rn) FROM (
    SELECT *,
           ROW_NUMBER() OVER (PARTITION BY id ORDER BY updated_date DESC) as rn
    FROM read_parquet('/data/authors/**/*.parquet', union_by_name=true)
) WHERE rn = 1;

-- ============================================================================
-- CONCEPTS
-- ============================================================================
CREATE OR REPLACE VIEW concepts AS
SELECT * EXCLUDE (rn) FROM (
    SELECT *,
           ROW_NUMBER() OVER (PARTITION BY id ORDER BY updated_date DESC) as rn
    FROM read_parquet('/data/concepts/**/*.parquet', union_by_name=true)
) WHERE rn = 1;

-- ============================================================================
-- DOMAINS
-- ============================================================================
CREATE OR REPLACE VIEW domains AS
SELECT * EXCLUDE (rn) FROM (
    SELECT *,
           ROW_NUMBER() OVER (PARTITION BY id ORDER BY updated_date DESC) as rn
    FROM read_parquet('/data/domains/**/*.parquet', union_by_name=true)
) WHERE rn = 1;

-- ============================================================================
-- FIELDS
-- ============================================================================
CREATE OR REPLACE VIEW fields AS
SELECT * EXCLUDE (rn) FROM (
    SELECT *,
           ROW_NUMBER() OVER (PARTITION BY id ORDER BY updated_date DESC) as rn
    FROM read_parquet('/data/fields/**/*.parquet', union_by_name=true)
) WHERE rn = 1;

-- ============================================================================
-- FUNDERS
-- ============================================================================
CREATE OR REPLACE VIEW funders AS
SELECT * EXCLUDE (rn) FROM (
    SELECT *,
           ROW_NUMBER() OVER (PARTITION BY id ORDER BY updated_date DESC) as rn
    FROM read_parquet('/data/funders/**/*.parquet', union_by_name=true)
) WHERE rn = 1;

-- ============================================================================
-- INSTITUTIONS
-- ============================================================================
CREATE OR REPLACE VIEW institutions AS
SELECT * EXCLUDE (rn) FROM (
    SELECT *,
           ROW_NUMBER() OVER (PARTITION BY id ORDER BY updated_date DESC) as rn
    FROM read_parquet('/data/institutions/**/*.parquet', union_by_name=true)
) WHERE rn = 1;

-- ============================================================================
-- PUBLISHERS
-- ============================================================================
CREATE OR REPLACE VIEW publishers AS
SELECT * EXCLUDE (rn) FROM (
    SELECT *,
           ROW_NUMBER() OVER (PARTITION BY id ORDER BY updated_date DESC) as rn
    FROM read_parquet('/data/publishers/**/*.parquet', union_by_name=true)
) WHERE rn = 1;

-- ============================================================================
-- SOURCES
-- ============================================================================
CREATE OR REPLACE VIEW sources AS
SELECT * EXCLUDE (rn) FROM (
    SELECT *,
           ROW_NUMBER() OVER (PARTITION BY id ORDER BY updated_date DESC) as rn
    FROM read_parquet('/data/sources/**/*.parquet', union_by_name=true)
) WHERE rn = 1;

-- ============================================================================
-- SUBFIELDS
-- ============================================================================
CREATE OR REPLACE VIEW subfields AS
SELECT * EXCLUDE (rn) FROM (
    SELECT *,
           ROW_NUMBER() OVER (PARTITION BY id ORDER BY updated_date DESC) as rn
    FROM read_parquet('/data/subfields/**/*.parquet', union_by_name=true)
) WHERE rn = 1;

-- ============================================================================
-- TOPICS
-- ============================================================================
CREATE OR REPLACE VIEW topics AS
SELECT * EXCLUDE (rn) FROM (
    SELECT *,
           ROW_NUMBER() OVER (PARTITION BY id ORDER BY updated_date DESC) as rn
    FROM read_parquet('/data/topics/**/*.parquet', union_by_name=true)
) WHERE rn = 1;

-- ============================================================================
-- WORKS
-- ============================================================================
CREATE OR REPLACE VIEW works AS
SELECT * EXCLUDE (rn) FROM (
    SELECT *,
           ROW_NUMBER() OVER (PARTITION BY id ORDER BY updated_date DESC) as rn
    FROM read_parquet('/data/works/**/*.parquet', union_by_name=true)
) WHERE rn = 1;

-- ============================================================================
-- VALIDATION QUERIES
-- ============================================================================

-- Count records per entity type (uncomment to run)
-- SELECT 'authors' as entity, COUNT(*) as record_count FROM authors
-- UNION ALL
-- SELECT 'concepts', COUNT(*) FROM concepts
-- UNION ALL
-- SELECT 'domains', COUNT(*) FROM domains
-- UNION ALL
-- SELECT 'fields', COUNT(*) FROM fields
-- UNION ALL
-- SELECT 'funders', COUNT(*) FROM funders
-- UNION ALL
-- SELECT 'institutions', COUNT(*) FROM institutions
-- UNION ALL
-- SELECT 'publishers', COUNT(*) FROM publishers
-- UNION ALL
-- SELECT 'sources', COUNT(*) FROM sources
-- UNION ALL
-- SELECT 'subfields', COUNT(*) FROM subfields
-- UNION ALL
-- SELECT 'topics', COUNT(*) FROM topics
-- UNION ALL
-- SELECT 'works', COUNT(*) FROM works;

-- Check for duplicates (should return 0 for all entities)
-- SELECT 'authors' as entity, COUNT(*) - COUNT(DISTINCT id) as duplicates FROM authors
-- UNION ALL
-- SELECT 'works', COUNT(*) - COUNT(DISTINCT id) FROM works;

-- ============================================================================
-- USAGE NOTES
-- ============================================================================
--
-- 1. DEDUPLICATION LOGIC:
--    Each view uses ROW_NUMBER() window function to deduplicate records:
--    - PARTITION BY id: Group by entity ID
--    - ORDER BY updated_date DESC: Select the most recent version
--    - WHERE rn = 1: Keep only the latest version
--
-- 2. WILDCARD PATTERNS:
--    Views use (**/*.parquet) to automatically include new files.
--
-- 3. SCHEMA EVOLUTION:
--    The 'union_by_name=true' parameter handles new columns gracefully.
--
-- 4. PERFORMANCE CONSIDERATIONS:
--    - Deduplication adds overhead (typically 2-3x for simple queries)
--    - Most queries with WHERE clauses see minimal impact
--    - Trade-off: Slower queries vs guaranteed data accuracy
--
-- 5. QUERYING FROM METABASE:
--    Use view names directly:
--    - SELECT * FROM works WHERE publication_year = 2024;
--    - SELECT * FROM authors WHERE cited_by_count > 100;
--
-- 6. TO DISABLE DEDUPLICATION (not recommended):
--    Replace each view with simple version:
--    CREATE OR REPLACE VIEW authors AS
--    SELECT * FROM read_parquet('/data/authors/**/*.parquet', union_by_name=true);
--
-- ============================================================================
