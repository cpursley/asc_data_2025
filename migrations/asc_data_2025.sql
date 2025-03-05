-- Create uszips table
CREATE TABLE IF NOT EXISTS uszips (
    -- Primary identifier
    zip TEXT PRIMARY KEY,
    
    -- Geographic coordinates (adjusted precision based on data)
    lat NUMERIC(8, 5),
    lng NUMERIC(8, 5),
    
    -- Location info
    city TEXT NOT NULL,
    state_id TEXT NOT NULL,  -- Two-letter state code
    state_name TEXT NOT NULL,
    
    -- ZCTA (ZIP Code Tabulation Area) info
    zcta BOOLEAN DEFAULT FALSE,
    parent_zcta TEXT,  -- Can be null
    
    -- Demographics (adjusted precision based on data)
    population INTEGER,
    density NUMERIC(7, 1),
    
    -- County info
    county_fips TEXT,
    county_name TEXT,
    county_weights JSONB,  -- Store the county weights as JSON
    county_names_all TEXT,  -- Pipe-delimited string
    county_fips_all TEXT,   -- Pipe-delimited string
    
    -- Additional flags
    imprecise BOOLEAN DEFAULT FALSE,
    military BOOLEAN DEFAULT FALSE,
    
    -- Timezone
    timezone TEXT,
    
    -- Metadata
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Create indexes for common queries
CREATE INDEX idx_uszips_state_id ON uszips(state_id);
CREATE INDEX idx_uszips_county_fips ON uszips(county_fips);
CREATE INDEX idx_uszips_city ON uszips(city);
CREATE INDEX idx_uszips_population ON uszips(population);

-- Add trigger for updated_at
CREATE TRIGGER update_uszips_updated_at
    BEFORE UPDATE ON uszips
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- Add helpful comments
COMMENT ON TABLE uszips IS 'US ZIP code data from SimpleMaps including cities, counties, and geographic information';
COMMENT ON COLUMN uszips.county_weights IS 'JSON object containing county FIPS codes as keys and weights as values';
COMMENT ON COLUMN uszips.county_names_all IS 'Pipe-delimited string of county names (e.g., "County1|County2")';
COMMENT ON COLUMN uszips.county_fips_all IS 'Pipe-delimited string of county FIPS codes (e.g., "12345|67890")'; 

-- ASC Tables
DROP TABLE IF EXISTS "public"."asc_data";
-- This script only contains the table creation statements and does not fully represent the table in the database. Do not use it as a backup.

-- Table Definition
CREATE TABLE "public"."asc_data" (
    "Licensing State" text,
    "State License Number" text,
    "First Name" text,
    "Middle Name" text,
    "Last Name" text,
    "Name Suffix" text,
    "Effective Date of License" text,
    "Expiration Date of License" text,
    "License Certificate Type" text,
    "Status" text,
    "Company Name" text,
    "Telephone Number" text,
    "Street Address" text,
    "City" text,
    "State" text,
    "County" text,
    "Zip Code" text,
    "Conforms to AQB Criteria" text,
    "Disciplinary Action" text,
    "Disciplinary Action Effective Date" text,
    "Disciplinary Action Ending Date" text
);

-- Helper data cleaning functions

-- Create a composite type for phone number with extension
CREATE TYPE normalized_phone AS (
    phone_number varchar( 10),
    EXTENSION varchar(10));

-- Create function to normalize US phone numbers
CREATE OR REPLACE FUNCTION normalize_us_phone(phone text)
    RETURNS normalized_phone
    LANGUAGE plpgsql
    IMMUTABLE
    AS $$
DECLARE
    digits text;
    EXTENSION text := NULL;
    result normalized_phone;
BEGIN
    -- Return null if input is null or empty
    IF phone IS NULL OR TRIM(phone) = '' OR TRIM(phone) = 'NONE' THEN
        RETURN NULL;
    END IF;
    -- Extract digits and potential extension
    digits := REGEXP_REPLACE(phone, '[^0-9]', '', 'g');
    -- Check for extension patterns and extract if found
    IF phone ~* 'x\s*\d+' THEN
        EXTENSION := REGEXP_REPLACE(phone, '.*x\s*(\d+).*', '\1', 'i');
        -- Remove extension from digits
        digits := REGEXP_REPLACE(digits, EXTENSION || '$', '');
    END IF;
    -- Handle different digit lengths
    CASE LENGTH(digits)
    WHEN 10 THEN
        -- Perfect case, exactly 10 digits
        result.phone_number := digits;
    WHEN 11 THEN
        -- Remove leading 1 if present
        IF
        LEFT (digits,
        1) = '1' THEN
                result.phone_number :=
            RIGHT (digits,
                10);
        ELSE
            RETURN NULL;
            END IF;
ELSE
    -- Invalid length
    RETURN NULL;
    END CASE;
    -- Validate area code (first 3 digits)
    IF
    LEFT (result.phone_number,
    1) IN ('0', '1') THEN
        RETURN NULL;
    END IF;
    result.extension := EXTENSION;
    RETURN result;
END;
$$;

-- Create function to normalize zip codes
CREATE OR REPLACE FUNCTION normalize_zip(zip text)
    RETURNS text
    LANGUAGE plpgsql
    IMMUTABLE
    AS $$
DECLARE
    clean_zip text;
BEGIN
    -- Return null if input is null or empty
    IF zip IS NULL OR TRIM(zip) = '' THEN
        RETURN NULL;
    END IF;
    -- Extract just the digits
    clean_zip := REGEXP_REPLACE(zip, '[^0-9]', '', 'g');
    -- Handle different cases
    CASE LENGTH(clean_zip)
    WHEN 5 THEN
        -- Perfect case
        RETURN clean_zip;
    WHEN 9 THEN
        -- ZIP+4, take first 5
        RETURN
    LEFT (clean_zip,
        5);
    WHEN 4 THEN
        -- Add leading zero
        RETURN '0' || clean_zip;
    WHEN 3 THEN
        -- Add two leading zeros
        RETURN '00' || clean_zip;
    ELSE
        -- Invalid length
        RETURN NULL;
    END CASE;
    END;
$$;

-- Create function to normalize names
CREATE OR REPLACE FUNCTION normalize_name(full_name text)
    RETURNS text
    LANGUAGE plpgsql
    IMMUTABLE
    AS $$
DECLARE
    normalized text;
    suffix_pattern text := '\s+(Jr\.?|JR\.?|Sr\.?|SR\.?|III?|IV|VI?|Esq\.?|3rd|3RD|MAI|[MP][RSrs]\.?|\(M\)|111|lll)$';
    title_pattern text := '^(Dr\.?|Mr\.?|Mrs\.?|Ms\.?|Miss\.?)\s+';
BEGIN
    -- Return null if input is null or empty
    IF full_name IS NULL OR TRIM(full_name) = '' THEN
        RETURN NULL;
    END IF;
    -- First remove apostrophes and special characters
    normalized := REGEXP_REPLACE(TRIM(full_name), '[''`]', '', 'g');
    -- Then convert to proper case
    normalized := INITCAP(LOWER(normalized));
    -- Remove titles from the beginning
    normalized := REGEXP_REPLACE(normalized, title_pattern, '', 'i');
    -- Remove common name suffixes
    normalized := REGEXP_REPLACE(normalized, suffix_pattern, '', 'i');
    -- Clean up spaces
    normalized := REGEXP_REPLACE(normalized, '\s+', ' ', 'g');
    normalized := TRIM(normalized);
    RETURN normalized;
END;
$$;

-- Create normalized view of ASC data
CREATE OR REPLACE VIEW asc_data_normalized AS
SELECT
    -- License information (first in original)
    NULLIF(UPPER(TRIM("Licensing State")), '') AS licensing_state,
    NULLIF(TRIM("State License Number"), '') AS license_number,
    -- Name fields
    normalize_name("First Name") AS first_name,
    normalize_name("Middle Name") AS middle_name,
    normalize_name("Last Name") AS last_name,
    NULLIF(TRIM("Name Suffix"), '') AS name_suffix,
    -- License dates and type
    NULLIF(TRIM("Effective Date of License"), '')::date AS effective_date,
    NULLIF(TRIM("Expiration Date of License"), '')::date AS expiration_date,
    NULLIF(TRIM("License Certificate Type"), '') AS certification_type,
    NULLIF(TRIM("Status"), '') AS status_license,
    -- Company and contact
    CASE WHEN TRIM("Company Name") IS NULL
        OR TRIM("Company Name") = '' THEN
        NULL
    ELSE
        TRIM(REGEXP_REPLACE(REGEXP_REPLACE(REGEXP_REPLACE(INITCAP(TRIM("Company Name")), '[^A-Za-z0-9\s]', ' ', 'g'), '\s+', ' ', 'g'), '(?i)(LLC|INC|CORP|LTD|PC|PA|LP|LLP)\.?\s*$', '', 'g'))
    END AS company_name,
(normalize_us_phone(NULLIF(TRIM("Telephone Number"), ''))).phone_number AS phone_number,
    -- Address fields
    REGEXP_REPLACE(INITCAP(TRIM(LOWER(NULLIF(TRIM("Street Address"), '')))), '''', '', 'g') AS address_line1, REGEXP_REPLACE(INITCAP(TRIM(LOWER(NULLIF(TRIM("City"), '')))), '''', '', 'g') AS city_name, COALESCE(NULLIF(UPPER(TRIM("State")), ''), NULLIF(UPPER(TRIM("Licensing State")), '')) AS state_code, INITCAP(NULLIF(TRIM("County"), '')) AS county_name, normalize_zip(NULLIF(TRIM("Zip Code"), '')) AS zip_code,
                                    -- Additional fields
                                    NULLIF(TRIM("Conforms to AQB Criteria"), '') AS aqb_compliant, NULLIF(TRIM("Disciplinary Action"), '') AS disciplinary_action, NULLIF(TRIM("Disciplinary Action Effective Date"), '')::date AS disciplinary_start_date, NULLIF(TRIM("Disciplinary Action Ending Date"), '')::date AS disciplinary_end_date FROM public.asc_data;

-- Create materialized view for unique appraisers with detailed identity analysis
CREATE MATERIALIZED VIEW asc_data_appraisers AS
WITH normalized_records AS (
    SELECT
        first_name,
        last_name,
        state_code,
        company_name,
        phone_number,
        certification_type,
        license_number,
        licensing_state,
        effective_date,
        expiration_date,
        status_license
    FROM
        asc_data_normalized
    WHERE
        first_name IS NOT NULL
        AND last_name IS NOT NULL
        AND status_license = 'Active'
)
SELECT
    first_name,
    last_name,
    state_code,
    COUNT(*) AS license_count,
    jsonb_agg(jsonb_build_object('certification_type', certification_type, 'state', licensing_state, 'number', license_number, 'status_license', status_license, 'effective_date', effective_date, 'expiration_date', expiration_date)
    ORDER BY licensing_state, certification_type) AS licenses,
    ROUND(DATE_PART('year', AGE(CURRENT_DATE, MIN(effective_date)::date)))::integer AS years_licensed,
    array_agg(DISTINCT company_name) FILTER (WHERE company_name IS NOT NULL) AS companies,
    array_agg(DISTINCT phone_number) FILTER (WHERE phone_number IS NOT NULL) AS phone_numbers,
    MIN(effective_date) AS earliest_license_date,
    MAX(expiration_date) AS latest_expiration_date,
    CASE WHEN COUNT(*) >= 10 THEN
        'national'
    WHEN COUNT(*) >= 3 THEN
        'regional'
    ELSE
        'local'
    END AS market_coverage,
    CASE WHEN COUNT(DISTINCT company_name) = 1
        AND COUNT(DISTINCT phone_number) = 1 THEN
        'high'
    WHEN COUNT(DISTINCT company_name) <= 2
        AND COUNT(DISTINCT phone_number) <= 2 THEN
        'medium'
    ELSE
        'low'
    END AS identity_confidence
FROM
    normalized_records
GROUP BY
    first_name,
    last_name,
    state_code;

COMMENT ON MATERIALIZED VIEW asc_data_appraisers IS 'Detailed analysis of unique appraisers by state, including identity confidence based on company and contact consistency.';

-- Create materialized view for active licenses
CREATE MATERIALIZED VIEW asc_data_licenses AS
SELECT
    first_name,
    last_name,
    certification_type,
    licensing_state,
    license_number,
    status_license,
    effective_date,
    expiration_date
FROM
    asc_data_normalized
WHERE
    status_license = 'Active';

COMMENT ON MATERIALIZED VIEW asc_data_licenses IS 'Active appraiser licenses across all states.';

-- Create materialized view for state-level analysis including certification breakdowns and population metrics
CREATE MATERIALIZED VIEW asc_data_states AS
WITH cert_counts AS (
    SELECT
        licensing_state AS state_id,
        COUNT(DISTINCT license_number) AS total_licenses,
        COUNT(DISTINCT CONCAT(first_name, ' ', last_name)) AS total_appraisers,
        -- License counts by certification type
        COUNT(*) FILTER (WHERE certification_type = 'Certified General') AS certified_general_licenses,
        COUNT(*) FILTER (WHERE certification_type = 'Certified Residential') AS certified_residential_licenses,
        COUNT(*) FILTER (WHERE certification_type = 'Licensed') AS licensed_licenses,
        -- Unique appraiser counts by certification type
        COUNT(DISTINCT CONCAT(first_name, ' ', last_name)) FILTER (WHERE certification_type = 'Certified General') AS certified_general_appraisers,
        COUNT(DISTINCT CONCAT(first_name, ' ', last_name)) FILTER (WHERE certification_type = 'Certified Residential') AS certified_residential_appraisers,
        COUNT(DISTINCT CONCAT(first_name, ' ', last_name)) FILTER (WHERE certification_type = 'Licensed') AS licensed_appraisers
    FROM
        asc_data_normalized
    WHERE
        status_license = 'Active'
    GROUP BY
        licensing_state
),
state_population AS (
    SELECT
        state_id,
        SUM(population) AS total_population
    FROM
        uszips
    WHERE
        zcta = TRUE
    GROUP BY
        state_id
)
SELECT
    c.state_id,
    c.total_licenses,
    c.total_appraisers,
    c.certified_general_licenses,
    c.certified_residential_licenses,
    c.licensed_licenses,
    c.certified_general_appraisers,
    c.certified_residential_appraisers,
    c.licensed_appraisers,
    p.total_population,
    CAST(p.total_population AS decimal) / NULLIF(c.total_appraisers, 0) AS population_per_appraiser,
    CAST(c.certified_general_appraisers * 100.0 AS decimal) / NULLIF(c.total_appraisers, 0) AS certified_general_pct,
    CAST(c.certified_residential_appraisers * 100.0 AS decimal) / NULLIF(c.total_appraisers, 0) AS certified_residential_pct,
    CAST(c.licensed_appraisers * 100.0 AS decimal) / NULLIF(c.total_appraisers, 0) AS licensed_pct,
    CAST(c.total_licenses AS decimal) / NULLIF(c.total_appraisers, 0) AS licenses_per_appraiser,
    CAST(c.total_appraisers * 100000.0 AS decimal) / NULLIF(p.total_population, 0) AS appraisers_per_100k_pop
FROM
    cert_counts c
    LEFT JOIN state_population p ON c.state_id = p.state_id
ORDER BY
    c.total_appraisers DESC;

-- Create index for better query performance
CREATE UNIQUE INDEX idx_state_stats_state ON asc_data_states(state_id);

-- Add comment explaining the view
COMMENT ON MATERIALIZED VIEW asc_data_states IS 'State-level analysis showing appraiser counts, certification distributions, and population metrics.';

-- Create materialized view for region-level analysis including certification breakdowns and population metrics
CREATE MATERIALIZED VIEW asc_data_regions AS
WITH region_cert_counts AS (
    SELECT
        r.region,
        COUNT(DISTINCT a.license_number) AS total_licenses,
        COUNT(DISTINCT CONCAT(a.first_name, ' ', a.last_name)) AS total_appraisers,
        -- License counts by certification type
        COUNT(*) FILTER (WHERE a.certification_type = 'Certified General') AS certified_general_licenses,
        COUNT(*) FILTER (WHERE a.certification_type = 'Certified Residential') AS certified_residential_licenses,
        COUNT(*) FILTER (WHERE a.certification_type = 'Licensed') AS licensed_licenses,
        -- Unique appraiser counts by certification type
        COUNT(DISTINCT CONCAT(a.first_name, ' ', a.last_name)) FILTER (WHERE a.certification_type = 'Certified General') AS certified_general_appraisers,
        COUNT(DISTINCT CONCAT(a.first_name, ' ', a.last_name)) FILTER (WHERE a.certification_type = 'Certified Residential') AS certified_residential_appraisers,
        COUNT(DISTINCT CONCAT(a.first_name, ' ', a.last_name)) FILTER (WHERE a.certification_type = 'Licensed') AS licensed_appraisers
    FROM
        asc_data_normalized a
        JOIN us_states_by_region r ON a.licensing_state = ANY (r.state_ids)
    WHERE
        a.status_license = 'Active'
    GROUP BY
        r.region
),
region_population AS (
    SELECT
        r.region,
        SUM(z.population) AS total_population,
        r.state_count
    FROM
        uszips z
        JOIN us_states_by_region r ON z.state_id = ANY (r.state_ids)
    WHERE
        z.zcta = TRUE
    GROUP BY
        r.region,
        r.state_count
)
SELECT
    c.region,
    c.total_licenses,
    c.total_appraisers,
    c.certified_general_licenses,
    c.certified_residential_licenses,
    c.licensed_licenses,
    c.certified_general_appraisers,
    c.certified_residential_appraisers,
    c.licensed_appraisers,
    p.state_count AS states_in_region,
    p.total_population,
    ROUND(CAST(p.total_population AS decimal) / NULLIF(c.total_appraisers, 0), 2) AS population_per_appraiser,
    ROUND(CAST(c.certified_general_appraisers * 100.0 AS decimal) / NULLIF(c.total_appraisers, 0), 2) AS certified_general_pct,
    ROUND(CAST(c.certified_residential_appraisers * 100.0 AS decimal) / NULLIF(c.total_appraisers, 0), 2) AS certified_residential_pct,
    ROUND(CAST(c.licensed_appraisers * 100.0 AS decimal) / NULLIF(c.total_appraisers, 0), 2) AS licensed_pct,
    ROUND(CAST(c.total_licenses AS decimal) / NULLIF(c.total_appraisers, 0), 2) AS licenses_per_appraiser,
    ROUND(CAST(c.total_appraisers * 100000.0 AS decimal) / NULLIF(p.total_population, 0), 2) AS appraisers_per_100k_pop
FROM
    region_cert_counts c
    LEFT JOIN region_population p ON c.region = p.region
ORDER BY
    c.total_appraisers DESC;

-- Create index for better query performance
CREATE UNIQUE INDEX idx_region_stats_region ON asc_data_regions(region);

-- Add comment explaining the view
COMMENT ON MATERIALIZED VIEW asc_data_regions IS 'Region-level analysis showing appraiser counts, certification distributions, and population metrics.';

-- Create materialized view for company-level analysis
CREATE MATERIALIZED VIEW asc_data_companies AS
WITH company_metrics AS (
    SELECT
        company_name,
        COUNT(DISTINCT CONCAT(first_name, ' ', last_name)) AS appraiser_count,
        COUNT(DISTINCT licensing_state) AS state_count,
        COUNT(DISTINCT zip_code) AS location_count,
        -- Certification type counts
        COUNT(*) FILTER (WHERE certification_type = 'Certified General') AS certified_general_count,
        COUNT(*) FILTER (WHERE certification_type = 'Certified Residential') AS certified_residential_count,
        COUNT(*) FILTER (WHERE certification_type = 'Licensed') AS licensed_count,
        -- Experience metrics
        ROUND(AVG(DATE_PART('year', AGE(CURRENT_DATE, effective_date::date))))::integer AS avg_years_licensed,
        -- Geographic spread
        array_agg(DISTINCT licensing_state ORDER BY licensing_state) AS states_present,
        array_agg(DISTINCT city_name) FILTER (WHERE city_name IS NOT NULL) AS cities_present,
        -- Market classification
        CASE WHEN COUNT(DISTINCT licensing_state) >= 10 THEN
            'national'
        WHEN COUNT(DISTINCT licensing_state) >= 3 THEN
            'regional'
        ELSE
            'local'
        END AS market_coverage
    FROM
        asc_data_normalized
    WHERE
        company_name IS NOT NULL
        AND TRIM(company_name) != ''
    GROUP BY
        company_name
)
SELECT
    company_name,
    appraiser_count,
    state_count,
    location_count,
    certified_general_count,
    certified_residential_count,
    licensed_count,
    avg_years_licensed,
    states_present,
    cities_present,
    market_coverage,
    ROUND(100.0 * certified_general_count / appraiser_count, 2) AS certified_general_pct,
    ROUND(100.0 * certified_residential_count / appraiser_count, 2) AS certified_residential_pct,
    ROUND(100.0 * licensed_count / appraiser_count, 2) AS licensed_pct,
    -- Size classification
    CASE WHEN appraiser_count >= 100 THEN
        'large'
    WHEN appraiser_count >= 20 THEN
        'medium'
    WHEN appraiser_count >= 5 THEN
        'small'
    ELSE
        'micro'
    END AS company_size
FROM
    company_metrics
ORDER BY
    appraiser_count DESC;

-- Create index for better query performance
CREATE UNIQUE INDEX idx_company_stats_name ON asc_data_companies(company_name);

-- Add comment explaining the view
COMMENT ON MATERIALIZED VIEW asc_data_companies IS 'Company-level analysis showing appraiser counts, certification distributions, geographic presence, and experience metrics.';

-- Create materialized view for city-level analysis
CREATE MATERIALIZED VIEW asc_data_cities AS
WITH city_cert_counts AS (
    SELECT
        UPPER(TRIM(a.state_code)) AS state_id,
        INITCAP(TRIM(a.city_name)) AS city_name,
        COUNT(DISTINCT a.license_number) AS total_licenses,
        COUNT(DISTINCT CONCAT(a.first_name, ' ', a.last_name)) AS total_appraisers,
        COUNT(*) FILTER (WHERE a.certification_type = 'Certified General') AS certified_general_licenses,
        COUNT(*) FILTER (WHERE a.certification_type = 'Certified Residential') AS certified_residential_licenses,
        COUNT(*) FILTER (WHERE a.certification_type = 'Licensed') AS licensed_licenses,
        COUNT(DISTINCT CONCAT(a.first_name, ' ', a.last_name)) FILTER (WHERE a.certification_type = 'Certified General') AS certified_general_appraisers,
        COUNT(DISTINCT CONCAT(a.first_name, ' ', a.last_name)) FILTER (WHERE a.certification_type = 'Certified Residential') AS certified_residential_appraisers,
        COUNT(DISTINCT CONCAT(a.first_name, ' ', a.last_name)) FILTER (WHERE a.certification_type = 'Licensed') AS licensed_appraisers
    FROM
        asc_data_normalized a
    WHERE
        a.status_license = 'Active'
        AND a.city_name IS NOT NULL
        AND a.state_code IS NOT NULL
    GROUP BY
        UPPER(TRIM(a.state_code)),
        INITCAP(TRIM(a.city_name))
),
city_population AS (
    SELECT
        state_id,
        city AS city_name,
        SUM(population) AS city_population,
        COUNT(DISTINCT zip) AS zip_codes,
        ROUND(AVG(density), 2) AS avg_density,
        ROUND(MIN(lat)::numeric, 4) AS city_lat,
        ROUND(MIN(lng)::numeric, 4) AS city_lng
    FROM
        uszips
    WHERE
        zcta = TRUE
    GROUP BY
        state_id,
        city
)
SELECT
    c.state_id,
    c.city_name,
    c.total_licenses,
    c.total_appraisers,
    c.certified_general_licenses,
    c.certified_residential_licenses,
    c.licensed_licenses,
    c.certified_general_appraisers,
    c.certified_residential_appraisers,
    c.licensed_appraisers,
    p.city_population AS total_population,
    p.zip_codes,
    ROUND(CAST(p.city_population AS decimal) / NULLIF(c.total_appraisers, 0), 2) AS population_per_appraiser,
    ROUND(CAST(c.certified_general_appraisers * 100.0 AS decimal) / NULLIF(c.total_appraisers, 0), 2) AS certified_general_pct,
    ROUND(CAST(c.certified_residential_appraisers * 100.0 AS decimal) / NULLIF(c.total_appraisers, 0), 2) AS certified_residential_pct,
    ROUND(CAST(c.licensed_appraisers * 100.0 AS decimal) / NULLIF(c.total_appraisers, 0), 2) AS licensed_pct,
    ROUND(CAST(c.total_licenses AS decimal) / NULLIF(c.total_appraisers, 0), 2) AS licenses_per_appraiser,
    ROUND(CAST(c.total_appraisers * 100000.0 AS decimal) / NULLIF(p.city_population, 0), 2) AS appraisers_per_100k_pop,
    p.avg_density,
    p.city_lat,
    p.city_lng
FROM
    city_cert_counts c
    JOIN city_population p ON c.state_id = p.state_id
        AND c.city_name = p.city_name;

-- Create index for better query performance
CREATE UNIQUE INDEX idx_city_stats_city ON asc_data_cities(state_id, city_name);

-- Add comment explaining the view
COMMENT ON MATERIALIZED VIEW asc_data_cities IS 'City-level analysis showing appraiser counts, certification distributions, population metrics, and geographic data.';

-- Create function to refresh all ASC materialized views
CREATE OR REPLACE FUNCTION refresh_asc_materialized_views()
    RETURNS TRIGGER
    AS $$
BEGIN
    REFRESH MATERIALIZED VIEW CONCURRENTLY asc_data_appraisers;
    REFRESH MATERIALIZED VIEW CONCURRENTLY asc_data_licenses;
    REFRESH MATERIALIZED VIEW CONCURRENTLY asc_data_states;
    REFRESH MATERIALIZED VIEW CONCURRENTLY asc_data_regions;
    REFRESH MATERIALIZED VIEW CONCURRENTLY asc_data_companies;
    REFRESH MATERIALIZED VIEW CONCURRENTLY asc_data_cities;
    RETURN NULL;
END;
$$
LANGUAGE plpgsql;

-- Create trigger to refresh views when asc_data table changes
CREATE TRIGGER refresh_asc_materialized_views_trigger
    AFTER INSERT OR UPDATE OR DELETE OR TRUNCATE ON asc_data
    FOR EACH STATEMENT
    EXECUTE FUNCTION refresh_asc_materialized_views();

