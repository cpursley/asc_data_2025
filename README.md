# ASC Appraiser Data Analysis 2025

This repository contains the data processing code and SQL queries used to analyze the Appraisal Subcommittee's (ASC) Federal Registry data for 2025. 

## About the Data

The data comes from two main sources:

1. **ASC Federal Registry**: Contains all active real estate appraiser licenses in the United States. Downloaded from the [ASC website](https://www.asc.gov/appraiser/advanced?field_first_name__value_op=contains&field_first_name__value=&field_last_name__value_op=contains&field_last_name__value=&field_state_name_value=All&field_license_number__value=&field_license_type__value%5BCertified+General%5D=Certified+General&field_license_type__value%5BCertified+Residential%5D=Certified+Residential&field_license_type__value%5BLicensed%5D=Licensed&field_is_license_active__value=1&field_meets_board_criteria__value=All&field_city__value=&field_zip__value=&field_county__value=&field_company_name__value_op=contains&field_company_name__value=&field_is_public__value=All&field_discipline_action_type_value=All&items_per_page=20&submit=Apply) in Excel format.

2. **SimpleMaps US ZIP Codes**: A free database providing population data and geographic coordinates for US ZIP codes, used for calculating state and regional statistics. Available from [SimpleMaps](https://simplemaps.com/data/us-zips).

### Data Processing Challenges

The ASC data presents several challenges that this repository helps address:

- No unique national identifier for appraisers
- Inconsistent name formats across states
- Multiple licenses per appraiser (both across states and within states)
- Varying data quality and completeness

## Requirements

- [PostgreSQL](https://www.postgresql.org/) 16 or higher
  - PostgreSQL is a powerful, open-source database that's great for data analysis
  - Download and install from the [official website](https://www.postgresql.org/download/)

## Setup Instructions

1. **Install PostgreSQL**
   ```bash
   # macOS (using Homebrew)
   brew install postgresql
   
   # Ubuntu/Debian
   sudo apt-get install postgresql
   
   # Windows
   # Download and run the installer from postgresql.org
   ```

2. **Create the Database**
   ```bash
   # Create a new database
   createdb asc_data_2025
   
   # Or from psql
   psql
   CREATE DATABASE asc_data_2025;
   ```

3. **Run the Migration**
   ```bash
   # Apply the SQL migration
   psql -d asc_data_2025 -f migrations/asc_data_2025.sql
   ```

4. **Import Source Data**

   After running the migration, you'll need to import the source data:

   1. **ASC Data**: Import the ASC Excel file into the `asc_data` table
      ```sql
      -- Using psql's \copy command (replace with your file path)
      \copy asc_data FROM 'path/to/asc_data.csv' WITH (FORMAT csv, HEADER true);
      ```

   2. **ZIP Code Data**: Import the SimpleMaps data into the `uszips` table
      ```sql
      -- Using psql's \copy command (replace with your file path)
      \copy uszips FROM 'path/to/uszips.csv' WITH (FORMAT csv, HEADER true);
      ```

   Note: The materialized views will automatically refresh after data import. If you need to manually refresh them:
   ```sql
   SELECT refresh_asc_materialized_views();
   ```

## What's in the Migration?

The SQL migration file (`asc_data_2025.sql`) includes:

1. **Data Cleaning Functions**
   - Normalizes names (removes titles, standardizes formats)
   - Standardizes phone numbers and ZIP codes
   - Validates and formats addresses

2. **Materialized Views**
   - `asc_data_normalized`: Cleaned version of raw ASC data
   - `asc_data_appraisers`: Unique appraiser identification and analysis
   - `asc_data_states`: State-level statistics
   - `asc_data_cities`: City-level analysis
   - `asc_data_regions`: Regional breakdowns
   - `asc_data_companies`: Company-level metrics

3. **Indexes and Performance Optimizations**
   - Improves query performance for common lookups
   - Enables efficient geographic searches

```sql
-- Get top 10 states by number of appraisers
SELECT state_id, total_appraisers, total_population,
       population_per_appraiser, appraisers_per_100k_pop
FROM asc_data_states
ORDER BY total_appraisers DESC
LIMIT 10;

-- Find cities with highest appraiser density
SELECT city_name, state_id, total_appraisers,
       appraisers_per_100k_pop
FROM asc_data_cities
ORDER BY appraisers_per_100k_pop DESC
LIMIT 10;

-- Find appraisers with most state licenses
SELECT first_name || ' ' || last_name as name,
       license_count,
       years_licensed,
       market_coverage,
       identity_confidence
FROM asc_data_appraisers
ORDER BY license_count DESC
LIMIT 10;

-- Find largest appraisal companies and their geographic spread
SELECT company_name,
       appraiser_count,
       state_count,
       market_coverage,
       company_size,
       avg_years_licensed
FROM asc_data_companies
WHERE appraiser_count > 50
ORDER BY appraiser_count DESC;

-- Find cities with interesting certification distributions
SELECT city_name, 
       state_id,
       total_appraisers,
       ROUND(certified_general_pct, 1) as certified_general_pct,
       ROUND(certified_residential_pct, 1) as certified_residential_pct,
       ROUND(licensed_pct, 1) as licensed_pct
FROM asc_data_cities
WHERE total_appraisers > 100
AND (certified_general_pct > 80 OR 
     certified_residential_pct > 80 OR 
     licensed_pct > 20)
ORDER BY total_appraisers DESC;

-- Find experienced appraisers with multiple licenses
SELECT first_name || ' ' || last_name as name,
       years_licensed,
       license_count,
       array_length(companies, 1) as company_count,
       market_coverage
FROM asc_data_appraisers
WHERE years_licensed > 20
AND license_count > 10
ORDER BY years_licensed DESC, license_count DESC
LIMIT 10;
```

## Contributing

We welcome contributions to improve the analysis! Some areas where you could help:

- Improving name matching algorithms
- Adding new metrics or views
- Enhancing data validation
- Documenting state-specific licensing quirks
- Adding new analysis queries

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Acknowledgments

- ASC for maintaining the Federal Registry
- SimpleMaps for their US ZIP code database
- The appraisal community for feedback and insights

## Related Resources

For a detailed analysis of this data, check out our [2025 ASC Data Analysis](https://jobsinappraisal.com/resources/asc-data-analysis-2025). 
