# primed-pgs-catalog

This repository contains code to fetch data from the PGS catalog and format it 
in data tables in the [PRIMED data model](https://github.com/UW-GAC/primed_data_models).

Load the functions with `source('pgs-catalog-functions.R')`

`pgs_scoring_file_table`: 
- `pgs_id`: id from the PGS Catalog, e.g. "PGS000001"
- `dest_bucket`: google bucket path where the files will be copied to. Do not include a trailing "/"
- `harmonized`; whether to retrieve the scores files harmonized to a reference assembly. Default `TRUE`
- `assembly`: If `harmonized=TRUE`, this controls which files to download. Default `"GRCh38"`

This function fetches data files from the PGS catalog, copies them to a google 
bucket specified by `dest_bucket`, and returns a tibble with a "pgs_scoring_file" table 
containing the bucket paths to the files.

`pgs_model_tables`:
- `pgs_id`: id from the PGS Catalog, e.g. "PGS000001"
- `assembly`: use the same value as supplied to `pgs_scoring_file_table`

This function uses the [quincunx](https://github.com/maialab/quincunx) R package 
to fetch data from the PGS catalog and format it into "pgs_analysis" and
"pgs_sample_devel" data tables. Returns a list with two tibbles.